# Super+Y: global send/pull

Reference: `~/.config/bspwm/sxhkd/sxhkdrc`:

```sh
bspc query -N -n focused.automatic && bspc node -n last.!automatic || bspc node last.leaf -n focused
```

In bspwm, `automatic` means **no preselection on the node**, and `last` uses
**focus history**, not window creation order. The previous Lua implementation
used the newest/oldest leaf of only the current workspace.

`hl.dsp.layout("pull")` now searches Hyprland's global `focus_history_id` order:

- If the current node has no preselection, send it to the most recently focused
  node with a preselection, on any desktop/monitor.
- Otherwise (also when no manual target exists), pull the last focused eligible
  leaf into the current node.
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

Hyprland only has window focus history, not bspwm's internal-node history.
Internal preselections are therefore associated with their representative leaves'
focus history. Overlapping source/destination subtrees are skipped.

## Native callbacks and reloads

A native workspace move synchronously removes/adds layout targets. For subtree
moves, intermediate callbacks must not prune the subtree while its leaves are
still moving. During the operation, the provider retains the latest native
context tables, commits the tree surgery after successful moves, then replays
filtered snapshots. These contexts are retained only for that synchronous move.
A now-empty source is explicitly pruned because Hyprland skips empty callbacks.

A failed move is reported, and the trees are reconciled with actual window
ownership. Multi-window native moves aren't atomic: a partial failure may leave
some windows transferred, but must not duplicate/resurrect leaves. Checkpointing
and preselection feedback are deferred until the transfer is reconciled. Failed
or partial moves do not trigger the final focus step. If only the focus request
fails, the completed transfer is retained and the focus failure is reported.

No new persistent history format is needed: native history survives reloads,
and the existing checkpoint contains the tree/preselections. Negative workspace
IDs use `name:...` selectors, since this version's dispatcher interprets negative
numeric selectors as relative moves (even when passed a workspace object).

Tests: `lua tests/bspwm_pull_test.lua` (also run with `luajit`). The fixture models
native callbacks but does not replace desktop verification.
