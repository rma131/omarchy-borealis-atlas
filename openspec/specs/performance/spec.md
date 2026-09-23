# Performance Specification

## Purpose
Keep the scene worth its cost. It is a fullscreen fragment shader that redraws
every frame, and `docs/measurements.md` measures what that means on real
hardware. On mains it draws everything. On battery it draws the same picture
with fewer pixels and a cheaper mirror, because a laptop running on its own cell
is the one case where the bill is paid by someone who may not be watching.

## Requirements

### Requirement: The cost is chosen by how the machine is powered
The system SHALL decide how much work the scene is worth from the power state
alone, and SHALL treat a machine with no battery as mains-powered. It MUST NOT
require the person to choose, and MUST NOT change what is drawn on mains.

#### Scenario: Mains draws everything and battery does not
- GIVEN a laptop on mains
- WHEN the scene is drawn
- THEN it is drawn at full resolution with five reflection taps
- AND unplugging it drops to the cheaper scene without anything being typed
- VERIFIED: test

#### Scenario: Nothing changes for anyone on mains
- GIVEN the plugin on a machine that is plugged in
- WHEN the GPU clock is sampled over a 30 s window
- THEN it matches the measurement taken before this capability existed
- VERIFIED: live

### Requirement: The cheaper scene is the same scene
The system SHALL reduce cost by drawing fewer pixels and by simplifying only
what the water is made of. The sky above the waterline MUST be drawn at full
detail in every mode, and the reduced scene MUST remain one a person would
choose to look at.

#### Scenario: The sky is never drawn cheaply
- GIVEN the scene in its cheapest mode
- WHEN the sky above the waterline is drawn
- THEN it keeps all three aurora curtains, its meteors and its starfield
- AND only the copies of it that the water is made from are simplified
- VERIFIED: live

#### Scenario: The ridge still reads as a treeline
- GIVEN the cheapest mode at a place with a dense treeline
- WHEN the ridge is compared against the same scene at full cost
- THEN the crowns are softer but the silhouette and the turned colour still read
- VERIFIED: live

### Requirement: The shader is told the size it is drawing at
The system SHALL pass the render target's own size as `resolution`, not the
size the result is displayed at. The ridge's anti-aliasing and the starfield's
cell size are both derived from it, so a mismatch would harden every edge and
shrink every star by exactly the factor the picture is about to be stretched by.

#### Scenario: Feathering and star size follow the render scale
- GIVEN the scene rendered into a smaller texture
- WHEN the ridge and the starfield are drawn
- THEN both are sized in texels of that texture rather than in screen pixels
- VERIFIED: live

### Requirement: Frames are spent where they can be seen
In the reduced-cost mode the system SHALL pace its redraws, drawing at the
display's rate while the scene is being touched, scrubbed, searched or
inspected, at a middle rate when the sky itself has fast motion in it, and
slowly when the sky is merely drifting. Everything the scene animates MUST hang
off a single clock, because two at unrelated phases interleave into the full
rate and pay the timer cost twice. The mains path MUST keep its vsync-aligned
declarative animation unchanged.

#### Scenario: Frames are spent where they can be seen
- GIVEN the scene being touched, a sky with rain in it, and a calm sky
- WHEN the frame interval is chosen
- THEN touch is drawn at the display's rate
- AND touch outranks the weather
- AND rain is drawn faster than a calm sky
- VERIFIED: test

#### Scenario: A drifting sky costs almost nothing
- GIVEN the reduced-cost mode on battery with a calm sky
- WHEN the GPU clock is sampled over 50 s
- THEN it sits near the idle clock rather than near the ceiling
- VERIFIED: live

#### Scenario: Touching it brings the frames back
- GIVEN the scene paced down on a calm sky
- WHEN the search is opened and then dismissed
- THEN the clock rises to the full rate and falls back afterwards
- VERIFIED: live
