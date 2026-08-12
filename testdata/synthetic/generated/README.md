# Generated synthetic samples

These files are generated test fixtures and contain no personal data.

- `plain.jpg`: normal JPEG, should not be detected as Motion Photo.
- `motion_detect_only.MP.jpg`: JPEG with Motion Photo XMP and appended MP4-like payload.
- `motion_playable.MP.jpg`: JPEG with Motion Photo XMP and appended real MP4 payload, generated when ffmpeg is available.
- `motion_playable_source.mp4`: source MP4 used by `motion_playable.MP.jpg`, generated when ffmpeg is available.
- `broken_missing_xmp_appended_video.jpg`: appended payload but no Motion Photo XMP.
- `broken_xmp_without_video.jpg`: Motion Photo XMP but missing appended payload.

`motion_detect_only.MP.jpg` is for detector / stripper regression tests and is not intended to be a playable video.

`motion_playable.MP.jpg` should be validated on a real Android device with Google Photos or another gallery app. Local generation only proves the file structure and MP4 payload; it does not prove gallery compatibility.
