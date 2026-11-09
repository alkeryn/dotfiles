#include "geometry.hpp"
#include "geometry_policy.hpp"

#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WaylandBackend.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <utility>

static_assert(std::string_view(GIT_COMMIT_HASH) == "acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9",
              "Review initial configure, floating-size capture and protocol states before updating this guard");
static_assert(sizeof(void*) == 8);

namespace extras::geometry {
namespace {
using configure_fn = void (*)(Desktop::View::CWaylandBackend*, const CBox&, PHLMONITOR, bool);
CFunctionHook* configure_hook = nullptr;
CHyprSignalListener floating_listener;

struct tracked_toplevel {
    WP<CXDGToplevelResource> resource;
    bool tiled_supported;
};
std::vector<tracked_toplevel> toplevels;

bool supports_tiled(CXDGToplevelResource* self) {
    // v0.57.1's constructor advertises all four tiled edges iff version >= 2.
    // Remember that capability BEFORE clearing the edges, without accessing the
    // private protocol wrapper or emitting v2 states to a v1 client. Weak refs
    // prevent address reuse and do not keep closed applications alive.
    std::erase_if(toplevels, [](const auto& entry) { return entry.resource.expired(); });
    for (const auto& entry : toplevels) {
        if (entry.resource.get() == self)
            return entry.tiled_supported;
    }
    const bool supported = std::ranges::any_of(self->m_pendingApply.states, is_tiled_state);
    toplevels.push_back({self->m_self, supported});
    return supported;
}

void on_configure(Desktop::View::CWaylandBackend* self, const CBox& box, PHLMONITOR monitor, bool force) {
    const auto surface = self->surface();
    const auto role = surface ? dynamicPointerCast<CXDGSurfaceRole>(surface->m_role) : nullptr;
    const auto owner = role ? role->m_xdgSurface.lock() : nullptr;
    const auto toplevel = owner ? owner->m_toplevel.lock() : nullptr;
    const auto window = toplevel ? toplevel->m_window.lock() : nullptr;
    auto requested_box = box;
    if (window) {
        auto size = box.size();
        prepare_configure(size, toplevel->m_pendingApply.states,
                          owner->m_initialCommit, self->isMapped(), window->isFloating(), supports_tiled(toplevel.get()));
        requested_box.width = size.x;
        requested_box.height = size.y;
    }

    // 0.57 caches this size and records it against the configure serial in the
    // backend. Changing only pendingApply later sends 0x0 but records the tile
    // prediction: the first client-chosen buffer is then falsely "small" and
    // rendered as a rectangle in an otherwise transparent tile. Change the
    // INPUT instead, so the native cache, wire size and ack tracker all agree.
    // Position, output, force flag, later sizes and all ack handling stay native.
    reinterpret_cast<configure_fn>(configure_hook->m_original)(self, requested_box, std::move(monitor), force);
}
} // namespace

void init(HANDLE handle, hooks& registry) {
    const auto source = find_function(handle, "configure",
        "Desktop::View::CWaylandBackend::configure(Hyprutils::Math::CBox const&, Hyprutils::Memory::CSharedPointer<Monitor::CMonitor>, bool)");
    configure_hook = registry.add(source, reinterpret_cast<void*>(&on_configure));

    // State-only transitions can otherwise skip sendWindowSize's identical-size
    // guard. This event is AFTER native placement, so use its final size and let
    // sendWindowSize record its own ack, rather than calling setSize directly.
    floating_listener = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) {
        if (window && window->mapped() && !window->backend().isX11())
            window->sendWindowSize(true);
    });
}

void reset() {
    floating_listener.reset();
    const auto old_toplevels = std::exchange(toplevels, {});
    for (const auto& entry : old_toplevels) {
        const auto resource = entry.resource.lock();
        if (!resource)
            continue;
        // Return to the revision's native, unconditional tiled-edge hints on
        // unload. Do not reset sizes or forget the user's native floating size.
        set_tiled_states(resource->m_pendingApply.states, entry.tiled_supported);
        const auto window = resource->m_window.lock();
        if (window && window->mapped() && !window->backend().isX11())
            window->sendWindowSize(true);
    }
    configure_hook = nullptr;
}
} // namespace extras::geometry
