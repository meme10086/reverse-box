extends Node
## 游戏流程中枢（autoload，全局名 GameManager）。
##
## 玩法核心 = **对象独立回溯**：
##   - 玩家、以及每一个箱子，各自拥有一条独立的时间轨迹（TimeTrail）。
##   - 回溯只作用于「被选中的那一个对象」：把它送回它自己走过的某个位置，
##     其它对象原地不动。
##   - 回溯资源 = 还能改变多少次对象的时间状态（玩家回溯 1 次、箱子回溯 1 次）。
##
## 本文件不包含任何特效绘制与面板布局；特效由 fx.gd 监听信号，面板由 rewind_panel.gd 实现。

signal level_started(level_index: int)
signal completed
signal rewound(kind: int, box_index: int, ghost_world: Array)
signal rewind_mode_changed(active: bool)

const KIND_PLAYER := 0
const KIND_BOX := 1

var current_level := 0
var move_count := 0
var push_count := 0             # 推箱次数（引导步骤用）
var panel_opens := 0            # 打开过几次回溯面板（引导步骤用）
## 玩家每次行动之后所在的位置（地图号, x, y）。通关后交给 Progress 存成"幽灵轨迹"，
## 下次重玩这一关时会把上一次的自己重演一遍。
var run_path: Array = []

# ---- 回溯资源 ----
var rewind_budget := 3          # 本关总量
var rewind_left := 3            # 剩余
var rewinds_used := 0           # 已用
var par_rewinds := 1            # 设计最优（评级用）
var rewind_span := 0            # 0 = 可回到任意过去；>0 = 只能回到不超过这么多步之前（第二大关用）

# ---- 回溯选择状态 ----
var rewind_mode := false
var target_kind := KIND_PLAYER
var target_box := 0
var node_index := 0             # 选中的历史节点下标

var _player: Player
var _box_list: Array[Box] = []
var _player_trail := TimeTrail.new()
var _box_trails: Array = []     # Array[TimeTrail]
var _completed := false
## 最近一次通关刷新了哪些纪录：{"first":bool,"steps":bool,"rewinds":bool}
var last_break: Dictionary = {}
## 是否把通关写进 Progress 存档。测试脚本（solve_test/room_test）会把它关掉，
## 否则跑一遍自检就会把 30 关全标成"已通关"。
var record_runs := true
var _sfx: AudioStreamPlayer
var _streams := {}
var sfx_on := true            # 只在音效开关关掉时拦住播放，不去动 Master 总线（否则会一并静掉音乐）


func _ready() -> void:
	_register_input_actions()
	_setup_audio()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("rewind"):
		toggle_rewind()
	if rewind_mode:
		_rewind_mode_input()


# ---------------- 关卡生命周期 ----------------

func start_level(level_index: int, data_override: Dictionary = {}) -> void:
	current_level = level_index
	rewind_mode = false

	var level := get_node_or_null("Level") as LevelManager
	if level == null:
		level = LevelManager.new()
		level.name = "Level"
		add_child(level)
	level.build(level_index, data_override)

	if data_override.is_empty():
		rewind_budget = LevelManager.level_rewind_budget(level_index)
		par_rewinds = LevelManager.level_par_rewinds(level_index)
		rewind_span = LevelManager.level_rewind_span(level_index)
	else:
		rewind_budget = int(data_override.get("rewind_budget", 3))
		par_rewinds = int(data_override.get("par_rewinds", 1))
		rewind_span = int(data_override.get("rewind_span", 0))
	rewind_left = rewind_budget
	rewinds_used = 0

	_spawn_player(level)
	_spawn_boxes(level)

	move_count = 0
	push_count = 0
	panel_opens = 0
	_completed = false
	run_path.clear()
	run_path.append(Vector3i(_player.room, _player.cell.x, _player.cell.y))

	# 轨迹重置：每个对象从自己的起点开始（带所在地图）
	_player_trail.reset(_player.cell, 0, _player.room)
	_box_trails.clear()
	for b in _box_list:
		var t := TimeTrail.new()
		t.reset(b.cell, 0, b.room)
		_box_trails.append(t)

	target_kind = KIND_PLAYER
	target_box = 0
	node_index = 0

	level_started.emit(level_index)
	rewind_mode_changed.emit(false)

	print("[ReverseBox] ", LevelManager.level_name(level_index), " 就绪：",
		level.width, "x", level.height, "，地图 ", level.room_count(),
		"，目标 ", level.total_goal_count(),
		"，箱子 ", _box_list.size(), "，回溯次数 ", rewind_budget,
		"（最优 ", par_rewinds, "）")


func restart_level() -> void:
	start_level(current_level)


func is_completed() -> bool:
	return _completed


# ---------------- 移动（传统推箱子规则，未改） ----------------

func try_move_player(dir: Vector2i) -> bool:
	if rewind_mode:
		return false
	var level := get_node_or_null("Level") as LevelManager
	if level == null or _player == null or _completed:
		return false

	var room: int = _player.room
	var from: Vector2i = _player.cell
	var to: Vector2i = from + dir
	if not level.is_walkable_in(room, to):
		return false

	var teleported := false
	var pushed: Box = level.get_box_at_in(room, to)
	if pushed != null:
		var beyond: Vector2i = to + dir
		# 箱子前方是传送门 → 箱子被"推过门"，出现在另一张地图对应的门里
		var box_portal: Array = level.portal_at(room, beyond)
		if box_portal.is_empty():
			if not level.is_walkable_in(room, beyond) or level.get_box_at_in(room, beyond) != null:
				return false
			level.move_box_record(to, beyond, room)
			pushed.room = room
			pushed.move_to(beyond, level.cell_to_world(beyond),
					level.is_goal_for(room, beyond, pushed.color))
		else:
			var tr: int = box_portal[0]
			var tc: Vector2i = box_portal[1]
			if level.get_box_at_in(tr, tc) != null:
				return false          # 对面门口被占着 → 推不动
			level.move_box_record(to, beyond, room)      # 先离开本格
			level.boxes.erase(Vector3i(room, beyond.x, beyond.y))
			pushed.room = tr
			pushed.cell = tc
			pushed.move_to(tc, level.cell_to_world(tc),
					level.is_goal_for(tr, tc, pushed.color))
			level.register_box(pushed)
			teleported = true
		var k := _box_list.find(pushed)
		if k >= 0:
			(_box_trails[k] as TimeTrail).record(pushed.cell, move_count + 1, pushed.room)

	# 玩家自己走进传送门 → 立刻换地图。
	# 注意：如果这一步是「推箱」，玩家不传送 —— 你正忙着推箱子，脚底下踩到门不该被吸走，
	# 否则"把箱子从门上推开"会变成"自己反而被传送"，非常反直觉。
	var p_portal: Array = level.portal_at(room, to)
	if not p_portal.is_empty() and pushed == null:
		var pr: int = p_portal[0]
		var pc: Vector2i = p_portal[1]
		if level.get_box_at_in(pr, pc) != null:
			return false              # 对面门口被箱子占着 → 进不去
		_player.room = pr
		level.set_room(pr)
		_player.move_to(pc, level.cell_to_world(pc), pushed != null)
		room = pr
		to = pc
		teleported = true
	else:
		_player.move_to(to, level.cell_to_world(to), pushed != null)
	_sync_entity_visibility()

	move_count += 1
	if pushed != null:
		push_count += 1
	_player_trail.record(to, move_count, room)
	run_path.append(Vector3i(room, to.x, to.y))

	if teleported:
		_play_sfx("portal")
	else:
		_play_sfx("push" if pushed != null else "move")
	_check_complete()
	return true


func _check_complete() -> void:
	var level := get_node_or_null("Level") as LevelManager
	if level == null or level.goal_count() <= 0 or _completed:
		return
	if boxes_on_goal() >= level.total_goal_count():
		_completed = true
		if rewind_mode:
			_exit_rewind()
		_play_sfx("success")
		if record_runs:
			last_break = Progress.record_run(current_level, move_count, rewinds_used, run_path)
		else:
			last_break = {}
		completed.emit()
		print("[ReverseBox] 通关！步数 ", move_count, "，回溯 ", rewinds_used,
			" 次；历史最佳 ", Progress.best_steps(current_level), " 步 / ",
			Progress.best_rewinds(current_level), " 次回溯；",
			Progress.stars(current_level), " 星")


func boxes_on_goal() -> int:
	var level := get_node_or_null("Level") as LevelManager
	var n := 0
	for b in _box_list:
		if b == null:
			continue
		# 颜色必须对上：同色箱子压同色地砖才算到位（无色箱子压无色目标点）
		if level != null and level.is_goal_for(b.room, b.cell, b.color):
			n += 1
	return n


# ---------------- 回溯：对象独立 ----------------

func toggle_rewind() -> void:
	if rewind_mode:
		_exit_rewind()
	else:
		_enter_rewind()


func _enter_rewind() -> void:
	if _completed or rewind_left <= 0 or _player == null:
		return
	if not has_any_history():
		return
	rewind_mode = true
	panel_opens += 1
	if _current_trail().past_count() <= 0:
		_select_first_with_history()
	node_index = default_node_for(_current_trail())
	rewind_mode_changed.emit(true)


func _exit_rewind() -> void:
	rewind_mode = false
	rewind_mode_changed.emit(false)


func has_any_history() -> bool:
	if _player_trail.past_count() > 0:
		return true
	for t in _box_trails:
		if (t as TimeTrail).past_count() > 0:
			return true
	return false


func _trail_of(kind: int, box_index: int) -> TimeTrail:
	if kind == KIND_PLAYER:
		return _player_trail
	if box_index < 0 or box_index >= _box_trails.size():
		return null
	return _box_trails[box_index]


func _current_trail() -> TimeTrail:
	return _trail_of(target_kind, target_box)


# 对象数量 = 玩家 + 每个箱子
func object_count() -> int:
	return 1 + _box_list.size()


func selected_object_index() -> int:
	return 0 if target_kind == KIND_PLAYER else 1 + target_box


func object_name(idx: int) -> String:
	if idx <= 0:
		return "玩家"
	var k := idx - 1
	return "箱子 %s" % char(65 + k)     # 箱子 A / B / C ...


func trail_of_object(idx: int) -> TimeTrail:
	if idx <= 0:
		return _player_trail
	return _trail_of(KIND_BOX, idx - 1)


func select_object(idx: int) -> void:
	idx = clampi(idx, 0, object_count() - 1)
	if idx == 0:
		target_kind = KIND_PLAYER
		target_box = 0
	else:
		target_kind = KIND_BOX
		target_box = idx - 1
	node_index = default_node_for(_current_trail())


func _select_first_with_history() -> void:
	for i in object_count():
		if trail_of_object(i).past_count() > 0:
			select_object(i)
			return


# 进入面板 / 切换对象时的默认落点：从最近的过去位置往前找，优先落在「可用」的那个，
# 避免玩家一打开面板就撞到灰色节点（例如箱子唯一的历史位置正被自己占着）。
func default_node_for(trail: TimeTrail) -> int:
	var last := maxi(0, trail.past_count() - 1)
	for i in range(last, -1, -1):
		if _node_valid(trail, i):
			return i
	return last


func select_node(i: int) -> void:
	var t := _current_trail()
	if t == null or t.size() <= 0:
		node_index = 0
		return
	node_index = clampi(i, 0, t.size() - 1)


func move_node(delta: int) -> void:
	select_node(node_index + delta)


func selected_cell() -> Vector2i:
	var t := _current_trail()
	if t == null:
		return Vector2i.ZERO
	return t.cell_at(node_index)


# 该历史节点能不能落地：必须是严格过去，且目标格当前空闲
func node_valid_by_index(idx: int, i: int) -> bool:
	return _node_valid(trail_of_object(idx), i)


func _node_valid(trail: TimeTrail, i: int) -> bool:
	var level := get_node_or_null("Level") as LevelManager
	if level == null or trail == null or _player == null:
		return false
	if i < 0 or i >= trail.size() - 1:
		return false
	# 距离上限（第二大关）：只能回到不超过 rewind_span 步之前
	if rewind_span > 0 and (trail.size() - 1 - i) > rewind_span:
		return false
	var dest := trail.cell_at(i)
	var dest_room: int = trail.room_at(i)
	if dest == trail.current() and dest_room == trail.room_at(trail.size() - 1):
		return false
	if not level.is_walkable_in(dest_room, dest):
		return false
	# 目标格必须当前空闲：玩家回溯不能被箱子占，箱子回溯也不能被玩家或别的箱子占
	if level.get_box_at_in(dest_room, dest) != null:
		return false
	if dest_room == _player.room and dest == _player.cell:
		return false
	return true


func node_valid(i: int) -> bool:
	return _node_valid(_current_trail(), i)


func can_apply() -> bool:
	return rewind_mode and rewind_left > 0 and node_valid(node_index)


# 执行回溯：只动选中对象，消耗 1 次
func apply_rewind() -> bool:
	if not can_apply():
		return false
	var level := get_node_or_null("Level") as LevelManager
	if level == null:
		return false

	var trail := _current_trail()
	var dest := trail.cell_at(node_index)
	var dest_room: int = trail.room_at(node_index)

	# 残影：从当前位置一路退回目标节点经过的那些位置（只画同一张地图上的）
	var ghost: Array = []
	for i in range(trail.size() - 1, node_index, -1):
		if trail.room_at(i) == trail.room_at(trail.size() - 1):
			ghost.append(level.cell_to_world(trail.cell_at(i)))

	if target_kind == KIND_PLAYER:
		_player.room = dest_room
		_player.snap_to(dest, level.cell_to_world(dest))
	else:
		var b: Box = _box_list[target_box]
		b.room = dest_room
		b.snap_to(dest, level.cell_to_world(dest),
				level.is_goal_for(dest_room, dest, b.color))
		_rebuild_box_registry(level)

	trail.truncate_to(node_index)
	# 视野跟着玩家走：玩家回溯会换地图，箱子回溯不会
	level.set_room(_player.room)
	_sync_entity_visibility()
	rewind_left -= 1
	rewinds_used += 1
	run_path.append(Vector3i(_player.room, _player.cell.x, _player.cell.y))

	_play_sfx("rewind")
	rewound.emit(target_kind, target_box, ghost)

	print("[ReverseBox] 回溯 %s → 第 %d 个历史位置（%d 步前），剩余 %d" % [
		"玩家" if target_kind == KIND_PLAYER else "箱子 %s" % char(65 + target_box),
		node_index, move_count - trail.steps[node_index] if node_index < trail.steps.size() else 0,
		rewind_left])

	# 轨迹被截断后，光标回到新的"上一刻"，并立刻退出面板（玩家马上能继续操作）
	node_index = default_node_for(trail)
	_exit_rewind()
	_check_complete()
	return true


func _rebuild_box_registry(level: LevelManager) -> void:
	level.clear_box_registry()
	for b in _box_list:
		level.register_box(b)


func rewinds_remaining() -> int:
	return rewind_left


# ---------------- 距离回溯（第二大关：地图下方的按钮） ----------------

# 把"当前选中的对象"送回到 n 步之前。n 由按钮决定（1/2/3）。
# 与面板回溯是同一套规则：目标格必须空闲、严格过去、且不超过 rewind_span。
func try_span_rewind(n: int) -> bool:
	if _completed or rewind_left <= 0 or _player == null:
		return false
	if rewind_span > 0 and n > rewind_span:
		return false
	var trail := _current_trail()
	if trail == null:
		return false
	var i := trail.size() - 1 - n
	if i < 0 or not _node_valid(trail, i):
		return false
	# 借用面板的执行路径，保证扣次数、残影特效、退出面板等行为完全一致
	var was_mode := rewind_mode
	rewind_mode = true
	node_index = i
	var ok := apply_rewind()
	if not ok:
		rewind_mode = was_mode
	return ok


# 面板/按钮都能用：当前可回溯的最大步数（受 span 与轨迹长度限制）
func max_rewind_distance() -> int:
	var trail := _current_trail()
	if trail == null:
		return 0
	var reach := trail.size() - 1
	if rewind_span > 0:
		reach = mini(reach, rewind_span)
	return maxi(0, reach)


# 切换"当前选中的对象"（按钮模式下用，玩家 → 箱子 A → 箱子 B → …）
func cycle_object() -> void:
	select_object((selected_object_index() + 1) % object_count())


# ---------------- 回溯模式下的键盘操作 ----------------
# A/D 或 ←/→：换对象；W/S 或 ↑/↓：换历史节点；Enter/空格：执行；R/Esc：退出

func _rewind_mode_input() -> void:
	if Input.is_action_just_pressed("move_right"):
		select_object(selected_object_index() + 1)
	elif Input.is_action_just_pressed("move_left"):
		select_object(selected_object_index() - 1)
	elif Input.is_action_just_pressed("move_up"):
		move_node(1)          # 往上 = 更新的历史（离现在更近）
	elif Input.is_action_just_pressed("move_down"):
		move_node(-1)         # 往下 = 更早的历史
	elif Input.is_action_just_pressed("rw_confirm"):
		apply_rewind()


# ---------------- 实体生成 ----------------

func player_cell() -> Vector2i:
	return _player.cell if _player != null else Vector2i.ZERO


func box_cells() -> Array:
	var out: Array = []
	for b in _box_list:
		out.append(b.cell)
	return out


func box_at(idx: int) -> Box:
	if idx < 0 or idx >= _box_list.size():
		return null
	return _box_list[idx]


func _spawn_player(level: LevelManager) -> void:
	if _player == null:
		_player = Player.new()
		_player.name = "Player"
		level.add_child(_player)
	var cell: Vector2i = level.player_start
	_player.room = 0
	_player.init(cell, level.cell_to_world(cell))
	_ensure_preview(level)


# 时间轨迹预览层（与地块同一个父节点，共用坐标）
func _ensure_preview(level: LevelManager) -> void:
	if level.get_node_or_null("TrailPreview") != null:
		return
	var preview := Node2D.new()
	preview.name = "TrailPreview"
	preview.set_script(load("res://scripts/rewind_preview.gd"))
	level.add_child(preview)


func _spawn_boxes(level: LevelManager) -> void:
	for b in _box_list:
		if is_instance_valid(b):
			b.queue_free()
	_box_list.clear()

	var index := 0
	for spec in level.box_specs:
		var cell: Vector2i = spec["cell"]
		var rm: int = int(spec["room"])
		var col: int = int(spec["color"])
		var box := Box.new()
		box.name = "Box_%d" % index
		level.add_child(box)
		box.init(cell, level.cell_to_world(cell),
				level.is_goal_for(rm, cell, col), rm, col)
		level.register_box(box)
		_box_list.append(box)
		index += 1
	_sync_entity_visibility()


# 只显示"当前地图"上的对象（多地图关卡用；单地图关卡恒为全部可见）
func _sync_entity_visibility() -> void:
	var level := get_node_or_null("Level") as LevelManager
	if level == null:
		return
	var r: int = level.current_room()
	if _player != null:
		_player.visible = (_player.room == r)
	for b in _box_list:
		if is_instance_valid(b):
			b.visible = (b.room == r)


# ---------------- 音效 ----------------

func _setup_audio() -> void:
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)


func set_sfx_on(on: bool) -> void:
	sfx_on = on
	if _sfx != null and not on:
		_sfx.stop()


func _play_sfx(key: String) -> void:
	if _sfx == null or not sfx_on:
		return
	var stream = _streams.get(key)
	if stream == null:
		var path := "res://assets/audio/" + key + ".wav"
		if not ResourceLoader.exists(path):
			return
		stream = load(path)
		_streams[key] = stream
	_sfx.stream = stream
	_sfx.play()


# ---------------- 输入注册 ----------------

func _register_input_actions() -> void:
	if not InputMap.has_action("move_up"):
		_add_key_action("move_up", KEY_W)
		_add_key_action("move_up", KEY_UP)
		_add_key_action("move_down", KEY_S)
		_add_key_action("move_down", KEY_DOWN)
		_add_key_action("move_left", KEY_A)
		_add_key_action("move_left", KEY_LEFT)
		_add_key_action("move_right", KEY_D)
		_add_key_action("move_right", KEY_RIGHT)
	if not InputMap.has_action("rewind"):
		_add_key_action("rewind", KEY_R)
	if not InputMap.has_action("rw_confirm"):
		_add_key_action("rw_confirm", KEY_ENTER)
		_add_key_action("rw_confirm", KEY_SPACE)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
