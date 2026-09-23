# Design: low-cost-mode

## Findings

Measured on the machine in `docs/measurements.md`, GPU average clock over 35–45 s
windows, overlay open, same place and same minute where the rows are compared.
Idle with the overlay dismissed is 302 MHz, which reproduces the August figure
of 301 exactly — so the harness is sound.

| Scene | GPU avg | vs full |
|---|---|---|
| Toronto, full | 1021 MHz | — |
| Toronto, reflection taps 5 → 3 | 995 MHz | −2.5 % |
| Toronto, 75 % render resolution | 876 MHz | −14 % |
| Toronto, **shipped battery mode** | **688 MHz** | **−33 %** |
| Banff, 75 % / 60 % resolution | 703 / 601 MHz | −31 % / −41 % |

Two things the numbers say that the proposal did not.

**The scene got more expensive.** August measured 748 MHz average against an
1150 MHz ceiling. It is now 1021 — the eclipses, the storms, the globe and the
growing season have all been added since. The August reading is no longer the
state of this shader.

**The reflection taps are no longer the lever.** The proposal quoted
`docs/measurements.md`: "the bottom 18 % of the screen costs 5× the sky …
dropping to 3 taps is the cheapest big win". Measured today it is worth 2.5 %,
and that is *with* Lake Ontario filling the foreground — the first attempt was
made at Banff, which has no water at all and where it is worth nothing. A river
is a narrow band, and most places are not on a lake.

**Frame rate cannot show any of this.** Both modes sit at ~55 fps against a
60 Hz display: the work is vsync-bound, so what changes is how hard the GPU
worked inside the frame, not how many frames arrived. The clock is the metric
that moves; frames are not.

## Options considered

| Option | Result | Verdict |
|---|---|---|
| Reflection taps 5 → 3 | −2.5 % with a lake in view, 0 without | kept, but not the answer |
| Cheaper sky inside the reflection only | folded into the above | kept |
| Two aurora curtains instead of three, everywhere | changes the sky you look at | rejected |
| 30 fps cap | vsync-bound already; a QML timer is not vsync-aligned and would judder | not attempted |
| Render at 75 % and upscale | −14 to −31 % | superseded |
| **Render at 60 % and upscale** | **−33 % measured end to end** | **chosen** |

## Decision

On battery: render into a texture 60 % of each dimension and let the compositor
scale it up, and build the water from three cheap copies of the sky instead of
five full ones. On mains, nothing changes at all — the layer is off, so there is
not even an extra copy.

`resolution` is passed as the render target's own size rather than the screen's.
The shader feathers the ridge at `1.5 / resolution.y` and lays the starfield out
in cells of fourteen, so telling it the screen size while drawing into a smaller
texture would harden every edge and shrink every star by exactly the factor the
picture is about to be stretched by. Doing this correctly is why the shipped
mode measures better than the bare 60 % experiment did.

## Corrections

The approved proposal put "rendering at reduced resolution and upscaling" out of
scope, and chose fewer taps on the strength of the August measurement. That
measurement no longer describes this shader: fewer taps is worth 2.5 % and
resolution is worth 33 %. The numbers were put to the requester with the visual
cost stated — the tree crowns go soft, which is the one place the scene has
pixel-fine detail — and 60 % was chosen deliberately over 75 % and over
shipping nothing.

## Measured again on battery, 2026-09-23

The GPU clock understated it. Unplugged, where `power_now` reports real draw:

| State | Draw | GPU avg | Runtime on 45.2 Wh |
|---|---|---|---|
| Idle, dismissed | 6.62 W | 300 MHz | 6.8 h |
| Battery mode | 10.73 W | 618 MHz | 4.2 h |
| Full quality | 18.22 W | 863 MHz | 2.5 h |

The overlay's own cost is +11.60 W at full and +4.11 W in the cheap mode: **65 %
of it gone**, against the 33 % the clock had suggested. The clock is a governed,
coarse quantity and it hides work that scales with resolution, so it is a sign
of the direction but not of the size. Watts are the measurement; the clock is
only what can be read while plugged in.
