#include "hdr_feedback.hpp"

#include <hyprland/src/output/Monitor.hpp>
#include <optional>
#include <type_traits>

// Recheck both the preferred-description fallback and the independent renderer
// HDR detection path on upgrades. Never replace this with a generic HDR ban.
static_assert(std::string_view(GIT_COMMIT_HASH) == "acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9",
              "Review preferred HDR feedback and fullscreen HDR detection before updating this guard");
static_assert(sizeof(void*) == 8);

namespace extras::hdr_feedback {
namespace {
using hdr_offer = std::optional<NColorManagement::PImageDescription>;
using native_method = hdr_offer (Monitor::CMonitor::*)(const SP<CWLSurfaceResource>&);
static_assert(std::is_same_v<decltype(&Monitor::CMonitor::getAutoHDRImageDescription), native_method>);

hdr_offer no_fullscreen_hdr_offer(Monitor::CMonitor*, const SP<CWLSurfaceResource>&) {
    // Disengage the OPTIONAL, not merely the weak image-description pointer.
    // CWLSurfaceResource::getPreferredImageDescription() then falls back to the
    // monitor's current description, as in 0.56.2. SDR stays preferred on SDR
    // outputs; HDR/ICC outputs keep their real descriptions. Explicit HDR
    // submissions still reach the untouched renderer's auto-HDR detection.
    return std::nullopt;
}
} // namespace

void init(HANDLE handle, hooks& registry) {
    const auto source = find_function(handle, "getAutoHDRImageDescription",
        "Monitor::CMonitor::getAutoHDRImageDescription(Hyprutils::Memory::CSharedPointer<CWLSurfaceResource> const&)");
    registry.add(source, reinterpret_cast<void*>(&no_fullscreen_hdr_offer));
}
} // namespace extras::hdr_feedback
