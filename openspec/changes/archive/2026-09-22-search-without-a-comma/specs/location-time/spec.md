## MODIFIED Requirements

### Requirement: The search takes a place, a moment, or both
The search line SHALL accept `place @ when`, `place, when` and `place when` with
no separator at all, either half alone, and SHALL read a separator-less line as
a moment only when it plainly is one. A trailing moment MUST only be taken off a
line when what remains in front of it is not empty and the tail both looks
temporal and parses whole. An unreadable moment MUST be refused whole, and a
moment outside seven days back or sixteen forward MUST be refused with the
reason.

#### Scenario: A place and a moment are told apart
- GIVEN inputs such as "Istanbul @ tomorrow 15:00" and "Quito, 12 Sep"
- WHEN they are parsed
- THEN the place and the day and time are separated correctly
- VERIFIED: test

#### Scenario: A moment on the end of a place needs no separator
- GIVEN "Montreal 14:00", "Marseille 12 oct", "Quito sunset" and "Berlin 2026-10-05"
- WHEN they are parsed
- THEN each gives its place and its moment
- AND "Paris, France 14:00" keeps the comma inside the place
- AND the longest trailing moment wins, so "Marseille 12 oct" keeps the month
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
