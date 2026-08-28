# Borealis Touch

A touch-reactive fork of [marko-builds/borealis](https://github.com/marko-builds/borealis)
(MIT — see LICENSE), made for the ThinkPad X1 Yoga's digitiser.

## What differs from upstream

**The finger is a repulsor in the aurora, not a lamp drawn on top of it.**
Upstream dismissed on *any* press, so on a touchscreen the first finger-down closed
the overlay before the scene could react. Here each touch contributes a radial
field, and the aurora is *sampled through* that field:

- **The light is pushed away.** Curtains are sampled at `uv - displacement`, so
  the aurora physically clears out around your finger.
- **Emission follows compression.** The field's **divergence** drives brightness:
  where the light piles up it burns brighter, where it is rarefied it thins. So a
  held finger opens a dark well ringed by a brighter rim — the light is not
  deleted, it is displaced and concentrated.
- **The stars come through.** The starfield is drawn before the curtains and is
  not displaced, so wherever the aurora thins the stars behind read through it
  (and are lifted further by the thinning factor).
- **Waves travel.** Touch-down launches an expanding wave whose crests and
  troughs alternate compression and rarefaction, banking the light into moving
  rings that fade over ~3 s.
- **The light springs back.** On release the push does not vanish — it decays as
  a damped oscillation (`RELAX_TAU`, `RELAX_OMEGA`), so the aurora overshoots and
  settles instead of snapping, which is what makes it read as displaced matter
  rather than a mask being switched off.
- **The water carries it.** The reflection evaluates the same field at the
  mirrored sky point, so the disturbance appears in the water too; separately,
  the field displaces the water *surface* where the finger meets it.
- Up to **three** simultaneous points.

**Dismissal is split by gesture**, because a screensaver still has to be trivial
to escape — especially folded into tablet mode where there is no keyboard:

| Gesture | Result |
|---|---|
| Quick tap, one finger (< 300 ms, < 12 px) | dismiss |
| Quick tap, **two fingers** | next palette |
| Press and hold, or any drag | interact, no dismiss |
| Any key | dismiss |

The palette cycles `aurora → ember → gold → nord → ice`. The override lives as
long as the shell does and is deliberately **not** written back to `shell.json`,
so your configured palette is never silently rewritten — dropping the override
(a shell restart) returns to whatever the config says.

## Cost

The touch guards test *uniforms*, not varyings, so the branch is coherent across
the draw: with no finger down the added code costs three scalar compares and the
field collapses to zero, rendering the stock scene exactly.

Measured on a UHD 620 at 1920x1080, on AC (GPU clock, avg of 1150 max):

| | GPU avg |
|---|---|
| Stock upstream | 952 MHz |
| This fork, nothing touching | 1014 MHz |

The field model costs about **+6.5 %** even with nothing touching. That is not the
field maths — with no touch every slot early-outs and the field is exactly zero —
it is that `upperScene` now carries the field parameters through all five of the
water's reflection taps, and the extra live values cost occupancy on a 24-EU part.
Interaction on top of that is nearly free (measured ~+2 % with a wave relaunching
every 50 ms), because the field is evaluated **once** per pixel and shared across
those five taps: they sit far closer together than the field varies, so per-tap
evaluation would cost five times as much for no visible difference.

The earlier additive-bloom version was free at idle; this one is not. If you want
that back, the lever is the reflection tap count (five taps in `main()`), not the
touch code.

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

    { "id": "local.borealis-touch", "palette": "nord" }

## Branches

    git -C ~/.config/omarchy/plugins/local.borealis-touch log --oneline --all --decorate

| Branch | What |
|---|---|
| `main` (tag `working-night`) | night-only: repulsion field, spring-back, palette cycle |
| `dawn-vault` | adds the night→dawn drag (sun, setting moon, rotating stars, no aurora) |

Switching branches changes the shader on disk, and **Quickshell will not pick that
up on its own** — clear its QML cache and restart the shell:

    git switch main          # or: git switch dawn-vault
    rm -rf ~/.cache/quickshell ~/.cache/qtshadercache-*
    omarchy-restart-shell

### The dawn drag (`dawn-vault` only)

A vertical drag turns the celestial vault; up goes toward dawn, down back to
night. It is measured **relative to where the drag began**, so touching high on
the screen does not snap to daylight. Let go and it eases back to night over
~1.5 s, so the resting screensaver is unchanged.

**Clouds.** A wispy deck fades in with dawn, stretched hard in x so the bands run
parallel to the aurora curtains — texture, not weather. How it is lit depends on
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
