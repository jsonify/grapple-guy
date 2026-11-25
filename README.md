# Grapple Guy

A landscape iOS side-scroller: a line-art stickman swings through stages on a freeform grappling rope. See [`docs/plans/grapple-guy.md`](docs/plans/grapple-guy.md) for the full spec and the GitHub issues for the work plan.

## Layout

- `App/` — the iOS app: SwiftUI shell, SpriteKit scene, rendering, touch input, debug tuning overlay
- `Packages/GrappleCore/` — pure Swift game logic (simulation, aiming, levels), with unit tests; no SpriteKit/UIKit
- `project.yml` — XcodeGen spec; the `.xcodeproj` is generated, not committed

## Build and run (Mac)

Install XcodeGen once:

```bash
brew install xcodegen
```

Generate the Xcode project, then open it:

```bash
xcodegen && open GrappleGuy.xcodeproj
```

In Xcode, set your team under **Signing & Capabilities** (and change the bundle ID from `com.example.grappleguy` if needed), pick your iPhone, and run.

Run the core tests:

```bash
cd Packages/GrappleCore && swift test
```

## Controls (prototype)

- Touch and hold anywhere: fire the rope toward your finger (aim assist bends it to nearby orange blocks). Orange = grappleable, gray = solid.
- Lift: let go.
- After a crash or finish: tap to restart.
- **Tune** (top right): live sliders for every feel parameter. **Copy JSON** puts the values on the clipboard to paste back as defaults in `Packages/GrappleCore/Sources/GrappleCore/Tuning.swift`.
