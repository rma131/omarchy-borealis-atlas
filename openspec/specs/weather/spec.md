# Weather Specification

## Purpose
Draw the weather the forecast actually describes, at the intensity it actually
has. See `docs/design.md` — "A thunderstorm is a state of the atmosphere, not a
code".

## Requirements

### Requirement: A storm is read from the atmosphere
The system SHALL derive storm intensity from convective instability (CAPE or
lifted index) together with falling precipitation, with the weather code only as
a vote. Instability without precipitation MUST NOT draw a storm.

#### Scenario: A showers code in a thunderstorm atmosphere draws a storm
- GIVEN Toronto at 16:00 on 2 September 2026, code 82, 7.9 mm/h, CAPE 1970
- WHEN the sky is resolved
- THEN it is drawn as a thunderstorm
- VERIFIED: live

#### Scenario: Instability without rain is not a storm
- GIVEN the same afternoon at 14:00, CAPE 2140 and no precipitation
- WHEN the sky is resolved
- THEN no storm is drawn
- VERIFIED: live

### Requirement: Severe weather reaches a warning tier
The system SHALL raise a warning tier at the thresholds national services use for
severe thunderstorm and rainfall warnings, taking the strongest gust of the
neighbouring hours.

#### Scenario: A warned storm looks warned
- GIVEN a severe-tier hour
- WHEN it is drawn
- THEN the deck lowers, the rain becomes a curtain and a lightning channel shows
- VERIFIED: live
