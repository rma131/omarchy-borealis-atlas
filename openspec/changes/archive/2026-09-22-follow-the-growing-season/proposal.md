# Proposal: Let the vegetation follow the season, and look like where it grows

## Request

> "I would like to consider the vegetation of the location. In Montreal fall is
> starting and some trees are changing colors. It will continue until they all
> fall and we get winter. It would be nice to follow up this transition. Also to
> follow up what transition happens in different parts of the world depending on
> their native climate and vegetation."
> — 2026-09-22

And, after the first review of the plan:

> "Just to consider, vegetation that is diverse in some places like in ecuador
> and the andes the frailejon, and other places of the world, some vegatation
> shapes the landscape. Keep it simple but meaningful."
> — 2026-09-22

## Intent

The scene has no idea what month it is. `computeTerrain()` reduces a place to
`cold`, `arid`, `lush` and `alpine` from a 23-day mean temperature and a
whole-year aridity index, and in the shader `th`, `shp` and `spike` are pure
geometry — **trees have no colour at all**. Montreal in October therefore looks
exactly like Montreal in July.

Two things are missing, and they are different:

1. **Time.** Foliage turns and falls, and it does so on a schedule set by the
   place: early and fast at Tromsø, late at Kyoto, driven by drought rather than
   cold in the Sahel, and not at all in Singapore.
2. **Form.** In some places the vegetation *is* the landscape. The clearest case
   is also a plain bug: above the treeline the shader forces `bare = 0.97` and
   draws grey rock, so the slopes above Quito are bare stone when the real páramo
   is thick with frailejones.

## Scope

In scope:
- a monthly climatology from the archive request already being made
- a pure `vegetationState()` returning canopy, autumn, evergreen and browning
- four `flora` weights for characteristic form, including what grows above the
  treeline instead of rock
- two new uniforms and the shader work to draw both
- fixtures and scenarios for nine climates

Out of scope:
- any new data provider, or any second request per place
- the low-cost mode, proposed separately
- naming species on screen; this is a silhouette and a colour, not a field guide

## Approach

Everything is derived from data already fetched. The archive call gains two daily
variables (10 KB), and `climProc` keeps a monthly profile instead of collapsing
the year to one number. Day length and, crucially, **the rate it is changing**
come free from the 23 days of `sunrise`/`sunset` already held: at an equinox every
place on earth sits within minutes of 12 h, so absolute day length separates
nothing, while the rate separates Tromsø from Kyoto cleanly.

Form is four blended weights, not an enum, matching how `land` already works.

## Capabilities affected

- `terrain-water` — MODIFIED: what grows above the treeline
- `vegetation` — ADDED: a new capability for season and form

## Risks

The model is a heuristic and two prototypes were already wrong in different ways.
Mitigated by nine cached year-long fixtures and a calibration table asserted as
scenarios, so being wrong fails a test rather than shipping.
