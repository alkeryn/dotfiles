// Native-shaped inert backend for the hook's forwarding test. No compositor or
// fake object layout: this has the actual installed class/vtable. Only surface()
// is expected before forwarding to the mocked configure trampoline.
#include <hyprland/src/desktop/view/window/WaylandBackend.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <stdexcept>

using namespace Desktop::View;

namespace {
[[noreturn]] void unexpected() { throw std::logic_error("unexpected inert Wayland backend call"); }
}

IWindowBackend::IWindowBackend() = default;
IWindowBackend::~IWindowBackend() = default;
CWaylandBackend::CWaylandBackend(SP<CXDGSurfaceResource>) {}
SP<CWLSurfaceResource> CWaylandBackend::surface() const { return {}; }
bool CWaylandBackend::valid() const { unexpected(); }
bool CWaylandBackend::isMapped() const { unexpected(); }
eBackendType CWaylandBackend::type() const { return eBackendType::WINDOW_BACKEND_WAYLAND; }
pid_t CWaylandBackend::pid() const { unexpected(); }
PHLWINDOW CWaylandBackend::parent() const { unexpected(); }
SBackendClientID CWaylandBackend::clientID() const { unexpected(); }
bool CWaylandBackend::initialCommit() const { unexpected(); }
SClientGeometry CWaylandBackend::geometry() const { unexpected(); }
SGeometryHints CWaylandBackend::geometryHints(eBackendState) const { unexpected(); }
SBackendMetadata CWaylandBackend::metadata() const { unexpected(); }
SBackendTraits CWaylandBackend::traits() const { unexpected(); }
double CWaylandBackend::surfaceScale() const { unexpected(); }
Vector2D CWaylandBackend::reportedSize() const { unexpected(); }
CBox CWaylandBackend::clientToLogical(const CBox&, PHLMONITOR) const { unexpected(); }
CBox CWaylandBackend::logicalToClient(const CBox&, PHLMONITOR) const { unexpected(); }
Vector2D CWaylandBackend::surfaceLocalToBuffer(const Vector2D&) const { unexpected(); }
Vector2D CWaylandBackend::bufferToSurfaceLocal(const Vector2D&) const { unexpected(); }
void CWaylandBackend::configure(const CBox&, PHLMONITOR, bool) { unexpected(); }
void CWaylandBackend::acknowledgeConfigure(const CBox&) { unexpected(); }
void CWaylandBackend::setActive(bool) { unexpected(); }
void CWaylandBackend::setFullscreen(bool) { unexpected(); }
void CWaylandBackend::setMaximized(bool) { unexpected(); }
void CWaylandBackend::setResizing(bool) { unexpected(); }
bool CWaylandBackend::setSuspended(bool) { unexpected(); }
void CWaylandBackend::setMinimized(bool) { unexpected(); }
void CWaylandBackend::restackToTop() { unexpected(); }
void CWaylandBackend::close() { unexpected(); }
void CWaylandBackend::ping() { unexpected(); }
void CWaylandBackend::attach(PHLWINDOWREF) { unexpected(); }
