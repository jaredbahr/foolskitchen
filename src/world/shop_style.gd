class_name ShopStyle
extends Resource
## One little business on a street (#422): its walls, awning stripes, blank sign
## board and the small thing it sets out in front. No text anywhere: the sign
## stays blank for now. A StreetSet lists the styles a street can use.

enum Accent { CRATE, BUCKETS, PORTHOLE, JARS, TABLE, TOYS, PETS }

@export var id: StringName = &""
@export var wall: Color = Color.WHITE
@export var awning_a: Color = Color.WHITE
@export var awning_b: Color = Color.WHITE
@export var sign_board: Color = Color.WHITE
@export var door: Color = Color.WHITE
@export var accent: Accent = Accent.CRATE


static func make(shop_id: StringName, wall_colour: Color, stripe_a: Color, stripe_b: Color, board: Color,
		door_colour: Color, accent_kind: Accent) -> ShopStyle:
	var style: ShopStyle = ShopStyle.new()
	style.id = shop_id
	style.wall = wall_colour
	style.awning_a = stripe_a
	style.awning_b = stripe_b
	style.sign_board = board
	style.door = door_colour
	style.accent = accent_kind
	return style
