# Making levels

Levels live in `App/Levels/` as JSON. There are two kinds of file:

- **`chunks.json`**: the library of reusable pieces ("chunks").
- **`<level-name>.json`**: one file per level, listing chunks left to right.

Coordinates are in world points, with **y pointing up** and the start platform's top at y = 0. For scale, the stickman is about 70 points tall, and the screen shows about 1400 points of height.

## Chunks (`chunks.json`)

```json
{
  "id": "ceiling-pillar",
  "width": 420,
  "elements": [
    { "type": "grapple", "rect": [130, 560, 160, 40] },
    { "type": "solid",   "rect": [340, -600, 80, 820] }
  ]
}
```

- `id`: a unique name that levels refer to.
- `width`: where the next chunk starts, measured from this chunk's left edge.
- `elements`: placed in chunk-local coordinates, with x = 0 at the chunk's left edge.

| Element | JSON | Notes |
|---|---|---|
| Grappleable block | `{"type": "grapple", "rect": [x, y, w, h]}` | Orange. The rope sticks to it. |
| Solid block | `{"type": "solid", "rect": [x, y, w, h]}` | Gray. Blocks the stickman and the rope. |
| Spawn | `{"type": "spawn", "at": [x, y]}` | Exactly one per level. |
| Finish line | `{"type": "finish", "x": 100}` | Exactly one per level. |
| Gem | `{"type": "gem", "at": [x, y]}` | Collect all of them for a star. |
| Water hazard | `{"type": "water", "rect": [x, y, w, h]}` | Entering it costs +1 swing; you're put back where you last stood still (or the last checkpoint). Put it in pits or recessed pools. |
| Sand trap | `{"type": "sand", "rect": [x, y, w, h]}` | A solid surface that stops you dead, softens hard landings and weakens your next rope tug. |
| Checkpoint | `{"type": "checkpoint", "at": [x, y]}` | Activates when the stickman passes its x. Crashes then respawn at `at`, so put it on a platform. |

`rect` is `[left, bottom, width, height]`.

## Levels

```json
{
  "name": "Test Room",
  "par": 12,
  "killY": -500,
  "chunks": [
    { "id": "start" },
    { "id": "ceiling", "dy": 60 },
    { "id": "ceiling-pillar" },
    { "id": "finish" }
  ]
}
```

- Chunks are laid out left to right. Each one starts where the previous one's `width` ends.
- `dy` (optional) shifts that one placement up (positive) or down (negative).
- `par` (required, > 0): the target number of strokes. Every rope shot is a stroke, and finishing at or under par earns a star.
- `killY`: falling below this height is **out of bounds**: +1 swing, back to where you last stood.
- `wind` (optional): maximum wind strength. Each attempt picks a steady wind between `-wind` and `+wind` (about 100–300 is noticeable); shown on the HUD.

**Stars:** finish the level, finish at or under par, and collect every gem. A level with no gems gives the gem star automatically.

## Checking your work

```bash
cd Packages/GrappleCore && swift test
```

`testEveryShippedLevelLoads` loads every level in `App/Levels`. It fails, naming the file and the problem, if a level uses an unknown chunk, lacks a spawn or finish (or has two of either), or contains a malformed element. To play a different level, change the name passed to `LevelLoader.load` in `App/ContentView.swift`.
