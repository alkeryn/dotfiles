"""Script-only, click-through preselection display for Hyprland.

Geometry comes from Lua. GTK/layer-shell only displays translucent rectangles;
there is no compiler, generated protocol code, plugin or custom executable.
"""
import argparse
from dataclasses import dataclass
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import sys

MAX_STATE_BYTES = 131072
MAX_RECTANGLES = 256
NAMESPACE = "bspwm-presel-feedback"
COLOR = (16 / 255, 0, 0)  # bspwm's #100000, no outline
OPACITY = 0.5  # original picom.conf: 50:class_g='Bspwm' && class_i='presel_feedback'


@dataclass(frozen=True)
class Preview:
    output: str
    box: tuple
    monitor: tuple


def parse_box(value, local=False):
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError("invalid geometry")
    if any(type(number) is not int or abs(number) > 1_000_000 for number in value):
        raise ValueError("invalid coordinates")
    x, y, width, height = value
    if width <= 0 or height <= 0 or (local and (x < 0 or y < 0)):
        raise ValueError("invalid rectangle size/position")
    return tuple(value)


def parse_state(data):
    if len(data) > MAX_STATE_BYTES:
        raise ValueError("feedback state is too large")
    state = json.loads(data)
    if not isinstance(state, dict) or type(state.get("version")) is not int or state["version"] != 3:
        raise ValueError("unsupported feedback state version")
    rectangles = state.get("rectangles")
    if not isinstance(rectangles, list) or len(rectangles) > MAX_RECTANGLES:
        raise ValueError("invalid rectangle list")
    result = []
    for entry in rectangles:
        if not isinstance(entry, dict):
            raise ValueError("invalid rectangle")
        name = entry.get("output")
        if not isinstance(name, str) or not name or len(name) > 1024:
            raise ValueError("invalid output name")
        result.append(Preview(name, parse_box(entry.get("box"), local=True),
                              parse_box(entry.get("monitor"))))
    return result


def placements(previews, monitor_boxes):
    """Match runtime logical monitor bounds, never an index or a device name.

    GTK3 does not expose a portable connector getter. Lua exports full logical
    output bounds to identify the GDK monitor. Hide ambiguous/unmatched outputs
    rather than silently drawing on the wrong display. No second scale factor.
    """
    result, unmatched = {}, set()
    for index, preview in enumerate(previews):
        matches = [i for i, box in enumerate(monitor_boxes) if tuple(box) == preview.monitor]
        if len(matches) != 1:
            unmatched.add(preview.output)
            continue
        x, y, width, height = preview.box
        mw, mh = preview.monitor[2:]
        right, bottom = min(x + width, mw), min(y + height, mh)
        if right > x and bottom > y:
            result[(index, matches[0])] = (x, y, right - x, bottom - y)
    return result, unmatched


def draw_feedback(context, width, height):
    import cairo
    # Replace rather than blend with the previous frame: repeated redraws
    # must retain the original picom rule's 50% opacity.
    context.set_operator(cairo.OPERATOR_SOURCE)
    context.set_source_rgba(*COLOR, OPACITY)
    context.rectangle(0, 0, width, height)
    context.fill()


def native_cache_dir():
    return Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "hypr" / "presel_feedback"


def script_version():
    stat = Path(__file__).stat()
    return f"{stat.st_mtime_ns}:{stat.st_size}"


def process_matches(argv, executable, state_path):
    """Recognize only this script or the previous helper for this exact state."""
    state_matches = any(arg == "--state" and argv[i + 1] == str(state_path)
                        for i, arg in enumerate(argv[:-1]))
    if not state_matches:
        return False
    native = str(native_cache_dir() / "presel_feedback")
    python = str(Path(sys.executable).resolve())
    script = str(Path(__file__).resolve())
    return (executable == native and argv[0] == native) or (executable == python and script in argv)


def retire_previous(lock, state_path):
    """Retire only a verified stale helper, using a pidfd to avoid PID reuse."""
    lock.seek(0)
    metadata = lock.read(256).splitlines()
    if not metadata:
        raise RuntimeError("feedback lock has no process identity")
    pid = int(metadata[0])
    if pid <= 1 or pid == os.getpid():
        raise RuntimeError("invalid feedback process identity")
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return True
    try:
        proc = Path(f"/proc/{pid}")
        if proc.stat().st_uid != os.getuid():
            raise RuntimeError("feedback lock belongs to another user")
        argv = (proc / "cmdline").read_bytes().decode().rstrip("\0").split("\0")
        executable = os.readlink(proc / "exe").removesuffix(" (deleted)")
        if not process_matches(argv, executable, state_path):
            raise RuntimeError("feedback lock owner is not a recognized helper; left untouched")
        if len(metadata) > 1 and metadata[1] == script_version():
            return False  # this version is already serving the state
        signal.pidfd_send_signal(fd, signal.SIGTERM)
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        if not poller.poll(2000):
            raise RuntimeError("previous feedback helper did not exit")
        return True
    except (FileNotFoundError, ProcessLookupError):
        return True  # previous process exited while its identity was checked
    finally:
        os.close(fd)


def retire_legacy(state_path):
    if state_path is None:
        return
    try:
        lock = open(str(state_path) + ".lock", "r")
    except FileNotFoundError:
        return
    with lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            retire_previous(lock, state_path)


def run(state_path, legacy_states=()):
    with open(str(state_path) + ".lock", "a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if not retire_previous(lock, state_path):
                return 0
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock.seek(0)
        lock.truncate()
        lock.write(f"{os.getpid()}\n{script_version()}\n")
        lock.flush()
        # Legacy helpers use other protocol files/locks. Failure to identify
        # one must never prevent this renderer from starting on its own file.
        for legacy in legacy_states:
            if legacy == state_path:
                continue
            try:
                retire_legacy(legacy)
            except (OSError, ValueError, RuntimeError) as error:
                print(f"preselection feedback: legacy cleanup skipped for {legacy}: {error}",
                      file=sys.stderr, flush=True)
        return run_gtk(state_path)


def run_gtk(state_path):
    os.environ["GDK_BACKEND"] = "wayland"  # never create fallback X11 windows
    import gi
    gi.require_foreign("cairo")
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import Gtk, Gdk, GtkLayerShell, GLib
    import cairo

    initialized, _ = Gtk.init_check([])
    if not initialized or not GtkLayerShell.is_supported():
        raise RuntimeError("a Wayland display with layer-shell support is required")

    class FeedbackWindow(Gtk.Window):
        def __init__(self, monitor):
            super().__init__(type=Gtk.WindowType.TOPLEVEL)
            self.monitor, self.geometry = monitor, None
            self.set_decorated(False)
            self.set_accept_focus(False)
            self.set_focus_on_map(False)
            self.set_app_paintable(True)
            visual = self.get_screen().get_rgba_visual()
            if visual is None:
                raise RuntimeError("RGBA visual unavailable")
            self.set_visual(visual)
            GtkLayerShell.init_for_window(self)
            GtkLayerShell.set_namespace(self, NAMESPACE)
            GtkLayerShell.set_monitor(self, monitor)
            GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
            # Coordinates already account for panels; do not offset them again.
            GtkLayerShell.set_exclusive_zone(self, -1)
            for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.LEFT):
                GtkLayerShell.set_anchor(self, edge, True)
            self.connect("realize", self.make_click_through)
            self.connect("map", self.make_click_through)
            self.connect("draw", self.draw)

        def make_click_through(self, *_args):
            self.input_shape_combine_region(cairo.Region())

        def draw(self, _widget, context):
            draw_feedback(context, self.get_allocated_width(), self.get_allocated_height())
            return True

        def update(self, geometry):
            if geometry == self.geometry:
                return
            self.geometry = geometry
            x, y, width, height = geometry
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, x)
            GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, y)
            self.set_size_request(width, height)
            self.resize(width, height)
            self.show_all()
            self.queue_draw()

    display = Gdk.Display.get_default()
    overlays, previews, unmatched = {}, [], set()
    last_stamp = object()

    def refresh():
        nonlocal previews, last_stamp, unmatched
        try:
            stat = state_path.stat()
            stamp = (stat.st_ino, stat.st_mtime_ns, stat.st_size)
        except FileNotFoundError:
            stamp = None
        if stamp != last_stamp:
            last_stamp = stamp
            try:
                if stamp is None:
                    previews = []
                else:
                    with state_path.open("rb") as stream:
                        previews = parse_state(stream.read(MAX_STATE_BYTES + 1))
            except (OSError, ValueError) as error:
                previews = []  # never retain feedback over the wrong workspace
                print(f"preselection feedback: {error}", file=sys.stderr, flush=True)
        monitors = [display.get_monitor(i) for i in range(display.get_n_monitors())]
        boxes = []
        for monitor in monitors:
            geometry = monitor.get_geometry()
            boxes.append((geometry.x, geometry.y, geometry.width, geometry.height))
        desired, missing = placements(previews, boxes)
        if missing != unmatched:
            unmatched = missing
            if missing:
                print(f"preselection feedback: no unique GDK geometry match for {sorted(missing)}",
                      file=sys.stderr, flush=True)
        for key in list(overlays):
            if key not in desired or overlays[key].monitor != monitors[key[1]]:
                overlays.pop(key).destroy()
        for key, geometry in desired.items():
            if key not in overlays:
                overlays[key] = FeedbackWindow(monitors[key[1]])
            overlays[key].update(geometry)
        return GLib.SOURCE_CONTINUE

    def stop():
        for overlay in overlays.values():
            overlay.destroy()
        overlays.clear()
        Gtk.main_quit()
        return GLib.SOURCE_REMOVE

    def safe_refresh():
        try:
            return refresh()
        except Exception as error:
            print(f"preselection feedback stopped: {error}", file=sys.stderr, flush=True)
            stop()
            return GLib.SOURCE_REMOVE

    def refresh_once():
        safe_refresh()
        return GLib.SOURCE_REMOVE

    GLib.timeout_add(50, safe_refresh)
    GLib.idle_add(refresh_once)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    Gtk.main()
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--legacy-state", type=Path, action="append", default=[])
    args = parser.parse_args()
    try:
        return run(args.state, args.legacy_state)
    except (OSError, ImportError, ValueError, RuntimeError) as error:
        print(f"preselection feedback: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
