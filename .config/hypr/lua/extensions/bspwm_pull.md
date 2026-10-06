# Super+Y: global send/pull

Reference: `~/.config/bspwm/sxhkd/sxhkdrc`:

```sh
bspc query -N -n focused.automatic && bspc node -n last.!automatic || bspc node last.leaf -n focused
```

In bspwm, `automatic` means **no preselection on the node**, and `last` uses
**focus history**, not window creation order. The literal `last.leaf` fallback
above was too narrow for the requested group workflow: after selecting a subtree
and focusing the destination, it pulled only its representative window. The Lua
binding now extends that fallback to the remembered **logical node**.

`hl.dsp.layout("pull")` now searches Hyprland's global `focus_history_id` order:

- If the current node has no preselection, send it to the most recently focused
  node with a preselection, on any desktop/monitor. With `Super+b`, this means
  the **entire selected subtree**, not its keyboard-focus representative. A
  preselection on one of its children does not make the parent node manual.
- Otherwise (also when no manual target exists), pull the last focused eligible
  external node beside the **whole current node**. If that source was selected
  with `Super+b`, pull its entire remembered subtree; an ordinary leaf source
  still pulls just one window. Preserve both source and destination trees.
- Consume the destination's preselection direction/ratio, or insert along its
  longest side. Preserve moved subtrees and their ratios/preselections/ages.
- Focus the **inserted node** after a successful insertion, both for send and
  pull. Cross-workspace sends also focus the destination desktop/monitor. Native
  moves remain silent (`follow = false`) while assembling the insertion; focus
  happens once afterwards, not once per leaf. Moved subtrees retain their original
  keyboard-focus representative and become the selected node at the destination.

Candidates must be mapped, unhidden, ungrouped tiles in either bspwm provider
alias. An inactive desktop's windows are eligible: visibility is NOT a filter.
Floats and native groups aren't moved through the binary tree. Empty desktops
and floating keyboard focus are no-ops rather than acting on an unrelated tile.

## Selecting a group first, then its destination

1. Focus the source and use `Super+b` to select its subtree.
2. Focus a destination outside that subtree. Source selection borders clear,
   but the layout remembers the source node and its representative window.
3. Preselect at the destination, then press `Super+y`. The whole source subtree
   is inserted there and becomes selected again. Without preselection, the
   history-based pull also uses a remembered group when it is the latest source.

Hyprland only has window focus history, not bspwm's internal-node history. Each
remembered split node records its representative and original leaf membership;
its native focus-history position determines when it is the source. Newer
ordinary windows still take precedence over older groups. This is independent
of transient border highlighting. Internal preselection targets continue to use
their representative leaves' history. Overlapping source/destination nodes are
skipped, never reduced to one of their constituent leaves.

Explicitly focusing/clicking a member or descending to a leaf cancels its group
association. Selecting a parent/child replaces overlapping remembered groups;
disjoint groups can be remembered independently. Swapping or moving an intact
subtree preserves the association. Closing/floating members or changing the
membership inside it invalidates the old association. An unavailable member of
a still-remembered group produces an error instead of a single-window fallback.

## Native callbacks and reloads

A native workspace move synchronously removes/adds layout targets. For subtree
moves, intermediate callbacks must not prune the subtree while its leaves are
still moving. During the operation, the provider retains the latest native
context tables, commits the tree surgery after successful moves, then replays
filtered snapshots. These contexts are retained only for that synchronous move.
A now-empty source is explicitly pruned because Hyprland skips empty callbacks.

Same-desktop sends/pulls also use the guard: selection-border tag changes can
reenter the layout even without a native workspace move. The invoking layout's
context is retained and replayed explicitly, so the new geometry is applied
**before** focus/selection follows the inserted node. This avoids focusing or
warping toward an old rectangle and prevents tag callbacks from saving a
partially updated selection.

A failed move is reported, and the trees are reconciled with actual window
ownership. Multi-window native moves aren't atomic: a partial failure may leave
some windows transferred, but must not duplicate/resurrect leaves. Checkpointing
and preselection feedback are deferred until the transfer is reconciled. Failed
or partial moves do not trigger the final focus step. If only the focus request
fails, the completed transfer is retained and the focus failure is reported.
Rule/placement exceptions release both transfer guards and report an error
without following, rather than leaving all subsequent moves/pulls disabled.

The V2 session checkpoint stores remembered source representatives on split
nodes; their membership is reconstructed and validated on reload. V1 checkpoints
remain readable, so installing this change does not discard the existing tree.
This also supports reloading after focusing the destination but before pulling.
Negative workspace IDs use `name:...` selectors, since this version's dispatcher
interprets negative numeric selectors as relative moves (even when passed a
workspace object).

Tests: `lua tests/bspwm_pull_test.lua` (also run with `luajit`). Actual-binding
coverage includes **select source → focus/preselect destination → pull**, on
one desktop and across desktops, with and without destination preselection. It
also covers cancellation, stale/unavailable members, competing history entries,
subtree-to-subtree pulls, use after swaps/moves, V1/V2 checkpoint reloads,
reentrant tag callbacks and placement-error recovery.
The fixture models native callbacks but does not replace desktop verification.
