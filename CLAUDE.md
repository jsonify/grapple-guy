# Grapple Guy

iOS stickman grappling side-scroller. Spec: `docs/plans/grapple-guy.md`. Work is tracked as GitHub issues grouped under milestone epics (#1–#4).

## Commands

- Generate project: `xcodegen` (never hand-edit or commit `GrappleGuy.xcodeproj`; change `project.yml`)
- Core tests: `cd Packages/GrappleCore && swift test`
- App build: `xcodebuild -project GrappleGuy.xcodeproj -scheme GrappleGuy -destination 'generic/platform=iOS Simulator' build`

## Architecture rules

- All physics and game rules go in `GrappleCore` (pure Swift, no SpriteKit/UIKit) with unit tests. The app layer only renders and turns input into calls on `SwingSimulation`.
- The simulation runs at a fixed timestep (`SwingSimulation.update(deltaTime:)` accumulates real frame time).
- The rope is a single length constraint, not a chain of segments (avoids jitter).
- Every feel number belongs in `Tuning` and gets a slider in `App/TuningPanel.swift`.
- World units are points, y up (matches SpriteKit).
