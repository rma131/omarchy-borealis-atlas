# Sky and Astronomy Specification

## Purpose
Put the sun and moon where they really are for the place and moment shown, at
their real relative sizes, so the sky can do what the real one does — including
eclipses. See `docs/design.md` — "Sunrise and sunset, where you actually are"
and "An eclipse is two discs the same size".

## Requirements

### Requirement: The sun follows the real day
The system SHALL place the sun using the day's actual sunrise and sunset for the
place, scaling both the length of the day and the height the sun reaches.

#### Scenario: A winter sun stays low
- GIVEN Montreal in December
- WHEN midday is shown
- THEN the sun stands visibly lower than at an equinox
- VERIFIED: live

### Requirement: Sun and moon are the same apparent size
The sun and moon discs SHALL be drawn at the same size, with the moon's radius
scaled by its true ratio to the sun's so that its distance decides total against
annular.

#### Scenario: The discs are drawn the same size
- GIVEN a sky with both bodies up
- WHEN it is drawn
- THEN the two discs are of matching size
- VERIFIED: live

### Requirement: The moon is where it really is
The moon's phase and ecliptic latitude SHALL be computed from Meeus' mean
elements with the principal periodic terms.

#### Scenario: Phase is right to within minutes
- GIVEN the real new moon of 12 August 2026
- WHEN the phase is computed
- THEN it is within half an hour of new
- VERIFIED: test

### Requirement: Eclipses happen when they really do
Solar eclipses SHALL be decided by the separation of the discs less the moon's
horizontal parallax; lunar eclipses by the moon's distance from the earth's
umbra. Totality SHALL darken the sky and show the corona; an annular eclipse
SHALL leave a ring and no stars.

#### Scenario: Every eclipse from 2026 to 2028 lands on its day with the right kind
- GIVEN the solar and lunar eclipses of 2026 to 2028
- WHEN the moon is computed at each maximum
- THEN each is named with its correct kind
- VERIFIED: test

#### Scenario: New and full moons off the node pass without an eclipse
- GIVEN new and full moons far from a node, and a penumbral eclipse
- WHEN the moon is computed
- THEN no eclipse is named
- VERIFIED: test

#### Scenario: Totality darkens the sky and shows the corona
- GIVEN a total solar eclipse in daylight
- WHEN the scene is drawn
- THEN the sky darkens, stars appear and a corona surrounds the black disc
- VERIFIED: live
