class_name DayReportSources
extends RefCounted
## What `DayReportBuilder.build()` reads to write one evening report (#526).
## The session fills one per report (`Main._report_sources()`); the builder
## only reads it. A unit test fills one by hand, with no scene.
##
## Objects are the live ones, not copies: the builder copies what the report
## keeps. The two forecasts are plain values, because working them out needs
## the session (the reorder settings, the shop's storage, the demand state).

var sim: RestaurantSim
var content: ContentDB
## The active site and its books: the report shows this site only (FK-087).
var site: StringName = &""
var ledger: Ledger
var stock: Stock
var menu: MenuSettings
var special: DailySpecial
var regulars: RegularCast
var viral: ViralReview
var owner: OwnerProgress
## Null in a game without service events.
var service_events: ServiceEvents
var notes: DayNotes
var reputation_average: float = 0.0
## Today's tallies, kept by the session.
var dishes_sold: Dictionary[StringName, int] = {}
var dish_metrics: Dictionary[StringName, Dictionary] = {}
## A `PurchaseBasis`: {cost, recorded}.
var food_cost: Dictionary = PurchaseBasis.zero()
## {day, site, percent, saved} of the last haggled order; empty when none.
var haggle_receipt: Dictionary = {}
## `StockAlerts.forecast()` for tomorrow morning.
var stock_forecast: Dictionary = {}
## `Main.forecast_next_demand()`; empty when there is none.
var demand_forecast: Dictionary = {}
