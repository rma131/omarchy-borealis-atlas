# Terrain and Water Specification

## Purpose
Draw the land and water that are actually around the place being looked at:
the measured skyline, snow and trees at the heights they really occur, and water
only where there is water. The reasoning, and what was tried and rejected, is in
`docs/design.md` — "The skyline is the one that is really there", "Water is the
flat thing" and "What the flat test cannot see".

## Requirements

### Requirement: Water is found by flatness, under fixed gates
The system SHALL identify a water surface as an exact elevation repeated at
least four times, isolated from its neighbouring metre levels (isolation ≥ 1.5)
and among the two lowest distinct levels sampled. These gates MUST NOT be
loosened to admit a particular place: the window that admits below-sea-level
polder is the same one that admits dry farmland.

#### Scenario: A lake beyond the near field is found in the wider pass
- GIVEN Toronto, whose geocoded centre is about 7 km from Lake Ontario
- WHEN only the 12 km near field is classified
- THEN no water is found
- AND classifying the 25 km skyline pass finds a lake at 74 m
- VERIFIED: test

#### Scenario: A river close by is found in the near field
- GIVEN Montreal beside the St Lawrence
- WHEN the near field is classified
- THEN a river is found at 4 m
- VERIFIED: test

#### Scenario: Flat farmland is not water
- GIVEN the Kansas plains, which repeat exact metres without being water
- WHEN either pass is classified
- THEN no water is found
- VERIFIED: test

#### Scenario: Mountains with no water stay dry
- GIVEN Quito in the Andes
- WHEN either pass is classified
- THEN no water is found
- VERIFIED: test

#### Scenario: Below-sea-level polder is not taken for water
- GIVEN Amsterdam, whose repeated levels are drained polder
- WHEN either pass is classified
- THEN the elevation test finds no water
- VERIFIED: test

### Requirement: Open sea is asked for rather than inferred
The system SHALL probe the marine model at points around the place and treat a
reported wave height as open water, using the grid cell the model answered for,
not the point requested, to set distance and bearing. The probe MUST only add
water the ground could not describe.

#### Scenario: Flat coastal country gets its sea from the marine probe
- GIVEN Amsterdam, which the elevation test cannot see
- WHEN the terrain for it is resolved
- THEN sea is drawn about 4.7 km to the east, the IJmeer
- VERIFIED: live

#### Scenario: The marine cell's own position sets the bearing
- GIVEN Limassol, with the Mediterranean to its south
- WHEN the marine probe answers
- THEN the water lies at a bearing near 176 degrees, not to the north
- VERIFIED: live

### Requirement: Measured water outranks modelled water
When several verdicts exist the system SHALL prefer one measured from the ground
over one from the marine model, and among verdicts of the same source the
nearest.

#### Scenario: The ground's verdict outranks the marine probe
- GIVEN a lake measured by the ground and a nearer marine cell
- WHEN both are adopted
- THEN the measured lake is kept
- AND the marine verdict is used only where the ground found nothing
- VERIFIED: test

### Requirement: Test data matches the sampling that produced it
Elevation fixtures SHALL record the geometry they were sampled with, and every
fixture SHALL be used by a scenario.

#### Scenario: Fixtures and scenarios stay in step
- GIVEN the fixtures under tests/fixtures/elevation
- WHEN the tests run
- THEN each fixture belongs to a place some scenario uses
- AND a fixture sampled with other constants fails as stale
- VERIFIED: test

### Requirement: Elevation requests stay within the service limit
Every elevation request SHALL carry at most 100 coordinates; the service rejects
101 with HTTP 400.

#### Scenario: No pass asks for more than 100 points
- GIVEN the near, ring and fan sampling constants
- WHEN they are multiplied out
- THEN each pass requests at most 100 points
- VERIFIED: lint

### Requirement: Snow and trees follow real heights
The system SHALL draw snow above the day's freezing level and trees below the
latitude-dependent treeline, as horizontal contours across the measured ridge.

#### Scenario: Snow caps only the peaks above the freezing level
- GIVEN Quito on a day whose freezing level is below Pichincha's summit
- WHEN the scene is drawn
- THEN only the part of the ridge above that height is white
- VERIFIED: live
