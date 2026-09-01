# Developing Borealis Atlas

Before changing anything in `shaders/aurora.frag` or the palette table in
`BorealisAtlas.qml`, know which parts are Marko Stankovic's from
[Borealis](https://github.com/marko-builds/borealis) — six shader functions and
all five palettes, carried here unchanged. They are marked in the headers of
both files and accounted for in the [Credits](../README.md#credits). Improving
them is allowed; doing it silently is not.

Notes for changing the plugin, not for using it. For that, see
[the README](../README.md); for why the scene works the way it does, see
[design.md](design.md).

## Developing this plugin: clear the QML cache

Quickshell caches compiled QML in `~/.cache/quickshell/qmlcache`, and it will
happily serve a **stale** component after you edit a plugin. Symptom: your edits
appear to do nothing at all — not a wrong result, no result, as if the file were
never touched. Clearing `~/.cache/qtshadercache-*` alone is not enough.

    rm -rf ~/.cache/quickshell ~/.cache/qtshadercache-*
    omarchy-restart-shell

Also note `open()` calls `clearSlots()`. If you pin a touch slot to a literal for
testing, pin it *inside* `clearSlots()` — a pinned property default is wiped the
moment the overlay is summoned, which looks exactly like the uniform never
arriving.

## Rebuilding the shader

The `.qsb` is the only binary in this repository, and it is reproducible: see
[build-provenance.md](build-provenance.md) for the pinned toolchain, the exact
command, the digests, and a one-command way for anyone to check the shipped
artifact against a rebuild. CI enforces it. Always commit the `.frag` and the
`.qsb` together.

`qsb` ships in `qt6-shadertools` but is not on `PATH`:

    export PATH="$PATH:/usr/lib/qt6/bin"
    qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
        -o shaders/aurora.frag.qsb shaders/aurora.frag

Those targets match upstream's. Tuning lives at the top of `aurora.frag`:
`PUSH_AMP`/`PUSH_SIGMA` (how hard and how tightly a finger shoves the light),
`COMPRESS` (divergence into brightness), `WAVE_AMP`/`WAVE_K` (ring depth and
spacing), and `RELAX_TAU`/`RELAX_OMEGA`/`RELAX_LIFE` (the spring-back). **Never introduce a const array or a
dynamically-indexed array**: the GLSL 120 target rejects them at runtime with
`C7516: OpenGL does not allow constant arrays` and a blank overlay, while qsb
itself compiles clean. That is why the touch slots are three separate `vec4`
uniforms rather than an array, mirroring how upstream passes its palette.

## Palette

As upstream — set `palette` on this plugin's entry in `~/.config/omarchy/shell.json`
(`aurora` | `ember` | `gold` | `nord` | `ice`):

    { "id": "io.github.rma131.borealis-atlas", "palette": "nord" }

## History

    git -C ~/.config/omarchy/plugins/io.github.rma131.borealis-atlas log --oneline --decorate

`main` carries everything: the night interaction and the dawn drag. The
night-only build — repulsion field, spring-back, palette cycle, no dawn — is kept
at the tag **`working-night`**, which is the thing to go back to if the dawn work
ever needs undoing:

    git switch -d working-night     # look at it
    git switch -c night-only working-night   # or branch from it

Whenever you move between these, the shader on disk changes and **Quickshell will
not notice** — it serves its cached QML instead. Clear the cache and restart:

    rm -rf ~/.cache/quickshell ~/.cache/qtshadercache-*
    omarchy-restart-shell

### The time-of-day drag

Drag **left to right** to run the clock forward, right to left to run it back.
The whole 24 h cycle is covered: full night → dawn → full daylight → afternoon →
dusk → night, with the usual transitions between.

When you summon the overlay it **seeds itself from the real clock**, so it opens
on whatever time of day it actually is. From there the drag is measured relative
to where it began — touching near an edge does not jump the sky to a different
hour — and dragging the full width of the screen advances one whole day
(`todGain`). Where you let go is where it stays; the next summon re-syncs.

What moves with the hour:

| | |
|---|---|
| Sun | rises east, arcs overhead at noon, sets west; reddens near the horizon |
| Moon | rides the opposite half of the clock, fading out in daylight |
| Sky | night palette → golden-hour band → daylight blue |
| Stars | night only, and the vault turns slowly through the night |
| Aurora, meteors | night only — they fade as the sun approaches the horizon |
| Clouds | day and golden hour, lit by the sun's angle; held at zero at night |
| Ridge | silhouette by night, lit green by day |

`tod` is deliberately **unbounded** on the QML side: letting it run past 1 means a
drag through midnight keeps going forward, instead of the easing animation
winding backwards through a whole day. The shader wraps it with `fract()`.

**Cost.** Measured back to back on AC: the previous build at night 1076 MHz GPU
avg, this build at night 1075 MHz — the cycle is free when it is dark. Daytime is
1080 MHz, because the aurora's three curtain layers switching off very nearly
pays for the cloud deck switching on.

### The dawn drag

A vertical drag turns the celestial vault; up goes toward dawn, down back to
night. It is measured **relative to where the drag began**, so touching high on
the screen does not snap to daylight. Let go and it eases back to night over
~1.5 s, so the resting screensaver is unchanged.

**Clouds.** A wispy deck fades in with dawn, stretched hard in x so the bands run
parallel to the aurora curtains — texture, not weather. It drifts on a wind that
complements the aurora rather than fighting it: the brightest curtain travels
left at ~0.030 uv/s (its ray term `sin(fx*23 + t*0.7)` moves at `-rayS/rayF`), so
the deck goes the same way at about a third of that, with the upper layer lagging
the lower for parallax and a slow swell so it breathes instead of sliding as a
rigid sheet. Measured by isolating the cloud field and correlating two frames 8 s
apart: **+163 px, or +0.0106 uv/s leftward**, against +0.0105 predicted. How it is lit depends on
where the sun sits relative to the horizon: grazing gives red underlight, higher
gives gold, and cloud far from the sun stays cool. The deck is displaced by the
touch field exactly like the curtains, and compression concentrates its highlight,
so pushing the sky slides the sunlit edge across the cloud rather than moving the
cloud under a fixed glow.

**The palette grounds the dawn without repainting it.** The warm horizon and the
sun keep their real colours; only the cool half — zenith and the shaded side of
the cloud — takes a hint of the palette (`PALETTE_TINT`, 0.30), applied as a
*multiply* so it shifts hue without wrecking luminance. A warm palette therefore
reads as contrast against a cool sky, a cool one harmonises with it, and it still
looks like a sunrise rather than a theme swap.

**Cost.** Night is untouched — every addition sits behind `if (dawn > 0.0)`, which
is uniform across the draw (measured: 761 MHz GPU avg at night, same as without
this branch). Full dawn runs ~997 MHz, about +31 %, because the cloud noise is
evaluated inside `upperScene` and so runs five times over in the water band. That
only applies while you are actually dragging.

Tunables: `dawnGain` in the QML (how much drag covers the range), `PALETTE_TINT`
and `cloudField` in the shader, and the `dawn`-keyed constants in `upperScene`.
