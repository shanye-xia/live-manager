# Synthetic test media

This directory is for generated, non-private test files used to validate LiveKit's Live Photo / Motion Photo detection and stripping logic.

Planned sample types:

- Plain JPEG with no Motion Photo payload.
- Standard Motion Photo JPEG with appended video payload and valid XMP metadata.
- Boundary samples: missing metadata, broken offsets, truncated payload, Ultra HDR / GainMap adjacent metadata.

Only generated files without personal content should be stored here.

## Generate samples

Run from the repository root:

```powershell
python tools/generate_motion_photo_samples.py
```

The script writes generated files to:

```text
testdata/synthetic/generated/
```

These generated files are for detector / stripper regression tests. The Motion Photo sample contains valid JPEG + Motion Photo metadata + an appended MP4-like payload, but the appended video payload is intentionally tiny and is not intended for playback testing.

## Reference policy

When adding new synthetic fixtures, compare behavior against Android official Motion Photo documentation, AndroidX Media3, and public GitHub implementations where useful.

GitHub projects should be used for protocol behavior, edge cases, and test ideas only. Do not copy GPL or license-incompatible implementation code into LiveKit.
