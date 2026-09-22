# Proposal: Let a place and a moment be typed without a separator

## Request

> "Let's do the unseparated search form"
> — 2026-09-22

Following the finding reported the same day: `Montreal 14:00` did not do what it
looks like it does.

## Intent

The search accepts `place @ when` and `place, when`. Without one of those
separators it took the whole line as a place, so `Montreal 14:00` was handed to
the geocoder as the string "Montreal 14:00" and the time was lost.

It used to be worse. Until `1048f68`, `parseWhen` matched a month or a weekday
on a token's first three letters, so the same line parsed as *Monday at 14:00*
with no place at all — the search went somewhere else entirely and said nothing.
That is fixed; what is left is a line that fails visibly instead of one that
lies. Failing visibly is better, and working is better still.

The separator is not something a person thinks to type. It is punctuation the
parser wanted, not the user.

## Scope

In scope:
- `splitQuery` takes a trailing moment off a separator-less line
- `suggestSplit` uses the same rule, so the suggestion list agrees with what
  Return will do, and stops geocoding half-typed times

Out of scope:
- guessing at a moment that does not parse
- a moment in front of a place ("14:00 Montreal")

## Approach

One pure function, `trailingWhen()`, finds the longest trailing moment that
still leaves a place in front of it. The whole line is tested as a moment first,
so `12 sep 14:00` does not become a place called "12".

Safety is one condition: the tail must satisfy `looksTemporal` as well as parse.
That wants a digit or a word from the moment vocabulary, so a bare weekday or
month at the end of a line stays part of the name — which is what it usually is.

## Capabilities affected

- `location-time` — MODIFIED: the search takes a place, a moment, or both

## Risks

A place name whose last word parses as a moment would be split. The
`looksTemporal` gate makes that require a digit or a plain moment word in the
name itself; "Morning Sun", "Santa Fe", "Rio de Janeiro", "Satu Mare",
"Area 51", "Route 66" and "Washington 3" are all in the scenario as the guard.
