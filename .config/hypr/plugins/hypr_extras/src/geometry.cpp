#include "geometry.hpp"
#include "geometry_policy.hpp"

#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <utility>

static_assert(std::string_view(GIT_COMMIT_HASH) == "efb50993780079460b0cbed1363e2166a2de1d9f",
              "Review initial configure, floating-size capture and protocol states before updating this guard");
static_assert(sizeof(void*) == 8);

namespace extras::geometry {
namespace {
using schedule_fn = void (*)(CXDGToplevelResource*);
CFunctionHook* schedule_hook = nullptr;
CHyprSignalListener floating_listener;

struct tracked_toplevel {
    WP<CXDGToplevelResource> resource;
    bool tiled_supported;
};
std::vector<tracked_toplevel> toplevels;

bool supports_tiled(CXDGToplevelResource* self) {
    // v0.56.2's constructor advertises all four tiled edges iff version >= 2.
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

void on_schedule(CXDGToplevelResource* self) {
    const auto owner = self->m_owner.lock();
    const auto window = self->m_window.lock();
    if (owner && window && !window->m_isX11) {
        prepare_configure(self->m_pendingApply.size, self->m_pendingApply.states,
                          owner->m_initialCommit, window->m_isMapped, window->m_isFloating, supports_tiled(self));
    }

    // setSize has already written the prediction, but nothing was sent yet.
    // Run before the native coalescing early return too: the deferred callback
    // reads pendingApply at send time. Native code still owns scheduling,
    // configure serials, acknowledgements, constraints and actual layout.
    reinterpret_cast<schedule_fn>(schedule_hook->m_original)(self);
}
} // namespace

void init(HANDLE handle, hooks& registry) {
    const auto source = find_function(handle, "scheduleStateApplication", "CXDGToplevelResource::scheduleStateApplication()");
    schedule_hook = registry.add(source, reinterpret_cast<void*>(&on_schedule));

    // State-only transitions can otherwise skip sendWindowSize's identical-size
    // guard. This event is AFTER native placement, so use its final size and let
    // sendWindowSize record its own ack, rather than calling setSize directly.
    floating_listener = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) {
        if (window && window->m_isMapped && !window->m_isX11)
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
        if (window && window->m_isMapped && !window->m_isX11)
            window->sendWindowSize(true);
    }
    schedule_hook = nullptr;
}
} // namespace extras::geometry
