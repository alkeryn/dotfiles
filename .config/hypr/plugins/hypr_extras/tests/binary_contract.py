"""Read-only check of the installed executable's relevant call sites (not a live test)."""
import re
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


binary = sys.argv[1]
revision = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
assert revision in run(binary, "--version"), "unreviewed Hyprland version"

symbols = {}
for line in run("nm", "-D", "-S", "-C", "--defined-only", binary).splitlines():
    match = re.fullmatch(r"([0-9a-f]+) ([0-9a-f]+) T (.+)", line)
    if match:
        address, size, name = match.groups()
        symbols[name] = (int(address, 16), int(size, 16))

refocus = "CInputManager::refocus(std::optional<Hyprutils::Math::Vector2D>)"
mouse = "CInputManager::mouseMoveUnified(unsigned int, bool, bool, std::optional<Hyprutils::Math::Vector2D>, bool)"
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

# Geometry now hooks the backend's configure INPUT, before its cache and ack
# record are written. The old schedule hook ran between setSize and ack.add:
# changing only pendingApply there made wire and recorded sizes disagree.
schedule = "CXDGToplevelResource::scheduleStateApplication()"
set_size = "CXDGToplevelResource::setSize(Hyprutils::Math::Vector2D const&)"
surface_schedule = "CXDGSurfaceResource::scheduleConfigure()"
set_size_calls = calls(set_size)
assert set_size_calls.count(schedule) == 1
assert set_size_calls.count(surface_schedule) == 1
assert set_size_calls.index(schedule) < set_size_calls.index(surface_schedule)
# 0.57 moves protocol size/ack ownership from CWindow to its Wayland backend.
configure = "Desktop::View::CWaylandBackend::configure(Hyprutils::Math::CBox const&, Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>, bool)"
configure_calls = calls(configure)
ack_add = "Desktop::View::CWindowConfigureAckTracker::add(unsigned int, Hyprutils::Math::Vector2D const&)"
assert configure_calls.count(set_size) == 1
assert configure_calls.count(ack_add) == 1
assert configure_calls.index(set_size) < configure_calls.index(ack_add), "backend configure/ack ordering changed"
for setter in ("setMaximized", "setFullscreen", "setActive", "setResizing"):
    assert calls(f"CXDGToplevelResource::{setter}(bool)").count(schedule) == 1, f"{setter} state scheduling changed"
# setSuspeneded inlines scheduling in this binary. It only changes SUSPENDED,
# not size/tiling; leave it native. Floating changes force the configure path.
assert set_size not in calls("CXDGToplevelResource::setSuspeneded(bool)")
assert any(name.startswith("CEventLoopManager::doLaterLock(") for name in calls(schedule))
print("PASS installed-binary backend configure hook, ack recording order and native state scheduling")

# Only the unsolicited fullscreen preference is suppressed, not HDR capability
# or the renderer's detection of actual submitted HDR-format surfaces. The
# preferred-description call must remain out-of-line for the native hook.
auto_hdr = "Monitor::CMonitor::getAutoHDRImageDescription(Hyprutils::Memory::CSharedPointer<CWLSurfaceResource> const&)"
preferred = "CWLSurfaceResource::getPreferredImageDescription()"
fullscreen_settings = "Render::IHyprRenderer::handleFullscreenSettings(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"
assert symbols[auto_hdr][1] > 0, "missing HDR feedback hook target"
assert calls(preferred).count(auto_hdr) == 1, "preferred HDR lookup moved/inlined: review hook"
assert "CCompositor::getHDRImageDescription()" in calls(preferred), "explicit prefer_hdr quirk path changed"
assert "CCompositor::getPreferredImageDescription()" in calls(preferred), "no-monitor fallback changed"
assert auto_hdr not in calls(fullscreen_settings), "feedback lookup is now used to control HDR output"
assert calls(fullscreen_settings).count("CColorManagementSurface::isHDR()") == 1, "native submitted-HDR detection changed"
print("PASS installed-binary HDR preference hook and independent native HDR output detection")
