# hypr_extras

A small native home for changes that the Lua config cannot make. No daemon,
plugin framework, polling, or extra config language. Currently: the focus fix
from [Hyprland PR #12998](https://github.com/hyprwm/Hyprland/pull/12998), plus
restoring the pre-lock window and monitor after session unlock (v0.2.0).

**Automatic first builds, loading, and changed-binary reloading are enabled.**
Startup or `hyprctl reload` builds a missing library; existing binaries are not
rebuilt automatically. Reload picks up changed binaries, leaving unchanged ones
loaded. Live-session validation is still pending. Native plugins can crash the compositor.

## First-use automatic build

The config passes `source_dir` and `target` to `lua/plugins.lua`. If the `.so` is
missing, it starts `scripts/plugin_build.py` asynchronously and does not declare
the plugin yet. This avoids blocking the compositor or exceeding its 1.5-second
Lua config timeout. Startup/reload continues without the plugin until it is ready.

The worker configures CMake with **Clang**, Ninja, Release, and tests disabled;
builds only the requested target with two jobs in `build/.autobuild-hypr_extras`;
and atomically publishes the finished `.so`. It then requests a reload of the
**exact instance that started it**, which loads the normal immutable snapshot.
There is no persistent daemon. Concurrent requests share one build; repeated
requests from the same instance are deduplicated.

Build output and errors: `plugins/hypr_extras/build/hypr_extras.so.build.log`.
Failures do not trigger reload loops: fix the problem, then reload to retry.
Required build dependencies must already be installed; nothing is auto-installed.
An existing but stale/incompatible binary is not automatically rebuilt. Source
changes still require a manual build. `--verify-config` never starts a build.

Other local CMake plugins can opt in with
`load(binary_path, { source_dir = project_dir, target = target_name })`; the target
must produce the requested `.so` filename at the root of its build directory.

## Manual build and check

From `~/.config/hypr` (see the one-time migration note below if the original
build-path library is still loaded directly):

```sh
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build -G Ninja
cmake --build plugins/hypr_extras/build
ctest --test-dir plugins/hypr_extras/build --output-on-failure
hyprctl reload
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

The `require("lua/plugins").load(...)` declaration near the start of `hyprland.lua`
enables first-use building, automatic loading, and changed-binary reloading. There is no Lua focus
workaround: without the plugin loaded, Hyprland's native refocus behavior applies.

To disable a config-managed plugin, comment out its declaration and reload.

**One-time migration:** a plugin loaded by the earlier manual `hyprctl plugin load`
commands is not config-owned. Hyprland will not automatically unload that instance
when the declared path changes. Restart Hyprland once to hand ownership to the
config. Alternatively, disable the declaration and reload, manually unload the
original build-path plugin, then re-enable the declaration and reload. Do not
manually load it again. An existing config-owned instance migrates automatically.

### Updating a running session

`lua/plugins.lua` runs the short `scripts/plugin_snapshot.py` helper during config
parsing. It hashes a consistent read of the source `.so` and publishes an immutable
copy under `${XDG_CACHE_HOME:-~/.cache}/hypr/plugin-cache/<name>/<sha256>.so`.
Hyprland loads that cached path, **not** the build output. A changed binary gives
a new declaration: Hyprland unloads the old config-owned library before loading
the new one. Plugin-triggered reloads see the same hash and do nothing, avoiding
loops. There is no watcher, daemon, synchronous IPC, or extra native hook.

Build first, then run `hyprctl reload`. Touching a file without changing its content
does not reload it. The helper rejects missing/non-ELF files, observed concurrent
writes and corrupted cache entries. Config verification without an instance just
checks the ordinary declaration; it does not run the snapshot helper.

Once using snapshots, rebuilding the original output cannot overwrite the mapped
library. Before the first migration, or when using manual loading for tests, build
separately and atomically replace the original instead:

```sh
cmake -S plugins/hypr_extras -B plugins/hypr_extras/build-next -G Ninja
cmake --build plugins/hypr_extras/build-next
ctest --test-dir plugins/hypr_extras/build-next --output-on-failure
cp plugins/hypr_extras/build-next/hypr_extras.so plugins/hypr_extras/build/hypr_extras.so.new
mv plugins/hypr_extras/build/hypr_extras.so.new plugins/hypr_extras/build/hypr_extras.so
```

Then run `hyprctl reload` **while unlocked**, and check `hyprctl plugin list`.
Unchanged config reloads leave the plugin and its lock snapshot intact. A reload
that replaces the plugin cannot preserve its in-memory pre-lock snapshot.

Older cached versions are intentionally not overwritten or automatically deleted;
other sessions may still use them. Remove `~/.cache/hypr/plugin-cache` (or its
`XDG_CACHE_HOME` equivalent) when Hyprland is stopped if you want to reclaim space.
The helper works for other self-contained plugins too; plugins depending on files
next to their original `.so` need their own packaging.

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
- Installed-executable call-site checks and config verification pass. Config-side
  reload tests cover stable/changed declarations, reload-loop convergence, quoting,
  immutable snapshots, concurrent publication and helper failures. Build tests
  cover missing/existing outputs, Clang selection, failed-build retry, deduplicated
  jobs, cross-session builds and exact-instance reloads. A real clean first-use
  build also passed, using a stub reload command rather than a live compositor.
- **Real trampoline installation and desktop behavior still need a live test.**
  The disposable headless attempt in this sandbox aborted at
  `CBackend::create() failed!`, before plugin initialization. Neither the actual
  hooks nor a running desktop were exercised by that attempt.
