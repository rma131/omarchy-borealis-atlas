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

## A real sky

The scene is driven by actual data, resolved in QML and handed to the shader as
two vec4s. The shader does no lookups and holds no arrays — deliberately, since
the GLSL 120 target rejects them (see the note atop `aurora.frag`).

**Weather.** Open-Meteo hourly (the source Omarchy's own weather panel already
uses), `past_days=1&forecast_days=3` — 96 samples in local time, aligned to the
`tod` axis. `past_days=7&forecast_days=16` (16 is the API maximum) gives **552
hourly samples across 23 days** — a week back, a fortnight forward — for about
21 KB. The scrub is clamped to that window, derived from the data rather than
hard-coded, and `resolveSky` refuses to report weather outside it, so the drag
never invents a forecast it does not hold.

Note the Kp forecast only runs ~3 days ahead. Beyond that the aurora falls back to
its floor and the readout shows `Kp —` rather than guessing. Scrub across the day and the sky changes with the forecast: cloud
cover closes the deck, rain and snow fall in front of everything, thunder bruises
the cloud and fires irregular flashes. Location comes from wttr.in by IP, the same
chain the bar widget uses. Cached to `~/.local/state/omarchy/borealis-sky.json`
and refreshed at most every 30 minutes. **Offline, everything is zero and the
scene renders exactly as it would without the feature** — no error state on screen.

**Aurora, only when it is real.** NOAA's Kp forecast is small and *time-indexed at
3 h resolution*, so it moves with the scrub — unlike the OVATION grid, which is
923 KB and a single "now" snapshot that cannot answer *at what time tonight*. Your
geographic position is converted to geomagnetic latitude and compared against the
auroral oval, whose equatorward edge sits near `66.5 - 2*Kp` degrees:

    prob = smoothstep(0, 10, magLat - (66.5 - 2*Kp - 8))

Never quite zero — `auroraFloor` (default 0.12, settable per-plugin in
`shell.json`) keeps a ghost of it on quiet nights so the screensaver stays itself.

**Clouds sit on top of the aurora**, because the aurora is 100 km up and the
weather is not. The curtain colour is held in a variable and fed forward, so the
cloud deck is lit *from above* by it and the ridge is bathed in it. An overcast
auroral night reads as glowing cloud, not a hidden aurora.

**The moon is accurate.** Phase from the synodic cycle drives a real terminator
(`x > cos(2*pi*phase) * sqrt(1-y^2)`, mirrored when waning), so crescent, quarter,
gibbous and full all render properly, with earthshine as a ghost on the dark limb.
Its *position* comes from the same phase — the moon's offset from the sun **is**
its phase, so a new moon rides with the sun and a full moon opposes it. Apparent
size follows the anomalistic cycle, so a perigee full moon is visibly bigger.

### Gestures

| Gesture | Result |
|---|---|
| Quick tap, one finger | dismiss |
| Quick tap, two fingers (no movement) | next palette |
| Drag left/right | scrub time of day (inverted: you pull the sky, as when scrolling content) |
| **Second finger while dragging** | inspect: parts the cloud, lifts the aurora, shows Kp |
| Press, hold or drag | push the light around |
| Any key | dismiss |

The two-finger gestures cannot collide: the palette tap requires *no* movement,
the inspect tap requires the first finger to already be dragging.

The readout stays hidden until a scrub actually begins — resting a finger on the
glass leaves the sky clean. Once moving, it names the moment: condition and
temperature on top, and the day being explored — `Saturday 29 August` — smaller
and quieter beneath.

`todGain` sets how many days a full-width drag covers (2.5). At that rate a pixel
is about two minutes of forecast, far finer than the hourly data, while the whole
23-day window is nine swipes wide.

Releasing returns the sky to the real time, taking the short way round — `tod` is
unbounded, so the nearest equivalent of "now" may be a whole day up or down.

**Cost.** Measured back to back on AC: previous build 1048 MHz GPU avg, this one
1093 MHz — about +4.3% for the whole feature. Precipitation composites in `main()`
after the branch, so it costs once per pixel rather than five times through the
water's reflection taps, and every weather block is guarded on a uniform, so clear
weather pays almost nothing.

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

## History

    git -C ~/.config/omarchy/plugins/local.borealis-touch log --oneline --decorate

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

## A real sky

The scene is driven by actual data, resolved in QML and handed to the shader as
two vec4s. The shader does no lookups and holds no arrays — deliberately, since
the GLSL 120 target rejects them (see the note atop `aurora.frag`).

**Weather.** Open-Meteo hourly (the source Omarchy's own weather panel already
uses), `past_days=1&forecast_days=3` — 96 samples in local time, aligned to the
`tod` axis. `past_days=7&forecast_days=16` (16 is the API maximum) gives **552
hourly samples across 23 days** — a week back, a fortnight forward — for about
21 KB. The scrub is clamped to that window, derived from the data rather than
hard-coded, and `resolveSky` refuses to report weather outside it, so the drag
never invents a forecast it does not hold.

Note the Kp forecast only runs ~3 days ahead. Beyond that the aurora falls back to
its floor and the readout shows `Kp —` rather than guessing. Scrub across the day and the sky changes with the forecast: cloud
cover closes the deck, rain and snow fall in front of everything, thunder bruises
the cloud and fires irregular flashes. Location comes from wttr.in by IP, the same
chain the bar widget uses. Cached to `~/.local/state/omarchy/borealis-sky.json`
and refreshed at most every 30 minutes. **Offline, everything is zero and the
scene renders exactly as it would without the feature** — no error state on screen.

**Aurora, only when it is real.** NOAA's Kp forecast is small and *time-indexed at
3 h resolution*, so it moves with the scrub — unlike the OVATION grid, which is
923 KB and a single "now" snapshot that cannot answer *at what time tonight*. Your
geographic position is converted to geomagnetic latitude and compared against the
auroral oval, whose equatorward edge sits near `66.5 - 2*Kp` degrees:

    prob = smoothstep(0, 10, magLat - (66.5 - 2*Kp - 8))

Never quite zero — `auroraFloor` (default 0.12, settable per-plugin in
`shell.json`) keeps a ghost of it on quiet nights so the screensaver stays itself.

**Clouds sit on top of the aurora**, because the aurora is 100 km up and the
weather is not. The curtain colour is held in a variable and fed forward, so the
cloud deck is lit *from above* by it and the ridge is bathed in it. An overcast
auroral night reads as glowing cloud, not a hidden aurora.

**The moon is accurate.** Phase from the synodic cycle drives a real terminator
(`x > cos(2*pi*phase) * sqrt(1-y^2)`, mirrored when waning), so crescent, quarter,
gibbous and full all render properly, with earthshine as a ghost on the dark limb.
Its *position* comes from the same phase — the moon's offset from the sun **is**
its phase, so a new moon rides with the sun and a full moon opposes it. Apparent
size follows the anomalistic cycle, so a perigee full moon is visibly bigger.

### Gestures

| Gesture | Result |
|---|---|
| Quick tap, one finger | dismiss |
| Quick tap, two fingers (no movement) | next palette |
| Drag left/right | scrub time of day (inverted: you pull the sky, as when scrolling content) |
| **Second finger while dragging** | inspect: parts the cloud, lifts the aurora, shows Kp |
| Press, hold or drag | push the light around |
| Any key | dismiss |

The two-finger gestures cannot collide: the palette tap requires *no* movement,
the inspect tap requires the first finger to already be dragging.

The readout stays hidden until a scrub actually begins — resting a finger on the
glass leaves the sky clean. Once moving, it names the moment: condition and
temperature on top, and the day being explored — `Saturday 29 August` — smaller
and quieter beneath.

`todGain` sets how many days a full-width drag covers (2.5). At that rate a pixel
is about two minutes of forecast, far finer than the hourly data, while the whole
23-day window is nine swipes wide.

Releasing returns the sky to the real time, taking the short way round — `tod` is
unbounded, so the nearest equivalent of "now" may be a whole day up or down.

**Cost.** Measured back to back on AC: previous build 1048 MHz GPU avg, this one
1093 MHz — about +4.3% for the whole feature. Precipitation composites in `main()`
after the branch, so it costs once per pixel rather than five times through the
water's reflection taps, and every weather block is guarded on a uniform, so clear
weather pays almost nothing.

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

## History

    git -C ~/.config/omarchy/plugins/local.borealis-touch log --oneline --decorate

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
