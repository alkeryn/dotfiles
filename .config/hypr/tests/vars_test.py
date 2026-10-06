"""Run with: python3 tests/vars_test.py (requires lua and bash)."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest


CONFIG_DIR = Path(__file__).resolve().parents[1]


class VarsTest(unittest.TestCase):
    ignore_sigchld = False

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="hypr vars '")
        self.addCleanup(self.temp_dir.cleanup)
        self.home = Path(self.temp_dir.name)

    def write_wpc(self, path, content):
        script = self.home / path
        script.parent.mkdir(parents=True, exist_ok=True)
        script.write_text(content)

    def load_vars(self):
        return subprocess.run(
            ["lua", "-e", 'local v = require("lua/vars"); '
             'print(v.PC, v.BORDER, v.FLOAT_STEP)'],
            cwd=CONFIG_DIR,
            env={**os.environ, "HOME": str(self.home), "PC": "stale"},
            text=True,
            capture_output=True,
            preexec_fn=(
                (lambda: signal.signal(signal.SIGCHLD, signal.SIG_IGN))
                if self.ignore_sigchld else None
            ),
        )

    def test_installed_script_controls_mainpc_detection(self):
        self.write_wpc("bin/wpc", 'export PC=mainpc\n')
        result = self.load_vars()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "mainpc\t1\t20")

    def test_bash_script_controls_laptop_detection(self):
        self.write_wpc("bin/wpc", '[[ 1 == 1 ]] && export PC=laptop\necho diagnostic\n')
        result = self.load_vars()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "laptop\t2\t40")

    def test_missing_script_is_not_silently_treated_as_mainpc(self):
        result = self.load_vars()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("vars.lua: wpc failed", result.stderr)

    def test_invalid_or_failed_script(self):
        for content in ('export PC=unknown\n', 'unset PC\n', 'export PC=mainpc\nfalse\n'):
            with self.subTest(content=content):
                self.write_wpc("bin/wpc", content)
                result = self.load_vars()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("vars.lua: wpc failed", result.stderr)


class AutoReapedVarsTest(VarsTest):
    # On Linux, ignoring SIGCHLD auto-reaps children just like Hyprland's
    # SA_NOCLDWAIT. Lua inherits this disposition across exec, so pclose gets
    # ECHILD even when wpc succeeds. Re-run success AND failure cases this way.
    ignore_sigchld = True


if __name__ == "__main__":
    unittest.main()
