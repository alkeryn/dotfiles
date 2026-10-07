#pragma once

#include "hooks.hpp"

namespace extras::geometry {
void init(HANDLE handle, hooks& registry);
// Called after removing hooks: restore native protocol hints on live resources.
void reset();
} // namespace extras::geometry
