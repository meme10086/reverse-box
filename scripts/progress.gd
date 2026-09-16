extends Node
## 关卡进度记录（autoload 名：Progress）。
##
## 记录三样东西：
##   ① 哪些关通关了（关卡地图上的通关标记）
##   ② 每关的**最好成绩**：最少步数 / 最少回溯次数（三星评价用）
##   ③ 每关最好那一次通关的**行动轨迹**（"幽灵回放"用：重玩时把过去的你重演一遍）
##
## 不参与任何玩法逻辑；读写失败一律安静降级，绝不因此崩溃。
## 存盘位置：user://progress.cfg

const SAVE_PATH := "user://progress.cfg"

var _cleared: Dictionary = {}      # level_index -> true
var _steps: Dictionary = {}        # level_index -> 历史最少步数
var _rewinds: Dictionary = {}      # level_index -> 历史最少回溯次数
var _ghost: Dictionary = {}        # level_index -> "r:x:y|r:x:y|..."（玩家每次行动后的位置）


func _ready() -> void:
	load_progress()


# ---------------- 查询 ----------------

func is_completed(index: int) -> bool:
	return _cleared.has(index)


func best_steps(index: int) -> int:
	return int(_steps.get(index, 0))


func best_rewinds(index: int) -> int:
	return int(_rewinds.get(index, -1))


func ghost_path(index: int) -> Array:
	"""返回 Array[Vector3i]（地图号, x, y）；没有记录就返回空数组。"""
	var raw: String = String(_ghost.get(index, ""))
	var out: Array = []
	if raw == "":
		return out
	for seg in raw.split("|", false):
		var p := seg.split(":")
		if p.size() == 3:
			out.append(Vector3i(int(p[0]), int(p[1]), int(p[2])))
	return out


func completed_count() -> int:
	return _cleared.size()


func total_steps() -> int:
	var n := 0
	for k in _steps:
		n += int(_steps[k])
	return n


func total_rewinds() -> int:
	var n := 0
	for k in _rewinds:
		n += int(_rewinds[k])
	return n


# ---------------- 星级 ----------------
## 1★ 通关 · 2★ 回溯次数不超过设计最优 · 3★ 步数不超过设计最优。
## 两颗评价星互相独立（各自取历史最好），所以可能"步数最优但回溯多一次"。

func stars(index: int) -> int:
	if not _cleared.has(index):
		return 0
	var par_r: int = LevelManager.level_par_rewinds(index)
	var par_s: int = LevelManager.level_par_steps(index)
	var n := 1
	if _rewinds.has(index) and int(_rewinds[index]) <= par_r:
		n += 1
	if _steps.has(index) and int(_steps[index]) <= par_s:
		n += 1
	return n


func total_stars() -> int:
	var n := 0
	for i in LevelManager.level_count():
		n += stars(i)
	return n


func max_stars() -> int:
	return LevelManager.level_count() * 3


# ---------------- 写入 ----------------

## 兼容旧调用：只标记通关。
func mark_completed(index: int) -> void:
	if _cleared.has(index):
		return
	_cleared[index] = true
	save_progress()


## 记录一次通关。返回 "本次刷新了什么"（用于通关界面提示）。
## path: Array[Vector3i]，玩家每次行动之后所在的位置（含回溯/传送）。
func record_run(index: int, steps: int, rewinds: int, path: Array) -> Dictionary:
	var fresh := {"steps": false, "rewinds": false, "first": not _cleared.has(index)}
	_cleared[index] = true
	if not _steps.has(index) or steps < int(_steps[index]):
		_steps[index] = steps
		fresh["steps"] = true
	if not _rewinds.has(index) or rewinds < int(_rewinds[index]):
		_rewinds[index] = rewinds
		fresh["rewinds"] = true
	# 幽灵只跟"最好那一次"走：步数更少就换；步数相同但回溯更少也换。
	if fresh["steps"] or fresh["rewinds"]:
		_ghost[index] = _encode_path(path)
	save_progress()
	return fresh


func _encode_path(path: Array) -> String:
	var parts: Array = []
	for c in path:
		var v: Vector3i = c
		parts.append("%d:%d:%d" % [v.x, v.y, v.z])
	return "|".join(parts)


func clear_all() -> void:
	_cleared.clear()
	_steps.clear()
	_rewinds.clear()
	_ghost.clear()
	save_progress()


# ---------------- 存盘 ----------------

func save_progress() -> void:
	var cfg := ConfigFile.new()
	var keys: Array = _cleared.keys()
	keys.sort()
	cfg.set_value("progress", "cleared", keys)
	cfg.set_value("records", "steps", _steps)
	cfg.set_value("records", "rewinds", _rewinds)
	cfg.set_value("records", "ghost", _ghost)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("[ReverseBox] 进度保存失败：%d" % err)


func load_progress() -> void:
	_cleared.clear()
	_steps.clear()
	_rewinds.clear()
	_ghost.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var raw: Variant = cfg.get_value("progress", "cleared", [])
	if raw is Array:
		for k in raw:
			_cleared[int(k)] = true
	_load_dict(cfg, "records", "steps", _steps)
	_load_dict(cfg, "records", "rewinds", _rewinds)
	_load_dict(cfg, "records", "ghost", _ghost)


func _load_dict(cfg: ConfigFile, section: String, key: String, dst: Dictionary) -> void:
	var raw: Variant = cfg.get_value(section, key, {})
	if raw is Dictionary:
		for k in raw:
			dst[int(k)] = raw[k]
