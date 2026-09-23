## ADDED Requirements

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
