// Runs the real plugin, hook registry, ELF range lookup and replacement functions.
// Only Hyprland services/trampoline installation are mocked; no compositor needed.
#include "../src/hooks.hpp"
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/helpers/cm/ColorManagement.hpp>
#include <algorithm>
#include <cassert>
#include <dlfcn.h>
#include <iostream>
#include <optional>
#include <stdexcept>

class CInputManager;
// Opaque stand-ins: the plugin only passes these through native focus APIs;
// it never accesses their layout. The native-service shims below model focus.
namespace Monitor { class CMonitor {}; }
namespace Desktop::View {
class CWindow {
  public:
    PHLMONITORREF monitor;
    bool pinned = false;
    void sendWindowSize(bool);
};
}
PPLUGIN_API_VERSION_FUNC plugin_api_version;
PPLUGIN_INIT_FUNC plugin_init;
PPLUGIN_EXIT_FUNC plugin_exit;

using refocus_fn = void (*)(CInputManager*, std::optional<Vector2D>);
using mouse_fn = void (*)(CInputManager*, uint32_t, bool, bool, std::optional<Vector2D>);
using monitor_fn = void (*)(Desktop::CFocusState*, PHLMONITOR);
using schedule_fn = void (*)(CXDGToplevelResource*);

namespace fixture {
Config::INTEGER follow = 2;
bool mouse_monitor = false;
void* follow_ptr = &follow;
void* monitor_ptr = &mouse_monitor;
int mouse_calls = 0, monitor_calls = 0, cleanup_calls = 0;
uint32_t last_time = 0;
bool last_refocus = false, last_mouse = false, focus_window = false;
std::optional<Vector2D> last_position;
std::string abi;
std::string missing, ambiguous;
int fail_hook = 0, hook_attempts = 0, create_attempts = 0, fail_create = 0;
std::vector<CFunctionHook*> live_hooks;
std::vector<void*> removed;
bool session_locked = false;
PHLMONITOR current_monitor, cursor_monitor;
PHLWINDOWREF remembered_window, keyboard_window;
int restore_calls = 0, surface_clear_calls = 0, schedule_calls = 0;

void clear_counts() {
    mouse_calls = monitor_calls = cleanup_calls = 0;
    restore_calls = surface_clear_calls = 0;
    focus_window = false;
    last_position.reset();
}
}

// Named, exported, non-inlined functions provide real ELF bounds/return addresses.
#define NATIVE extern "C" __attribute__((noinline))
NATIVE void native_refocus(CInputManager*, std::optional<Vector2D>);
NATIVE void native_mouse(CInputManager*, uint32_t, bool, bool, std::optional<Vector2D>);
NATIVE void native_monitor(Desktop::CFocusState*, PHLMONITOR);
NATIVE void native_schedule(CXDGToplevelResource*) { ++fixture::schedule_calls; }
schedule_fn schedule_entry = native_schedule;
refocus_fn refocus_entry = native_refocus;
mouse_fn mouse_entry = native_mouse;
monitor_fn monitor_entry = native_monitor;

NATIVE void native_window_focus() { monitor_entry(nullptr, {}); }
NATIVE void native_monitor(Desktop::CFocusState*, PHLMONITOR monitor) {
    ++fixture::monitor_calls;
    fixture::current_monitor = monitor;
}
NATIVE void native_mouse(CInputManager*, uint32_t time, bool refocus, bool mouse, std::optional<Vector2D> position) {
    ++fixture::mouse_calls;
    fixture::last_time = time;
    fixture::last_refocus = refocus;
    fixture::last_mouse = mouse;
    fixture::last_position = position;
    if (fixture::mouse_monitor || refocus)
        monitor_entry(nullptr, fixture::cursor_monitor);
    if (fixture::focus_window)
        native_window_focus();
}
NATIVE void native_refocus(CInputManager* self, std::optional<Vector2D> position) {
    mouse_entry(self, 0, true, false, position);
}
NATIVE void native_explicit_refocus() { refocus_entry(nullptr, {}); }
NATIVE void native_unmap(bool inlined, bool candidate, bool callback) {
    if (callback)
        native_explicit_refocus(); // reentrant explicit action is NOT a fallback
    if (candidate)
        native_window_focus();
    else if (inlined)
        mouse_entry(nullptr, 0, true, false, {});
    else
        refocus_entry(nullptr, {});
    ++fixture::cleanup_calls;
}
NATIVE void native_layer_unmap(bool inlined) {
    if (inlined)
        mouse_entry(nullptr, 0, true, false, {});
    else
        refocus_entry(nullptr, {});
    ++fixture::cleanup_calls;
    // The real layer unmap also simulates ordinary mouse motion afterward.
    mouse_entry(nullptr, 91, false, true, {});
}
NATIVE bool native_last_window(bool inlined, bool candidate) {
    if (candidate)
        native_window_focus();
    else if (inlined)
        mouse_entry(nullptr, 0, true, false, {});
    else
        refocus_entry(nullptr, {});
    return true;
}

// Minimal native-service shims, compiled against the installed headers.
// Geometry uses real CWindow fields; these opaque focus fixtures must NEVER be
// passed to it. Its policy has separate tests; here we test lifecycle, symbol
// binding and the real hook's orphan-resource pass-through only.
void Desktop::View::CWindow::sendWindowSize(bool) { assert(false && "not a real window fixture"); }
CXDGToplevelResource::CXDGToplevelResource(SP<CXdgToplevel>, SP<CXDGSurfaceResource>) {}
CXDGToplevelResource::~CXDGToplevelResource() = default;
CSessionLockManager::CSessionLockManager() = default;
bool CSessionLockManager::isSessionLocked() { return fixture::session_locked; }
UP<Event::CEventBus>& Event::bus() {
    static auto bus = makeUnique<CEventBus>();
    return bus;
}
Desktop::CFocusState::CFocusState() = default;
SP<Desktop::CFocusState> Desktop::focusState() {
    static auto state = makeShared<CFocusState>();
    return state;
}
PHLMONITOR Desktop::CFocusState::monitor() { return fixture::current_monitor; }
PHLWINDOW Desktop::CFocusState::window() { return fixture::remembered_window.lock(); }
void Desktop::CFocusState::rawMonitorFocus(PHLMONITOR monitor) { monitor_entry(this, monitor); }
void Desktop::CFocusState::fullWindowFocus(PHLWINDOW window, Desktop::eFocusReason reason, SP<CWLSurfaceResource>, bool) {
    assert(!fixture::session_locked && "must NEVER restore application focus while locked");
    assert(reason == Desktop::FOCUS_REASON_DESKTOP_STATE_CHANGE);
    ++fixture::restore_calls;
    fixture::remembered_window = window;
    if (window) {
        if (!window->pinned)
            rawMonitorFocus(window->monitor.lock());
        fixture::keyboard_window = window;
    }
}
void Desktop::CFocusState::rawSurfaceFocus(SP<CWLSurfaceResource> surface, PHLWINDOW) {
    assert(!surface);
    ++fixture::surface_clear_calls;
    fixture::keyboard_window.reset();
}
WP<const NColorManagement::CImageDescription> NColorManagement::CImageDescription::from(const SImageDescription&) { return {}; }
const NColorManagement::SPCPRimaries& NColorManagement::getPrimaries(ePrimaries) {
    static const SPCPRimaries primaries{};
    return primaries;
}
CHyprColor::CHyprColor(float red, float green, float blue, float alpha) : r(red), g(green), b(blue), a(alpha) {}
Log::CLogger::CLogger() = default;
void Log::CLogger::log(Hyprutils::CLI::eLogLevel, const std::string_view& text) { std::cerr << text << '\n'; }
CConfigValueBase::CConfigValueBase() { registry().push_back(this); }
CConfigValueBase::~CConfigValueBase() { std::erase(registry(), this); }
std::vector<CConfigValueBase*>& CConfigValueBase::registry() {
    static std::vector<CConfigValueBase*> values;
    return values;
}
void CConfigValueBase::bindInternal(const std::string& name) {
    m_valueName = name;
    if (name == "input:follow_mouse") {
        m_p = &fixture::follow_ptr;
        m_typeIndex = typeid(Config::INTEGER);
    } else {
        assert(name == "misc:mouse_move_focuses_monitor");
        m_p = &fixture::monitor_ptr;
        m_typeIndex = typeid(bool);
    }
}

APICALL const char* __hyprland_api_get_hash() { return fixture::abi.c_str(); }
APICALL std::vector<SFunctionMatch> HyprlandAPI::findFunctionsByName(HANDLE, const std::string& name) {
    const std::vector<SFunctionMatch> all = {
        {(void*)&native_unmap, "unmapWindow", "Desktop::View::CWindow::unmapWindow()"},
        {(void*)&native_layer_unmap, "onUnmap", "Desktop::View::CLayerSurface::onUnmap()"},
        {(void*)&native_last_window, "refocusLastWindow", "CInputManager::refocusLastWindow(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"},
        {(void*)&native_refocus, "refocus", "CInputManager::refocus(std::optional<Hyprutils::Math::Vector2D>)"},
        {(void*)&native_mouse, "mouseMoveUnified", "CInputManager::mouseMoveUnified(unsigned int, bool, bool, std::optional<Hyprutils::Math::Vector2D>)"},
        {(void*)&native_monitor, "rawMonitorFocus", "Desktop::CFocusState::rawMonitorFocus(Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>)"},
        {(void*)&native_schedule, "scheduleStateApplication", "CXDGToplevelResource::scheduleStateApplication()"},
    };
    std::vector<SFunctionMatch> result;
    for (const auto& entry : all) {
        if (entry.signature.contains(name) && entry.signature != fixture::missing) {
            result.push_back(entry);
            if (entry.signature == fixture::ambiguous)
                result.push_back(entry);
        }
    }
    return result;
}
CFunctionHook::CFunctionHook(HANDLE owner, void* source, void* destination)
    : m_source(source), m_destination(destination), m_owner(owner) { m_original = source; }
CFunctionHook::~CFunctionHook() = default;
bool CFunctionHook::hook() {
    if (++fixture::hook_attempts == fixture::fail_hook)
        return false;
    if (m_source == (void*)&native_refocus) refocus_entry = (refocus_fn)m_destination;
    else if (m_source == (void*)&native_mouse) mouse_entry = (mouse_fn)m_destination;
    else if (m_source == (void*)&native_monitor) monitor_entry = (monitor_fn)m_destination;
    else if (m_source == (void*)&native_schedule) schedule_entry = (schedule_fn)m_destination;
    else assert(false);
    return true;
}
bool CFunctionHook::unhook() {
    if (m_source == (void*)&native_refocus) refocus_entry = native_refocus;
    if (m_source == (void*)&native_mouse) mouse_entry = native_mouse;
    if (m_source == (void*)&native_monitor) monitor_entry = native_monitor;
    if (m_source == (void*)&native_schedule) schedule_entry = native_schedule;
    fixture::removed.push_back(m_source);
    return true;
}
APICALL CFunctionHook* HyprlandAPI::createFunctionHook(HANDLE owner, const void* source, const void* destination) {
    if (++fixture::create_attempts == fixture::fail_create)
        return nullptr;
    auto* hook = new CFunctionHook(owner, const_cast<void*>(source), const_cast<void*>(destination));
    fixture::live_hooks.push_back(hook);
    return hook;
}
APICALL bool HyprlandAPI::removeFunctionHook(HANDLE, CFunctionHook* hook) {
    assert(std::ranges::find(fixture::live_hooks, hook) != fixture::live_hooks.end());
    hook->unhook();
    std::erase(fixture::live_hooks, hook);
    delete hook;
    return true;
}

void lock_session() {
    g_pSessionLockManager->m_events.lock.emit();
    fixture::session_locked = true;
    fixture::keyboard_window.reset(); // lock surfaces take keyboard focus
}

void unlock_session(bool inlined = false) {
    fixture::session_locked = false; // protocol changes this BEFORE emitting unlock
    const auto before = fixture::restore_calls;
    g_pSessionLockManager->m_events.unlock.emit();
    assert(fixture::restore_calls == before); // never restore inside the signal
    if (inlined)
        mouse_entry(nullptr, 0, true, false, {});
    else
        refocus_entry(nullptr, {});
}

void test_unlock_focus() {
    auto left = makeShared<Monitor::CMonitor>();
    auto right = makeShared<Monitor::CMonitor>();
    auto window = makeShared<Desktop::View::CWindow>();
    window->monitor = left;
    fixture::cursor_monitor = right;
    for (int mode : {0, 1, 2, 3}) {
        for (bool inlined : {false, true}) {
            for (bool pinned : {false, true}) {
                fixture::follow = mode;
                fixture::clear_counts();
                fixture::current_monitor = left;
                fixture::remembered_window = window;
                window->pinned = pinned;
                lock_session();
                fixture::current_monitor = right; // clicking the lock screen can change it
                unlock_session(inlined);
                assert(fixture::mouse_calls == (mode == 1 ? 1 : 0));
                assert(fixture::restore_calls == (mode == 1 ? 0 : 1));
                assert(fixture::current_monitor == (mode == 1 ? right : left));
                if (mode != 1)
                    assert(fixture::keyboard_window == window);
                const auto restores = fixture::restore_calls;
                native_explicit_refocus();
                assert(fixture::restore_calls == restores); // consumed, never sticky
            }
        }
    }

    fixture::follow = 2;
    fixture::clear_counts();
    unlock_session(); // forceUnlock when already unlocked: no snapshot, don't steal focus
    assert(fixture::restore_calls == 0 && fixture::mouse_calls == 1);
    fixture::clear_counts();
    fixture::current_monitor = left;
    fixture::remembered_window = window;
    lock_session();
    native_explicit_refocus(); // normal lock-screen input is unaffected
    assert(fixture::restore_calls == 0 && fixture::mouse_calls == 1);
    fixture::current_monitor = right;
    lock_session(); // locker crash/replacement: no unlock, don't overwrite saved monitor
    unlock_session();
    assert(fixture::current_monitor == left && fixture::keyboard_window == window);

    fixture::clear_counts();
    fixture::current_monitor = left;
    lock_session();
    auto other_window = makeShared<Desktop::View::CWindow>();
    other_window->monitor = right;
    fixture::remembered_window = other_window; // e.g. a focus-priority surface during lock
    unlock_session();
    assert(fixture::keyboard_window == window); // pre-lock snapshot, not the later window

    fixture::clear_counts();
    fixture::current_monitor = left;
    lock_session();
    fixture::current_monitor = right;
    fixture::remembered_window.reset(); // focused window closed while locked
    Event::bus()->m_events.window.close.emit(window); // object can survive for fade-out
    unlock_session();
    assert(fixture::current_monitor == left && !fixture::keyboard_window);
    assert(fixture::surface_clear_calls == 1 && fixture::mouse_calls == 0);

    fixture::clear_counts();
    fixture::remembered_window = window;
    lock_session();
    window.reset(); // expired snapshot also fails safely without keeping the object alive
    unlock_session();
    assert(!fixture::keyboard_window && fixture::surface_clear_calls == 1);

    fixture::clear_counts();
    fixture::current_monitor = left;
    lock_session(); // started on an empty workspace
    fixture::current_monitor = right;
    Event::bus()->m_events.monitor.removed.emit(left); // still alive, but disconnected
    unlock_session();
    assert(fixture::current_monitor == right && fixture::monitor_calls == 0);
    assert(fixture::surface_clear_calls == 1);

    fixture::clear_counts();
    fixture::current_monitor = left;
    lock_session();
    fixture::current_monitor = right;
    left.reset(); // weak snapshot must not keep a monitor alive
    unlock_session();
    assert(fixture::current_monitor == right && fixture::monitor_calls == 0);

    fixture::clear_counts();
    lock_session();
    g_pSessionLockManager->m_events.unlock.emit(); // malformed/early signal: still locked
    native_explicit_refocus();
    assert(fixture::restore_calls == 0 && fixture::session_locked);
    unlock_session();
    assert(fixture::restore_calls == 1); // early signal did not discard the lock snapshot
    fixture::current_monitor.reset();
    fixture::cursor_monitor.reset();
    fixture::clear_counts();
    std::cout << "PASS unlock focus, pinned/closed windows, relock, monitor removal and lock guard\n";
}

void assert_unloaded() {
    assert(fixture::live_hooks.empty());
    assert(CConfigValueBase::registry().empty());
    assert(refocus_entry == native_refocus && mouse_entry == native_mouse && monitor_entry == native_monitor);
    assert(schedule_entry == native_schedule);
}
void expect_init_failure() {
    bool threw = false;
    try { plugin_init((HANDLE)1); } catch (const std::runtime_error&) { threw = true; }
    assert(threw);
    assert_unloaded();
}

int main(int argc, char** argv) {
    assert(argc == 2);
    auto* module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!module) throw std::runtime_error(dlerror());
    plugin_api_version = (PPLUGIN_API_VERSION_FUNC)dlsym(module, PLUGIN_API_VERSION_FUNC_STR);
    plugin_init = (PPLUGIN_INIT_FUNC)dlsym(module, PLUGIN_INIT_FUNC_STR);
    plugin_exit = (PPLUGIN_EXIT_FUNC)dlsym(module, PLUGIN_EXIT_FUNC_STR);
    assert(plugin_api_version && plugin_init && plugin_exit);
    assert(plugin_api_version() == HYPRLAND_API_VERSION);
    fixture::abi = "wrong ABI";
    expect_init_failure();
    assert(fixture::create_attempts == 0);
    fixture::abi = __hyprland_api_get_client_hash();
    expect_init_failure(); // no session lock manager yet
    g_pSessionLockManager = makeUnique<CSessionLockManager>();
    for (const auto& name : {"unmapWindow", "onUnmap", "refocusLastWindow", "refocus", "mouseMoveUnified", "rawMonitorFocus", "scheduleStateApplication"}) {
        fixture::missing = name;
        expect_init_failure();
        fixture::missing.clear();
        fixture::ambiguous = name;
        expect_init_failure();
        fixture::ambiguous.clear();
    }
    for (int i = 1; i <= 4; ++i) {
        fixture::hook_attempts = fixture::create_attempts = 0;
        fixture::fail_hook = i;
        expect_init_failure();
        fixture::fail_hook = 0;
        fixture::hook_attempts = fixture::create_attempts = 0;
        fixture::fail_create = i;
        expect_init_failure();
        fixture::fail_create = 0;
    }
    std::cout << "PASS ABI, symbol validation and partial-install rollback\n";

    const auto description = plugin_init((HANDLE)1);
    assert(description.name == "hypr_extras" && description.version == "0.3.0" && fixture::live_hooks.size() == 4);
    {
        CXDGToplevelResource orphan({}, {});
        orphan.m_pendingApply.size = {123, 456};
        orphan.m_pendingApply.states = {XDG_TOPLEVEL_STATE_TILED_LEFT};
        schedule_entry(&orphan);
        assert(fixture::schedule_calls == 1);
        assert(orphan.m_pendingApply.size == Vector2D(123, 456));
        assert(orphan.m_pendingApply.states == std::vector{XDG_TOPLEVEL_STATE_TILED_LEFT});
    }
    std::cout << "PASS real geometry hook orphan-resource pass-through\n";
    for (int mode : {0, 1, 2, 3}) {
        fixture::follow = mode; // config values stay live without reinstalling hooks
        for (bool inlined : {false, true}) {
            fixture::clear_counts();
            native_unmap(inlined, false, false);
            assert(fixture::cleanup_calls == 1);
            assert(fixture::mouse_calls == (mode == 1 ? 1 : 0));
            assert(fixture::monitor_calls == (mode == 1 ? 1 : 0));
            fixture::clear_counts();
            native_layer_unmap(inlined);
            assert(fixture::cleanup_calls == 1);
            assert(fixture::mouse_calls == (mode == 1 ? 2 : 1));
            assert(fixture::monitor_calls == (mode == 1 ? 1 : 0));
            fixture::clear_counts();
            assert(native_last_window(inlined, false));
            assert(fixture::mouse_calls == (mode == 1 ? 1 : 0));
            fixture::clear_counts();
            assert(native_last_window(inlined, true));
            assert(fixture::mouse_calls == 0 && fixture::monitor_calls == 1);
        }
    }
    std::cout << "PASS window/layer/history fallbacks, inlined calls, all follow_mouse modes\n";

    fixture::follow = 2;
    fixture::clear_counts();
    native_unmap(false, true, false);
    assert(fixture::mouse_calls == 0 && fixture::monitor_calls == 1);
    fixture::clear_counts();
    native_unmap(false, false, true);
    assert(fixture::mouse_calls == 1); // explicit callback allowed, fallback suppressed
    fixture::clear_counts();
    fixture::focus_window = true;
    native_explicit_refocus(); // simulate clicking another monitor's window
    assert(fixture::mouse_calls == 1 && fixture::monitor_calls == 1);
    fixture::clear_counts();
    monitor_entry(nullptr, {}); // direct focusmonitor/keyboard action
    assert(fixture::monitor_calls == 1);
    fixture::clear_counts();
    fixture::mouse_monitor = true;
    native_explicit_refocus();
    assert(fixture::mouse_calls == 1 && fixture::monitor_calls == 1);
    fixture::mouse_monitor = false;
    std::cout << "PASS candidates, explicit/reentrant focus, clicks and mouse-focus opt-in\n";

    fixture::clear_counts();
    mouse_entry(nullptr, 123, false, true, Vector2D{17, 29});
    assert(fixture::mouse_calls == 1 && fixture::monitor_calls == 0);
    assert(fixture::last_time == 123 && !fixture::last_refocus && fixture::last_mouse);
    assert(fixture::last_position && fixture::last_position->x == 17 && fixture::last_position->y == 29);
    fixture::clear_counts();
    refocus_entry(nullptr, Vector2D{41, 53}); // touch/other explicit override preserved
    assert(fixture::mouse_calls == 1 && fixture::last_refocus);
    assert(fixture::last_position && fixture::last_position->x == 41 && fixture::last_position->y == 53);
    const auto span = extras::find_function((HANDLE)1, "unmapWindow", "Desktop::View::CWindow::unmapWindow()");
    assert(span.contains(span.address));
    assert(span.contains(reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(span.address) + span.size - 1)));
    assert(!span.contains(reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(span.address) + span.size)));
    assert(!span.contains(nullptr));
    std::cout << "PASS argument forwarding and ELF range boundaries\n";

    test_unlock_focus();
    lock_session();
    fixture::session_locked = false;
    g_pSessionLockManager->m_events.unlock.emit(); // unload with a pending restoration
    fixture::removed.clear();
    plugin_exit();
    assert_unloaded();
    assert((fixture::removed == std::vector<void*>{(void*)&native_schedule, (void*)&native_monitor, (void*)&native_mouse, (void*)&native_refocus}));
    fixture::clear_counts();
    native_explicit_refocus();
    assert(fixture::restore_calls == 0); // pending work was discarded
    fixture::session_locked = true;
    plugin_init((HANDLE)1); // loading mid-lock must not focus an application
    assert(fixture::restore_calls == 0);
    unlock_session();
    assert(fixture::restore_calls == 1);
    plugin_exit();
    assert_unloaded();
    dlclose(module);
    assert_unloaded();
    // No listeners may retain code in the unloaded .so.
    lock_session();
    unlock_session();
    Event::bus()->m_events.monitor.removed.emit({});
    Event::bus()->m_events.window.close.emit({});
    Event::bus()->m_events.window.floating.emit({});
    std::cout << "PASS reverse-order unload and reload\n";
}
