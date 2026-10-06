"""Run with python3 tests/autostart_test.py; no compositor/X server/apps needed."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


CONFIG_DIR = Path(__file__).resolve().parents[1]
LUA_FIXTURE = r'''
package.loaded["lua/vars"] = { PC = os.getenv("TEST_PC") }
local events, commands = {}, {}
hl = {
    on = function(name, callback) events[name] = callback end,
    exec_cmd = function(command) commands[#commands + 1] = command end,
}
require("lua/autostart")
assert(#commands == 0, "loading/reloading config must not launch apps")
assert(events["config.reloaded"] == nil, "reload must not relaunch Signal")
assert(events["hyprland.start"], "missing startup handler")
events["hyprland.start"]()
local callback = os.getenv("TEST_CALLBACK")
if callback and callback ~= "" then
    commands = {}
    if os.getenv("TEST_RELOAD") == "1" then
        -- The config can reload while xrdb runs. IPC must resolve the current module.
        package.loaded["lua/autostart"] = nil
        require("lua/autostart")
        assert(#commands == 0, "reload must not launch apps")
    end
    local complete = assert((loadstring or load)(callback))
    complete()
    complete() -- repeated completion in the same Lua state must be harmless
end
for _, command in ipairs(commands) do io.write(command, "\n") end
'''


class AutostartTest(unittest.TestCase):
    def commands(self, pc, callback="", reload=False):
        result = subprocess.run(
            ["lua", "-e", LUA_FIXTURE], cwd=CONFIG_DIR,
            env={**os.environ, "TEST_PC": pc, "TEST_CALLBACK": callback,
                 "TEST_RELOAD": "1" if reload else "0"},
            text=True, capture_output=True, check=True, timeout=10,
        )
        return result.stdout.splitlines()

    def run_xrdb(self, command, status=0):
        # Execute the real configured shell command, but never real X/IPC clients.
        with tempfile.TemporaryDirectory(prefix="hypr startup '") as temp_dir:
            home = Path(temp_dir)
            bin_dir = home / "bin"
            bin_dir.mkdir()
            (home / ".Xresources").write_text("Xft.dpi: 120\n")
            stubs = {
                "xrdb": '''#!/bin/sh
[ "$#" = 2 ] && [ "$1" = -merge ] && [ "$2" = "$HOME/.Xresources" ] || exit 91
printf 'xrdb-start\\n'
sleep 0.05
[ "$XRDB_STATUS" = 0 ] || exit "$XRDB_STATUS"
printf '120\\n' > "$HOME/dpi-ready"
printf 'xrdb-ready\\n'
''',
                "hyprctl": '''#!/bin/sh
[ "$#" = 2 ] && [ "$1" = eval ] || exit 92
[ -f "$HOME/dpi-ready" ] || exit 93
printf '%s' "$2" > "$HOME/callback"
printf 'callback\\n'
''',
                "signal-desktop": '''#!/bin/sh
printf 'Signal must be launched by Lua, not the xrdb shell' >&2
exit 94
''',
            }
            for name, content in stubs.items():
                path = bin_dir / name
                path.write_text(content)
                path.chmod(0o755)
            result = subprocess.run(
                ["/bin/sh", "-c", command],
                env={**os.environ, "HOME": str(home),
                     "PATH": f"{bin_dir}:/usr/bin:/bin", "XRDB_STATUS": str(status)},
                text=True, capture_output=True, timeout=10,
            )
            callback_path = home / "callback"
            callback = callback_path.read_text() if callback_path.exists() else None
            return result, callback

    def test_startup_requests_xrdb_but_defers_signal_on_both_machines(self):
        for pc in ("mainpc", "laptop"):
            with self.subTest(pc=pc):
                commands = self.commands(pc)
                resource_commands = [cmd for cmd in commands if "xrdb" in cmd]
                self.assertEqual(len(resource_commands), 1)
                self.assertFalse(any("signal-desktop" in cmd for cmd in commands))
                self.assertEqual("ckb-next -b" in commands, pc == "mainpc")
                self.assertIn("hypridle", commands)
                self.assertEqual(commands.count("hyprpaper"), 1)
                self.assertIn("nm-applet", commands)

    def test_success_launches_signal_in_its_own_exec_even_after_pending_reload(self):
        for pc in ("mainpc", "laptop"):
            with self.subTest(pc=pc):
                command = next(cmd for cmd in self.commands(pc) if "xrdb" in cmd)
                result, callback = self.run_xrdb(command)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(),
                                 ["xrdb-start", "xrdb-ready", "callback"])
                self.assertTrue(callback)
                for reload in (False, True):
                    self.assertEqual(self.commands(pc, callback, reload), ["signal-desktop"])

    def test_xrdb_failure_does_not_notify_or_launch_signal(self):
        for pc in ("mainpc", "laptop"):
            with self.subTest(pc=pc):
                command = next(cmd for cmd in self.commands(pc) if "xrdb" in cmd)
                result, callback = self.run_xrdb(command, status=7)
                self.assertEqual(result.returncode, 7, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ["xrdb-start"])
                self.assertIsNone(callback)


if __name__ == "__main__":
    unittest.main()
