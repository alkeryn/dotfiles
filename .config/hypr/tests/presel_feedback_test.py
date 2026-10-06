"""Script-only tests with synthetic outputs; no connected displays required."""
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "presel_feedback.py"
spec = importlib.util.spec_from_file_location("presel_feedback", SCRIPT)
feedback = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = feedback
spec.loader.exec_module(feedback)


def monitor_fixture(index, origin=(0, 0), size=(1200, 800)):
    return {"name": f"fixture-output-{index}", "geometry": (*origin, *size)}


def preview_fixture(monitor, box=(20, 30, 200, 100)):
    return feedback.Preview(monitor["name"], box, monitor["geometry"])


def state_for(previews):
    return json.dumps({"version": 3, "rectangles": [
        {"output": p.output, "box": p.box, "monitor": p.monitor} for p in previews]})


class FeedbackTests(unittest.TestCase):
    def test_parse_state(self):
        monitor = monitor_fixture(1, origin=(-1200, 20))
        preview = preview_fixture(monitor)
        self.assertEqual(feedback.parse_state(state_for([preview])), [preview])
        self.assertEqual(feedback.parse_state(state_for([])), [])

    def test_names_are_arbitrary_runtime_data(self):
        monitor = monitor_fixture(2)
        for name in [monitor["name"], "fixture with spaces", 'fixture "quoted"\\name', "écran fictif"]:
            with self.subTest(name=name):
                monitor["name"] = name
                preview = preview_fixture(monitor)
                self.assertEqual(feedback.parse_state(state_for([preview])), [preview])
                result, unmatched = feedback.placements([preview], [monitor["geometry"]])
                self.assertEqual(result, {(0, 0): preview.box})
                self.assertFalse(unmatched)

    def test_lua_wire_format_round_trip(self):
        monitor = monitor_fixture(8, origin=(-1200, 20))
        monitor["name"] += ' "quoted"\\écran\n'
        preview = preview_fixture(monitor)
        x, y, w, h = preview.box
        mx, my, mw, mh = preview.monitor
        source = f'''local feedback = require("lua/presel_feedback")
io.write(feedback.encode({{{{output=arg[1], x={mx+x}, y={my+y}, w={w}, h={h},
monitor_x={mx}, monitor_y={my}, monitor_w={mw}, monitor_h={mh}}}}}))'''
        result = subprocess.run(["lua", "-", preview.output], input=source, text=True,
                                cwd=SCRIPT.parents[1], capture_output=True, check=True)
        self.assertEqual(feedback.parse_state(result.stdout), [preview])

    def test_monitor_order_is_not_identity(self):
        left = monitor_fixture(1, origin=(-1200, 0))
        right = monitor_fixture(2, origin=(0, 0), size=(1600, 1000))
        previews = [preview_fixture(left), preview_fixture(right, (700, 60, 500, 900))]
        for monitors in [[left, right], [right, left]]:
            with self.subTest(order=[m["name"] for m in monitors]):
                result, missing = feedback.placements(previews, [m["geometry"] for m in monitors])
                self.assertFalse(missing)
                for i, monitor in enumerate([left, right]):
                    self.assertEqual(result[(i, monitors.index(monitor))], previews[i].box)

    def test_logical_coordinates_are_not_scaled_twice(self):
        monitor = monitor_fixture(1, origin=(1500, 40), size=(1000, 750))
        preview = preview_fixture(monitor, (500, 30, 500, 700))
        result, missing = feedback.placements([preview], [monitor["geometry"]])
        self.assertEqual(result, {(0, 0): preview.box})
        self.assertFalse(missing)

    def test_missing_or_ambiguous_monitor_is_hidden(self):
        monitor = monitor_fixture(1)
        preview = preview_fixture(monitor)
        for monitors in [[], [monitor["geometry"], monitor["geometry"]], [(1, 0, 1200, 800)]]:
            result, missing = feedback.placements([preview], monitors)
            self.assertFalse(result)
            self.assertEqual(missing, {monitor["name"]})

    def test_rectangles_clip_to_output(self):
        monitor = monitor_fixture(1, size=(1000, 700))
        preview = preview_fixture(monitor, (900, 650, 200, 100))
        result, _ = feedback.placements([preview], [monitor["geometry"]])
        self.assertEqual(result, {(0, 0): (900, 650, 100, 50)})

    def test_invalid_state_is_rejected(self):
        monitor = monitor_fixture(1)
        entry = {"output": monitor["name"], "box": [0, 0, 10, 10], "monitor": list(monitor["geometry"])}
        invalid = [None, [], {}, {"version": True, "rectangles": []}, {"version": 2, "rectangles": []},
                   {"version": 3, "rectangles": [None]}, {"version": 3, "rectangles": "bad"}]
        for field, value in [("box", [0, 0, 0, 10]), ("box", [-1, 0, 10, 10]),
                             ("box", [0, 0, True, 10]), ("box", [0, 0, float("nan"), 10]),
                             ("monitor", [0, 0, 10]), ("output", ""), ("output", 123)]:
            invalid.append({"version": 3, "rectangles": [dict(entry, **{field: value})]})
        for state in invalid:
            with self.subTest(state=state), self.assertRaises(ValueError):
                feedback.parse_state(json.dumps(state))
        with self.assertRaises(ValueError):
            feedback.parse_state(" " * (feedback.MAX_STATE_BYTES + 1))
        with self.assertRaises(ValueError):
            feedback.parse_state(state_for([preview_fixture(monitor)] * (feedback.MAX_RECTANGLES + 1)))

    def test_color_is_opaque_and_uniform_without_outline(self):
        import cairo
        width, height = 120, 80
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
        feedback.draw_feedback(cairo.Context(surface), width, height)
        surface.flush()
        pixels = memoryview(surface.get_data()).cast("I")
        self.assertEqual(set(pixels), {0xFF100000})

    def test_process_identity_requires_exact_state_and_known_program(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(os.environ, {"XDG_CACHE_HOME": directory}):
            state = Path(directory) / "session.state"
            native = str(feedback.native_cache_dir() / "presel_feedback")
            python = str(Path(sys.executable).resolve())
            script = str(SCRIPT)
            self.assertTrue(feedback.process_matches([native, "--state", str(state)], native, state))
            self.assertTrue(feedback.process_matches([python, script, "--state", str(state)], python, state))
            self.assertFalse(feedback.process_matches([native, "--state", str(state)+"-other"], native, state))
            self.assertFalse(feedback.process_matches([native, "--state", str(state)], "/unrelated/program", state))
            self.assertFalse(feedback.process_matches([python, "--state", str(state)], python, state))

    def test_run_creates_lock_without_any_build_step(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "session.state"
            with mock.patch.object(feedback, "run_gtk", return_value=0) as run_gtk:
                self.assertEqual(feedback.run(state), 0)
                run_gtk.assert_called_once_with(state)
                lines = Path(str(state) + ".lock").read_text().splitlines()
                self.assertEqual(lines, [str(os.getpid()), feedback.script_version()])
                self.assertEqual({p.name for p in Path(directory).iterdir()}, {"session.state.lock"})

    def test_legacy_lock_refusal_does_not_block_versioned_renderer(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            legacy = Path(directory) / "session.state"
            current = Path(directory) / "session.v3.json"
            with open(str(legacy) + ".lock", "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                refusal = RuntimeError("feedback lock owner is not a recognized helper; left untouched")
                with mock.patch.object(feedback, "retire_previous", side_effect=refusal) as retire, \
                     mock.patch.object(feedback, "run_gtk", return_value=0) as run_gtk, \
                     mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
                    self.assertEqual(feedback.run(current, [legacy]), 0)
                    retire.assert_called_once()
                    run_gtk.assert_called_once_with(current)
                    self.assertIn("legacy cleanup skipped", stderr.getvalue())
                # The old lock stays owned; startup must not bypass its guard.
                with open(str(legacy) + ".lock", "a+") as other:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_legacy_cleanup_failures_do_not_skip_other_legacy_sessions(self):
        with tempfile.TemporaryDirectory() as directory:
            current = Path(directory) / "session.v3.json"
            legacy = [Path(directory) / "session.state", Path(directory) / "session.json"]
            with mock.patch.object(feedback, "retire_legacy", side_effect=[PermissionError("denied"), None]) as retire, \
                 mock.patch.object(feedback, "run_gtk", return_value=0) as run_gtk, \
                 mock.patch("sys.stderr", new_callable=io.StringIO):
                self.assertEqual(feedback.run(current, legacy), 0)
                self.assertEqual(retire.call_args_list, [mock.call(path) for path in legacy])
                run_gtk.assert_called_once_with(current)

    def test_current_protocol_lock_guard_is_not_bypassed(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            current = Path(directory) / "session.v3.json"
            with open(str(current) + ".lock", "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with mock.patch.object(feedback, "retire_previous", side_effect=RuntimeError("unrecognized owner")), \
                     mock.patch.object(feedback, "run_gtk") as run_gtk:
                    with self.assertRaisesRegex(RuntimeError, "unrecognized owner"):
                        feedback.run(current)
                    run_gtk.assert_not_called()

    def test_cli_accepts_both_legacy_protocols(self):
        with tempfile.TemporaryDirectory() as directory:
            current = Path(directory) / "session.v3.json"
            legacy = [Path(directory) / "session.state", Path(directory) / "session.json"]
            argv = ["presel_feedback.py", "--state", str(current)]
            for path in legacy:
                argv.extend(["--legacy-state", str(path)])
            with mock.patch.object(sys, "argv", argv), mock.patch.object(feedback, "run", return_value=0) as run:
                self.assertEqual(feedback.main(), 0)
                run.assert_called_once_with(current, legacy)

    def test_duplicate_run_does_not_open_another_display(self):
        import fcntl
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "session.state"
            with open(str(state) + ".lock", "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with mock.patch.object(feedback, "retire_previous", return_value=False), \
                     mock.patch.object(feedback, "run_gtk") as run_gtk:
                    self.assertEqual(feedback.run(state), 0)
                    run_gtk.assert_not_called()


if __name__ == "__main__":
    unittest.main()
