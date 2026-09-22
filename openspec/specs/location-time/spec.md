# Location and Time Specification

## Purpose
Know where the scene is and what moment it shows: whose clock, which place, and
what the user asked for — and tell them when any of it changes. See
`docs/design.md` — "The clock belongs to the place, not the machine" and
"Suggesting, without spending".

## Requirements

### Requirement: The clock belongs to the place
The scene SHALL show the local time of the place being looked at, using the UTC
offset returned with that place's forecast, and SHALL re-seed to that zone's
present whenever the zone changes and no moment is being held.

#### Scenario: A place in another zone shows its own hour
- GIVEN this machine in Toronto at 08:15
- WHEN the user goes to Istanbul
- THEN the sky and readout show Istanbul's 15:15
- VERIFIED: live

#### Scenario: Returning to this machine returns to now
- GIVEN the scene showing another place
- WHEN the user submits an empty search
- THEN it follows this machine's location at the present moment
- VERIFIED: live

### Requirement: The search takes a place, a moment, or both
The search line SHALL accept `place @ when` or `place, when`, either half alone,
and SHALL read a separator-less line as a moment only when it plainly is one. An
unreadable moment MUST be refused whole, and a moment outside seven days back or
sixteen forward MUST be refused with the reason.

#### Scenario: A place and a moment are told apart
- GIVEN inputs such as "Istanbul @ tomorrow 15:00" and "Quito, 12 Sep"
- WHEN they are parsed
- THEN the place and the day and time are separated correctly
- VERIFIED: test

#### Scenario: Place names that look like dates stay places
- GIVEN "March", "Sunday", "New York", "banana" and "3"
- WHEN they are parsed
- THEN each is taken as a place
- VERIFIED: test

#### Scenario: A moment it cannot read is refused whole
- GIVEN a moment containing an unknown word, or a month with no day
- WHEN it is parsed
- THEN nothing is returned
- VERIFIED: test

### Requirement: Suggestions show what will be chosen
The search SHALL suggest places with region and country and moments from a local
vocabulary, SHALL keep geocoding within a debounce, a minimum length and a
per-opening budget, and an accepted suggestion MUST NOT cost a further lookup.

#### Scenario: Suggested moments are always ones the search accepts
- GIVEN any partial moment after an @
- WHEN moments are suggested
- THEN every suggestion parses
- VERIFIED: test

#### Scenario: Places are suggested with region and country
- GIVEN the user types "amst"
- WHEN suggestions arrive
- THEN both Amsterdams appear, told apart by region
- VERIFIED: live

### Requirement: A country resolves within that country
When the geocoder's best answer is not a populated place, the system SHALL
prefer a populated place in the same country and MUST NOT choose one abroad.

#### Scenario: A country name never resolves abroad
- GIVEN the query "Cyprus", whose answers include a village in Jamaica
- WHEN it is geocoded
- THEN the result stays in Cyprus
- VERIFIED: live

### Requirement: The user is told what changed
After a change of place the readout SHALL show the place, its local time and
conditions for several seconds, and say it is fetching until they arrive. A moment
the user typed SHALL hold still, with the readout up, until the screen is touched.

#### Scenario: Changing place shows where and when you are
- GIVEN the user goes to a new place
- WHEN its forecast lands
- THEN the readout names the place, its time and zone, and the conditions
- VERIFIED: live
