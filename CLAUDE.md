# Shadow43 – project context for Claude

Shadow43 is a native visionOS app (Swift, SwiftUI, RealityKit) that shows the rotating 3D projection
("shadow") of 4D objects: polytopes, surfaces in 4D and Hopf fibres. It is open source under the
Apache 2.0 licence, © Andreas Keese.

## Status
DESIGN.md (v0.5) describes the current implementation (app version 1.0.0). For the unattended
overnight run, follow `NIGHT_RUN.md`.

## Files
- `DESIGN.md`: the spec and single source of truth. Read all of it at the start of every session.
  Keep it one coherent description of the current state: change the text where it belongs instead
  of appending history. Add lessons from testing to §13 under their topic. Record new decisions in
  the decision log (§15) with date, section and rationale, and cite them in the text as [Dn]. When
  sections move, update the "DESIGN x.y" pointers in code comments.
- `NIGHT_RUN.md`: plan and rules for unattended runs. `NIGHT_REPORT.md` is the progress log of such
  a run.
- `project.yml`: XcodeGen spec. `Shadow43.xcodeproj` is generated and git-ignored, so never edit it
  by hand. Run `xcodegen generate` after adding targets or changing settings.

## Rules
These are in addition to `~/Develop/CLAUDE.md` and `AGENTS_general.md`.
- **Never commit or push.** Do not run git commands that change history or the working tree
  (reset, checkout, restore, clean, stash). The user handles git.
- No third-party dependencies or tools without asking first. XcodeGen is the only approved tool.
- Never change signing or team settings. Real team and bundle IDs live only in the git-ignored
  `Config/Signing.local.xcconfig`, which the user creates. Never write Apple IDs, team IDs, device
  names or device IDs into tracked files.
- Everything is in English: UI, identifiers, comments and docs. UI strings go through a String
  Catalog.
- `Packages/Core4D` imports only Foundation and simd, never RealityKit or SwiftUI. Every public
  function gets tests (DESIGN.md §12.4). Use Swift Testing (`import Testing`).
- `ViewState` is the single source of truth. The scene entity is never rotated; all rotation lives
  in R (DESIGN.md §4). Scene content must not depend on its host scene (§9.3, `SceneHost`).
- Every gesture needs a UI equivalent. Every visual state must be reachable through launch
  arguments (snapshot mode, §12.5).
- The SDK is visionOS 27, newer than your training data. Verify APIs against the SDK interface
  files rather than memory, and mark unverified assumptions as [verify]:
  `/Applications/Xcode.app/Contents/Developer/Platforms/XROS.platform/Developer/SDKs/XROS.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/RealityFoundation.swiftmodule/arm64e-apple-xros.swiftinterface`
  The SwiftUI and RealityKit interfaces are in the same `Frameworks` folder.
- Performance: implement on the CPU with SIMD first and measure. Move to Metal compute only if the
  budget in §11.9 is exceeded, and ask first.
- `App.body` must be declared as `some SwiftUI.Scene`, because RealityKit also defines `Scene`.
- This project is small and new, and the jbcontext MCP server is currently not connecting. For code
  discovery, use direct reads and grep; the jbcontext/context-explorer step from
  `~/Develop/CLAUDE.md` is not needed here.

## Build, test, run
`.claude/settings.json` sets `DEVELOPER_DIR`. It also lets `swift`, `xcodebuild`, `xcodegen` and
`xcrun` run outside the sandbox, because they fail inside it.

**Invocation rules.** Otherwise the command stays sandboxed and fails:
- Never put `cd`, pipes, redirects or `$(...)` in a toolchain command.
- Always use absolute paths.

Commands (PROJ = `/Users/andreas/Develop/visionpro_shadow43`):
- Generate project: `xcodegen generate --spec PROJ/project.yml`
- Core tests: `swift test --package-path PROJ/Packages/Core4D`
- Build: `xcodebuild -quiet -project PROJ/Shadow43.xcodeproj -scheme Shadow43 -destination 'generic/platform=visionOS Simulator' -derivedDataPath PROJ/build/DerivedData build`
- The built app is at `PROJ/build/DerivedData/Build/Products/Debug-xrsimulator/Shadow43.app`.
- Simulator (device name "Apple Vision Pro", visionOS 27.0):
  1. `xcrun simctl boot "Apple Vision Pro"`
  2. `xcrun simctl bootstatus "Apple Vision Pro" -b`
  3. Wait about 20 s. Installing right after boot fails with `IXErrorDomain code=3 "Failed to
     locate promise"`; if that happens, wait and retry once.
  4. `xcrun simctl install booted <app path>`
  5. `xcrun simctl launch --terminate-running-process booted com.example.shadow43 -object tesseract …`
     If `Config/Signing.local.xcconfig` exists, it overrides the bundle ID, also for simulator
     builds: use the ID from that file (never copy it into tracked files).
  6. `xcrun simctl io booted screenshot PROJ/build/screenshots/<name>.png`, then look at the image
     with the Read tool.
  7. Shut down at the end with `xcrun simctl shutdown all`.

## Device loop
Claude cannot deploy to the Vision Pro. The user runs the app from Xcode (Personal Team; installs
expire after 7 days) and reports back. For each milestone, write a short device checklist.
