class_name TimeTrail
extends RefCounted
## 一个可回溯对象（玩家 / 某个箱子）的独立时间轨迹。
##
## 语义（与玩法设计文档一致）：
##   - 只记录这个对象**真实经过过**的格子，起点是 trail[0]。
##   - 位置没变就不追加（避免轨迹被原地踏步灌水）。
##   - 回溯 = 回到自己轨迹上的某个**更早**的节点：轨迹会被截断到该节点，
##     也就是"这个对象的未来被剪掉了"。
##   - 轨迹里的节点都可以被选中预览；能不能落地由 GameManager 判定（目标格必须空闲）。

var cells: Array[Vector2i] = []
var steps: Array[int] = []          # 每个节点是在第几步产生的（只用于显示）
var rooms: Array[int] = []          # 每个节点所在的地图（单地图关卡恒为 0）


func reset(start_cell: Vector2i, step: int, room: int = 0) -> void:
	cells.clear()
	steps.clear()
	rooms.clear()
	cells.append(start_cell)
	steps.append(step)
	rooms.append(room)


# 记录一个新位置；与当前位置相同则忽略。
func record(cell: Vector2i, step: int, room: int = 0) -> bool:
	if cells.is_empty():
		cells.append(cell)
		steps.append(step)
		rooms.append(room)
		return true
	if cells[cells.size() - 1] == cell and rooms[rooms.size() - 1] == room:
		return false
	cells.append(cell)
	steps.append(step)
	rooms.append(room)
	return true


# 第 i 个节点所在的地图
func room_at(i: int) -> int:
	if i < 0 or i >= rooms.size():
		return 0
	return rooms[i]


func current() -> Vector2i:
	return cells[cells.size() - 1] if not cells.is_empty() else Vector2i.ZERO


func size() -> int:
	return cells.size()


# 可以被选中的历史节点：严格早于当前节点的全部下标
func past_count() -> int:
	return maxi(0, cells.size() - 1)


func cell_at(i: int) -> Vector2i:
	if i < 0 or i >= cells.size():
		return Vector2i.ZERO
	return cells[i]


func steps_before(i: int) -> int:
	if i < 0 or i >= steps.size():
		return 0
	return steps[cells.size() - 1] - steps[i]


# 回溯落地：截断到节点 i（i 必须合法且严格早于当前）
func truncate_to(i: int) -> bool:
	if i < 0 or i >= cells.size() - 1:
		return false
	cells = cells.slice(0, i + 1)
	steps = steps.slice(0, i + 1)
	rooms = rooms.slice(0, i + 1)
	return true


func duplicate_cells() -> Array:
	return cells.duplicate()
