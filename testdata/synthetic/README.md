# Synthetic test media

This directory is for generated, non-private test files used to validate LiveKit's Live Photo / Motion Photo detection and stripping logic.

Planned sample types:

- Plain JPEG with no Motion Photo payload.
- Standard Motion Photo JPEG with appended video payload and valid XMP metadata.
- Boundary samples: missing metadata, broken offsets, truncated payload, Ultra HDR / GainMap adjacent metadata.

Only generated files without personal content should be stored here.
