# Moving windows and selected subtrees to another desktop

Desktop sends transfer the focused tile, or the whole parent node selected with
`Super+b`, not only Hyprland's keyboard-focused representative window:

- `Super+Shift+number row`: send to the numbered desktop.
- `Super+Shift+dead_circumflex` / `Super+Shift+dollar`: send to the previous/next
  desktop on this monitor, including empty persistent desktops and wrapping at
  the ends. Resolve the destination once, before any windows move.
- The monitor fallback of `Super+Shift+h/j/k/l` also sends the whole selection.

Reference: `~/tmp/bspwm/src/messages.c` handles `node -d --follow` by passing the
selected node to `tree.c:transfer_node`, which unlinks and inserts it intact.
The Lua implementation likewise preserves internal splits, ratios, insertion
ages and preselections. On a first visit it inserts beside the destination's
last focused node, consuming that node's preselection if present; an empty
desktop receives the node as its root. Tiled/monocle mode remains a property of
each desktop.

Return trips reuse the node's old position on that desktop: sibling, split
axis, side and ratio. This applies to both individual tiles and selected
subtrees, so repeated next/previous sends do not gradually rearrange either
layout. The remaining destination tree must still have the same leaf order,
splits, ratios and floating vacancies; otherwise insertion falls back to the
current destination anchor. Explicit anchor or pending preselection takes
priority over a remembered slot. Focus and monitor geometry changes do not
invalidate slots. These return positions are transient (reset on config reload),
not placeholders in the tree or extra checkpointed windows.

Before a move, snapshot the source desktop's most recently focused **staying**
window (including floats, excluding all members of the moving subtree, hidden
and closed windows). Focus that survivor inside the transfer guard before the
first native move. This bypasses v0.56.2's silent-move spatial fallback: it would
otherwise pick a window at the departing tile's old center, or force cursor
refocus, and overwrite the desktop's remembered focus. A later ordinary desktop
switch must return to the real last-focused survivor, not that spatial pick.
No extra cursor warp is enabled; `cursor.no_warps` remains unchanged. For a
covering fullscreen window, defer survivor focus until after the native moves
so focusing underneath it cannot demote it before transfer. A failed move that
rolls back also restores the original keyboard focus.

The desktop switch waits until every selected window has reached the destination
and both layouts have been recalculated. Focus then follows the original
representative once, and the moved subtree remains selected. This also makes
repeated desktop sends operate on the same selection. Unselected tiles use the
same guarded transfer without acquiring subtree highlighting. Floating windows,
native groups and unselected windows in other layouts retain native behavior.

Native callbacks are deferred using the layout's existing transfer guard, so
moving leaves one at a time cannot prune the selected tree midway. Empty source
trees are cleared explicitly. Failed moves attempt rollback, then reconcile
actual ownership even if rollback fails; they never fall back to moving just the
representative. Checkpoints/feedback wait until reconciliation. Selected native
groups, unavailable leaves, and non-bspwm destinations are rejected rather than
partially transferring the selection.

Tests: `lua tests/bspwm_pull_test.lua` and `luajit tests/bspwm_pull_test.lua`.
They exercise actual bindings, subtree geometry/identity, empty/new/named and
monocle destinations, repeated relative sends, exact return geometry for every
leaf and selected subtrees, stale-slot/preselection overrides, focus/highlights,
move/return/ordinary-switch focus with deliberately wrong spatial candidates,
floating survivors, fullscreen ordering, focus refusal, native callback ordering,
rollback, and reload persistence of the live tree.
The plain-data slot helper is also covered by
`tests/bspwm_workspace_slots_test.lua`. Native moves are mocked; verify on the
desktop by sending each tile back and forth with the next/previous shortcuts,
then repeat with two or more windows selected using `Super+b`.
