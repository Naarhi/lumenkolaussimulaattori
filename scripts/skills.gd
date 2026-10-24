extends RefCounted
## Taitotasot Old School RuneScapen XP-käyrällä (taso 2 = 83 XP, taso 99 = 13 034 431 XP).

const MAX_LEVEL := 99

static var _table := PackedInt32Array()


## Tasoon level vaadittava XP.
static func xp_for_level(level: int) -> int:
	_ensure_table()
	return _table[clampi(level, 1, MAX_LEVEL) - 1]


static func level_for_xp(xp: int) -> int:
	_ensure_table()
	var level := 1
	while level < MAX_LEVEL and xp >= _table[level]:
		level += 1
	return level


static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	_table.append(0)
	var points := 0.0
	for level in range(1, MAX_LEVEL):
		points += floorf(level + 300.0 * pow(2.0, level / 7.0))
		_table.append(int(floorf(points / 4.0)))
