# Borealis Atlas — how the scene is built

Everything here is the reasoning behind what you see, kept because most of it
was arrived at by measuring rather than guessing, and the measurements are the
part worth keeping. For what the plugin *is* and how to install it, see
[the README](../README.md).

**The scene is [marko-builds/borealis](https://github.com/marko-builds/borealis)
(MIT), by Marko Stankovic, with a great deal built around it.** Read that
sentence literally: `curtain()`, `ramp()`, `vnoise()`, `hash21()`, `dither()`
and `meteors()` are his, unchanged, and so are all five palettes. Everything
described below is an addition to a scene that was already beautiful, and where
a section says "the aurora" or "the palette" it is describing his work, not
ours. The full accounting, with line counts measured against his source, is in
the [Credits](../README.md#credits).

The first section is simply what changed first: making a finger something the
aurora reacts to rather than something that closes it.

## The finger is a repulsor, not a lamp

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

**Three elevation requests per location change**, not one — the compass rings,
the near field, and the fan — plus the forecast and the climate archive. All of
it happens only when the place changes, which is rare, and nothing recurs per
frame. It is enough to matter during development, though: a day of probing this
into shape exhausted Open-Meteo's free daily quota and the endpoint started
answering `429`, so the last round of scene checks was driven from measured
values injected into the cache rather than live. The requests now carry
`--retry 2`, because a transient `503` used to leave the chain dead until the
next refresh.

**The measured skyline was not measurable.** The ridge went from four
transcendentals per fragment to twelve when it stopped inventing its harmonics
and started summing the fitted ones. Interleaved back to back in one session,
before/after/before/after: 1036, 1016, 972, 1007 MHz. The gap between the two
*identical* "before" runs is 6.6 %, larger than any before-to-after difference,
so this says nothing except that the change is smaller than the noise floor of
this machine. No claim is made either way. The two elevation requests are the
real cost, and they happen once per location change.

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

**Or type it.** Press `/` and the scene dims to a single field: type a place,
press Enter, and the sky becomes that place. Enter on an empty field goes back
to following the machine; Esc cancels. Forward geocoding returns the name and
country along with the coordinates, so a typed place needs no second lookup to
be labelled, and an unrecognised one says *No such place* rather than quietly
going somewhere else. A typed place outranks both `shell.json` and the IP, and
survives a restart in the same state file as the forecast.

`/` was chosen so that **every other key still dismisses**, which is the one
property a screensaver must not lose: grabbing letters to start typing would
mean a cat on the keyboard opens a search box instead of getting out of the way.

*Removed:* a tappable world map lived here briefly (`20dca08`…`5ac7f3c`,
reverted in `5ed1b55`). Two gestures were tried to open it and neither survived
contact with a hand — two fingers held still could not reliably be performed,
and the edge swipe raised the sheet but `MouseArea` never sees a finger on this
overlay, so nothing on it could be tapped and it would not close. The lesson
worth keeping: there is exactly one input path that works here, the
`MultiPointTouchArea`, and a feature needing any other kind of pointer handling
does not belong on the glass. Typing has no such problem.

To point it somewhere else permanently, add either a place name or explicit
coordinates to this plugin's entry in `~/.config/omarchy/shell.json`:

    { "id": "io.github.rma131.borealis-atlas", "location": "Reykjavik" }
    { "id": "io.github.rma131.borealis-atlas", "latitude": 64.15, "longitude": -21.94 }

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
| `alpine` | elevation against the local treeline | bare rock on the ground you stand on |
| `relief` | how tall the horizon looks, in degrees | how high the skyline stands |
| `water` | the near field, measured | whether there is water, and what kind |

Two more are altitudes rather than scalars, and become horizontal lines across
the picture: see **The skyline is the one that is really there** below.

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

**Where there is no water, ground.** The lake used to be unconditional — the
Sahara got one — and then it was inferred from humidity, which gave Quito one
for being wet. It is now found: see **Water is the flat thing** below. Where
there is none, the foreground is the ground you are standing on, and what that
is made of comes from the climate rather than from a choice: crested dunes
where it is genuinely arid, smooth pasture where it is not, stone where it is
cold. The Sahara and the paramo above Quito are the same branch with different
numbers.

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

### The skyline is the one that is really there

The ridge used to be three sines with hand-tuned constants, scaled by a single
relief number — so Quito and Kathmandu got the same invented range, taller or
shorter. It is now the country that is actually out there, measured in two
requests of a hundred coordinates. A hundred exactly: the elevation API accepts
100 and answers 101 with a `400`.

- **Pass 1** — a centre and 33 azimuths at 4, 11 and 25 km. Does the old job
  (spread for the terrain scalars, points at zero elevation for water) and, from
  the largest apparent angle, says which way the country rises. That is the way
  the view faces.
- **Pass 2** — 20 azimuths across the 150° facing that way, five distances each,
  merged with whatever pass 1 already saw inside the same window.

Apparent angle is `atan((h − h₀ − d²/2R) / d)` with `R` the earth's radius times
7/6, the standard optical correction, so a distant summit is not pushed below
the horizon by curvature it does not visually suffer.

**Shape comes from altitude, size from angle.** These are not the same question
and conflating them was the one real dead end. A near 3400 m ridge subtends more
than Pichincha does behind it, so a profile built from apparent angle drew the
near ridge as the summit — and scaled Quito's mountain at 718 m of altitude per
unit of drawn ridge when the truth is 1707, which put the snowline past the top
of a mountain that was not the right mountain anyway. So the silhouette is built
from the highest *ground* along each bearing, and how tall the whole thing
stands is a separate number taken from the angle:

| | faces | tallest in frame | summit | `relief` | ridge height |
|---|---|---|---|---|---|
| Montreal | WSW | 2.3° | 177 m — Mount Royal, 2 km | 0.18 | 0.096 |
| Tromso | — | 5.9° | 1165 m | 0.38 | 0.135 |
| Quito | W | 14.1° | 4565 m — Pichincha, 11 km | 0.75 | 0.211 |
| Zermatt | — | 26.8° | 4157 m | 1.00 | 0.260 |

Twenty columns reach the shader as **twelve coefficients of a half-range cosine
series** — a cosine fit and not a Fourier one, because a Fourier fit forces
`profile(0) == profile(1)` and puts a seam down the edge of the frame. Twelve
places the summit within 0.03 of where it belongs and fits in three `vec4`s;
eight was visibly soft. The fit is smooth by construction and rock is not, so
two octaves of synthetic crag ride on top, scaled by relief.

**Snow lies above the freezing level and nowhere else.** `freezing_level_height`
is one more hourly variable on the forecast call that already happens, so it
costs nothing and already spans the whole scrub range. It becomes a fraction of
the ridge's own height — `(flz − base) / span` — and the shader draws it as a
**horizontal line**, because that is what a contour is: a snowline cuts straight
through a range, it does not drape itself over each crest in turn. Past 1.0 the
line clears every summit and there is simply no snow, which needs no flag.

This is the whole of the behaviour Quito was asked for. Pichincha's top is at
4565 m in this dataset; the freezing level over a typical three weeks runs
4540–5430, so the mountain is bare almost always and carries a cap on the cold
nights when the line dips under the summit. The city below never does. Zermatt,
where the freezing level runs 3230–4740 against a 4157 m skyline, shows the line
sweep hundreds of metres down the slope as you scrub from a warm day to a cold
one.

The treeline is the same machinery: roughly 3500 m at the equator falling 40 m
per degree of latitude, so Quito's 2920 m floor is below its own 3491 m treeline
and drawn green while the top of Pichincha is bare, and Zermatt's whole visible
ridge is above the line and drawn as rock. `alpine` was rebased on this too — it
used to mean "high above the sea", which put Quito at 1.0 and painted the entire
city as grey rock under permanent caps.

**Where it is soft.** The model is a 90 m DEM sampled a hundred points at a time,
so a lone spire reads as a broad peak and a summit can come in a little low —
Pichincha at 4565 against a published 4696, though a 100-point grid over the
whole massif only reaches 4645, so most of that gap is the dataset's. A summit
read low biases the snowline late rather than early. Features narrower than
about 8° of arc are not resolved. And facing the terrain means the view no
longer points any particular compass direction, so the sun still rises on the
left in Quito while the mountain it lights is due west.

Not every model carries `freezing_level_height` — Tromso returns 48/48 nulls
with units `"undefined"` — so where it is missing it is estimated from the
surface temperature and the standard 6.5 °C/km lapse rate. Checked where both
exist: Montreal 3153 m against 3291 measured, Quito 5228 against 4925.

### Water is the flat thing

Water was the last part of the scene still being guessed at. Sea shows up in
the elevation ring as points at zero, but lakes and rivers sit above sea level,
so inland water was inferred from humidity — which gave Quito a lake for being
wet, and gave a place with a river beside it exactly the same lake as a place
with none.

It is now measured, and the signal could not be simpler: **water is flat.**
Copernicus conditions water surfaces to a single exact value, and real terrain
essentially never repeats an exact metre, so a repeated elevation is a water
surface. A hundred points on a 12 km square, 1.3 km apart, is enough to find it.

Flat farmland is the one confound, and two further properties settle it. Water
is the **lowest** level present — it is where water collects — and it is an
**isolated spike** rather than the shoulder of a smooth cluster:

| | level | share | isolation | lowest? | |
|---|---|---|---|---|---|
| New York | 0 m | 32% | 5.9 | yes | **sea** |
| Chicago | 174 m | 42% | 48.0 | yes | **lake** |
| Montreal | 4 m | 6% | 2.5 | yes | **river** |
| Kansas farmland | 508 m | 7% | 0.7 | no, 71% up | dry |
| Quito | — | — | — | — | dry |

Kansas repeats 508 m seven times, but 507 and 509 are there too and 508 sits
most of the way up the local range. Lake Michigan repeats 174 m forty-eight
times with *nothing* at 173 or 175, at the very bottom. Quito returns 95
distinct values out of 100 and no repeats at all, which is how "there is no
water here" gets said.

Sea reads as exactly zero. Past that, how much of the near field the water
covers says whether it is open or a channel, and the difference reaches the
shader as one number — how far toward you the water comes:

| | near bank | wave | mirror | what you see |
|---|---|---|---|---|
| none | at the waterline | — | — | the water branch never runs |
| river | 0.90 | 0.55 | 2.2 | a band, with a bank in front of you |
| lake | 0.965 | 1.00 | 3.2 | nearly the whole foreground, a sliver of shore |
| sea | 1.00 | 1.50 | 4.2 | all of it, the longest swell |

The mirror figure is how hard the reflection is squashed, which is what says
how wide the water is: a channel gives back a short section of sky, an ocean a
long one.

**And the eye stands across it.** This scene has always been composing a view
across water toward land, so when there is water near the place, the viewpoint
goes to the far side of it and faces back — the eye at the water's own level,
which is exactly where the scene puts its horizon. Montreal becomes the
postcard: the St Lawrence in front, Mount Royal on the skyline behind it.

Mount Royal is the reason this matters. Open-Meteo's geocoder puts "Montreal"
*on the summit* at 226 m, where nothing rises above you and the profile
collapsed to a flat plain. It is not that the hill is too small — from across
the river it is a 182 m peak at 1.4 degrees, alone on an otherwise flat
horizon, which is exactly what Mount Royal is.

Two things had to be got right for that to work. The distance is the **median**
of the water samples along the bearing, not the farthest: the near field is a
square, so its corners are 8.5 km out, and a river running diagonally across
one pushed the viewpoint to the cap and halved the hill. And the fan's rings
**scale with how far back you stand** — fixed rings at 6 and 11 km straddled a
2 km hill 7 km away and missed it completely.

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

### The clock belongs to the place, not the machine

The forecast was always fetched with `timezone=auto`, so its hours were already
the target's hours. What was not was the clock the scene was seeded from: `tod`
started at the local wall clock, so asking for Istanbul from Montreal drew
Istanbul's data under Montreal's sun — a fourteen-hour error, which is night for
day.

`utc_offset_seconds` comes back on the same reply the hours do, so the two can
never disagree. One shift function turns a real instant into a `Date` whose
local getters read the target's wall clock, and everything that needed a
midnight now takes the target's:

- the seed for `tod`, and the moment a double tap returns to;
- `t0`, the first sample's distance from midnight — which has to be computed
  *after* the offset is set, or the entire 23-day window slides;
- NOAA's Kp timestamps, which are real instants in UTC. Kp is a global number,
  but *when* it applies is local, and an eight-hour error put the aurora
  forecast on the wrong side of the night;
- "Yesterday"/"Tomorrow" in the readout.

Landing on a place in another zone re-seeds the sky to the hour it actually is
there, unless a finger is on the timeline — a moment that was chosen is not ours
to take back. The readout names the zone only when it differs from yours; its
absence is the statement that they agree.

### An eclipse is two discs the same size

The sun's apparent radius is 0.2666°, the moon's mean 0.2596°. That
near-equality is the only reason an eclipse is a thing that happens at all, and
the scene used to throw it away: the moon was drawn at nearly twice the sun, so
the two read as different kinds of object and one could never hide the other.
They are now the same size, and the moon's own distance — which swings its
radius from 0.92 to 1.03 of the sun's — decides whether an eclipse goes total or
leaves a ring showing.

The phase model had to be rebuilt for this. Two counters ticking off a synodic
and an anomalistic month are good to about half a day, which is fine for a
crescent in the corner and useless for an alignment that lasts two hours. It is
now Meeus' mean elements with the largest periodic terms — the moon's true
longitude less the sun's — which lands within about two minutes, plus the
ecliptic latitude, because the orbit's five-degree tilt is *why* an eclipse is
rare rather than monthly.

Two things then had to be got right that are easy to get wrong:

- **Parallax.** At a *total* solar eclipse the geocentric separation of the two
  centres is around 0.9°, not zero — nearly two disc widths. An observer stands
  four thousand miles off the centre of the earth and sees the moon displaced by
  up to its horizontal parallax. Treating the geocentric separation as the
  criterion found no eclipses at all. What is drawn is what the best-placed
  observer sees: the separation less the parallax, floored at zero.
- **Scale.** The rest of this sky compresses a month across a screen width. At
  that scale the two discs would sit on each other for three days instead of two
  hours, so near conjunction the moon is placed off the sun at true angular
  scale instead, and the override is gated so the handover cannot manufacture a
  shallow false eclipse of its own.

Checked against every eclipse from 2026 to 2028:

| | geocentric lat | moon/sun | drawn as |
|---|---|---|---|
| 2026-02-17 | −0.93° | 0.960 | annular |
| 2026-03-03 | −0.37° | — | total lunar |
| 2026-08-12 | +0.91° | 1.031 | total |
| 2026-08-28 | +0.47° | — | partial lunar |
| 2027-02-06 | −0.27° | 0.914 | annular |
| 2027-08-02 | +0.16° | 1.060 | total |
| 2028-07-22 | −0.60° | 1.042 | total |
| new moon 2026-05-16 | +4.94° | — | nothing |
| new moon 2026-10-10 | −3.83° | — | nothing |

The lunar case needs no parallax correction, because the shadow is out there
with the moon. Its depth falls out of the same geometry — umbra 0.70° of radius,
moon 0.26° — and so, for free, does its duration: three and a half hours of
shadow with an hour of totality inside it, which is what a total lunar eclipse
actually is. Penumbral eclipses correctly produce nothing, because a penumbral
eclipse is invisible.

Totality dims the day, brings the stars out and puts a sunset all the way round
the horizon; an annular eclipse gets a fraction of the dimming and no stars,
because a ring of photosphere is millions of times brighter than the corona.

### A thunderstorm is a state of the atmosphere, not a code

Toronto, 2 September, is the case that made this. A storm everyone outdoors
remembers, and the scene drew ordinary rain — because storminess was decided
entirely by the WMO code being 95 or above, and the code for that hour was 82,
"violent rain showers". Asked about the same hour, the four global models said:

| model, 16:00 local | code | precipitation | CAPE | gusts |
|---|---|---|---|---|
| GFS (`best_match` here) | 82 violent rain showers | 7.9 mm/h | 1970 | 14 km/h |
| ICON | 80 rain showers *(96, thunderstorm with hail, an hour later)* | 0.8 mm/h | 1770 | 36 km/h |
| ECMWF | 95 thunderstorm | 1.2 mm/h | 2690 | 36 km/h |
| GEM | 51 drizzle | 0.2 mm/h | 2220 | 13 km/h |

They cannot all be right, and picking one is picking a coin toss. They disagree
about the rate by a factor of forty and about the hour as well. But every one of
them put CAPE between 1770 and 2690 J/kg, and GFS — the one that called it
showers — put the lifted index at −6.4. That is not a disagreement: that is a
severe-thunderstorm atmosphere, and it is what the code is supposed to be a
summary of.

So the physics decides and the code only votes. `cape` and `lifted_index` come
back on the forecast request already being made. 2200 J/kg is a strong cell and
a lifted index of −6.5 says the same thing another way; either alone is enough.
Instability on its own is just a hot afternoon, though — Toronto had 2140 J/kg
at 14:00 under a clear sky — so something has to be falling out of it before any
of it is a storm you can see.

| hour | code | mm/h | CAPE | storm | drawn as |
|---|---|---|---|---|---|
| 14:00 | 1 | 0.0 | 2140 | 0.00 | a hot clear afternoon |
| 15:00 | 3 | 0.0 | 2100 | 0.00 | overcast |
| **16:00** | 82 | 7.9 | 1970 | **0.98** | **thunderstorm** |
| 17:00 | 81 | 2.9 | 1510 | 0.64 | thunderstorm |
| 19:00 | 63 | 6.1 | 170 | 0.23 | heavy rain, no storm |

Rain intensity was recalibrated at the same time: a linear 3 mm/h ceiling
saturated at moderate rain, so the 8 mm/h hour of a real cell drew exactly what
an ordinary wet afternoon did.

**Warnings.** There is no free global feed of official warnings — they are
national, and stitching the NWS, MeteoAlarm and Environment Canada together
would be three more providers for three parts of the world. What this has
instead is the *threshold* rather than the bulletin: Environment Canada and the
NWS both issue a severe thunderstorm warning at roughly 90 km/h gusts, and a
rainfall warning around 50 mm in an hour. Gusts are taken as the strongest of
the hours either side, because a damaging gust is a ten-minute event that an
hourly sample lands on or misses. Above that tier the deck hangs lower and goes
green-black, the rain gains a third faster layer and a curtain you cannot see
through, the strike rate climbs, the sky lights from a point instead of evenly,
and a forked channel is drawn for the frames the flash is alive.

The honest limit: this is one model. On the Toronto cell it reaches a moderate
warning tier rather than a high one, because GFS — which is what `best_match`
picks for Toronto — never put that afternoon's gusts above 27 km/h, while ICON
peaked at 39 and GEM at 46. Taking the worst of several models is what a
forecaster does for severe weather, and it would cost one more request; it would
also make every place on earth stormier than it is, which is the opposite of the
point. CAPE and the lifted index were chosen precisely because they are the
fields the models agree on.

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
| `/` | type a place to go to |
| Any other key | dismiss |

The two-finger gestures cannot collide: the palette tap requires *no* movement,
the inspect tap requires the first finger to already be dragging.

**A tap has to land in the same place twice.** This is the constraint the
multi-tap gestures were missing, and its absence produced both failures in turn.
Judging a tap only by how far it strayed from its own start meant either the
double tap never fired after a drag — at 12 px, less than a fingertip shifts on
contact — or, once loosened to 34 px, the return home firing on mispresses. Taps
now allow 22 px of wander each, but a tap more than 110 px from the previous one
**starts a new count** rather than continuing it, so playing with the light in
two places cannot add up to "go home". The window between taps is 430 ms.

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
