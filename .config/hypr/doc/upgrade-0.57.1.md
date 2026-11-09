# Hyprland 0.56.2 → 0.57.1 audit

Follow-up: [terminal initial-size fix](terminal_initial_size.md), `hypr_extras`
v0.4.1, corrects a wire/cache/ack mismatch in the initial v0.4.0 port described
below. The geometry hook now runs before backend configure bookkeeping.
[HDR feedback compatibility](hdr_feedback.md) in v0.4.2 additionally restores
pre-0.57 preferred-format negotiation without disabling automatic HDR.

## Upstream references

- [0.57.0 release notes](https://github.com/hyprwm/Hyprland/releases/tag/v0.57.0)
- [0.57.1 release notes](https://github.com/hyprwm/Hyprland/releases/tag/v0.57.1)
- [Full source comparison](https://github.com/hyprwm/Hyprland/compare/v0.56.2...v0.57.1)

Reviewed the tagged sources as well as the notes. Installed target:
`acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` (0.57.1), Linux x86-64.

## Fixed incompatibilities

### Window IDs are hexadecimal strings

`HL.Window.stable_id` changed from an integer to a hexadecimal string, matching
IPC. This includes letters and values beyond LuaJIT's exact integer range.

- The BSP checkpoint codec previously required numbers and used decimal float
  formatting. V4 preserves strings exactly, including selected/insertion/pull
  representative IDs; V1–V3 numeric checkpoints remain readable.
- Pointer swap/resize previously parsed IDs with `tonumber` and emitted `%d`.
  Messages now match tokens to live IDs without conversion and emit strings.
- Numeric IDs still work for an already-running 0.56.2 session. Checkpoints are
  scoped to the instance signature; they are not transferred across restarts.

### Named/special workspace IDs are now nil

Only numbered workspaces expose `.id`. `.name` is a display name;
`.addressable_name` provides the address for selectors.

- `lua/extensions/bspwm_workspace.lua` centralizes workspace keys and absolute
  selectors. Numbered keys remain numeric; named/special keys are strings.
- Layout placement, membership, selection, transfers, swaps, mouse grabs, focus,
  monocle, preselection feedback and overlay fullscreen checks use those keys.
- Workspace navigation sorts numbered and named entries without comparing nils.
- V4 checkpoints encode string workspace keys as bounded hex-encoded bytes,
  preserving spaces and UTF-8 without evaluating code.
- Monocle and move/focus operations use the addressable name, not the display
  label; different workspaces cannot alias just because their labels match.

### Native plugin API/ABI changed

`hypr_extras` v0.4.0 is rebuilt for 0.57.1:

- `CInputManager::mouseMoveUnified` gained a trailing `pointerOnly` argument.
  The hook signature, symbol lookup and trampoline forwarding now include it.
  Pointer-only refreshes do not suppress pointer updates or consume a pending
  keyboard-focus restoration after unlocking.
- Window headers moved to `desktop/view/window/`; window state/backend accessors
  replace removed public fields.
- Protocol size/configure acknowledgements moved into `CWaylandBackend`.
  Its configure path still reaches the scheduling hook used by the geometry fix.
- Exact source-revision and runtime ABI guards remain enabled, not bypassed.
  Installed-executable call-site tests cover close/layer/history fallback,
  explicit monitor focus, normal/forced unlock and XDG scheduling.

The new config loads **`plugins/hypr_extras/build-0.57.1/hypr_extras.so`**.
A session whose signature still identifies 0.56.2 keeps the existing
`build/hypr_extras.so`, without rebuilding it against incompatible new headers.
The old binary was not overwritten. The normal immutable snapshot loader and
asynchronous missing-binary builder remain in use.

## Reviewed and retained

- Main configuration is already Lua. Legacy Hyprland config removal requires no
  syntax migration. `hypridle.conf`, `hyprlock.conf` and `hyprpaper.conf` belong to
  separate programs and must not be converted to Lua for this update.
- Bindings use instantiated dispatchers, valid argument counts and no duplicated
  chord keys. Idle DPMS already uses a Lua dispatcher expression. Reload/exec/
  eval IPC used by local scripts remains supported.
- No spring `dampening` fields, moved `misc` layer options, removed
  `workspace.config_name`, or renamed layer `.interactivity` fields are used.
  DMS-generated snippets were inspected but not rewritten.
- Existing window-open handlers remain suitable for `window.open` now being
  delivered after native setup; early lifecycle cleanup uses `window.open_early`.
  The new `workspace.created_early` distinction does not affect this config.
- The Lua-layout reload/checkpoint and independent client/WM fullscreen policies
  remain in place. No blind removal of workarounds merely because upstream has
  other focus/fullscreen fixes. Relevant layout/provider and fullscreen paths
  were compared, and their existing regression suites retained.
- Monitor modes, 10-bit output, scaling, HDR auto-switching, direct scanout and
  disabled blur remain as configured. 0.57.1 already contains the opt-in KMS
  format-filtering restoration and bit-depth/HDR fixes; no speculative GPU or
  EDID overrides were added.
- New blur variants/wobble are not enabled. Other intentional upstream defaults
  (such as the new system bell) are not treated as config errors.

## Validation

Passed in the sandbox:

- All Python tests (`python3 -m unittest discover -s tests -p '*_test.py'`).
- Every `tests/*_test.lua` under Lua and LuaJIT, including exact 64-bit hexadecimal
  IDs, mixed workspace key types, named/special workspaces with `id=nil`, reload,
  pointer resize/swap, transfers, monocle and workspace navigation.
- Release build and all three CTest suites for the native plugin.
- AddressSanitizer/UndefinedBehaviorSanitizer build and the same CTest suites.
- Native `Hyprland --verify-config` for both `mainpc` and `laptop`, with a temporary
  HOME containing a fixture `bin/wpc` and this config. It reports `config ok`.
  The verifier also emits a socket2 warning because no compositor instance is
  running in that verification process; this is not a config parse error.

Build/check commands from `~/.config/hypr`:

```sh
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build-0.57.1 -G Ninja
cmake --build plugins/hypr_extras/build-0.57.1 --parallel 2
ctest --test-dir plugins/hypr_extras/build-0.57.1 --output-on-failure
Hyprland --verify-config -c "$PWD/hyprland.lua"
```

**Not live-tested:** the sandbox cannot connect to the desktop's Hyprland socket.
The native harness mocks trampoline installation; it is not an actual compositor
load. HDR/scanout, real keyboard/mouse input, Wayland size negotiation and session
unlock need the desktop checks below. No live reload, logout or restart was issued.

## Apply and desktop checks

1. Save your work. Check `hyprctl version` (running process), not just
   `Hyprland --version` (installed binary). If still on 0.56.2, log out and back in;
   reloading configuration cannot upgrade the executable.
2. While unlocked, `hyprctl reload`. Check `hyprctl configerrors` and
   `hyprctl plugin list`; expect no config errors and `hypr_extras` v0.4.2.
3. Test Super+mouse drag/resize, Super+b selection, Super+y pull, workspace
   sends/swaps, monocle and Super+Escape reload. Check that tree ratios,
   preselections, floating rectangles and fullscreen video survive reload.
4. Open a named desktop and a special workspace; repeat tiling/drag/reload there.
5. On two monitors, close the last window with the pointer over the other output;
   then test lock/unlock focus. Prefer a disposable test session for native-hook
   validation as described in [the plugin README](../plugins/hypr_extras/README.md).
6. Open **new** floating/tiled terminals and compare their remembered sizes.
   Test HDR fullscreen entry/exit, screenshots and DPMS wake on actual hardware.

The pre-edit source/config backup from this audit is
`/tmp/hypr-before-0.57.1-fixes.tar.gz` (temporary, may be removed on reboot).
Do not load the old native binary into 0.57.1 or the new binary into 0.56.2.
