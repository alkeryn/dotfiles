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


def disassemble(name):
    address, size = symbols[name]
    assert size, f"missing function size: {name}"
    return run("objdump", "-d", "-C", "--no-show-raw-insn",
               f"--start-address={address}", f"--stop-address={address + size}", binary)


def calls(name):
    # Ignore internal branches (+0x...), but include tail calls to whole functions.
    return re.findall(r"\b(?:call|jmp)\s+[0-9a-f]+ <(.+)>\s*$", disassemble(name), re.MULTILINE)


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
# The session manager emits unlock, tears down its lock surfaces, then makes
# one synchronous refocus call. The listener arms only that next forced refocus.
assert calls("CSessionLockManager::forceUnlock()").count(refocus) == 1
assert calls("CSessionLockManager::forceUnlock()").count("CSessionLockManager::clearSessionLock()") == 1
# The normal-unlock callback is local, not hookable through the dynamic API.
# objdump can read it from the installed separate debug symbols.
unlock_callbacks = []
for line in run("objdump", "-t", "-C", binary).splitlines():
    match = re.fullmatch(r"([0-9a-f]+)\s+\w+\s+F\s+\.text\s+([0-9a-f]+)\s+(.+)", line)
    if not match:
        continue
    address, size, name = match.groups()
    if ("std::_Function_handler<void (), CSessionLockManager::onNewSessionLock(" in name
            and "::_M_invoke(" in name and "[clone" not in name):
        symbols[name] = (int(address, 16), int(size, 16))
        if calls(name).count(refocus) == 1:
            unlock_callbacks.append(name)
assert len(unlock_callbacks) == 1, "normal-unlock callback changed or debug symbols unavailable"
unlock_assembly = disassemble(unlock_callbacks[0])
assert unlock_assembly.index("CSignalBase::emitInternal") < unlock_assembly.index("<" + refocus + ">")
print("PASS installed-binary close/unlock call sites, inline coverage and explicit window focus")
