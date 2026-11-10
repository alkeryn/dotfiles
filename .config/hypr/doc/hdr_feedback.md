# Restore pre-0.57 automatic HDR negotiation

Implemented by `hypr_extras` **v0.4.3** for Hyprland **0.57.2**.

## What changed upstream

[Commit aabab87](https://github.com/hyprwm/Hyprland/commit/aabab87c387bd6b6b1e5b443308b25cafa16225e)
added `CMonitor::getAutoHDRImageDescription()`. With auto-HDR enabled, Hyprland
can advertise an HDR preferred description to the fullscreen application's
surface even while the monitor is SDR. Apps/toolkits that follow that preference
can start submitting HDR-format surfaces containing ordinary SDR content, which
then triggers the monitor's HDR mode.

The native output decision checks the submitted surface's encoding (PQ, HLG or
Windows-style scRGB), not the media file's HDR metadata or actual pixel brightness.

## Compatibility behavior

`plugins/hypr_extras/src/hdr_feedback.cpp` hooks only that new helper and returns
**a disengaged `std::optional`**. Its caller already does:

```cpp
monitor->getAutoHDRImageDescription(surface).value_or(monitor->m_imageDescription)
```

It therefore falls back to the monitor's current profile, matching the old
preferred-description behavior:

- SDR output advertises SDR, whether the application is fullscreen or windowed.
- Applications can still submit HDR explicitly; native auto-HDR still detects it.
- Once an output is actually HDR, its actual HDR profile is still advertised.
- Explicit HDR output configuration, ICC profiles, colour-management capabilities
  and the early `quirks:prefer_hdr` path remain native.

`hyprland.lua` retains **`render.cm_auto_hdr = 1`**, colour management, 10-bit
output, HDR capability overrides and direct scanout. No `no_auto_hdr` application
rules, renderer hook, forced SDR mode, daemon or polling are added.

The module has no retained monitor/surface references or event subscriptions.
Exact source revision, native method signature and runtime ABI are checked. Hook
ownership/rollback uses the existing registry (five total hooks).

## Limitations

This restores the older negotiation policy, not content inspection. An app that
explicitly submits an HDR-encoded surface full of SDR pixels can still activate
HDR. Conversely, clients that wait for an HDR preferred description before
producing HDR may remain SDR, as they did under the old behavior.

Already-running apps may have cached their HDR format. The hook does not rewrite
active surfaces or force the monitor out of HDR. Exit fullscreen before applying
it; reopen an affected app if necessary. Native fullscreen/output changes refresh
feedback normally. Removing the hook likewise takes effect as feedback is queried
again; it does not reset application state.

## Apply and check

The tested Release binary is published at the existing configured path:
`plugins/hypr_extras/build-0.57.1/hypr_extras.so`.

Exit fullscreen, then, **while unlocked**:

```sh
hyprctl reload
hyprctl plugin list
hyprctl configerrors
```

Expect `hypr_extras` **v0.4.3**. Check:

1. Start from an SDR desktop. Fullscreen an affected SDR app: entering fullscreen
   should no longer encourage it to switch its output to HDR.
2. Play known HDR content in an app configured to submit HDR explicitly: automatic
   HDR should still work, and exiting fullscreen should return to the SDR baseline.
3. Reopen apps that retained their prior HDR output. Check `quirks:prefer_hdr`
   if gamescope or an explicitly forced client still selects HDR.
4. Recheck ordinary terminal opening and close/unlock focus; previous fixes remain.

The sandbox cannot reach the live compositor, so no live reload or display-mode
validation was issued. Release and ASan/UBSan CTest suites exercise the real hook
with mock native services, including optional-return ABI, fallback semantics,
failed fifth-hook installation, reverse unload and reload. Installed-binary checks
verify the preferred-description call reaches this helper and the renderer still
uses independent submitted-surface `isHDR()` detection. Lua/Python suites and
native config verification are also run; these are not a live HDR playback test.

## Rollback

The pre-change binary is retained as
`plugins/hypr_extras/build-0.57.1/hypr_extras.so.before-hdr-feedback`.
While unlocked, restore it atomically and reload:

```sh
cp plugins/hypr_extras/build-0.57.1/hypr_extras.so.before-hdr-feedback \
   plugins/hypr_extras/build-0.57.1/hypr_extras.so.new
mv plugins/hypr_extras/build-0.57.1/hypr_extras.so.new \
   plugins/hypr_extras/build-0.57.1/hypr_extras.so
hyprctl reload
```

This restores v0.4.1, including its terminal-size fix, without the HDR compatibility
hook. A subsequent build from current sources reinstates the hook; to disable it
in source, remove its `init` call in `src/plugin.cpp` and rebuild instead.
