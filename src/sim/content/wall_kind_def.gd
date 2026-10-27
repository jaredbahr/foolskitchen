class_name WallKindDef
extends Resource
## One buildable wall segment type (FK-070). IDs are save data; names are
## player text. What the segment does to movement comes from `segment`.

@export var id: StringName = &""
@export var display_name: String = ""
## SimGrid.Segment value: 1 wall, 2 doorway, 3 window.
@export_enum("None", "Wall", "Doorway", "Window") var segment: int = 0
## Price per segment (one 0.5 m grid edge). Removing refunds half, like furniture.
@export var price: int = 0
## Catalogue order, lowest first.
@export var order: int = 0
## Kenney piece shown on the catalogue card (presentation only).
@export var thumbnail_scene: PackedScene
