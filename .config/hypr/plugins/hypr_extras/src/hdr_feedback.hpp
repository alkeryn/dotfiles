#pragma once

#include "hooks.hpp"

namespace extras::hdr_feedback {
// No owned state/listeners: the shared registry completely undoes this module.
void init(HANDLE handle, hooks& registry);
} // namespace extras::hdr_feedback
