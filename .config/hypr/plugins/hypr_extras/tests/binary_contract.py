"""Read-only check of the installed executable's relevant call sites (not a live test)."""
import re
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


binary = sys.argv[1]
revision = "efb50993780079460b0cbed1363e2166a2de1d9f"
assert revision in run(binary, "--version"), "unreviewed Hyprland version"

symbols = {}
for line in run("nm", "-D", "-S", "-C", "--defined-only", binary).splitlines():
    match = re.fullmatch(r"([0-9a-f]+) ([0-9a-f]+) T (.+)", line)
    if match:
        address, size, name = match.groups()
        symbols[name] = (int(address, 16), int(size, 16))

refocus = "CInputManager::refocus(std::optional<Hyprutils::Math::Vector2D>)"
mouse = "CInputManager::mouseMoveUnified(unsigned int, bool, bool, std::optional<Hyprutils::Math::Vector2D>)"
monitor = "Desktop::CFocusState::rawMonitorFocus(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"
window = "Desktop::View::CWindow::unmapWindow()"
layer = "Desktop::View::CLayerSurface::onUnmap()"
history = "CInputManager::refocusLastWindow(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"


def calls(name):
    address, size = symbols[name]
    assert size, f"missing function size: {name}"
    assembly = run("objdump", "-d", "-C", "--no-show-raw-insn",
                   f"--start-address={address}", f"--stop-address={address + size}", binary)
    # Ignore internal branches (+0x...), but include tail calls to whole functions.
    return re.findall(r"\b(?:call|jmp)\s+[0-9a-f]+ <(.+)>\s*$", assembly, re.MULTILINE)


assert calls(window).count(refocus) == 1, "window fallback moved/inlined: review hooks"
assert calls(layer).count(refocus) == 1, "layer fallback moved/inlined: review hooks"
assert calls(layer).count(history) == 1, "layer history restoration changed"
history_calls = calls(history)
assert history_calls.count(mouse) + history_calls.count(refocus) == 2, "history fallback call sites changed"
assert calls(refocus).count(mouse) == 1, "refocus no longer forwards to mouseMoveUnified"
assert calls(mouse).count(monitor) == 1, "mouse monitor-focus call site changed"
# A focused window must still be able to focus its own monitor independently.
window_focus = next(name for name in symbols if name.startswith("Desktop::CFocusState::rawWindowFocus("))
assert calls(window_focus).count(monitor) == 1, "window monitor-focus call site changed"
print("PASS installed-binary call sites, inline/tail-call coverage and explicit window focus")
