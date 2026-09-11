# Optional side-by-side video composition

This Remotion composition aligns an iPhone login recording with a Browserbase
recording. It is presentation material, not part of the iMessage app build.

Supply your own recordings in `public/`:

- `iphone-h264.mp4`: the 17.5-second iPhone login capture, H.264 encoded.
- `browser.mp4`: the corresponding Browserbase recording.

Recordings and rendered output are ignored by Git. Do not include private login
footage or session details in a shared repository. The composition's timings are
specific to the original demo; adjust them for new footage.

```sh
cd examples/video-demo
npm ci
npm run studio
# After adding recordings:
npm run render
```

Output: `out/cookieclip-auth-handoff.mp4`. The root `make setup` and `make check`
do not install dependencies or render this optional example.
