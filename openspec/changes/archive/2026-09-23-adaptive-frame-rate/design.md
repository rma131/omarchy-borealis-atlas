# Design: adaptive-frame-rate

## Findings

The whole case, from `docs/measurements.md`: the overlay open and **frozen**
draws 6.64 W against 6.62 W dismissed, at the idle GPU clock. The picture is
free; the redrawing is the entire bill.

Measured after this change, on battery, calm sky, 50 s window:

| State | Draw | GPU avg | Overlay's own cost |
|---|---|---|---|
| Idle, dismissed | 6.62 W | 301 MHz | — |
| **Paced, calm sky** | **8.76 W** | **354 MHz** | **+2.14 W** |
| Unpaced cheap mode (before) | ~11.4 W | 589 MHz | +4.8 W |
| Full quality | 18.22 W | 863 MHz | +11.60 W |

**82 % of the overlay's cost is gone** against full quality, and it is still the
same picture. Runtime on the 45.2 Wh cell goes from 2.5 h to about 5.2 h.

The three rates were each observed on the machine: 354 MHz on a calm Montreal
sky, 509 MHz at Quito while it was drizzling, 658 MHz with the search open.

## Options considered

| Option | Result | Verdict |
|---|---|---|
| Cap `time` alone at 30 Hz | no saving: `tod` still animated every vsync | rejected |
| Separate 33 ms timers for `time` and `tod` | *worse* than 60 fps — they interleave into 60 renders and pay double timer cost | rejected |
| One clock at 30 fps | −13 % GPU, lost to +5 pp CPU | too small a step |
| **One clock, 10 fps idle / 30 fps weather / 60 fps touched** | −82 % of the overlay's cost | chosen |
| Pace the mains path too | a QML timer is not vsync-aligned; judder for no reason to save | rejected |

## Decision

One timer, running only in the reduced-cost mode, advancing the shader clock and
the drift together. The interval is a pure function of two booleans the scene
already knows, so the rule is readable and testable rather than buried in timer
conditions.

The `Behavior on tod` is disabled while drifting under that clock. Leaving it on
would interpolate between the paced steps and put every frame straight back —
which is precisely the trap the 30 fps attempt fell into.

## What is left

`docs/measurements.md` now shows the cheap mode's remaining cost is small enough
that the 60 % render scale is arguably no longer worth its blur: ten frames a
second at full resolution measured cheaper than sixty at 60 %. That is a
separate change with a look to judge, and the requester's choice of 60 % was
made deliberately, so it is not reversed here.
