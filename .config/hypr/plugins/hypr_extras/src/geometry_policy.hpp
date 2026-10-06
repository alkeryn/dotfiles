#pragma once

#include <hyprland/protocols/xdg-shell.hpp>
#include <hyprutils/math/Vector2D.hpp>
#include <algorithm>
#include <array>
#include <vector>

namespace extras::geometry {

inline constexpr std::array tiled_states = {
    XDG_TOPLEVEL_STATE_TILED_LEFT, XDG_TOPLEVEL_STATE_TILED_RIGHT,
    XDG_TOPLEVEL_STATE_TILED_TOP, XDG_TOPLEVEL_STATE_TILED_BOTTOM,
};

inline bool is_tiled_state(xdgToplevelState state) {
    return std::ranges::find(tiled_states, state) != tiled_states.end();
}

inline void set_tiled_states(std::vector<xdgToplevelState>& states, bool tiled) {
    std::erase_if(states, is_tiled_state);
    if (tiled)
        states.insert(states.end(), tiled_states.begin(), tiled_states.end());
}

// Only the initial, ordinary configure relinquishes size selection. Later
// configures (including the pre-map interval) must retain native size/serials.
// Fullscreen/maximized, activation, resizing, suspension and unknown states
// remain native. In particular we do not remove Hyprland's post-map CSD hint.
inline void prepare_configure(Hyprutils::Math::Vector2D& size, std::vector<xdgToplevelState>& states,
                              bool initial, bool mapped, bool floating, bool tiled_supported) {
    const bool covering = std::ranges::find(states, XDG_TOPLEVEL_STATE_FULLSCREEN) != states.end()
        || std::ranges::find(states, XDG_TOPLEVEL_STATE_MAXIMIZED) != states.end();
    if (initial && !mapped && !covering)
        size = {};
    set_tiled_states(states, tiled_supported && mapped && !floating);
}

} // namespace extras::geometry
