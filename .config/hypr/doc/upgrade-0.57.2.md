# Hyprland 0.57.1 → 0.57.2 audit

`hypr_extras` **v0.4.3** targets `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`
(0.57.2) on Linux x86-64. This is a **revision bump, not a feature change**: no
module was made obsolete and no hook policy changed. Background:
[the 0.57.1 audit](upgrade-0.57.1.md),
[terminal initial-size fix](terminal_initial_size.md),
[HDR feedback compatibility](hdr_feedback.md).

## Upstream references

- [0.57.2 release notes](https://github.com/hyprwm/Hyprland/releases/tag/v0.57.2)
- [Full source comparison](https://github.com/hyprwm/Hyprland/compare/v0.57.1...v0.57.2)

23 commits, 39 files. The tagged sources were reviewed, not just the notes.

## Result: all four features still apply

Every hook target is **source-identical** between the two tags:

| Module | Hooked function | 0.57.1 → 0.57.2 |
| --- | --- | --- |
| focus / unlock | `CInputManager::refocus`, `::mouseMoveUnified`, `::refocusLastWindow`, `CFocusState::rawMonitorFocus` | `src/managers/input/InputManager.cpp` byte-identical; `FocusState.cpp`, `SessionLockManager.cpp` untouched |
| geometry | `CWaylandBackend::configure` | untouched |
| HDR feedback | `CMonitor::getAutoHDRImageDescription` | `src/output/Monitor.cpp` untouched |

`tests/binary_contract.py` passes against the installed `/usr/bin/Hyprland`
0.57.2 with only the revision string updated: close/layer/history call sites and
inlined `refocus()` coverage, the configure→`setSize`→ack ordering, and the HDR
preference helper with independent `isHDR()` detection are all still as assumed.

Upstream PR [#12998](https://github.com/hyprwm/Hyprland/pull/12998) (the focus
fix) is still open and unmerged, so the focus module is not redundant upstream
either.

## Changes nearby, reviewed and compatible

- `f0d38186` `CLayerSurface::onMap` now calls `refocusPointer()` instead of
  `simulateMouseMovement()`, i.e. `mouseMoveUnified(..., pointerOnly = true)`.
  The hook already forwards `pointerOnly` and never suppresses pointer-only
  refreshes, so layer map/unmap now bypasses the keyboard-focus fallback entirely
  instead of relying on the cursor-floored hack. Unlock bookkeeping is unaffected.
- `f6e27b1c` `CDefaultFloatingAlgorithm::newTarget` drops a duplicated
  work-area re-centering. Position only: `rememberFloatingSize`, the first
  committed-size capture and the equal-size floating-toggle nudge are unchanged.
- `b280c55a` layer-visibility-under-fullscreen, `6cc4567f` scrolling un-fullscreen
  column width, `f1c344c4` client-requested-fullscreen handling,
  `e65d6d13`/`ef9abc0b` XDG activation and render invalidation are unrelated to
  these hooks, which do not touch fullscreen, layer alpha or activation.

Not treated as fixed upstream: unconditional tiled-edge advertisement on the
initial configure (geometry), and 0.57's unsolicited fullscreen HDR preference
(HDR feedback) are both still present in 0.57.2.

## Config-side changes

- `hyprland.lua` selects `plugins/hypr_extras/build-0.57.2/hypr_extras.so` for
  0.57.2 and later, keeps `build-0.57.1/hypr_extras.so` for a session whose
  signature is still 0.57.1, and keeps `build/hypr_extras.so` for 0.56.2 —
  neither older binary is rebuilt. Do not load a 0.57.2 build into 0.57.1 or vice
  versa: the runtime ABI hash check in `src/plugin.cpp` rejects it.
- Revision guards in `src/focus.cpp`, `src/geometry.cpp`,
  `src/hdr_feedback.cpp` and `tests/binary_contract.py` now name the 0.57.2
  commit; plugin version is `0.4.3`.
- `tests/plugins_test.lua` covers all three revision branches plus verify-config.

## Validation (sandbox)

- Release build and an AddressSanitizer/UndefinedBehaviorSanitizer build of
  v0.4.3; all three CTest suites (`extras`, `geometry_policy`, `binary_contract`
  run against the installed 0.57.2 executable) pass in both.
- All 43 config Python tests and every `tests/*_test.lua` suite under Lua and
  LuaJIT pass (with a fixture `$HOME/bin/wpc`); `Hyprland --verify-config`
  reports `config ok` for both `mainpc` and `laptop`, plus the usual socket2
  warning from having no compositor instance.

**Not live-tested:** this sandbox has no compositor socket. Trampoline
installation, real Wayland configure negotiation, HDR/scanout and unlock still
need the desktop checks in the plugin README. No reload or restart was issued
from here.

## Apply and desktop checks

```sh
cd ~/.config/hypr
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build-0.57.2 -G Ninja
cmake --build plugins/hypr_extras/build-0.57.2 --parallel 2
ctest --test-dir plugins/hypr_extras/build-0.57.2 --output-on-failure
```

1. `hyprctl version` must show 0.57.2 for the *running* process; reloading cannot
   upgrade the executable. Log out and back in if it still says 0.57.1 (that
   session keeps `build-0.57.1/hypr_extras.so` and does not need a rebuild).
2. While unlocked, `hyprctl reload`. Expect no `hyprctl configerrors` and
   `hypr_extras` v0.4.3 in `hyprctl plugin list`.
3. Re-check close/unlock focus on two outputs, initial floating terminal sizes
   for **new** windows, and fullscreen HDR entry/exit, as listed in
   [the plugin README](../plugins/hypr_extras/README.md).

## Forward look (0.58-dev)

Upstream `main` already rewrites `CWaylandBackend::configure` (`floor()`-normalized
sizes, geometry transactions, #16919). The geometry module will need a real
re-audit then — not just a hash bump. `getAutoHDRImageDescription` and the
refocus logic are still untouched on `main`, so those two remain bump-only.
