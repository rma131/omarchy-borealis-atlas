# Text Art Specification

## Purpose
Draw the whole scene as a grid of braille cells — two dots across and four
down per character, which is the most detail a character grid can carry while
still reading as text rather than as a dither. Three flat inks, taken from the
hour's sky, in the proportions of the 60:30:10 rule.

It is not a power feature, and `docs/measurements.md` says so with numbers:
drawing the scene at a character grid removes 90 % of the overlay's GPU work
and that is worth about half a watt, which is under this machine's noise floor.
It exists because of what it looks like.

## Requirements

### Requirement: The grid is the resolution, and nothing else changes
The system SHALL render text art by snapping the sampling coordinate to the
centre of the braille dot it falls in, so every existing path answers a coarser
question rather than a different one. It MUST NOT maintain a second rendering
path for the scene, and MUST NOT require a second compiled shader.

#### Scenario: A character cell keeps its dots square
- GIVEN a panel of a given logical size
- WHEN the grid is derived from it
- THEN a cell is about twice as tall as it is wide
- AND its two-by-four dots are therefore square
- VERIFIED: test

#### Scenario: Off by default, and off costs nothing
- GIVEN no `textArt` key on the plugin's entry in shell.json
- WHEN the scene is drawn
- THEN the column count is zero and the shader does not take the braille path
- VERIFIED: live

### Requirement: The three inks come from the hour's sky
The system SHALL choose the dominant, secondary and accent inks by blending
four keyframes — night, dawn, noon and dusk — according to where the moment
sits against that day's real sunrise and sunset. The dominant ink SHALL carry
the sky, the secondary the land and water, and the accent what is bright.

#### Scenario: Each hour has its own three tones
- GIVEN a day with a known sunrise and sunset
- WHEN the inks are resolved at midnight, at sunrise, at midday and at sunset
- THEN each lands on its own keyframe
- AND the four weights always sum to one and none is negative
- AND a polar day never reaches night, because the weights follow the sun
- VERIFIED: test

#### Scenario: The day reads at a glance
- GIVEN the same place at dawn, noon, dusk and midnight
- WHEN each is drawn
- THEN the four are distinct in colour without reading the clock
- AND the sun, the horizon glow and the aurora appear in the accent ink
- VERIFIED: live

### Requirement: The tone curve follows the sky it is drawing
The system SHALL set the luminance pivot from the same hour the inks come from,
so the sky of that moment sits near half dot-coverage. A fixed pivot MUST NOT be
used: it renders a night sky as an empty page and a noon sky as a full one.

#### Scenario: The pivot tracks the hour
- GIVEN midnight and midday
- WHEN the pivot is resolved for each
- THEN midday's is substantially higher than midnight's
- VERIFIED: test

### Requirement: The ridge does not beat against the dot grid
The system SHALL reduce the tree count in text mode. At the scene's own 170
trees across a 320-dot grid a tree is 1.88 dots — a sawtooth just under two
samples per period, which aliases into a moire that crawls as the sky drifts.

#### Scenario: Trees are coarser than the dots that draw them
- GIVEN a grid of a given column count
- WHEN the tree count is chosen
- THEN there are at least two dots per tree
- VERIFIED: test
