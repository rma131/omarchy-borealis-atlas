# Design: add-text-art-mode

## Findings

**The cost question was settled before any of this was written.** See the spike
in `docs/measurements.md`: a braille grid removes 90 % of the overlay's GPU work
for about half a watt, which is under this machine's ±0.6 W noise, and the
frame-rate lever a character grid was supposed to unlock had already been spent
by the pacing shipped the same morning (10 → 3 fps is worth 0.10 W).

That verdict is what chose the architecture. The two-pass design — render the
scene into a 320×180 texture, then a second shader draws dots from it — exists
only to stop every pixel redundantly evaluating the full scene. That redundancy
is the half watt. So the single pass wins on everything that could be measured,
and costs one line instead of a second binary, a `layer.effect`, a provenance
rewrite and a CI change.

## Three things that had to be built and looked at

**A fixed tone curve cannot serve both ends of the day.** The first version used
a linear threshold at 0.42 and rendered the night as a black screen with a sun
in it — a night sky sits near 0.05. Adding a gamma of 0.45 fixed the night and
blew out noon into a solid white field. The pivot now comes from the same four
keyframes the inks do: night 0.26, dawn 0.45, noon 0.78, dusk 0.48, so the sky
of the moment always lands near half coverage and everything reads against it.

**Cells need a margin or this is a halftone screen, not text.** Dots tiled on an
even grid read as newsprint. Insetting the block of eight to 78 % of its cell
puts more space between cells than between the dots within one, and that margin
is the whole difference between "a dithered picture" and "a grid of characters".

**Cell size is the aesthetic.** At a 12 px cell (160×45) the result is a fine
halftone — technically braille, visually a mesh. At a 19 px cell (100×28) the
cells resolve and it reads as a character grid. The larger cell was chosen.

**The treeline aliases.** 170 trees across a 320-dot grid is 1.88 dots per tree
— a sawtooth just under two samples per period. Point-sampled against a
continuously drifting `tod` that does not merely alias, it *crawls*. Text mode
asks for half as many trees as characters, so a tree is four dots wide.

## Options considered

| Option | Result | Verdict |
|---|---|---|
| Two passes via `layer.effect` | removes the redundant work, worth ~0.5 W | rejected: under the noise, and costs a second binary |
| A glyph atlas of real ASCII | needs a font or a new asset | rejected: braille needs no glyphs, only arithmetic |
| A QML grid of `Text` items | cheap to draw, selectable | rejected: the scene model would be reimplemented in JS and free to diverge |
| Hashed dither | shimmers once per frame at 10 fps — reads as a fault | rejected |
| **Single pass, ordered dither, procedural dots** | same picture, one file | chosen |

## What is left

- The ink is chosen per dot, not per cell, because in a single pass the scene is
  only ever evaluated at dot centres. The dominant/secondary split comes from
  the region the scene itself reports, so only the accent can vary inside a
  cell, and the accent threshold is high enough that it rarely does. If it shows
  on a sun's limb, the fix is a second evaluation at the cell centre — which
  costs what the two-pass design would have saved.
- 60:30:10 is a target, not a guarantee. Holding the true proportion needs a
  histogram of the frame, which needs a readback, which costs more than the
  whole idea. The pivot keeps it close by making the sky half the coverage.
