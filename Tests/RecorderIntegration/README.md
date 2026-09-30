# Recorder integration checks

Run on an awake, signed-in macOS desktop with Xcode installed:

```sh
Scripts/test-recorder.sh
```

This compiles `Sources/SlopFactory/WebViewRecorder.swift` directly into a native
application event-loop host. It calls the synchronous `Recorder` contract on a
background task. There is no copied encoder, alternate HTML loading path, server,
or runtime dependency. AVFoundation decodes the resulting movies. PNG evidence
and MP4 files go to `.build/recorder-evidence`.
Allow several minutes. The host fails after ten minutes if recording hangs.

The suite records static, animated, empty, Claude, OpenAI, repeated static, and
black inputs in one process, then forces a real filesystem failure and records
again. Each successful movie must contain 270 silent H.264 frames at 1280×720,
15 fps, and 18 seconds within one frame interval. Content checks sample 1, 3, 5,
9, and 17 seconds. The static regions use 20×20 averages and RGB tolerance 25.
The animated marker must have both states. Trial pages must contain their warm
market scene and changing upper-scene surroundings. Empty output must fail
without creating a movie.
A timer fails the host if any visible window intersects an attached display.

Run one case or inspect an existing movie:

```sh
Scripts/test-recorder.sh .build/recorder-evidence/one animated
Scripts/test-recorder.sh .build/recorder-evidence/inspection inspect-animated /absolute/path/demo.mp4
```

`claude/index.html` and `openai/index.html` are byte-for-byte copies of the saved
CODING-2208 pixel trials, preserved as fixtures. Their hashes and original paths
are in [the verification report](../../docs/recording-verification-2026-09-29.md).
Assertions about scene colors and motion are fixture-specific tests, not runtime
quality checks. A black or static generated page remains valid input.

The optional built-app smoke check requires Python 3 and Xcode. It uses the
existing app-data override and saved CLI path to supply a local
fixture through a test CLI. The release app's scheduler and recording code run
unchanged. Networking is denied for the test process; it does not upload to X.
The script waits for the run's `post.log`, which the poster creates after the
recorder finishes writing, then terminates the app. It runs the native
`inspect-animated` check and fails if metadata, decoded colors, or changing
markers are wrong. No `ffprobe` installation is needed. Each run saves its movie,
app log, and decoded inspection frames under `.build/recorder-smoke/data-<timestamp>`.

```sh
Scripts/build-app.sh "$PWD/.build/recorder-smoke/Slop Factory.app"
python3 Scripts/test-recorder-app.py
```

The smoke command's process-boundary regression tests run without a desktop:

```sh
python3 -m unittest discover -s Tests/RecorderSmoke -v
```

QuickTime and actual X draft playback remain separate desktop checks. An upload
being Ready does not prove playback. Never publish a verification post.
