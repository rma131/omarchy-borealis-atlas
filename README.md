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

The scene is driven by actual data, resolved in QML and handed to the shader as a
handful of vec4s. The shader does no lookups and holds no arrays — deliberately,
since the GLSL 120 target rejects them (see the note atop `aurora.frag`).

Members added to the uniform block must go **last**. Anything inserted mid-block
is silently never written, which looks exactly like a shader bug and is not one.
The block currently ends `… ice, land, geo` and runs to 368 bytes.

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

**The moon.** A flat clean disc — deliberately not shaded like a sphere, which
read as modelled rather than minimal — carrying only a whisper of maria, plus a
soft **22-degree halo** thrown out at 3.3x its radius, stronger through thin cloud
because that is when you actually see one.

**The moon is accurate.** Phase from the synodic cycle drives a real terminator
(`x > cos(2*pi*phase) * sqrt(1-y^2)`, mirrored when waning), so crescent, quarter,
gibbous and full all render properly, with earthshine as a ghost on the dark limb.
Its *position* comes from the same phase — the moon's offset from the sun **is**
its phase, so a new moon rides with the sun and a full moon opposes it. Apparent
size follows the anomalistic cycle, so a perigee full moon is visibly bigger.

### Motion blur

Scrub fast and the stars smear along their arcs. The blur works by winding the
vault's **rotation** back and forth across seven taps, not by sliding the sample
point — sliding lands each tap on a different cell of the hash field, so seven
unrelated stars pile up dimly instead of one star drawing its path. Turning the
angle traces the same star, and the smear comes out tangential and longer further
from the pole for free. Speed is tracked in QML, rises instantly on a flick and is
eased back down by a timer, so a stop clears rather than freezing mid-trail. Below
a threshold there is one tap and no cost.

### Choosing a location

By default the location comes from an IP lookup. **geojs** is asked first and
wttr.in — the chain Omarchy's own weather widget uses — is the fallback, so
nothing new has to be reachable. The order matters through a VPN: on a Packethub
exit whose RIPE record reads `descr: Packethub Egypt, country: EG`, geojs
answered Cairo while wttr.in answered Vila Prota, **Brazil**. IP geolocation is
guesswork at the best of times — ipinfo.io and ipwho.is both put that same
address in *France* — so treat it as a good default rather than an authority,
and set a location explicitly when it matters.

To point it somewhere else — which is the easiest way to see the
interface in another climate — add either a place name or explicit coordinates to
this plugin's entry in `~/.config/omarchy/shell.json`:

    { "id": "local.borealis-touch", "location": "Reykjavik" }
    { "id": "local.borealis-touch", "latitude": 64.15, "longitude": -21.94 }

A name is geocoded once through Open-Meteo's geocoder (again, already used by
Omarchy). Editing the file re-resolves immediately, and a cache belonging to a
different place is discarded rather than trusted.

With **no** location configured it follows your IP, and **every summon forces a
fresh lookup** — change a VPN, reopen, and you are somewhere else. The cached
location is treated as where you *were*, never as the answer, so it is always
re-verified on load. A jump of more than about 20 km throws away the cached
forecast instead of showing the old city's weather under the new name. Changing
the configured place also drops the elevation ring and the climate figure, which
belong to where you were. `auroraFloor` and `palette` live in the same entry.

The label reads **date · city · country** — `Sunday 30 August · Montreal · Canada`.
The country comes from the same responses the city does (wttr.in's `country`,
the geocoder's `country`) and is simply left off when a lookup does not supply
one, rather than showing a trailing separator.

### The land follows the place

The ground is not one painted scene. Six scalars are derived from data about the
place, and the shader blends between them rather than switching between named
biomes, because the world has no hard edges:

| | from | drives |
|---|---|---|
| `cold` | mean temperature, latitude | conifers sharpen, the treeline thins, water runs to steel |
| `arid` | aridity index | ground goes to sand, trees disappear |
| `lush` | aridity index, temperature | deep saturated canopy, rounder crowns, water toward turquoise |
| `alpine` | elevation | bare rock, and snow on the tops regardless of today's weather |
| `relief` | elevation ring | how high and how jagged the skyline stands |
| `water` | elevation ring, aridity index | whether there is a lake at all |

**Aridity is a climate, not a fortnight.** Asking the 23-day forecast window put
Phoenix at 2.66 mm/day — a monsoon burst — and grew it a lush green lakeside. A
year of the reanalysis archive answers properly, and the measure is the UN's
aridity index, precipitation over potential evapotranspiration. The ratio also
cancels out the model's habit of over-raining on deserts, which a plain rainfall
total does not:

| | P | PET | P/PET |
|---|---|---|---|
| Sahara | 14 mm | 2616 mm | **0.01** |
| Dubai | 353 mm | 2012 mm | **0.18** |
| Phoenix | 493 mm | 1808 mm | **0.27** |
| Zermatt | 832 mm | 932 mm | **0.89** |
| Montreal | 1027 mm | 858 mm | **1.20** |

**Relief comes from one request.** `api.open-meteo.com/v1/elevation` takes
comma-separated coordinate lists, so a nine-point ring at roughly 50 km costs a
single call, and the spread across it is the skyline:

| | ring spread | `relief` | skyline |
|---|---|---|---|
| Montreal | 142 m | 0.09 | flat, a low treeline |
| Dubai | 266 m | 0.20 | low coast |
| Phoenix | 302 m | 0.23 | shallow hills |
| Tromso | 855 m | 0.69 | fjord ridges |
| Zermatt | 2213 m | 1.00 | jagged, crags on the crest |

Relief scales the ridge harmonics as well as its height, because a plain has to
read as a nearly straight horizon rather than as a shrunken mountain range. Both
ends are held: the ridge may not dip below the waterline, and may not wall off
the sky — this is a skyline, and the sky is most of what it is for.

**Where there is no water, a sand sea.** The lake used to be unconditional; the
Sahara got one. Sea shows up in the ring as points at zero elevation, but lakes
and rivers sit above sea level, so standing water inland is inferred from the
climate instead. Dubai is drier than Phoenix and still keeps its water, because
the ring finds the Gulf; Phoenix is semi-arid with no sea in reach and gets
dunes.

The dunes are crest lines running across the sand, crowding toward the horizon —
distance along a ground plane goes as 1/depth, and getting that backwards drew
fine corduroy at the viewer's feet instead. A low sun rakes across them and the
relief is everything; at noon it flattens out, which is how a dune field
actually looks. One tap of the sky does double duty: the light the sand is
bathed in, and, where it is hot enough, the mirage along the far edge — a mirage
being nothing but a false reflection. The lake spends five taps there; this
spends one.

Tree shape is a single exponent on the silhouette — high for conifers, low for a
rounded canopy, higher still and taller for palms on a hot wet coast. Drawn 170
across, a tree is a few pixels tall, so shape can only mean proportion; that is
enough to read as a palm, and it costs one `pow`.

### Sunrise and sunset, where you actually are

The sun used to rise at 06:00 and set at 18:00 everywhere on earth, every day of
the year — `dayPhase = (td - 0.25) * 2.0`, hard-coded in two places. It now comes
from `daily=sunrise,sunset,daylight_duration` on the forecast request already
being made, so it costs no extra call, and arrives as local wall-clock time under
the existing `timezone=auto`.

Two things follow from the day length, and getting only the first is worse than
getting neither:

- **When** the sun is up — a piecewise map onto the same 0..1-across-daylight
  axis, so `day`, `gold`, `night`, the arc, the cloud underlight and the water's
  glitter all keep working unchanged.
- **How high** it gets. Scaling only the duration gave a polar night a brief
  blazing noon, because the sine still reached full height inside its short day.
  `sin(altitude)` has the form `A + B cos(hour angle)`, and the day length fixes
  `A/B` on its own — the sun is up exactly while the cosine clears `-A/B`.

Normalised so a twelve-hour day still peaks at exactly 1.0, which is the look
this grew out of:

| | day length | peak altitude | hours above horizon |
|---|---|---|---|
| equinox | 12.0 h | 1.000 | 12.0 |
| Dubai, August | 12.7 h | 1.012 | 12.7 |
| Tromso, August | 15.6 h | 1.049 | 15.6 |
| Montreal, December | 9.0 h | **0.617** | 9.0 |
| polar night | — | 0.008 | 0.9 |
| polar day | — | 1.081 | 23.0 |

A winter sun now stays low all day, which the fixed model could never show.
Scrubbing the 23-day window shows the day length itself shortening by about nine
minutes a day.

### Time passes

Left alone the sky drifts forward at about **one sky-hour per real minute**, so
you look up and the day has moved. Touching it cancels the drift and returns to
the true now: idle is ambience, touched is truth — and since the readout is hidden
while it drifts, nothing on screen ever lies.

### The timeline strip

While scrubbing, a strip low on screen shows the hours around you as coloured
segments — clear, cloud, rain, snow, storm — with midnight dividers, a tick for
the real clock, and a playhead. The strip scrolls; the playhead does not, so the
moment you are looking at is always dead centre. It answers "when will it rain"
at a glance, which is the one thing scrubbing alone could never do.

### Winter

Whether snow *settles* is a different question from whether it is falling, and
the data answers both:

| Look | Source |
|---|---|
| Snow in the air | `snowfall` |
| Landscape white | **`snow_depth`** — falling snow that melts leaves this at zero |
| Frozen lake | trailing 72 h mean of `temperature_2m`, from the past days already fetched |
| Verglas | freezing-rain codes, or liquid precipitation onto sub-zero `soil_temperature_0cm` |

A frozen lake loses its ripple, its shimmer and its mirror — and gives nothing
back to a finger pushed across it, because ice does not ripple. Snow and ice are
lit by whatever light is up, moon included: keying them to daylight alone made
winter vanish at night, which is exactly backwards for a high-albedo surface.

### Wind, glitter, fog

Cloud drifts on the **real** wind (`wind_speed_10m` / `wind_direction_10m`),
reversing when the wind does, and rain and snow lean with it. A low sun or moon
lays a broken **glitter column** across the water, using the water's own facet
noise as a slope proxy. Fog gets its own low veil rather than being more cloud.
Precipitation intensity is no longer floored, so drizzle looks like drizzle.

### Gestures

| Gesture | Result |
|---|---|
| Double tap, one finger | roll back to today |
| Triple tap, one finger | leave |
| Quick tap, two fingers (no movement) | next palette |
| Drag left/right | scrub time of day (inverted: you pull the sky, as when scrolling content) |
| **Second finger while dragging** | inspect: parts the cloud, lifts the aurora, shows Kp |
| Press, hold or drag | push the light around |
| Any key | dismiss |

The two-finger gestures cannot collide: the palette tap requires *no* movement,
the inspect tap requires the first finger to already be dragging.

**Rolling home is paced by the distance**, roughly 800 ms per day travelled,
held between 0.9 s and 4.2 s — so you watch the days wind back rather than
having them flick past. It used to be a flat 1300 ms, which was right only while
the return snapped to the *nearest equivalent of now* and so never travelled
more than half a day; going to the true present made the same 1300 ms cover up
to three weeks, and three sunrises inside a second read as no animation at all.
The idle drift is gated on the return as well as on the scrub, because a drift
tick assigns `tod` and would otherwise cancel the animation and strand the sky
part-way home.

The readout stays hidden until a scrub actually begins — resting a finger on the
glass leaves the sky clean. Once moving, it names the moment: condition and
temperature on top, and the day being explored — `Saturday 29 August` — smaller
and quieter beneath.

`todGain` sets how many days a full-width drag covers (2.5). At that rate a pixel
is about two minutes of forecast, far finer than the hourly data, while the whole
23-day window is nine swipes wide.

Letting go **keeps** the hour you landed on, so a forecast can actually be read.
Double tap comes home to the real present; triple tap leaves. A single tap does
nothing on purpose — this is a screensaver you can park a forecast in, so leaving
should be deliberate. Any key still exits immediately.

While you are parked away from now, the readout and the strip stay faintly
visible, so a held forecast always says which moment it is showing.

**Cost.** Measured back to back on AC: previous build 1048 MHz GPU avg, this one
1093 MHz — about +4.3% for the whole feature. Precipitation composites in `main()`
after the branch, so it costs once per pixel rather than five times through the
water's reflection taps, and every weather block is guarded on a uniform, so clear
weather pays almost nothing.

## Considered and rejected: a real star catalogue

Prototyped properly before deciding, against the HYG catalogue with real
astronomy (sidereal time, RA/Dec to alt/az) for this location and time. It works,
and it still is not worth adopting. Recorded so it does not get re-investigated:

- **Half the sky is missing.** The scene faces south — the sun rises at the left
  edge — so the window spans azimuth 90 to 270. Measured at Montreal on a late
  August evening: **2118 of the 4246 stars above the horizon fall inside it, 50%**.
  Everything northern is behind the viewer, so the Plough, Cassiopeia and Polaris
  never appear. Those are the shapes people actually recognise.
- **A dead band across the top.** Altitude 90 maps to y = 0.175, so the top 17% of
  the frame is above the zenith and permanently empty.
- **Shapes stretch.** 180 degrees of sky across the width pulls the Summer
  Triangle into a long diagonal, with Deneb off-frame entirely.

Narrowing to a 120-degree window with altitude capped at 72 fixes all three and
looks genuinely good — the frame fills and the Milky Way's real clumping shows.
But the sun rises at azimuth 90 and sets at 270, both **outside** that window, so
sunrise and sunset would happen off-screen and the moon would spend much of the
night out of frame. That is not "add real stars", it is re-aiming the camera the
whole day cycle is built on.

The hash field costs nothing, fills the frame, and never has a dead band. The
scene is a mood piece, not a planetarium.

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
