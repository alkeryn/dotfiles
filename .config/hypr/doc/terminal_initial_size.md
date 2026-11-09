# Terminal first-frame rectangle on Hyprland 0.57.1

Reported symptom: opening a terminal briefly shows its translucent background
only in a small rectangle, with the remainder of the allocated tile completely
transparent, before the terminal fills the tile.

## Concrete sizing mismatch found

The natural-floating-size workaround asks the application to choose its initial
size (`0x0`), then lets Hyprland save that client-chosen size before tiling it.
The original hook changed `CXDGToplevelResource::m_pendingApply.size` in
`scheduleStateApplication`, after `setSize` received the layout prediction.

In 0.56.2, `CWindow::commitWindow` called `setSize(predicted_size)` directly for
the initial configure. In 0.57.1 that request goes through
`CWaylandBackend::configure`, which:

1. caches the requested size in `m_pendingReportedSize`;
2. calls `setSize`;
3. records the original requested size against the returned configure serial.

Changing only the wire state inside step 2 therefore sends `0x0` while the cache
and ack tracker retain the full tiled prediction. Two consequences follow:

- After the initial ack, `CWLSurface::small()` can classify the client's natural
  first buffer as undersized. `CSurfacePassElement::getTexBox()` then draws it as
  a small rectangle instead of filling the allocated tile.
- If the final tile equals the initial prediction (notably an otherwise empty
  workspace), the backend can skip the actual resize as an allegedly unchanged
  request. A later forced configure may then make the rectangle expand.

This is a source-confirmed inconsistency in the old workaround on the new backend,
and is consistent with the visual report. The desktop is inaccessible from this
sandbox, so it is not a captured end-to-end reproduction of the reported flicker.

## Fix: hypr_extras v0.4.1

Move the geometry hook to **`CWaylandBackend::configure`** and adjust its input
before any native caching or ack recording. The initial requested, cached and
wire sizes now all agree. The subsequent tile configure is no longer mistaken
for a duplicate.

There is still only one geometry hook (four hooks total). Native code still owns
configure serials, acknowledgements, deduplication and later resizing. Tiled-edge
hints are adjusted in this same path; floating-state changes still force a native
configure to cover same-size transitions.

No opacity, HDR, blur, terminal font, initial floating dimensions, fade, startup
delay or renderer-wide setting is changed. The first buffer may still be scaled
briefly until the client redraws; this corrects false undersized classification
and a skipped resize, rather than promising synchronized client rendering.

## Validation and desktop check

- Release and ASan/UBSan: all three CTest suites pass.
- Regression model reproduces the old wire/ack mismatch and skipped first tile
  resize, then verifies corrected ordering, native duplicate suppression and
  retained natural floating size.
- Existing state-policy matrix covers initial/later, mapped/unmapped,
  tiled/floating, protocol versions and fullscreen/maximized exceptions.
- Actual plugin harness checks ABI/symbol failures, four-hook rollback, the new
  hook's inert-backend forwarding (box, monitor, force flag), and focus/unlock.
- Installed-binary checks confirm `setSize` followed by ack recording in the
  backend; all Lua/Python suites and both machine-profile config checks pass.
- One initial `--verify-config` process segfaulted before printing a result;
  standalone reruns for both profiles and a debugger rerun completed with
  `config ok`. The verifier does not load native plugins. This intermittent
  verifier failure was also observed during the earlier upgrade audit.
- Real trampoline installation and visual behavior still need desktop testing.

The tested Release binary is published at the already-configured path
`plugins/hypr_extras/build-0.57.1/hypr_extras.so`. A pre-fix copy is retained as
`hypr_extras.so.before-size-ack-fix` beside it. Publication is atomic; no loaded
library is overwritten in place.

While **unlocked**:

```sh
hyprctl reload
hyprctl plugin list
hyprctl configerrors
```

Expect `hypr_extras` **v0.4.1 or later** (v0.4.2 also adds [HDR feedback compatibility](hdr_feedback.md)). Open new terminals on an empty workspace, beside
existing tiles, and directly floating (Super+Alt+Space). Also check float/tile
round-trips and fullscreen video. If the flash remains, report whether it occurs
in all three cases and whether the rectangle starts at the top-left or centre;
that distinguishes remaining buffer/redraw behavior from this ack mismatch.
