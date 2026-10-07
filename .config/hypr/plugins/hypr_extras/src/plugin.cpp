#include "focus.hpp"

#include <stdexcept>
#include <string_view>

namespace {
extras::hooks registry;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string_view(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("hypr_extras: Hyprland ABI mismatch; rebuild against the running compositor");

    registry.attach(handle);
    try {
        // Add future modules here, sharing only hook ownership and the ABI check.
        extras::focus::init(handle, registry);
    } catch (...) {
        registry.clear();
        extras::focus::reset();
        throw;
    }
    return {"hypr_extras", "Small native extensions for alkeryn's Hyprland config", "alkeryn", "0.2.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    registry.clear();
    extras::focus::reset();
}
