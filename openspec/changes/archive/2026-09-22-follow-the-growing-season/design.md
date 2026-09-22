# Design: follow-the-growing-season

## Findings

**The equinox defeats absolute day length.** The first prototype normalised
photoperiod over the year and read it as a season. At the September equinox
every place on earth is within minutes of 12 h, so on the date the request was
made the signal separated nothing; at the equator the whole annual swing is
about three minutes, and normalising it *invented* a season in Quito. What
separates places on that date is the **rate**: Tromsø is losing about ten
minutes of daylight a day and Kyoto about two. The plugin takes both from the
`sunrise`/`sunset` series it already holds, measured over a week rather than a
day — sunrise is reported to the minute, so a one-day difference is mostly
rounding and its sign can come out backwards.

**Cold nights, not mean temperature.** The second prototype gave Kyoto the same
autumn as Montreal. Accumulated cold below 16 °C over the last three weeks
separates them cleanly, because it is what actually turns a leaf.

**The response has to be linear, not a square root.** A square root was tried
to make Tromsø and Montreal less far apart and gives the wrong *shape*: it
front-loads the display, so Montreal read 0.42 turned in the third week of
September when the honest description is "some trees are changing". Linear, at
gain 2.20, traces 0.04 on 5 September, 0.31 on the 22nd, a peak of 0.77 in
mid-October and bare by mid-November — and Kyoto's peak lands in late November,
which is its real momiji season and is nowhere hard-coded.

**Species must not depend on the month.** The first classifier tested "is it dry
right now" for a mediterranean climate, and Sydney came out mediterranean in
November and mixed in February — a scene changing what grows in it as the date
is scrubbed. The test is now the rain of the three warmest months against the
three coldest, which is a property of the place.

**A columnar cactus is a desert's, not a savanna's.** Ouagadougou has almost
exactly Phoenix's aridity and grows acacia. Aridity alone made the Sahel
columnar; the class decides it, and warmth is the second gate so a cold desert
stays scrub.

**Meadow starts well below the arctic.** The cover gate above the treeline was
first written from 45°, which left Zermatt's alpine meadow as bare rock. From
30° up, gated on wetness, Phoenix stays rock because it is dry and Zermatt is
covered because it is not — height is not what leaves stone bare.

## Options considered

| Option | Result | Verdict |
|---|---|---|
| Normalised photoperiod | invents a season at the equator | rejected |
| Absolute day length | separates nothing at an equinox | rejected |
| Rate of change of day length + accumulated cold nights | Tromsø → Montreal → Kyoto in the right order, a month apart | chosen |
| Square-root response to cold | front-loaded; half-turned in September | rejected |
| A species enum | hard edges the world does not have | rejected |
| Blended weights, as `land` already works | one mechanism, extends the existing one | chosen |

## Decision

A pure `vegetationState()` returning canopy, turn, evergreen share and browning,
plus four form weights, from a monthly climatology and the nights immediately
before the day on screen. Nine cached years of real weather are the test, because
the model was wrong twice in ways only real data caught.

## Corrections

The approved plan listed a scenario "Zermatt above the treeline stays rock,
because it genuinely is". That is wrong above its own treeline: at 46° the
treeline is around 1660 m and what sits immediately above it is alpine meadow,
not stone. The scenario is now Phoenix — dry ground, not high ground, is what
leaves rock bare — and no Zermatt fixture was needed.

## Found on the machine, not in the tests

Two upgrade faults that no unit test could have caught, because both are about
data written before this change existed:

- **A cached climate is not stale.** It answered, so nothing asked again, and
  the monthly profile never arrived — the scene kept a full green canopy for as
  long as the cache lived. Fixed by `climateThin`: aridity without months is
  treated as not yet answered.
- **A cached forecast is not stale either.** The same fault, one layer down: the
  cached window had no nights in it, so the season could not move as the scene
  was scrubbed. Measured live at 21.38 % warm pixels on 22 September and 21.39 %
  on 7 October — identical, because the same twenty-one archived nights were
  being read on both dates. A cached forecast with no nights is now no cache.

And one model fault the fixtures showed only once it was on screen: with a
single temperature threshold for both leafing out and letting go, Montreal shed
a quarter of its canopy in early October, and since colour is carried on the
leaves that are still there, the display went flat exactly when it should have
been at its strongest — 0.41 against 0.46 between the two dates. Two thresholds
fixed it: put leaves out at 4 °C, hold them to 5 °C, which also stops Kyoto
keeping a full canopy through a mild January.
