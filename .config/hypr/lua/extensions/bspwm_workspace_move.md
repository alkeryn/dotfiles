# Moving a selected subtree to another desktop

`Super+b` selects a parent node in the bspwm tree. Desktop sends now transfer
that whole node, not only Hyprland's keyboard-focused representative window:

- `Super+Shift+number row`: send to the numbered desktop.
- `Super+Shift+dead_circumflex` / `Super+Shift+dollar`: send to the previous/next
  desktop on this monitor, including empty persistent desktops and wrapping at
  the ends. Resolve the destination once, before any windows move.
- The monitor fallback of `Super+Shift+h/j/k/l` also sends the whole selection.

Reference: `~/tmp/bspwm/src/messages.c` handles `node -d --follow` by passing the
selected node to `tree.c:transfer_node`, which unlinks and inserts it intact.
The Lua implementation likewise preserves internal splits, ratios, insertion
ages and preselections. It inserts beside the destination's last focused node,
consuming that node's preselection if present; an empty desktop receives the
subtree as its root. Tiled/monocle mode remains a property of each desktop.

Moves are silent until every selected window has reached the destination and
both layouts have been recalculated. Focus then follows the original
representative once, and the moved subtree remains selected. This also makes
repeated desktop sends operate on the same selection. With no selected subtree,
unselected tiles and floating windows retain native single-window behavior.

Native callbacks are deferred using the layout's existing transfer guard, so
moving leaves one at a time cannot prune the selected tree midway. Empty source
trees are cleared explicitly. Failed moves attempt rollback, then reconcile
actual ownership even if rollback fails; they never fall back to moving just the
representative. Checkpoints/feedback wait until reconciliation. Selected native
groups, unavailable leaves, and non-bspwm destinations are rejected rather than
partially transferring the selection.

Tests: `lua tests/bspwm_pull_test.lua` and `luajit tests/bspwm_pull_test.lua`.
They exercise actual bindings, subtree geometry/identity, empty/new/named and
monocle destinations, repeated relative sends, focus/highlights, native callback
ordering, rollback, and reload persistence. Native moves are mocked; verify on
the desktop by selecting two or more windows with `Super+b`, sending them with a
number-row or next/previous shortcut, then rotating or sending the same selection
again.
