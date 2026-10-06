#pragma once

#include "hooks.hpp"

namespace extras::focus {
void init(HANDLE handle, hooks& registry);
void reset();
} // namespace extras::focus
