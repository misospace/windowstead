## Worker cap calculation logic — extracted from main.gd for testability.
## This module has no dependencies on GameState or scene nodes, making it
## suitable for headless unit testing.

const Constants := preload("res://scripts/constants.gd")


## Calculate the worker capacity based on builds and constants.
## - Base cap from Constants.BASE_WORKER_CAP
## - Hut bonus for each completed hut from Constants.WORKER_CAP_BONUSES
static func calculate_worker_cap(builds: Array) -> int:
	var cap: int = Constants.BASE_WORKER_CAP
	for build in builds:
		if bool(build.get("complete", false)):
			var kind: String = str(build.get("kind", ""))
			cap += int(Constants.WORKER_CAP_BONUSES.get(kind, 0))
	return cap


## Check if the colony can recruit another worker.
static func can_recruit(builds: Array, workers: Array) -> bool:
	return workers.size() < calculate_worker_cap(builds)
