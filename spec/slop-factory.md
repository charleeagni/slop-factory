# Slop Factory

> "Slop Factory recognizes when there is a new model and it automatically burns
> all of your tokens and creates new slop. It also posts it automatically on
> Twitter without you even being in the loop." (from the release ad)

When a new Claude or OpenAI model shows up in the local `claude` or `codex`
CLI, Slop Factory gives it the same frozen prompt, records what the model
builds, posts it on X and tells you. Every model gets the same prompt, so
the clips can be compared side by side.

## Scope

- Open source (MIT), shipped as a native macOS menu bar app. You drag it into
  Applications, open it, log into X once, and after that it works on its own.
- Nothing to install besides `claude` and/or `codex`, which you already have.
  No Python, no Chrome, no ffmpeg, no Playwright.
- Only Claude models (through the `claude` CLI) and OpenAI models (through
  the `codex` CLI).
- The trigger is "the model is usable on my subscription", not "the provider
  announced it". No API keys are needed.

## First launch

1. Open `Slop Factory.app`. A 🏭 icon appears in the menu bar.
2. It finds `claude` and `codex` and shows which ones it found. If only one
   is installed, it skips the other.
3. A window shows x.com so you can log in once. The login stays in the app's
   own web storage.
4. It records the models that already exist (no posts), then turns on
   "Open at Login".

## Menu

```
🏭 Slop Factory
   Watching: 7 Claude · 7 OpenAI models
   Last slop: gpt-6-astra · 2 h ago ↗
   ─────────
   Check now
   Slop now ▸ <any seen model>
   Draft only (don't click Post)   ☐
   Open runs folder
   Log into X…
   Quit
```

## Pipeline

```
timer (every 30 min, while the app runs)
  -> Detection     current model IDs minus seen.json = new models
  -> Generation    frozen prompt, headless claude/codex, fresh folder, timeout
  -> Recording     offscreen WKWebView of the output -> 15-20 s demo.mp4
  -> Posting       WKWebView on x.com -> compose -> text + video -> Post
  -> Notification  "<model> slop posted" with the post link
```

"Slop now" sends any model already in `seen.json` through the same
Generation → Notification steps right away, without waiting for a new model.
It leaves `seen.json`'s model list and `lastCheck` alone.

Runs happen one at a time. A 🏭 that spins means a run is in progress.

## Detection

These three sources are combined into one set of model IDs:

| Source | How | Cost |
|---|---|---|
| Codex | `~/.codex/models_cache.json` → `models[].slug` where `visibility == "list"` (this drops `gpt-reserve` and `codex-auto-review`) | free |
| Claude aliases | `claude -p --model {opus,sonnet,haiku} --output-format json "ok"` → key of `modelUsage` in the `result` event (tested: `haiku` → `claude-haiku-4-5-20251001`) | 3 tiny calls |
| Claude extras | `~/.claude.json` → `additionalModelOptionsCache[].value` (for example `claude-fable-5-1[1m]`) | free |

An ID is added to `seen.json` only after its run finishes, so a crash means
the next check tries it again.

Caveat: these lists refresh only when the CLI updates or gets used. Claude
Code updates itself. Codex refreshes its cache whenever it runs.

## Generation

- Prompt: `Sources/FactoryCore/Resources/frozen-prompt.txt`, bundled in the app. It's frozen and never edited
  once runs exist. Changing it means starting a new series.
- My slop prompt: the menu's **Edit prompt…** copies the frozen prompt to
  `my-prompt.txt` in app data and opens it; builds use that file while it has
  text. **Reset to frozen prompt** deletes it.
- My slop post text: **Edit post text…** does the same with `my-post.txt`,
  the post headline (`{model}` becomes the model ID). The previous-post link
  and repo URL are always appended.
- Claude: `claude -p --model <id> --effort medium --dangerously-skip-permissions`
- OpenAI: `codex exec -m <slug>` with approvals disabled, workspace-write
  sandboxing, and medium reasoning effort independent of the user's CLI default.
- Both run in `runs/<model>/work/` through `Process`.
- One shot, no follow-ups: 0 prompts from the user, 1 frozen prompt to the
  model.
- Hard timeout per run (20 min). A failed build is logged and retried on a
  later check; it is not recorded or posted.
- PATH gotcha: apps launched from Finder don't get your shell's PATH. The app
  discovers the shell PATH with `/bin/zsh -lc` and saves it. Before each Codex
  build, it compares available Codex executables on that PATH and in standard
  ChatGPT app locations, then uses the newest installed CLI version.

## Recording

- An offscreen `WKWebView` (1280×720) loads `work/index.html`.
- `takeSnapshot` at 15 fps feeds `AVAssetWriter`, which writes an H.264
  `demo.mp4`.
- If there's no page or image to open, recording fails and nothing is posted.

## Posting

This uses a web view instead of the X API, so there's no developer app and no
paid tier.

- A `WKWebView` using the default persistent data store, which holds the X
  login from first launch.
- Steps: open `x.com/compose/post` → insert the text into the editor → send
  the mp4 bytes to JS, build a `File` and `DataTransfer`, and assign them to
  the media `<input type=file>` → wait for the upload to finish → click Post →
  read the new post URL.
- Post text: `New model detected: <model>. Zero prompts. Here's its slop.`,
  plus a link to the previous model's post and the repo.
- "Draft only" leaves the compose window open and asks you to click Post.
  Default is off, as the ad promises.
- Each post attempt has a run ID (its run folder name) and a record in
  `seen.json`'s `manualPosts`: `pending` while a draft waits for your click,
  `completed` once a post URL is confirmed, `failed` when X reports an error
  (with the failed step), or `uncertain` when the click got no confirmation.
  The next check re-posts the recorded demo for `failed` runs only, still
  honouring Draft only. `pending` and `uncertain` runs are never re-posted, so
  an untouched draft or an unconfirmed click can't make a duplicate.

## Notification

`UserNotifications`. Clicking one opens the post. If a run fails, the
notification says which step failed.

## Data

`~/Library/Application Support/Slop Factory/` holds `seen.json` and
`runs/<model>/` (the prompt, `work/`, `demo.mp4`, `post.txt` and a log).
`runs/` doubles as the leaderboard.

## Layout

```
slop-factory/                        (public repo)
  README.md                          the pitch (80s ad embedded), download, disclaimer
  LICENSE                            MIT
  Package.swift                      Swift package and app targets
  Resources/Info.plist               macOS app metadata
  Scripts/build-app.sh               builds and signs the app bundle
  Sources/FactoryCore/               detection, generation and run orchestration
    Resources/frozen-prompt.txt      frozen prompt
  Sources/SlopFactory/               menu app, recorder and X integration
  Tests/FactoryCoreTests/            core tests with no live services
  Tests/RecorderIntegration/         native recorder host plus fixtures
  spec/slop-factory.md
```

## Distribution

- GitHub Releases: a zipped `.app` or `.dmg`, built by a GitHub Action on tag.
- Not sandboxed, because it spawns CLIs and reads `~/.codex`. That rules out
  the Mac App Store.
- Signing: the release workflow imports a Developer ID certificate from
  repository secrets, signs with the hardened runtime, notarizes with
  `notarytool` and staples the ticket. Without the secrets it falls back to an
  ad hoc signature, and users right-click → Open the first time.
- Later: `brew install --cask slop-factory`.

## Operational notes

1. X sign-in popups open in child windows. The compose selectors may need
   maintenance when X changes its UI.
2. Background and restarts: the app is `LSUIElement` (no Dock icon, no
   window) and registers itself with `SMAppService.mainApp`, so it comes back
   after every restart or login. Timers pause while the Mac sleeps. The app
   saves `lastCheck` in `seen.json`. On launch and on
   `NSWorkspace.didWakeNotification`, if `lastCheck` is more than 30 min old,
   it checks right away. Nothing else is needed: a check compares the current
   list with `seen.json`, so every model that appeared while it was asleep
   gets its run. A crash isn't relaunched until the next login. If that becomes a
   problem, register the app as an `SMAppService.agent` with `KeepAlive`.
3. Claude alias checks make three small CLI calls every 30 minutes.
