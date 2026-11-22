class_name AchievementCatalog
extends RefCounted
## Local achievement definitions inspired by the public behavioral patterns of Sensory Overload.

const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "FIRST_DESCENT", "title": "First Descent", "description": "Begin your first drop into the tunnel."},
	{"id": "FIRST_DEATH", "title": "Terminal Impact", "description": "Experience your first obstacle impact."},
	{"id": "FIRST_DEATHWISH", "title": "Razor Margin", "description": "Pull off your first Death Wish graze."},
	{"id": "TUTORIAL_DONE", "title": "Calibrated", "description": "Clear all stages of Calibration (Level 1)."},
	{"id": "GRAZE_STREAK_5", "title": "Close Shave", "description": "Chain 5 consecutive grazes in one run."},
	{"id": "GRAZE_STREAK_10", "title": "Tunnel Dancer", "description": "Chain 10 consecutive grazes in one run."},
	{"id": "GRAZE_STREAK_20", "title": "Flow State", "description": "Chain 20 consecutive grazes in one run."},
	{"id": "GRAZE_STREAK_50", "title": "Untouchable", "description": "Chain 50 consecutive grazes in one run."},
	{"id": "MAX_CHAIN", "title": "Max Chain", "description": "Reach the maximum 8.0x graze multiplier."},
	{"id": "GRAZE_1000", "title": "Graze Addict", "description": "Accumulate 1,000 lifetime grazes."},
	{"id": "GRAZE_ALL_STAGE", "title": "Thread Every Needle", "description": "Graze every obstacle in a single stage clear."},
	{"id": "NODEATH_STAGE", "title": "Clean Run", "description": "Clear any stage on Normal or Ranked with zero deaths."},
	{"id": "NODEATH_STREAK_3", "title": "Iron Equilibrium", "description": "Clear 3 stages in a row without dying."},
	{"id": "PERFECT_STAGE", "title": "Perfect Flow", "description": "Clear a stage without deaths while reaching 70%+ Flow."},
	{"id": "DEATHWISH_STREAK_10", "title": "Death Wish Streak", "description": "Score 10 Death Wish grazes in a single stage."},
	{"id": "ATTEMPTS_100", "title": "Persistent", "description": "Log 100 total descent attempts."},
	{"id": "CLEAR_VERTIGO", "title": "Equilibrium Restored", "description": "Clear Level 2: Vertigo."},
	{"id": "CLEAR_TORNADO", "title": "Eye of the Storm", "description": "Clear Level 3: Tornado."},
	{"id": "CLEAR_SENSORY_OVERLOAD", "title": "Mind Quiet", "description": "Clear Level 6: Sensory Overload."},
	{"id": "CLEAR_ALL_HALLOWS", "title": "Midnight Survivor", "description": "Clear Level 7: All Hallows."},
]


static func find(achievement_id: String) -> Dictionary:
	for item in ACHIEVEMENTS:
		if str(item["id"]) == achievement_id:
			return item
	return {}
