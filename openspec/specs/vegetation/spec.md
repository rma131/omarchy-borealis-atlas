# Vegetation Specification

## Purpose
Show what grows where the scene is standing, and what it is doing this month.
Two separate things: the **season**, which is foliage turning, falling and
coming back on a schedule set by the place rather than by the calendar; and the
**form**, which is the shape the vegetation gives the landscape — the rosettes
of the páramo, the flat crown of an acacia, a column in the desert, and the
cover above a treeline that is not bare rock. The reasoning, and the two
prototypes that were wrong before this one, are in `docs/design.md`.

## Requirements

### Requirement: The season is read from this place's own year
The system SHALL decide the state of the foliage from a monthly climatology of
the location — mean temperature, rain and evaporative demand per month — and
from the nights immediately before the day being looked at. It MUST NOT key the
season to the calendar, to the hemisphere, or to a latitude band.

#### Scenario: Montreal turns through October and stands bare in November
- GIVEN Montreal's own year of weather
- WHEN the vegetation is resolved through the autumn
- THEN midsummer shows no turn at all
- AND late September has started but is under half turned
- AND mid-October is further on than late September
- AND by mid-November the canopy is down
- AND it is back by late spring
- VERIFIED: test

#### Scenario: Kyoto turns a month after Montreal
- GIVEN Kyoto and Montreal, both deciduous and at nearly the same day length
- WHEN both are resolved on the same dates
- THEN Kyoto has barely started in mid-October
- AND Kyoto is well into its turn in late November, when Montreal is already bare
- VERIFIED: test

#### Scenario: Tromso turns first and drops fastest
- GIVEN Tromsø at 69.6°N, losing about ten minutes of daylight a day
- WHEN it is compared with Montreal on the same date in late September
- THEN Tromsø is further into its turn
- AND its canopy is largely down by mid-October
- VERIFIED: test

#### Scenario: Sydney is in leaf while Montreal is turning
- GIVEN Sydney in late September, which is its spring
- WHEN the vegetation is resolved
- THEN nothing has turned and the canopy is full
- VERIFIED: test

#### Scenario: The tropics never turn
- GIVEN Singapore and Quito, whose annual temperature swing is a few degrees
- WHEN the vegetation is resolved at each solstice and equinox
- THEN nothing turns and the canopy stays full all year
- VERIFIED: test

#### Scenario: Ouagadougou browns with the dry season, not the calendar
- GIVEN the Sahel, where the year is wet and dry rather than warm and cold
- WHEN the vegetation is resolved in February and in late September
- THEN February is browned off by the Harmattan
- AND late September, the peak of the rains, is not browned at all
- AND neither is called autumn
- VERIFIED: test

#### Scenario: A place with no climate answer keeps its canopy
- GIVEN a location whose archive request has not answered
- WHEN the vegetation is resolved
- THEN the canopy is full, nothing has turned and nothing covers the high ground
- VERIFIED: test

### Requirement: The nights that drive the turn follow the day being looked at
The system SHALL accumulate cold from the nights immediately before the date on
screen, joining the archive's nights to the forecast window's without counting
the days where the two overlap twice. Scrubbing the scene forward or back MUST
move the season with it.

#### Scenario: The archive's nights stop where the forecast window starts
- GIVEN an archive ending after the forecast window opens, as it always does
- WHEN the two are joined
- THEN the archive is cut back to where the window starts
- AND scrubbing back shortens the window with it
- AND an absent forecast still leaves the archive answering
- VERIFIED: test

#### Scenario: Scrubbing forward moves the season
- GIVEN Montreal in late September
- WHEN the scene is dragged sixteen days forward
- THEN more of the ridge has turned than at the start of the drag
- VERIFIED: live

### Requirement: A place keeps its species all year
The system SHALL decide what grows at a location from the shape of its whole
year, not from the conditions of the current month. The classification MUST be
stable as the date changes.

#### Scenario: A place keeps its species all year
- GIVEN each of the nine fixture climates
- WHEN each is classified in February, May, August and November
- THEN every one is classified the same way on all four dates
- VERIFIED: test

### Requirement: Form follows the native climate
The system SHALL express characteristic vegetation as blended weights — rosette,
flat crown, columnar, and cover above the treeline — derived from latitude,
aridity and the monthly climatology, with zero for all of them meaning the
ordinary mix of conifer and broadleaf. A treeline SHALL mean that trees stop,
not that nothing grows.

#### Scenario: Above the treeline is paramo at the equator and tundra near the poles
- GIVEN Quito on the equator and Tromsø inside the arctic circle, both wet
- WHEN the form is resolved
- THEN both cover their ground above the treeline rather than showing rock
- AND only Quito's cover is rosettes
- VERIFIED: test

#### Scenario: Dry ground above the treeline stays rock
- GIVEN Phoenix, at an aridity index of 0.26
- WHEN the form is resolved
- THEN nothing covers its high ground
- AND what grows below it stands as columns
- AND Ouagadougou, as dry but tropical, is flat-crowned and not columnar
- VERIFIED: test

### Requirement: A cached climate is all twelve months or none
The system SHALL rebuild a cached climatology rather than trust it, and SHALL
accept the monthly profile only if all twelve months are present and valid.
Aridity alone MUST remain usable without it.

#### Scenario: A cached climate is all twelve months or none
- GIVEN a cache holding eleven months of temperature
- WHEN it is validated
- THEN the monthly profile is dropped and aridity alone is kept
- AND a complete profile is kept whole
- VERIFIED: test
