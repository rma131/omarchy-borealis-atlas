# Proposal: Draw the whole scene as braille

## Request

> "I want to check what are the options of doing a version of the project,
> another branch where ascii symbols make the full scene. and even the option
> of having [the 60:30:10 structural rule] for colors and evaluate if it would
> be a good alternative lower cost option. Can we predict this and plan?"
> — 2026-09-23

...and, once the spike had answered the cost question, "yes, build it on the
branch".

Chosen with the requester: an experimental branch, braille sub-dots, and the
three colours taken from the hour's sky.

## Intent

It is **not** a lower-cost option, and `docs/measurements.md` records the spike
that settled it before any of this was written:

- Drawing the scene at a braille grid removes **90 % of the overlay's GPU work**
  — +82 MHz over idle down to +8 — and that is worth about **half a watt**.
- Half a watt is under the noise: the same configuration read 8.10 W and 8.71 W
  an hour apart while its GPU clock reproduced at 383 MHz both times.
- The frame-rate lever a character grid was supposed to unlock is already spent.
  With fragments removed, 60 → 10 fps is worth 1.30 W and **10 → 3 fps is worth
  0.10 W**. The pacing shipped the same morning took all of it.

So this is here for what it looks like. Which turns out to be reason enough:
the aurora at midnight, drawn as cyan braille on a black page, is the best the
scene has looked.

## Scope

In scope:
- one coordinate snap at the top of `main()`, so every existing path answers for
  the dot instead of the pixel
- the dot drawn as a disc whose area tracks brightness, against an ordered
  threshold, inside a cell with a margin
- three inks and a tone pivot, blended from four keyframes by the hour
- fewer trees, so the ridge does not moire against the dot grid
- a `textArt` key on the plugin's shell.json entry

Out of scope:
- the two-pass structure the spike rejected: a second shader, a second binary,
  `layer.effect`, and the provenance and CI changes they would have needed
- any claim that this saves power

## Approach

Single pass. The braille grid is a sampling resolution, not a second renderer:
`uv` is snapped to the dot centre and the scene answers as it always has. Every
pixel still evaluates the full scene and neighbours inside a dot do identical
redundant work — which is exactly the redundancy the two-pass design would have
removed, for the half watt that could not be measured.

## Capabilities affected

- `text-art` — ADDED: a new capability

## Risks

The look is the whole point, so the risks are aesthetic and were met by
building and looking: a fixed tone curve renders night as an empty page and noon
as a full one; cells without a margin read as a halftone screen rather than as
characters; and the treeline aliases into a crawling moire at the scene's own
tree count. All three are recorded in design.md with what replaced them.
