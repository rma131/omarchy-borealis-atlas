# Proposal: Draw the same scene for less power on battery

## Request

> "Second thing to check, is if we can have a more efficient or low resolution
> mode, where we get the visualization less resource intensive, but still
> stylish even if it is a different proposal. That would be for later."
> — 2026-09-22

Chosen with the requester: keep the same picture rather than design a second
visual identity, and select it automatically on battery.

## Intent

`docs/measurements.md` measures the cost honestly: **+7.5 W, GPU 301 → 748 MHz
against an 1150 MHz ceiling, battery life 7.8 h → 3.3 h**. It also names the
cause — `main()` calls `upperScene()` five times below the waterline, so the
bottom 18 % of the screen costs five times the sky — and the remedy: "Dropping to
3 taps is the cheapest big win if this needs to get lighter."

The screensaver already runs only on mains, so this is for the case the user
summons it by hand, or leaves it running while unplugged.

## Scope

In scope, in order of effect:
- reflection taps 5 → 3
- one starfield tap instead of up to seven
- two aurora curtains instead of three
- the third rain layer, which is evaluated and then multiplied by `sev.y`, so it
  is free work whenever there is no storm
- a 30 fps cap (measurements.md lists this as deferred and untested)
- power state read the way `omarchy-screensaver-dispatch` reads it

Out of scope:
- a different visual style

**Revised 2026-09-22 after measuring.** Rendering at reduced resolution was out
of scope here and is now the main lever: the taps this proposal was built around
measure at 2.5 % and resolution at 33 %. See design.md, "Corrections".

## Approach

One `quality` number pushed as a uniform, with the expensive paths reading it, so
there is no second shader to keep in step — and the same number drives the render
scale in QML, so there is one decision and not two.

## Capabilities affected

- a new `performance` capability

## Risks

Reducing taps changes the water's look; the cheaper scene must still be one
someone would choose. Verification is a re-measurement in the same form as
`docs/measurements.md` — on battery, 60 s windows — not an impression.
