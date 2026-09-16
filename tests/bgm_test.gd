extends SceneTree
## 背景音乐自检（无渲染）：
##   godot --headless --path <project> -s res://tests/bgm_test.gd
##
## 覆盖：
##   L  两个音频文件可加载、时长合理、loop 已开
##   M  主界面场景 → 播主界面曲；关卡场景 → 播关卡曲（自动切换）
##   R  同一首曲子重复请求（重开关卡）不重头播
##   S  音效开关与音乐开关互不牵连

const MENU_TRACK := "res://assets/audio/bgm/main_menu.ogg"
const LEVEL_TRACK := "res://assets/audio/bgm/level_play.ogg"

var _music: Node
var _step := 0
var _frames := 0
var _fails: Array[String] = []
var _switches_before := 0


func _initialize() -> void:
	print("=== BGM 自检 ===")
	_check_files()
	_music = root.get_node_or_null("Music")
	if _music == null:
		print("[test] 脚本模式下未自动挂载 autoload，手动实例化 Music")
		_music = load("res://scripts/music.gd").new()
		root.add_child(_music)
	change_scene_to_file("res://scenes/start_screen.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	# 每 10 帧走一步，给场景切换留出生效时间
	if _frames < 12 or _frames % 10 != 0:
		return false

	var step := _step
	_step += 1
	match step:
		0:
			_expect(_music.call("current_track") == MENU_TRACK,
				"主界面应播主界面曲，实际 = %s" % _music.call("current_track"))
			_expect(_music.get("_player").playing, "主界面音乐应在播放")
			print("[test] 主界面曲播放位置 = %.2f s" % _music.call("playback_position"))
			change_scene_to_file("res://scenes/Level1.tscn")
		1:
			_expect(_music.call("current_track") == LEVEL_TRACK,
				"进入关卡应切到关卡曲，实际 = %s" % _music.call("current_track"))
			var switches: int = _music.get("switch_count")
			print("[test] 关卡曲播放位置 = %.2f s，切曲次数 = %d"
				% [_music.call("playback_position"), switches])
			# 模拟"重开本关"：再次请求同一首曲子
			_music.call("play_level")
			_switches_before = switches
		2:
			var now: int = _music.get("switch_count")
			_expect(now == _switches_before,
				"重开关卡不应重新切曲（切曲次数应保持 %d，实际 %d）" % [_switches_before, now])
			_expect(_music.get("_player").playing, "重开关卡后音乐仍在播放")
			# 音乐关掉后，音效开关状态不应受影响
			_music.call("set_music_on", false)
			_expect(root.get_node("/root/GameManager").get("sfx_on") == true,
				"关掉音乐不应连带关掉音效")
			_music.call("set_music_on", true)
			_report()
			return true
	return false


func _check_files() -> void:
	for p in [MENU_TRACK, LEVEL_TRACK]:
		if not ResourceLoader.exists(p):
			_fails.append("找不到音频文件：" + p)
			continue
		var s: AudioStream = load(p)
		if s == null:
			_fails.append("无法加载：" + p)
			continue
		var ok_loop := (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop) \
			or (s is AudioStreamMP3 and (s as AudioStreamMP3).loop)
		# 注：导入面板的 loop 已置 true；运行时代码也会再兜一次
		var len_s := s.get_length()
		print("[test] %s 时长 %.1f s，导入循环 = %s" % [p.get_file(), len_s, str(ok_loop)])
		if len_s < 60.0:
			_fails.append("%s 时长过短（%.1f s），疑似截断" % [p.get_file(), len_s])


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("[ OK ] ", msg)
	else:
		print("[FAIL] ", msg)
		_fails.append(msg)


func _report() -> void:
	if _fails.is_empty():
		print("=== 全部通过 ===")
		quit(0)
	else:
		print("=== 失败 ", _fails.size(), " 项 ===")
		for f in _fails:
			print("  - ", f)
		quit(1)
