// Runs the real plugin, hook registry, ELF range lookup and replacement functions.
// Only Hyprland services/trampoline installation are mocked; no compositor needed.
#include "../src/hooks.hpp"
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <algorithm>
#include <cassert>
#include <dlfcn.h>
#include <iostream>
#include <optional>
#include <stdexcept>

class CInputManager;
namespace Desktop { class CFocusState; }
PPLUGIN_API_VERSION_FUNC plugin_api_version;
PPLUGIN_INIT_FUNC plugin_init;
PPLUGIN_EXIT_FUNC plugin_exit;

using refocus_fn = void (*)(CInputManager*, std::optional<Vector2D>);
using mouse_fn = void (*)(CInputManager*, uint32_t, bool, bool, std::optional<Vector2D>);
using monitor_fn = void (*)(Desktop::CFocusState*, PHLMONITOR);

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

void clear_counts() {
    mouse_calls = monitor_calls = cleanup_calls = 0;
    focus_window = false;
    last_position.reset();
}
}

// Named, exported, non-inlined functions provide real ELF bounds/return addresses.
#define NATIVE extern "C" __attribute__((noinline))
NATIVE void native_refocus(CInputManager*, std::optional<Vector2D>);
NATIVE void native_mouse(CInputManager*, uint32_t, bool, bool, std::optional<Vector2D>);
NATIVE void native_monitor(Desktop::CFocusState*, PHLMONITOR);
refocus_fn refocus_entry = native_refocus;
mouse_fn mouse_entry = native_mouse;
monitor_fn monitor_entry = native_monitor;

NATIVE void native_window_focus() { monitor_entry(nullptr, {}); }
NATIVE void native_monitor(Desktop::CFocusState*, PHLMONITOR) { ++fixture::monitor_calls; }
NATIVE void native_mouse(CInputManager*, uint32_t time, bool refocus, bool mouse, std::optional<Vector2D> position) {
    ++fixture::mouse_calls;
    fixture::last_time = time;
    fixture::last_refocus = refocus;
    fixture::last_mouse = mouse;
    fixture::last_position = position;
    if (fixture::mouse_monitor || refocus)
        monitor_entry(nullptr, {});
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
    else assert(false);
    return true;
}
bool CFunctionHook::unhook() {
    if (m_source == (void*)&native_refocus) refocus_entry = native_refocus;
    if (m_source == (void*)&native_mouse) mouse_entry = native_mouse;
    if (m_source == (void*)&native_monitor) monitor_entry = native_monitor;
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

void assert_unloaded() {
    assert(fixture::live_hooks.empty());
    assert(CConfigValueBase::registry().empty());
    assert(refocus_entry == native_refocus && mouse_entry == native_mouse && monitor_entry == native_monitor);
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
    for (const auto& name : {"unmapWindow", "onUnmap", "refocusLastWindow", "refocus", "mouseMoveUnified", "rawMonitorFocus"}) {
        fixture::missing = name;
        expect_init_failure();
        fixture::missing.clear();
        fixture::ambiguous = name;
        expect_init_failure();
        fixture::ambiguous.clear();
    }
    for (int i = 1; i <= 3; ++i) {
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
    assert(description.name == "hypr_extras" && fixture::live_hooks.size() == 3);
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

    fixture::removed.clear();
    plugin_exit();
    assert_unloaded();
    assert((fixture::removed == std::vector<void*>{(void*)&native_monitor, (void*)&native_mouse, (void*)&native_refocus}));
    plugin_init((HANDLE)1);
    plugin_exit();
    assert_unloaded();
    dlclose(module);
    assert_unloaded();
    std::cout << "PASS reverse-order unload and reload\n";
}
