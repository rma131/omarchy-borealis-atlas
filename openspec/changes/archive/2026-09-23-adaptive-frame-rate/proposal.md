# Proposal: Draw fewer frames when nothing is happening

## Request

> "I would like to check as a list what are the next resource expensive features
> or qualities of the project that could be modified to achieve a real
> 'screen saver' for the low cost mode that keeps the fun interaction, beauty
> and information functionality."
> — 2026-09-23

...and, to the list that came back, "yes" to building the first item.

## Intent

`docs/measurements.md`, 2026-09-23: **the overlay open and frozen draws 6.64 W
against 6.62 W dismissed**, at the idle GPU clock. A still picture is free. Every
watt this costs is the redrawing, and the scene is redrawn sixty times a second
whether or not anything in it has moved.

The sky drifts an hour per minute of wall time. At ten frames a second the sun
moves about a hundredth of a degree between frames. Nobody can see that. What
they can see is a scrub, a ripple under a finger, rain, and a lightning flash —
and those are exactly the moments to spend frames on.

Measured: 60 → 10 fps is **+289 → +55 MHz over idle, 81 % of the GPU work gone**.

## Scope

In scope:
- one clock that everything animated hangs off, in the cheap mode
- a frame interval that rises to 60 fps while the scene is being touched,
  scrubbed, searched or inspected, and falls back when it is not
- a middle rate when the sky itself has fast motion in it — rain, snow, a storm

Out of scope:
- changing anything on mains; the declarative animation stays exactly as it is
- giving the blur back in exchange for the frames, which is worth doing and is
  a separate decision with its own look to judge

## Approach

**One clock.** Measured and recorded: capping `time` alone saved nothing because
`tod` is animated separately by a `Behavior`, and two 33 ms timers at unrelated
phases interleave into sixty renders a second with the timer overhead on top. So
in the cheap mode a single timer advances the shader clock and the drift, the
`Behavior` is disabled while drifting so the steps stay discrete, and the mains
path keeps the `NumberAnimation` untouched.

The interval is a pure function of what the scene is doing, so it can be tested.

## Capabilities affected

- `performance` — ADDED: frames are spent where they can be seen

## Risks

Ten frames a second is visible on anything that moves fast, which is why rain,
snow and storms get a middle rate. If a lightning flash or a meteor reads badly
at that rate the answer is a higher floor, not a lower one — the scenario names
what to look at.
