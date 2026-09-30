extends GutHookScript
## GUT pre-run hook (see .gutconfig.json). Runs once before the suite.

const KnownEngineWarnings := preload("res://tests/hooks/known_engine_warnings.gd")


func run() -> void:
	GutErrorTracker.register_logger(KnownEngineWarnings.new())
