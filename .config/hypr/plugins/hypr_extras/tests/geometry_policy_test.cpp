#include "../src/geometry_policy.hpp"
#include <cassert>
#include <iostream>
#include <optional>

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

    // 0.57 regression: CWaylandBackend caches the input and associates that
    // same input with the serial after setSize returns. Patching only the wire
    // state afterward lies to both the ack tracker and its equal-size guard.
    struct backend_model {
        std::optional<Vector2D> cached;
        Vector2D wire_size, ack_size;
        int configure_count = 0;
        bool configure(Vector2D requested) {
            if (cached == requested)
                return false;
            cached = requested;
            wire_size = ack_size = requested;
            ++configure_count;
            return true;
        }
    };
    const Vector2D predicted{3824, 2144}, first_buffer{729, 456};
    const auto is_small = [](Vector2D acked, Vector2D buffer) {
        return acked.x > buffer.x + 1 || acked.y > buffer.y + 1;
    };
    backend_model old;
    old.configure(predicted);
    old.wire_size = {}; // the old scheduleStateApplication hook's late rewrite
    assert(old.ack_size != old.wire_size && is_small(old.ack_size, first_buffer));
    assert(!old.configure(predicted)); // the first tile resize can be skipped too!

    backend_model fixed;
    Vector2D requested = predicted;
    std::vector initial_states(tiled_states.begin(), tiled_states.end());
    prepare_configure(requested, initial_states, true, false, false, true);
    assert(fixed.configure(requested)); // policy applies BEFORE the native cache/ack
    assert(fixed.wire_size == Vector2D{} && fixed.ack_size == fixed.wire_size);
    assert(!is_small(fixed.ack_size, first_buffer));
    assert(!fixed.configure(requested)); // native coalescing/dedup still applies
    const Vector2D saved_float_size = first_buffer;
    requested = predicted;
    prepare_configure(requested, initial_states, false, true, false, true);
    assert(fixed.configure(requested)); // even if final tile equals the prediction
    assert(fixed.configure_count == 2 && fixed.wire_size == predicted && fixed.ack_size == predicted);
    assert(!is_small(fixed.ack_size, predicted));
    assert(saved_float_size == first_buffer); // natural size remains independent
    std::cout << "PASS initial wire/cache/ack agreement and first-tile resize regression model\n";

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
        states.push_back(XDG_TOPLEVEL_STATE_MAXIMIZED); // preserve any explicit covering hint
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
