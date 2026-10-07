#include "../src/geometry_policy.hpp"
#include <cassert>
#include <iostream>

using namespace extras::geometry;
using Hyprutils::Math::Vector2D;

int main() {
    // Cross product: initial configure, later configure, mapped/unmapped,
    // tiled/floating, protocol v1/v2, and native covering modes. Non-geometry
    // states, including future/unknown values, must survive every path.
    for (bool initial : {false, true})
        for (bool mapped : {false, true})
            for (bool floating : {false, true})
                for (bool supported : {false, true})
                    for (auto covering : {xdgToplevelState(0), XDG_TOPLEVEL_STATE_MAXIMIZED, XDG_TOPLEVEL_STATE_FULLSCREEN}) {
                        Vector2D size{1920, 1080};
                        std::vector states = {XDG_TOPLEVEL_STATE_ACTIVATED, XDG_TOPLEVEL_STATE_RESIZING,
                                              XDG_TOPLEVEL_STATE_SUSPENDED, xdgToplevelState(99)};
                        if (covering != 0)
                            states.push_back(covering);
                        const auto preserved = states;
                        set_tiled_states(states, supported);
                        prepare_configure(size, states, initial, mapped, floating, supported);
                        assert(size == (initial && !mapped && covering == 0 ? Vector2D{} : Vector2D{1920, 1080}));
                        const bool tiled = supported && mapped && !floating;
                        for (auto edge : tiled_states)
                            assert(std::ranges::count(states, edge) == (tiled ? 1 : 0));
                        auto other_states = states;
                        std::erase_if(other_states, is_tiled_state);
                        assert(other_states == preserved);
                        const auto once = states;
                        prepare_configure(size, states, initial, mapped, floating, supported);
                        assert(states == once); // coalesced/repeated configures are idempotent
                    }

    // Model the relevant winit/Hyprland sequence, not a live Wayland test:
    // winit accepts Alacritty's grid resize only when initially unconstrained;
    // Hyprland records that first committed size before arranging the tile.
    for (bool born_floating : {false, true}) {
        Vector2D configure_size = born_floating ? Vector2D{} : Vector2D{3824, 2144};
        std::vector states(tiled_states.begin(), tiled_states.end());
        prepare_configure(configure_size, states, true, false, born_floating, true);
        assert(configure_size == Vector2D{} && states.empty());
        const Vector2D natural_size{729, 456}; // sample 81x24 grid, not a hardcoded application policy
        Vector2D saved_float_size = natural_size;
        Vector2D current_size = born_floating ? natural_size : Vector2D{1908, 2144};
        states.push_back(XDG_TOPLEVEL_STATE_MAXIMIZED); // native post-map CSD suppression
        prepare_configure(current_size, states, false, true, born_floating, true);
        assert(current_size == (born_floating ? natural_size : Vector2D{1908, 2144}));
        assert(saved_float_size == natural_size);

        // Floating restores the saved size; later tiling must not replace it.
        current_size = saved_float_size;
        prepare_configure(current_size, states, false, true, true, true);
        assert(!std::ranges::any_of(states, is_tiled_state));
        assert(current_size == natural_size);
        saved_float_size = {901, 701}; // user resizes; native floating removal remembers it
        current_size = {1908, 2144};
        prepare_configure(current_size, states, false, true, false, true);
        assert(std::ranges::count_if(states, is_tiled_state) == 4);
        current_size = saved_float_size;
        prepare_configure(current_size, states, false, true, true, true);
        assert(current_size == Vector2D(901, 701));

        // Unloading restores this Hyprland revision's unconditional native hints.
        set_tiled_states(states, true);
        assert(std::ranges::count_if(states, is_tiled_state) == 4);
        assert(current_size == saved_float_size);
    }
    std::cout << "PASS initial geometry, protocol versions, state preservation, coalescing and floating-size lifecycle model\n";
}
