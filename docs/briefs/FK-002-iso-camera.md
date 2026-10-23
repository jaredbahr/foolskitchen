# Brief FK-002: Isometric camera and test floor

- **Phase:** 0
- **Depends on:** FK-001
- **Branch:** `brief/fk-002-camera`

## Goal
A tycoon-style camera over a flat test floor that shows the 0.5 m build grid.

## Context
`docs/TECH.md` sections 2.1 and 3 (grid size, units). `AGENTS.md`.

## Do
- `src/world/camera_rig.gd` and its scene: a pivot `Node3D` with a `Camera3D`, either orthographic or a perspective camera with a narrow FOV (put both behind an `@export` toggle so we can choose).
- Controls: WASD and edge pan, mouse wheel zoom (clamped), Q and E to rotate in 90 degree steps with smoothing, and middle mouse drag to pan.
- Put all tuning values (speeds, limits) in `@export` variables.
- A 20 x 20 m test floor with a grid overlay shader at 0.5 m spacing that can be toggled with G.
- Place a 1.75 m capsule as a scale reference.

## Don't
- No build mode, selection or agents.

## Done when
- [ ] Every control works and feels smooth at 30 to 144 fps (motion is scaled by delta).
- [ ] `tools/check.sh` is green.
- [ ] A screenshot of the default view is included in the PR.
