# Night run – unattended implementation

This file serves two readers:
- **Part 1** is for the user, before and after the run.
- **Part 2** is for the Claude session that implements Shadow43 overnight, without anyone watching.

---

## Part 1 – For the user

### Before kick-off (once, about 5 minutes)

1. **Install the Claude permissions.** Claude may not change its own permissions, so you do it:
   ```sh
   cd ~/Develop/visionpro_shadow43
   mkdir -p .claude && cp setup/claude-settings.json .claude/settings.json
   ```
   What the file does:
   - It lets Claude edit files in the project and run `swift`, `xcodebuild`, `xcodegen` and `xcrun`
     outside the sandbox.
   - It forbids commit, push, destructive git commands, `speak`, `sudo`, `brew`, `curl` and web
     access.
2. **Smoke test.** About 1 minute; it checks that the night session will not get stuck:
   ```sh
   cd ~/Develop/visionpro_shadow43 && claude -p "Run each step, report OK or DENIED with one line of output, never work around a denial: 1) xcodebuild -version 2) swift --version 3) xcrun simctl list runtimes 4) xcodegen --version 5) Write the file smoke.txt with content hi, then Edit it to hello 6) Read the first 3 lines of /Applications/Xcode.app/Contents/Developer/Platforms/XROS.platform/Developer/SDKs/XROS.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/RealityFoundation.swiftmodule/arm64e-apple-xros.swiftinterface 7) git commit --dry-run -m test 8) speak test 9) rm smoke.txt" --permission-mode dontAsk --permission-prompts none
   ```
   Expected result: steps 1–6 and 9 are OK, steps 7 and 8 are DENIED. If anything else differs,
   do not start the run; the cause is almost certainly a rule in `.claude/settings.json`.
3. **Baseline commit**, so that `git diff` in the morning shows exactly the night's work:
   ```sh
   git add -A && git commit -m "Design v0.3, project setup"
   ```
4. **Keep the Mac on power** with the lid open. `caffeinate` below prevents sleep.

### Kick-off

```sh
cd ~/Develop/visionpro_shadow43
caffeinate -dims claude --permission-mode dontAsk
```

1. Confirm the trust dialog for the folder.
2. Paste this line:
   ```
   /goal The night run in NIGHT_RUN.md is finished: NIGHT_REPORT.md gives a final status (done, partial or blocked, with reason) for every milestone M0–M6, and the last `swift test` and `xcodebuild` runs in this transcript succeeded.
   ```
3. If Claude has not started working after a minute, or `/goal` is reported as an unknown
   command, type: `Start the night run as described in NIGHT_RUN.md.` Without `/goal`, the run
   relies on Part 2 to keep going through all milestones, so there is a somewhat higher chance it
   stops early.
4. Watch the first milestone start, then go to bed.

What `dontAsk` means:
- Anything not explicitly allowed is refused automatically, so the session never waits for you.
- `/goal` makes Claude keep working until the condition holds.

### In the morning

- Read `NIGHT_REPORT.md`: status per milestone, screenshots, open questions, and the device
  checklist.
- `git status` and `git diff` show the night's changes.
- To continue in the same session: `claude -c`.
- Device: open `Shadow43.xcodeproj` in Xcode. On the first run, create
  `Config/Signing.local.xcconfig` with your team ID and a unique bundle ID (see README), then run
  the app on the Vision Pro.
- If the run stopped early, the cause is in `NIGHT_REPORT.md` or at the end of the session. The
  usual causes are usage limits, an unrecoverable context overflow, or a network outage.

---

## Part 2 – For the implementing Claude

### Mission

Implement Shadow43 according to `DESIGN.md`. Work through milestones M0–M6 in order and get as far
as you can tonight. Nobody will answer questions until morning. You work autonomously: decide, keep
going, and document.

Read first, completely: `CLAUDE.md`, `DESIGN.md`, this file.

### Order and night-time acceptance

You only have the simulator. Everything that needs the device goes into the morning checklist.

| Step | Work | Done tonight when |
|---|---|---|
| M0 | `project.yml`, `Config/Shared.xcconfig`, `Packages/Core4D`, app skeleton with volumetric window and `ImmersiveSpace` stub (DESIGN 12.2, 7), String Catalog, snapshot mode (launch arguments → `ViewState`, fixed time) | project generates, builds, launches in the simulator; screenshot shows a placeholder |
| M1 | Core4D: `Complex4D`, polytope generator (10.5) for the 5-, 8-, 16- and 24-cell, rotation (R, Ω, step, orthonormalisation), projection (κ, s), tessellation to `RenderMesh4D` | all tests from 12.4 that apply to these objects are green |
| M2 | Rendering pipeline (11): `LowLevelMesh` for faces and tubes, a RealityKit `System`, motion and projection presets, basic control panel; **S2**: performance overlay (frame time, triangle count) | screenshots: tesseract in orthographic, perspective and stereographic; all 4 polytopes |
| M3 | Display layers, presets, colour sources (uniform, by W, per cell), explode, floor shadow; **S1**: all three transparency methods switchable in the Developer section; **S4** | screenshots of every display preset and colour source, each transparency method, and the floor shadow |
| M4 | Gestures, variant A (8.1, 10.7), throw and catch, friction; **S3**: gesture test scene with raw values, including `ManipulationComponent` events (variant C) | builds; mapping logic tested in Core4D; gestures listed in the device checklist |
| M5 | 600- and 120-cell via the bootstrap (10.5), duoprisms p×q, subdivision for smooth stereographic display, profiling | f-vector tests green; screenshots of the 120- and 600-cell, stereographic |
| M6 | Parametric surfaces and curves (10.6): Klein bottle, Clifford torus, Hopf fibration; colour sources surface parameter and per fibre | tests green; screenshots of all three |

### Rules for the unattended run

1. **Never wait for the user and never ask questions.**
   - If something is unclear, choose the option that is most consistent with DESIGN.md and easiest
     to reverse.
   - Record the question and your choice in the "Questions for the user" section of
     `NIGHT_REPORT.md`, and keep going.
2. **Never commit, push, call `speak` or install anything.** It is night, and `speak` would wake the
   user. No network access is needed.
3. **Follow the toolchain invocation rules in CLAUDE.md:** absolute paths, no `cd`, pipes or
   redirects. Otherwise the command lands in the sandbox and fails.
4. **If a permission is denied,** do not look for a workaround. Note it in the report and continue
   with other work.
5. **If you are stuck for more than about 45 minutes on one problem,**
   - document what you tried and what you suspect,
   - mark the item *blocked* or *partial*,
   - and move on to the next independent work.

   Example: if the S1 transparency methods do not work, ship the additive method and continue
   with M4.
6. **End every milestone with a green state:** tests green, build successful, the app launches.
   Unfinished features go behind a flag or into the Developer section; never leave a broken
   build behind. There are no commits, so this is the only safety net.
7. **Check the results visually.**
   - Look at every screenshot with the Read tool and judge it honestly: is the object visible,
     centred, plausible, without artefacts?
   - Name screenshots `build/screenshots/M<n>-<description>.png`.
   - If objects are too small in the screenshot, enlarge the default volume size or the object
     scale in snapshot mode.
8. **Keep the scope tight.** Only what DESIGN.md describes, no extra features. Small, readable
   files with brief doc comments on public types.
9. **Watch your context.** After each milestone, update `NIGHT_REPORT.md` so that a resumed session
   could continue from it alone. Update DESIGN.md §13 with lessons learnt, for example about API behaviour
   and the chosen spike approaches.
10. **At the end:**
    - finalise `NIGHT_REPORT.md`,
    - shut down the simulator (`xcrun simctl shutdown all`),
    - run `swift test` and `xcodebuild` one last time so that their success is visible in the
      transcript.

### `NIGHT_REPORT.md` (create in M0, update after every milestone)

```markdown
# Night report <date>

## Summary
<3–5 sentences: how far it got, what works, the most important problem>

## Milestones
| Milestone | Status (done/partial/blocked/not started) | Notes |

## Screenshots
<list: file – what it shows – your assessment>

## Device checklist for the morning
<numbered list: what the user must check on the Vision Pro (S1–S4, gestures, performance, feel), with the expected result>

## Questions for the user
<question – what you chose instead – how to change it>

## Deviations from DESIGN.md
<what and why>

## Files
<new and changed files, grouped by folder>
```
