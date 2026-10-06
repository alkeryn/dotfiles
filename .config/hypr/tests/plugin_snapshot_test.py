import concurrent.futures
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/plugin_snapshot.py"
spec = importlib.util.spec_from_file_location("plugin_snapshot", SCRIPT)
plugin_snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin_snapshot)


class PluginSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "some ' plugin.so"
        self.source.write_bytes(b"\x7fELFversion one")
        self.cache = self.root / "cache"

    def snapshot(self):
        return plugin_snapshot.snapshot(self.source, self.cache)

    def test_unchanged_content_keeps_path_and_inode(self):
        first = self.snapshot()
        inode = first.stat().st_ino
        self.source.write_bytes(self.source.read_bytes())  # timestamp alone is irrelevant
        self.assertEqual(self.snapshot(), first)
        self.assertEqual(first.stat().st_ino, inode)

    def test_rebuild_changes_path_without_touching_old_copy(self):
        first = self.snapshot()
        old_data = first.read_bytes()
        old_inode = first.stat().st_ino
        self.source.write_bytes(b"\x7fELFversion two")
        second = self.snapshot()
        self.assertNotEqual(first, second)
        self.assertEqual(first.read_bytes(), old_data)
        self.assertEqual(first.stat().st_ino, old_inode)
        self.assertEqual(second.read_bytes(), self.source.read_bytes())
        # Simulate Hyprland's declared-path comparison, including its own reload.
        declarations = [first, first, second, second, second]
        self.assertEqual(sum(a != b for a, b in zip(declarations, declarations[1:])), 1)

    def test_missing_or_non_elf_file_is_rejected(self):
        self.source.write_bytes(b"incomplete linker output")
        with self.assertRaises(ValueError):
            self.snapshot()
        self.source.unlink()
        with self.assertRaises(FileNotFoundError):
            self.snapshot()

    def test_source_changing_during_read_is_rejected(self):
        before = self.source.stat()
        after = SimpleNamespace(st_size=before.st_size, st_mtime_ns=before.st_mtime_ns + 1,
                                st_ctime_ns=before.st_ctime_ns)
        with mock.patch.object(plugin_snapshot.os, "fstat", side_effect=[before, after]):
            with self.assertRaisesRegex(ValueError, "changed while reading"):
                self.snapshot()

    def test_corrupt_cache_is_not_overwritten(self):
        cached = self.snapshot()
        cached.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "cache corrupted"):
            self.snapshot()
        self.assertEqual(cached.read_bytes(), b"corrupt")

    def test_concurrent_sessions_publish_the_same_snapshot(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            results = list(executor.map(lambda _: self.snapshot(), range(8)))
        self.assertEqual(len(set(results)), 1)
        self.assertEqual(list(results[0].parent.iterdir()), [results[0]])

    def test_cli_outputs_one_absolute_path_in_xdg_cache(self):
        env = {**os.environ, "XDG_CACHE_HOME": str(self.cache)}
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.source)],
                                env=env, text=True, capture_output=True, check=True)
        self.assertEqual(result.stderr, "")
        self.assertEqual(len(result.stdout.splitlines()), 1)
        cached = Path(result.stdout.strip())
        self.assertTrue(cached.is_relative_to(self.cache))
        self.assertEqual(cached.read_bytes(), self.source.read_bytes())


if __name__ == "__main__":
    unittest.main()
