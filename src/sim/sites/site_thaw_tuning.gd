class_name SiteThawTuning
extends Resource
## Balance rules for a restaurant that is frozen while the player is away.

## Fraction of the elapsed days that count towards each frozen stock lot's age.
@export_range(0.0, 1.0, 0.01) var away_stock_ageing: float = 0.34


func is_valid() -> bool:
	return is_finite(away_stock_ageing) and away_stock_ageing >= 0.0 and away_stock_ageing <= 1.0
