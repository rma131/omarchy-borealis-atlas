# Build provenance for `shaders/aurora.frag.qsb`

This repository ships exactly one binary: `shaders/aurora.frag.qsb`, the
compiled form of `shaders/aurora.frag`. Qt cannot compile GLSL at runtime — a
`ShaderEffect` takes a `.qsb` — so it has to be committed, which makes it the
one file in here you cannot read.

You do not have to trust it. The build is **deterministic**: the same source
and the same `qsb` version produce byte-identical output, so the artifact can
be reproduced and compared rather than believed.

## Toolchain

| | |
|---|---|
| Tool | `qsb`, Qt Shader Baker (QShader from Qt 6.11.2) |
| Package | `qt6-shadertools 6.11.2-1` (Arch Linux) |
| Pinned at | Arch Linux Archive snapshot `2026/09/01` |
| Pinned URL | `https://archive.archlinux.org/repos/2026/09/01/$repo/os/$arch` |

`qsb` is not on `PATH` on Arch; it lives at `/usr/lib/qt6/bin/qsb`.

## Build command

Complete and exact — no wrapper, no build system, no flags omitted:

```sh
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
  -o shaders/aurora.frag.qsb shaders/aurora.frag
```

The targets are inherited from
[marko-builds/borealis](https://github.com/marko-builds/borealis) and are the
reason no const array or dynamically-indexed array may appear in the source:
the GLSL 120 target rejects them at runtime with `C7516` and a blank overlay,
while `qsb` itself compiles clean.

## Digests

These are the bytes as shipped. They change only when the shader source or the
`qsb` version changes, and CI enforces the relationship on every push:

| file | SHA-256 |
|---|---|
| `shaders/aurora.frag` (source) | `413a956d40fcfb0ce5e5ddaaf160033af7f50adc5f193455d90937289eb56d68` |
| `shaders/aurora.frag.qsb` (shipped) | `f64cbe9f5acf86bfe3253bf519ab77658b68621c45ce690f4d66daa0963e00b1` |

## Verify it yourself

One command, no checkout of this repo's toolchain required. It rebuilds in a
clean container with the pinned snapshot and compares against what is shipped:

```sh
podman run --rm -v "$PWD":/src:ro docker.io/library/archlinux:base sh -c '
  printf "Server=https://archive.archlinux.org/repos/2026/09/01/\$repo/os/\$arch\n" \
    > /etc/pacman.d/mirrorlist
  pacman -Syuu --noconfirm --needed qt6-shadertools >/dev/null 2>&1
  /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
    -o /tmp/rebuilt.qsb /src/shaders/aurora.frag
  sha256sum /tmp/rebuilt.qsb /src/shaders/aurora.frag.qsb'
```

Both lines must print `f64cbe9f…`. Substitute `docker` for `podman` freely.

This was run before publishing: the artifact reproduces byte-for-byte both on
the author's machine and in a clean pinned container.

## Continuous verification

[`.github/workflows/shader-provenance.yml`](../.github/workflows/shader-provenance.yml)
performs exactly the steps above on every push that touches `shaders/`, and
**fails the build** if the committed `.qsb` is not byte-identical to a rebuild
of the committed `.frag`. It asserts the `qt6-shadertools` version too, so a
silent toolchain drift is an error rather than a surprise, and it publishes a
[build provenance attestation](https://docs.github.com/actions/security-guides/using-artifact-attestations)
for the artifact.

Verify a downloaded copy against that attestation with:

```sh
gh attestation verify shaders/aurora.frag.qsb --repo rma131/omarchy-borealis-atlas
```

## If you change the shader

Recompile and commit the `.frag` and the `.qsb` **in the same commit**, and
update the digest table above. CI will fail if they disagree. If you bump
`ARCH_SNAPSHOT` in the workflow, expect the artifact hash to change with the
`qsb` version and update `EXPECTED_QSB` and this document together.
