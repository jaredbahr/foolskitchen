extends RefCounted
# TEMPORARY issue #4 acceptance probe: intentionally invalid GDScript.
# Revert this entire commit after GitHub Actions records the expected failure.
func deliberately_invalid_ci_probe( -> void:
	pass
