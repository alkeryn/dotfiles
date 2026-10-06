#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <cstdint>
#include <string_view>
#include <vector>

namespace extras {

// ELF function bounds, resolved once at load time; no stack walk or hot-path dlsym.
struct function_span {
    void* address = nullptr;
    std::size_t size = 0;

    bool contains(const void* pc) const {
        const auto start = reinterpret_cast<std::uintptr_t>(address);
        const auto value = reinterpret_cast<std::uintptr_t>(pc);
        return value >= start && value - start < size;
    }
};

function_span find_function(HANDLE handle, const std::string& name, std::string_view signature);

// Explicit cleanup: Hyprland also owns the hooks and removes them on forced eject.
class hooks {
  public:
    void attach(HANDLE handle) { owner = handle; }
    CFunctionHook* add(const function_span& source, void* replacement);
    void clear();

  private:
    HANDLE owner = nullptr;
    std::vector<CFunctionHook*> entries;
};

} // namespace extras
