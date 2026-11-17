class_name ShopStyle
extends Resource
## One little business on a street (#422): its walls, awning stripes, sign board
## and the small thing it sets out in front. A StreetSet lists the styles a street
## can use. The starter street's signs stay blank; a named terrace neighbour (#596)
## paints its name on the board (`sign_text`) and may take another building form.

## New accents go on the end: presets store the number.
enum Accent { CRATE, BUCKETS, PORTHOLE, JARS, TABLE, TOYS, PETS, SURFBOARDS, BEACH_GOODS, CHIPS, PRIZES, DECKCHAIRS }
## The building: a shop, a hatch kiosk, a little beach hut or an arcade front (#596).
enum Form { SHOP, KIOSK, HUT, ARCADE }

@export var id: StringName = &""
@export var wall: Color = Color.WHITE
@export var awning_a: Color = Color.WHITE
@export var awning_b: Color = Color.WHITE
@export var sign_board: Color = Color.WHITE
@export var door: Color = Color.WHITE
@export var accent: Accent = Accent.CRATE
@export var form: Form = Form.SHOP
## The name painted on the sign board (shown as written); empty leaves it blank.
@export var sign_text: String = ""
## The colour the name is painted in.
@export var sign_ink: Color = Color(0.227451, 0.2941176, 0.4235294)
## The building's width along the street in metres; 0 picks one by hash.
@export_range(0.0, 5.0) var width: float = 0.0


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
