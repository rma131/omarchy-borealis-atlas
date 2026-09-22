# Globe Specification

## Purpose
Show at a glance where on earth the scene is. Deliberately removable: the whole
feature is `Globe.qml`, `coastline.js` and one block in `BorealisAtlas.qml`. See
`docs/design.md` — "A globe, and what it is not allowed to do" and
`docs/coastline.md`.

## Requirements

### Requirement: The globe centres on the place
The globe SHALL be an orthographic wireframe centred on the current place, with
coastlines, a graticule and a marker, shown with the readout.

#### Scenario: The marker sits on the place
- GIVEN the scene at Toronto
- WHEN the readout is showing
- THEN the globe shows the Americas with the marker on the Great Lakes
- VERIFIED: live

### Requirement: The globe costs nothing while the sky moves
The globe MUST NOT repaint on the time of day, and SHALL repaint only when the
place, its size or its visibility changes. It MUST NOT take input.

#### Scenario: Scrubbing time does not repaint the globe
- GIVEN the globe visible
- WHEN time is dragged
- THEN the globe is not repainted
- VERIFIED: live

### Requirement: The coastline data is reproducible
The coastline table SHALL be regenerable from its documented public-domain
source with the recorded method and tolerance.

#### Scenario: The coastlines can be rebuilt from source
- GIVEN docs/coastline.md
- WHEN its script is run on Natural Earth 110m at 0.9 degrees
- THEN it produces the 925 vertices shipped
- VERIFIED: live
