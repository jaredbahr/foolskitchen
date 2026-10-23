extends Node
## Save and load (stub for Phase 0). Saves are JSON in user://saves/ with a
## "version" field; each format change adds a migration step. Only sim state
## is saved, never nodes.

const SAVE_DIR: String = "user://saves/"
const FORMAT_VERSION: int = 1
