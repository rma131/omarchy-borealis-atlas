# Interaction Specification

## Purpose
Let a finger explore the sky without the screensaver ever losing its one
essential property: any key gets it out of the way. Gestures and their tuning
are described in `docs/design.md` — "Gestures".

## Requirements

### Requirement: Any key dismisses, except the search key
Every key SHALL dismiss the overlay, except `/`, which opens the search.

#### Scenario: A stray key gets out of the way
- GIVEN the overlay open with no search showing
- WHEN any key other than / is pressed
- THEN the overlay closes
- VERIFIED: live

### Requirement: Time is moved by touch
Dragging SHALL move through time across the fetched window, a double tap SHALL
return to the present, and a touch SHALL release any moment the user was holding.

#### Scenario: A double tap returns to now
- GIVEN the scene parked on another day
- WHEN the screen is double-tapped
- THEN it rolls back to the present moment
- VERIFIED: live

### Requirement: The search layer owns touch only while open
The search layer SHALL take pointer input only while it is showing, so its
suggestion rows can be tapped without swallowing gestures when it is hidden.

#### Scenario: A hidden search takes no touch
- GIVEN the search closed
- WHEN the sky is dragged
- THEN time moves as normal
- VERIFIED: live
