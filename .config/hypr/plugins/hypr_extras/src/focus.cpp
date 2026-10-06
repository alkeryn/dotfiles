#include "focus.hpp"

#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <array>
#include <optional>
#include <stdexcept>
#include <utility>

class CInputManager;
namespace Desktop { class CFocusState; }

// Call-site semantics must be rechecked on upgrades, not just recompiled blindly.
static_assert(std::string_view(GIT_COMMIT_HASH) == "efb50993780079460b0cbed1363e2166a2de1d9f",
              "Review the focus hooks for this Hyprland revision before updating this guard");
static_assert(sizeof(void*) == 8);

namespace extras::focus {
namespace {
using refocus_fn = void (*)(CInputManager*, std::optional<Vector2D>);
using mouse_move_fn = void (*)(CInputManager*, uint32_t, bool, bool, std::optional<Vector2D>);
using monitor_focus_fn = void (*)(Desktop::CFocusState*, PHLMONITOR);

CFunctionHook* refocus_hook = nullptr;
CFunctionHook* mouse_move_hook = nullptr;
CFunctionHook* monitor_focus_hook = nullptr;
std::array<function_span, 3> fallback_callers;
function_span mouse_move_source;
std::optional<CConfigValue<Config::INTEGER>> follow_mouse;
std::optional<CConfigValue<Config::INTEGER>> mouse_focuses_monitor;

bool suppress_fallback(const void* caller) {
    if (**follow_mouse == 1)
        return false;
    for (const auto& function : fallback_callers) {
        if (function.contains(caller))
            return true;
    }
    return false;
}

// Only inspect our immediate return address. The hook trampoline uses jumps,
// so this is the native call site, not a guessed stack frame or fixed offset.
void on_refocus(CInputManager* self, std::optional<Vector2D> position) {
    const auto caller = __builtin_extract_return_addr(__builtin_return_address(0));
    if (!suppress_fallback(caller))
        reinterpret_cast<refocus_fn>(refocus_hook->m_original)(self, position);
}

void on_mouse_move(CInputManager* self, uint32_t time, bool refocus, bool mouse, std::optional<Vector2D> position) {
    const auto caller = __builtin_extract_return_addr(__builtin_return_address(0));
    // GCC inlines refocus() in refocusLastWindow(). It also tail-calls this
    // function from refocus(). Cover both without blocking real mouse motion.
    if (refocus && suppress_fallback(caller))
        return;
    reinterpret_cast<mouse_move_fn>(mouse_move_hook->m_original)(self, time, refocus, mouse, position);
}

void on_monitor_focus(Desktop::CFocusState* self, PHLMONITOR monitor) {
    const auto caller = __builtin_extract_return_addr(__builtin_return_address(0));
    // This direct call is the PR's (*mouse_focuses_monitor || refocus) branch.
    // If mouse_focuses_monitor is false, reaching it already implies refocus.
    // Calls from rawWindowFocus (including clicks) and dispatchers pass through.
    if (**follow_mouse != 1 && !**mouse_focuses_monitor && mouse_move_source.contains(caller))
        return;
    reinterpret_cast<monitor_focus_fn>(monitor_focus_hook->m_original)(self, std::move(monitor));
}
} // namespace

void init(HANDLE handle, hooks& registry) {
    follow_mouse.emplace("input:follow_mouse");
    mouse_focuses_monitor.emplace("misc:mouse_move_focuses_monitor");
    if (!follow_mouse->good() || !mouse_focuses_monitor->good())
        throw std::runtime_error("hypr_extras: required focus configuration is unavailable");

    // These three native functions call refocus only at the fallback sites
    // changed by PR #12998. Leave all their other work (including candidate
    // selection, layer cleanup and refocusLastWindow's return value) untouched.
    fallback_callers = {
        find_function(handle, "unmapWindow", "Desktop::View::CWindow::unmapWindow()"),
        find_function(handle, "onUnmap", "Desktop::View::CLayerSurface::onUnmap()"),
        find_function(handle, "refocusLastWindow", "CInputManager::refocusLastWindow(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"),
    };
    const auto refocus_source = find_function(handle, "refocus", "CInputManager::refocus(std::optional<Hyprutils::Math::Vector2D>)");
    mouse_move_source = find_function(handle, "mouseMoveUnified",
        "CInputManager::mouseMoveUnified(unsigned int, bool, bool, std::optional<Hyprutils::Math::Vector2D>)");
    const auto monitor_source = find_function(handle, "rawMonitorFocus",
        "Desktop::CFocusState::rawMonitorFocus(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)");

    refocus_hook = registry.add(refocus_source, reinterpret_cast<void*>(&on_refocus));
    mouse_move_hook = registry.add(mouse_move_source, reinterpret_cast<void*>(&on_mouse_move));
    monitor_focus_hook = registry.add(monitor_source, reinterpret_cast<void*>(&on_monitor_focus));
}

void reset() {
    follow_mouse.reset();
    mouse_focuses_monitor.reset();
    refocus_hook = mouse_move_hook = monitor_focus_hook = nullptr;
}
} // namespace extras::focus
