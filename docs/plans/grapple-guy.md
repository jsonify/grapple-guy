# Grapple Guy: spec

## Goal
A landscape iOS side-scroller in which a stickman with hybrid ragdoll physics swings through handcrafted stages on a freeform grappling rope, Spider-Man style. It starts as a solo hobby project (about 10 hrs/week) that can grow into a commercial release if the swing feels great.

## Decisions
- **Ambition**: hobby project first, with the option to go commercial later, because the game depends on how the swing feels, and that can only be judged by playing it. Build a small vertical slice, put it on TestFlight, then decide.
- **Team and time**: solo, about 10 hrs/week. Claude writes all the code, so the developer's time goes to playtesting, tuning and level design.
- **Engine**: Swift + SpriteKit, iOS first, because the game is primarily for iOS and SpriteKit can be driven entirely from code, which suits Claude doing the programming (preferred over Godot despite enjoying Godot).
- **Dev setup**: Claude Code runs locally on the developer's Mac, so Claude can run `xcodebuild`, tests and the simulator and check its own work. A physical iPhone is used for feel testing.
- **Grapple control**: freeform aim with aim assist. Tap where you want to aim, the rope fires toward that point and sticks to the first surface it hits that can be grappled, bending toward a nearby good target if the tap is close. Lift your finger to release. This was chosen because it feels like Spider-Man rather than a one-button timing game, and aim assist forgives fat fingers. Levels are built from grappleable surfaces, not fixed anchor points.
- **Ragdoll**: hybrid. The torso is the main physics body and sets the path; the limbs are light jointed bodies that flop with real physics and barely affect the swing. On a crash or hard impact the whole body goes fully limp. This keeps the swing predictable while still giving funny flailing and satisfying crashes.
- **Rope physics**: a single length constraint, not a chain of linked segments, to avoid jitter at high speeds.
- **Stage structure**: handcrafted levels of 30-90 seconds, grouped into worlds, each world introducing a new idea, with optional star goals (time, collectibles). Levels are built from reusable chunks stored as data (JSON) so an endless mode can stitch them together later.
- **Orientation**: landscape, because freeform aiming needs a view of surfaces ahead and the one-finger controls make holding the phone sideways cheap.
- **v1 scope**: one world of about 10 levels, rope moves (reel in/out and release boost) and hazards (e.g. moving or crumbling surfaces, wind, spikes).
- **Rope moves in v1**: reel in/out by sliding the holding finger toward or away from the stickman, and a release boost for letting go at the right moment. Both work with the one finger already on the screen, so the controls stay one-handed. The yank/pull move is cut because its flick gesture clashes with reeling.
- **World 2**: introduces a second rope, fired with a second finger.
- **v1.1**: tricks and style (flips, combos, slow-mo near-misses) and cosmetics (skins, rope colors, trails), including neon glow trails.
- **Visual style**: clean line art, with the stickman drawn in code as thick, round-capped strokes, flat-color backgrounds with parallax layers and a color palette per world. No artist is needed, and it reads clearly at speed.

## Assumptions
- **Failure**: falling off screen or hitting a hazard triggers a ragdoll crash, then an instant restart at the level start, or at a checkpoint in longer levels. I proposed this and it wasn't objected to.
- **Code architecture**: physics and game logic live in plain Swift modules that can be unit-tested, separate from SpriteKit rendering, so Claude can check behavior without a person playing.
- **Game feel and audio**: punchy sound effects (rope fire, attach, whoosh, crash), screen shake on crashes, a short freeze-frame on hard hits and a camera zoom that follows speed. Music comes later.
- **Monetization**: none in v1, as a free hobby build distributed via TestFlight.
- **Feel tuning**: rope, gravity, aim-assist and boost parameters should be tweakable at runtime through a debug overlay, so the developer can tune feel on the device without asking for a rebuild.

## Risks accepted
- **iOS only**: SpriteKit rules out an easy Android or Steam port if the game goes commercial.
- **SpriteKit investment**: Apple has put little into SpriteKit recently. It's stable and sufficient for 2D physics, but new features are unlikely.
- **Physics stability**: jointed ragdoll limbs can jitter or explode at high speeds. This is mitigated by light limbs, the single-constraint rope and capped velocities.
- **Time budget**: about 40 hrs/month. "Feature rich" is staged across v1, world 2 and v1.1 so the core swing gets polished first.

## Open questions
- Minimum iOS version (suggest iOS 17+), to be settled when creating the Xcode project.
- How strong aim assist should be (snap radius and how far it bends), to be settled by playtesting on the device.
- Exact v1 hazard list and the theme of world 1, to be settled while designing the first 10 levels.
- Checkpoint rules (which levels get them), to be settled once level lengths are known.
- Music direction, after v1.
- Deferred features: meta progression, gadgets/power-ups, Game Center, level editor, endless mode, monetization. Revisit if the project moves toward a commercial release.

## Next steps
1. Create the Xcode project (SpriteKit, landscape, Swift) plus a Swift package for the game logic, with unit tests.
2. Build the swing prototype: a torso body, rope length constraint, freeform tap-to-fire with a raycast against grappleable surfaces, and release on lift, in a flat test room.
3. Add a runtime debug overlay with sliders for rope, gravity, aim-assist and boost parameters, then tune on the iPhone until swinging alone is fun.
4. Add hybrid ragdoll limbs and the limp-on-crash state.
5. Add reel in/out and the release boost.
6. Define the level-chunk JSON format and build 2 or 3 test levels, then hazards, then the remaining world-1 levels.
