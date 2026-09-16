extends Node2D
## 时间回溯特效：屏幕闪烁 + 时间冲击环 + 过去位置残影（玩家像素贴图）+ 时间粒子。
## 挂在 game 场景下，监听 GameManager.rewound 信号。纯视觉，不改动任何玩法逻辑。

const FLASH_COLOR := Color(0.72, 0.84, 1.0, 0.40)
const TEX_DIR := "res://assets/art/pixel/"

var _flash: ColorRect
var _ghosts: Array = []      # {pos: Vector2, age: float, life: float, size: float}
var _particles: Array = []   # {pos: Vector2, vel: Vector2, age: float, life: float}
var _rings: Array = []       # {pos: Vector2, age: float, life: float, size: float}

var _ghost_tex: Texture2D
var _ring_tex: Texture2D
var _part_tex: Texture2D


func _ready() -> void:
	_ghost_tex = load(TEX_DIR + "player_front.png")
	_ring_tex = load(TEX_DIR + "fx_ring.png")
	_part_tex = load(TEX_DIR + "fx_particles.png")

	# 全屏闪烁层
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_flash = ColorRect.new()
	_flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	GameManager.rewound.connect(_on_rewound)


func _on_rewound(kind: int, _box_index: int, ghost_world: Array) -> void:
	_flash_pulse()

	var size := LevelManager.CELL * 1.42
	for w in ghost_world:
		_ghosts.append({"pos": w, "age": 0.0, "life": 0.55, "size": size})

	if not ghost_world.is_empty():
		var center: Vector2 = ghost_world.back()

		# 时间冲击环：从回溯落点向外扩散
		_rings.append({"pos": center, "age": 0.0, "life": 0.45, "size": LevelManager.CELL * 1.5})

		# 粒子以「最近一次过去位置」为中心爆发
		for i in 26:
			var ang := randf_range(0.0, TAU)
			var speed := randf_range(60.0, 220.0)
			_particles.append({
				"pos": center,
				"vel": Vector2(cos(ang), sin(ang)) * speed,
				"age": 0.0,
				"life": randf_range(0.3, 0.6),
			})


func _flash_pulse() -> void:
	_flash.color = FLASH_COLOR
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.28)


func _process(delta: float) -> void:
	if _ghosts.is_empty() and _particles.is_empty() and _rings.is_empty():
		return

	var i := _ghosts.size() - 1
	while i >= 0:
		_ghosts[i].age += delta
		if _ghosts[i].age >= _ghosts[i].life:
			_ghosts.remove_at(i)
		i -= 1

	i = _particles.size() - 1
	while i >= 0:
		var p = _particles[i]
		p.age += delta
		p.pos += p.vel * delta
		p.vel *= 0.94
		if p.age >= p.life:
			_particles.remove_at(i)
		i -= 1

	i = _rings.size() - 1
	while i >= 0:
		_rings[i].age += delta
		if _rings[i].age >= _rings[i].life:
			_rings.remove_at(i)
		i -= 1

	queue_redraw()


func _draw() -> void:
	# 时间冲击环：向外扩散并淡出
	for r in _rings:
		var t: float = 1.0 - r.age / r.life
		var s: float = r.size * (1.0 + (1.0 - t) * 2.0)
		var rect := Rect2(r.pos - Vector2(s, s) * 0.5, Vector2(s, s))
		if _ring_tex != null:
			draw_texture_rect(_ring_tex, rect, false, Color(0.75, 0.9, 1.0, t * 0.9))
		else:
			draw_arc(r.pos, s * 0.45, 0.0, TAU, 32, Color(0.6, 0.85, 1.0, t), 3.0, true)

	# 残影：玩家像素贴图，半透明并逐渐淡出
	for g in _ghosts:
		var t2: float = 1.0 - g.age / g.life
		var sz: float = g.size
		var rect2 := Rect2(g.pos - Vector2(sz, sz) * 0.5 + Vector2(0.0, -sz * 0.07), Vector2(sz, sz))
		if _ghost_tex != null:
			draw_texture_rect(_ghost_tex, rect2, false, Color(0.72, 0.86, 1.0, 0.55 * t2))
		else:
			var half: float = g.size * 0.45
			draw_rect(Rect2(g.pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)),
				Color(0.55, 0.8, 1.0, 0.5 * t2))

	# 时间粒子：像素小方块向外漂移并淡出
	for p in _particles:
		var t3: float = 1.0 - p.age / p.life
		var ps: float = 3.0 + 6.0 * t3
		var rect3 := Rect2(p.pos - Vector2(ps, ps) * 0.5, Vector2(ps, ps))
		if _part_tex != null:
			draw_texture_rect(_part_tex, rect3, false, Color(0.8, 0.92, 1.0, t3))
		else:
			draw_circle(p.pos, 3.0 * t3 + 0.5, Color(0.65, 0.85, 1.0, 0.8 * t3))
