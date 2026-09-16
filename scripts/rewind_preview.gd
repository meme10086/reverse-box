extends Node2D
## 时间轨迹预览（挂在关卡节点下，与地块共用坐标）。
##   平时：每个对象只留下极淡的「时间痕迹」点，不抢画面。
##   回溯模式：被选中对象的整条历史亮起来，标出当前选中的历史位置与连线。

const COL_PLAYER := Color(0.45, 0.72, 1.0)
const COL_BOX := Color(0.96, 0.74, 0.32)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var lv := get_parent() as LevelManager
	if lv == null or lv.width <= 0:
		return
	var mode: bool = GameManager.rewind_mode
	var sel: int = GameManager.selected_object_index()

	for i in GameManager.object_count():
		var tr: TimeTrail = GameManager.trail_of_object(i)
		if tr == null or tr.size() <= 1:
			continue
		var is_sel: bool = mode and i == sel
		var col: Color = COL_PLAYER if i == 0 else COL_BOX
		var alpha: float = 0.36 if is_sel else 0.20
		var r: float = LevelManager.CELL * (0.14 if is_sel else 0.10)

		for k in tr.size():
			draw_circle(lv.cell_to_world(tr.cell_at(k)), r,
				Color(col.r, col.g, col.b, alpha))

		if not is_sel:
			continue

		# 历史连线（越早越淡）
		for k in range(tr.size() - 1):
			var a := lv.cell_to_world(tr.cell_at(k))
			var b := lv.cell_to_world(tr.cell_at(k + 1))
			var t: float = float(k + 1) / float(maxi(1, tr.size() - 1))
			draw_line(a, b, Color(col.r, col.g, col.b, 0.10 + 0.30 * t), 2.0)

		# 当前选中的历史位置
		var dest := tr.cell_at(GameManager.node_index)
		var dw := lv.cell_to_world(dest)
		var half := LevelManager.CELL * 0.44
		var rect := Rect2(dw - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
		var ok: bool = GameManager.node_valid(GameManager.node_index)
		var c2: Color = Color(0.55, 0.95, 0.68, 0.95) if ok else Color(1.0, 0.45, 0.40, 0.92)
		draw_rect(rect, Color(c2.r, c2.g, c2.b, 0.16), true)
		draw_rect(rect, c2, false, 3.0)

		# 从「它现在在哪」到「它要回到哪」的虚线
		_dashed(lv.cell_to_world(tr.current()), dw, Color(col.r, col.g, col.b, 0.55))

		# 被选对象本体描一圈
		var cur := lv.cell_to_world(tr.current())
		var h2 := LevelManager.CELL * 0.5
		draw_rect(Rect2(cur - Vector2(h2, h2), Vector2(h2 * 2.0, h2 * 2.0)),
			Color(col.r, col.g, col.b, 0.75), false, 3.0)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 1.0:
		return
	var dir := d / length
	var step := 12.0
	var t := 0.0
	while t < length:
		var t2: float = minf(length, t + step * 0.55)
		draw_line(a + dir * t, a + dir * t2, col, 2.0)
		t += step
