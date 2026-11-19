class_name ChainStats
extends RefCounted
## Chain-wide figures (docs/CITY_MAP.md sections 4 to 6): totals over the
## owner's sites for the chain strip, the evening report's chain line and the
## chain goals. Pure and static; reads the ledger and ChainSummary sites only.


## What a site brought in on `day`: its gross takings from guests where the
## owner worked, plus its net earnings while a manager ran it (SiteMorning).
static func site_income(ledger: Ledger, day: int, site: StringName) -> int:
	return SiteMorning.takings(ledger, day, site) + SiteMorning.away_earnings(ledger, day, site)


## The whole chain's income on `day` (site_income summed over `sites`).
static func chain_income(ledger: Ledger, day: int, sites: Array[StringName]) -> int:
	var total: int = 0
	for site: StringName in sites:
		total += site_income(ledger, day, site)
	return total


## A site's income for each of the `days` days ending on `last_day`, oldest
## first (0 for a day before day 1 or one the ledger no longer holds per site).
static func site_series(ledger: Ledger, last_day: int, days: int, site: StringName) -> Array[int]:
	var series: Array[int] = []
	for day: int in range(last_day - days + 1, last_day + 1):
		series.append(site_income(ledger, day, site))
	return series


## The chain's income over the `days` days ending on `last_day`.
static func chain_total(ledger: Ledger, last_day: int, days: int, sites: Array[StringName]) -> int:
	var total: int = 0
	for day: int in range(last_day - days + 1, last_day + 1):
		total += chain_income(ledger, day, sites)
	return total


## Golden Ladles across the chain (each site keeps 0 to 3 of its own).
static func total_ladles(sites: Array[ChainSummary.Site]) -> int:
	var total: int = 0
	for site: ChainSummary.Site in sites:
		total += site.golden_ladles
	return total


## The mean stars of the sites that have closed a day; NAN when none has.
static func mean_stars(sites: Array[ChainSummary.Site]) -> float:
	var total: float = 0.0
	var count: int = 0
	for site: ChainSummary.Site in sites:
		if is_finite(site.stars):
			total += site.stars
			count += 1
	return total / float(count) if count > 0 else NAN


## How many sites have each status, keyed by ChainSummary.Status.
static func status_counts(sites: Array[ChainSummary.Site]) -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}
	for status: int in ChainSummary.Status.values():
		counts[status] = 0
	for site: ChainSummary.Site in sites:
		counts[site.status] += 1
	return counts


## The signed total tonight's close books across every away site.
static func tonight_total(sites: Array[ChainSummary.Site]) -> int:
	var total: int = 0
	for site: ChainSummary.Site in sites:
		total += site.tonight
	return total


## Every alert across the chain as {"site": StringName, "alert":
## ChainSummary.Alert}, most urgent first, then in site order. Stable.
static func alerts(sites: Array[ChainSummary.Site]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for alert: int in ChainSummary.Alert.values():
		for site: ChainSummary.Site in sites:
			if site.alerts.has(alert):
				found.append({"site": site.id, "alert": alert})
	return found
