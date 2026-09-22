## MODIFIED Requirements

### Requirement: Snow and trees follow real heights
The system SHALL draw snow above the day's freezing level and trees below the
latitude-dependent treeline, as horizontal contours across the measured ridge.

Above the treeline the ground is no longer bare rock by definition. What is
drawn there is decided by the `vegetation` capability's cover weight: páramo,
meadow or tundra where it is wet enough, and rock only where it is not.

#### Scenario: Snow caps only the peaks above the freezing level
- GIVEN Quito on a day whose freezing level is below Pichincha's summit
- WHEN the scene is drawn
- THEN only the part of the ridge above that height is white
- VERIFIED: live

#### Scenario: Above the treeline is not automatically rock
- GIVEN Quito, whose páramo is thick with frailejones
- WHEN the ridge above the treeline is drawn
- THEN it carries low rosette cover rather than grey stone
- VERIFIED: live
