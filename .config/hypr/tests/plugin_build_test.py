import concurrent.futures
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/plugin_build.py"
spec = importlib.util.spec_from_file_location("plugin_build", SCRIPT)
plugin_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin_build)


class PluginBuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        (self.project / "CMakeLists.txt").write_text("# fixture")
        self.output = self.project / "build/test.so"
        self.commands = []

    def fake_cmake(self, args, **kwargs):
        self.commands.append(args)
        self.assertTrue(kwargs["check"])
        self.assertGreater(kwargs["timeout"], 0)
        if args[1] == "-S":
            Path(args[args.index("-B") + 1]).mkdir(parents=True, exist_ok=True)
        else:
            (Path(args[2]) / "test.so").write_bytes(b"\x7fELFbuilt")

    def run_build(self, instance="session-one"):
        plugin_build.run(self.project, self.output, "test", instance)

    def test_missing_plugin_is_built_before_reload(self):
        def reload(instance, log):
            self.assertEqual(instance, "session-one")
            self.assertEqual(self.output.read_bytes(), b"\x7fELFbuilt")
        with mock.patch.object(plugin_build.subprocess, "run", side_effect=self.fake_cmake), \
                mock.patch.object(plugin_build, "reload_instance", side_effect=reload) as reloader:
            self.run_build()
        reloader.assert_called_once()
        self.assertIn("-DCMAKE_CXX_COMPILER=clang++", self.commands[0])
        self.assertIn("-DBUILD_TESTING=OFF", self.commands[0])
        self.assertEqual(self.commands[1][-4:], ["--parallel", "2", "--target", "test"])
        self.assertNotEqual(Path(self.commands[1][2]), self.output.parent)

    def test_existing_binary_skips_cmake(self):
        self.output.parent.mkdir()
        self.output.write_bytes(b"\x7fELFexisting")
        inode = self.output.stat().st_ino
        with mock.patch.object(plugin_build.subprocess, "run") as cmake, \
                mock.patch.object(plugin_build, "reload_instance") as reloader:
            self.run_build()
        cmake.assert_not_called()
        reloader.assert_called_once()  # another session may have finished the build
        self.assertEqual(self.output.stat().st_ino, inode)

    def test_failed_build_does_not_publish_or_reload_and_can_retry(self):
        def fail(args, **kwargs):
            self.fake_cmake(args, **kwargs)
            if args[1] == "--build":
                raise subprocess.CalledProcessError(1, args)
        with mock.patch.object(plugin_build.subprocess, "run", side_effect=fail), \
                mock.patch.object(plugin_build, "reload_instance") as reloader:
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_build()
            reloader.assert_not_called()
        self.assertFalse(self.output.exists())
        self.assertIn("Build/reload failed", Path(str(self.output) + ".build.log").read_text())
        with mock.patch.object(plugin_build.subprocess, "run", side_effect=self.fake_cmake), \
                mock.patch.object(plugin_build, "reload_instance"):
            self.run_build()
        self.assertTrue(self.output.is_file())

    def test_no_cmake_project_is_reported_without_reload(self):
        (self.project / "CMakeLists.txt").unlink()
        with mock.patch.object(plugin_build.subprocess, "run") as cmake, \
                mock.patch.object(plugin_build, "reload_instance") as reloader:
            with self.assertRaises(FileNotFoundError):
                self.run_build()
        cmake.assert_not_called()
        reloader.assert_not_called()

    def test_concurrent_manual_output_is_not_overwritten(self):
        def concurrent_build(args, **kwargs):
            self.fake_cmake(args, **kwargs)
            if args[1] == "--build":
                self.output.write_bytes(b"\x7fELFmanual")
        with mock.patch.object(plugin_build.subprocess, "run", side_effect=concurrent_build), \
                mock.patch.object(plugin_build, "reload_instance"):
            self.run_build()
        self.assertEqual(self.output.read_bytes(), b"\x7fELFmanual")

    def test_repeated_requests_are_deduplicated_and_other_sessions_reload(self):
        started, release = threading.Event(), threading.Event()
        def slow_cmake(args, **kwargs):
            if args[1] == "--build":
                started.set()
                self.assertTrue(release.wait(5))
            self.fake_cmake(args, **kwargs)
        with mock.patch.object(plugin_build.subprocess, "run", side_effect=slow_cmake), \
                mock.patch.object(plugin_build, "reload_instance") as reloader, \
                concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            first = executor.submit(self.run_build)
            try:
                self.assertTrue(started.wait(5))
                duplicate = executor.submit(self.run_build)
                duplicate.result(timeout=2)
                reloader.assert_not_called()
                other = executor.submit(self.run_build, "session-two")
            finally:
                release.set()
            first.result(timeout=5)
            other.result(timeout=5)
        self.assertEqual(len(self.commands), 2)  # one configure/build pair
        self.assertEqual(sorted(call.args[0] for call in reloader.call_args_list),
                         ["session-one", "session-two"])

    def test_reload_targets_exact_instance(self):
        socket = self.root / "hypr/session-one/.socket.sock"
        socket.parent.mkdir(parents=True)
        socket.touch()
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
                mock.patch.object(plugin_build.subprocess, "run") as command:
            plugin_build.reload_instance("session-one", io.StringIO())
        self.assertEqual(command.call_args.args[0], ["hyprctl", "-i", "session-one", "reload"])

    def test_missing_instance_has_bounded_wait(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)}), \
                mock.patch.object(plugin_build.time, "monotonic", side_effect=[0, 31]), \
                mock.patch.object(plugin_build.subprocess, "run") as command:
            with self.assertRaises(TimeoutError):
                plugin_build.reload_instance("gone", io.StringIO())
        command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
