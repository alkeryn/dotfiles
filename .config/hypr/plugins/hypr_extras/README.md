# hypr_extras

A small native home for changes that the Lua config cannot make. No daemon,
plugin framework, polling, or extra config language. Currently: the focus fix
from [Hyprland PR #12998](https://github.com/hyprwm/Hyprland/pull/12998), plus
restoring the pre-lock window and monitor after session unlock (v0.2.0).

**Automatic loading is enabled in `hyprland.lua`.** Live-session validation is
still pending. Native plugins run inside the compositor and can crash it.

## Build and check

For a fresh build, or with the plugin unloaded, from `~/.config/hypr`:

```sh
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build -G Ninja
cmake --build plugins/hypr_extras/build
ctest --test-dir plugins/hypr_extras/build --output-on-failure
```

Requires Clang, CMake, Ninja, pkg-config, and installed Hyprland development
headers/dependencies. Tests also need Python 3, binutils, and Hyprland debug
symbols for the private unlock callback's call-site check. Clang is the default;
an explicit `-DCMAKE_CXX_COMPILER=...` overrides it. It uses **libstdc++**, matching
the installed GCC-built compositor, not libc++. The plugin itself is built with
Clang; linking GCC's runtime does not mean compiling it with GCC.

Output: `build/hypr_extras.so`. No installation step or background service.
`-DBUILD_TESTING=OFF` omits the test harness.

Supported target: **Linux x86-64, Hyprland v0.56.2**, commit
`efb50993780079460b0cbed1363e2166a2de1d9f`. The focus module deliberately fails to
compile against an unreviewed revision. The plugin also rejects a runtime ABI
string mismatch before installing hooks. These checks reduce risk; they are not
a guarantee of compiler/ABI compatibility. Recheck and rebuild after upgrades.

## Enable / disable

First start a **separate test session**, using a minimal config (not your full
config's autostart). Find that session's exact instance signature with
`hyprctl instances`. Then, from this config directory:

```sh
# Set this to the DISPOSABLE session's signature, never your daily session.
test_instance='REPLACE_WITH_TEST_SESSION_SIGNATURE'
hyprctl -i "$test_instance" plugin load "$PWD/plugins/hypr_extras/build/hypr_extras.so"
hyprctl -i "$test_instance" plugin list
```

On two outputs, test:

- `follow_mouse = 0`, `2`, and `3`, with `focus_on_close = 2` and
  `mouse_move_focuses_monitor = false`: focus a last window on A, leave the
  cursor on B, and close it. A must stay focused without first activating B.
- Repeat with the cursor over an empty B, floating/fullscreen windows, and
  numbered/named workspaces. Non-empty closes must retain normal candidate focus.
- Open/close a keyboard-interactive layer (e.g. your launcher), including on an
  empty workspace. Last-window restoration must work without cursor fallback.
- Explicit clicks and keyboard monitor/window focus must still work. Ordinary
  pointer motion must still reach clients. `follow_mouse = 1` must stay native.
- Set `mouse_move_focuses_monitor = true`: normal mouse-driven monitor switching
  remains enabled. This is independent of suppressing the close fallback.
- Lock with hyprlock while A's window has focus and the cursor is over B.
  Unlock: both keyboard input and monitor focus must return to A, without first
  focusing B. Repeat with a pinned window and with the window closing while
  locked. An empty workspace must stay unfocused rather than focus under the cursor.
- Unload and load again; test a config reload too.

Unload from that same session with:

```sh
hyprctl -i "$test_instance" plugin unload "$PWD/plugins/hypr_extras/build/hypr_extras.so"
```

The `hl.plugin.load(...)` line near the start of `hyprland.lua` enables automatic
loading on startup and config reload. There is no Lua workaround: without the
plugin loaded, Hyprland's native refocus behavior applies.

To disable a config-loaded plugin, comment out its load line and reload. A plugin
loaded manually with `hyprctl plugin load` also needs a manual unload.

### Updating a running session

Do not rebuild/overwrite a loaded `.so` in place. Build and test separately, then
replace the file by rename (existing mappings keep their old inode):

```sh
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build-next -G Ninja
cmake --build plugins/hypr_extras/build-next
ctest --test-dir plugins/hypr_extras/build-next --output-on-failure
cp plugins/hypr_extras/build-next/hypr_extras.so plugins/hypr_extras/build/hypr_extras.so.new
mv plugins/hypr_extras/build/hypr_extras.so.new plugins/hypr_extras/build/hypr_extras.so
```

The running session still uses the old version until you restart it or explicitly
reload the plugin **while unlocked**:

```sh
plugin="$HOME/.config/hypr/plugins/hypr_extras/build/hypr_extras.so"
hyprctl plugin unload "$plugin" && hyprctl plugin load "$plugin"
hyprctl plugin list
```

Check that `hypr_extras` reports **0.2.0**. A config reload alone does not replace
an already-loaded plugin at the same path.

## Implementation and scope

`src/plugin.cpp` owns lifecycle and ABI validation; `src/hooks.*` owns hook
installation, lookup and rollback; `src/focus.cpp` contains the feature. To add a
future change, add its source to CMake and call its `init`/cleanup from the entry
point. Keep feature policy out of `hooks.*`. No module discovery machinery needed.

The focus module uses three native hooks:

1. `CInputManager::refocus`: skip only calls from `CWindow::unmapWindow`,
   `CLayerSurface::onUnmap`, or `CInputManager::refocusLastWindow`, and only when
   `input:follow_mouse != 1`.
2. `CInputManager::mouseMoveUnified`: cover inlined/tail-called versions of the
   same fallback. Real mouse motion (`refocus == false`) is not suppressed.
3. `CFocusState::rawMonitorFocus`: apply the PR's monitor condition only to the
   direct call from `mouseMoveUnified`. Focus calls from `rawWindowFocus` and
   dispatchers remain untouched, so legitimate clicks still select their monitor.

Caller recognition uses the immediate return address and cached ELF function
bounds. No stack walking, absolute instruction offsets, polling, workspace
round-trips, or copying whole compositor functions. The installed binary has
inlined `refocus()` calls inside `refocusLastWindow()`; hooking only `refocus`
would miss them. `tests/binary_contract.py` checks those call sites in the actual
installed executable, including the separate window-to-monitor focus path.

Session unlock uses the same refocus hooks, not an additional hook or timer.
Native lock events save weak references to the pre-lock window and monitor;
close/removal events invalidate them. Unlock arms a single restoration, consumed
by the session manager's immediately following synchronous `refocus()` **after**
lock-surface cleanup. It restores the saved monitor and asks native window focus
to restore keyboard focus. If the window closed, it clears the stale lock-surface
focus instead. It checks that the protocol is unlocked and leaves `follow_mouse = 1`
native. Locker crashes do not trigger restoration, and re-locking preserves the
original snapshot. Loading mid-lock can only snapshot the focus still known then.

This follows the PR's revised `follow_mouse` policy, not its abandoned
`switch_monitor_on_empty` option. Candidate selection and cleanup remain native.
It does not add the separate `movetoworkspacesilent` fix discussed in the PR's
comments, nor globally ban all automatic refocusing. In particular, selecting a
window with `focus_on_close = 1` is still native behavior; this config uses `2`.

## Validation status

- Clang build succeeds; the actual `.so` loads into the isolated test executable.
  Both Release and AddressSanitizer/UndefinedBehaviorSanitizer builds pass.
- Tests exercise the real replacement functions and ELF caller matching against
  native-shaped fixture functions, with mocked config/trampoline services.
  Coverage includes all follow-mouse modes, inline calls, argument forwarding,
  preserved explicit focus/candidates, ABI/symbol failures, partial-install
  rollback, and reverse-order unload/reload. Unlock tests cover all follow-mouse
  modes, pinned/closed/expired windows, focus changes during lock, re-locking,
  disconnected monitors, pending-work cleanup and the still-locked safety guard.
- Installed-executable call-site checks and config verification pass.
- **Real trampoline installation and desktop behavior still need a live test.**
  The disposable headless attempt in this sandbox aborted at
  `CBackend::create() failed!`, before plugin initialization. Neither the actual
  hooks nor a running desktop were exercised by that attempt.
