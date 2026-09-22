# Data Integrity Specification

## Purpose
Treat every remote reply, and the plugin's own cache file, as untrusted input;
keep the load on shared free services low; and when data does not arrive, say
whose fault it was. Background: the marketplace security reviews recorded in the
commit history from `094cce7` onwards, and `docs/design.md`.

## Requirements

### Requirement: Untrusted input is bounded and range-checked
Every reply and every cache read SHALL pass through the bounded parser and
element-level validators before use. A single malformed element MUST reject the
whole series rather than being skipped.

#### Scenario: Non-finite numbers are rejected
- GIVEN a value that is NaN, infinite or out of range
- WHEN it is validated
- THEN it is refused
- VERIFIED: test

#### Scenario: One bad element rejects the whole series
- GIVEN a series with one string or unexpected null in it
- WHEN it is validated
- THEN the whole series is refused
- VERIFIED: test

#### Scenario: Oversized or non-object replies parse to nothing
- GIVEN an empty, oversized, scalar or malformed reply
- WHEN it is parsed
- THEN the result is nothing
- VERIFIED: test

#### Scenario: Locations are canonicalised before use
- GIVEN a location from the IP lookup, the geocoder or the cache
- WHEN it is adopted
- THEN its coordinates are range-checked and its names length-capped
- VERIFIED: test

#### Scenario: JSON is parsed in exactly one place
- GIVEN the plugin source
- WHEN it is linted
- THEN JSON.parse appears only inside boundedParse
- VERIFIED: lint

### Requirement: Rendered text is never interpreted as markup
Every Text element SHALL use plain-text format, because place names and
conditions come from third-party services.

#### Scenario: A name containing markup is shown literally
- GIVEN any Text element in the plugin
- WHEN the source is linted
- THEN it declares textFormat: Text.PlainText
- VERIFIED: lint

### Requirement: Failures say whose fault they are
Every network process SHALL capture curl's exit code and stderr, and the scene
SHALL show a persistent line naming what failed and why once a failure has
lasted five seconds. curl's stderr MUST NOT be rendered.

#### Scenario: A failed fetch says whether it was the network or the service
- GIVEN curl exit codes for no connection, timeout, a 429, a 5xx and a 404
- WHEN each is classified
- THEN they read offline, timeout, ratelimit, server and badrequest
- VERIFIED: test

#### Scenario: A rate limit is shown, not hidden
- GIVEN the weather service answering 429
- WHEN the failure persists
- THEN a line at the top reads that the service is busy and will be asked again
- VERIFIED: live

#### Scenario: Every network process can report failure
- GIVEN the plugin source
- WHEN it is linted
- THEN each network Process declares src, stderr and onExited
- VERIFIED: lint

### Requirement: Shared services are not hammered
The system MUST NOT let curl retry on its own, SHALL back off exponentially and
globally after a 429, and SHALL fetch immutable terrain once per place.

#### Scenario: curl never retries on its own
- GIVEN the curl command builder
- WHEN the source is linted
- THEN --retry is absent
- VERIFIED: lint

#### Scenario: Revisiting a place costs no terrain requests
- GIVEN a place whose terrain is already cached
- WHEN it is visited again
- THEN horizon, water and climate are restored without being fetched
- VERIFIED: live

### Requirement: A reply for a place already left is discarded
Each place-dependent request SHALL carry the generation of the place it was made
for, and a reply from an older generation MUST be ignored.

#### Scenario: Switching place mid-fetch never shows the old place's data
- GIVEN a forecast in flight for one place
- WHEN the user switches to another
- THEN the old reply is dropped and the new place is fetched
- VERIFIED: live
