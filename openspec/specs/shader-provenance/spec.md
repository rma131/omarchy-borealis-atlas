# Shader Provenance Specification

## Purpose
The one binary in the repository, `shaders/aurora.frag.qsb`, must be provably
built from its source, and the shader must keep working on every target the
shell may translate it to. See `docs/build-provenance.md`.

## Requirements

### Requirement: The shipped shader is reproducible
The compiled shader SHALL rebuild byte-for-byte from `shaders/aurora.frag` with
the pinned toolchain, and its digests SHALL be recorded in the provenance doc.

#### Scenario: The binary rebuilds from source
- GIVEN a clean pinned container
- WHEN the shader is compiled
- THEN the result matches the shipped file exactly
- VERIFIED: ci

#### Scenario: The documented digests are the shipped ones
- GIVEN docs/build-provenance.md
- WHEN it is linted
- THEN it records the digests of both shader files
- VERIFIED: lint

### Requirement: The uniform block only grows at the end
New uniform members SHALL be appended after all existing ones; inserting one
elsewhere shifts std140 offsets and leaves later members silently unwritten.

#### Scenario: A new uniform is appended last
- GIVEN a change to the shader
- WHEN it is linted against the base branch
- THEN the old member list is a prefix of the new one
- VERIFIED: lint

### Requirement: No constant arrays in the shader
The shader MUST NOT declare constant arrays, which the GLSL 120 target cannot
express and which blank the overlay at runtime.

#### Scenario: The shader declares no const array
- GIVEN the shader source
- WHEN it is linted
- THEN no const array is declared
- VERIFIED: lint
