# Clipshot example

Run the app, tap **Use bundled sample video**, and extract one frame or an
ordered batch of three. The included MP4 is procedurally generated from FFmpeg's
`testsrc2` and sine-wave sources, so tests do not depend on personal media or
machine-specific paths.

To regenerate it:

```sh
ffmpeg -f lavfi -i "testsrc2=size=320x180:rate=15:duration=3" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=3" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  example/assets/sample.mp4
```
