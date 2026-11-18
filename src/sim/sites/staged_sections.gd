class_name StagedSections
extends RefCounted
## The staging shelf of a load (#526): what each save section's restore
## function decoded, held until the whole save has been checked. Main keeps
## one as `_staged`. A restore function writes its field; Main's
## `_validate_staged_sections` checks the fields against each other and the
## clock, and `_install_staged_sections` puts them on the session. Nothing
## here is live state and nothing here is saved.
##
## A new saved section that stages adds its field here and a line to
## `clear_site()` (a per-site section, `SiteSections.PER_SITE`) or to the
## global half of `clear()` (`SiteSections.GLOBAL`). `tests/sim/
## test_staged_sections.gd` fails on a field that neither clears.
##
## A missing section leaves its field empty (null, 0, false or an empty
## Dictionary), and the load then takes the new-game or legacy default.

# --- Per-site sections: a site switch stages these too. ---

## The saved shop. After an install it is the live layout, kept for the lot
## view and the next wiring, so a site switch puts it back after clearing.
var layout: ShopLayout = null
var tray_level: int = 0
var lease_expanded: bool = false
## The saved "site_hours" section (FK-087); empty when the save has none.
var site_hours: Dictionary = {}
var menu: MenuSettings = null
var evening_schedule: EveningSchedule = null
## The saved daily special as a Dictionary, or null.
var daily_special: Variant = null
var signature: SignatureState = null
var staff: StaffRoster = null
var plates: PlateLedger = null
var reputation: ReputationBook = null
var regulars: RegularCast = null
var reorder: ReorderSettings = null
var deliveries: DeliveryBook = null
var demand: DemandState = null
var viral: ViralReview = null
var business_history: BusinessHistory = null
var shop_records: ShopRecords = null
## The saved cat section (adopted and its name).
var cat: Dictionary = {}
## The saved health inspection section (grade, day, plan).
var inspection: Dictionary = {}
## The saved food-critic section (#303: cooldown and today's plan).
var critic: Dictionary = {}
## The accepted booking plan.
var group_booking: GroupBooking = null
## The morning rush plan from the matching saved run.
var rush_hour: Dictionary = {}
## The saved fish tank section (#125: each tank's last cleaning day).
var aquarium: Dictionary = {}

# --- Global sections: staged by a morning load only. ---

var difficulty: Difficulty = null
## The saved sites section (FK-087).
var sites: SiteBook = null
var blueprints: BlueprintLibrary = null
var menu_presets: MenuPresetLibrary = null
var milestones: MilestoneTracker = null
var weekly_challenge: WeeklyChallengeState = null
var service_events: ServiceEvents = null
var opening_week: OpeningWeek = null
var weather: WeatherState = null
## First-completion toast acknowledgements, and whether the save had the
## section at all (an old save without it keeps the session's own list).
var collection_toast_ids: Array[StringName] = []
var has_collection_toast_section: bool = false


## Empties the whole shelf: before a load reads a save, and for a new game
## after a refused load.
func clear() -> void:
	clear_site()
	difficulty = null
	sites = null
	blueprints = null
	menu_presets = null
	milestones = null
	weekly_challenge = null
	service_events = null
	opening_week = null
	weather = null
	collection_toast_ids.clear()
	has_collection_toast_section = false


## Empties the per-site half, so a site switch's missing sections take their
## defaults and a refused switch leaves nothing staged behind. The global
## half is not touched.
func clear_site() -> void:
	layout = null
	tray_level = 0
	lease_expanded = false
	site_hours = {}
	menu = null
	evening_schedule = null
	daily_special = null
	signature = null
	staff = null
	plates = null
	reputation = null
	regulars = null
	reorder = null
	deliveries = null
	demand = null
	viral = null
	business_history = null
	shop_records = null
	cat = {}
	inspection = {}
	critic = {}
	group_booking = null
	rush_hour = {}
	aquarium = {}
