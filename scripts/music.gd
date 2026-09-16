extends Node
## 背景音乐总管（autoload，全局名 Music）。
##
## 主界面 = 《Deliberate Thought》，关卡内 = 《Thinking Music》
## 两首均由 Kevin MacLeod (incompetech.com) 创作，CC BY 4.0，署名写在 docs/音乐素材来源.md 与设置面板里。
##
## 两条设计约定：
##   1) 同一首曲子重复请求时**不重头播**——重开关卡、换关都不会打断音乐，只有真正换场景类型才切曲。
##   2) 切曲一律淡入淡出，不做硬切（玩家在关卡里思考时最怕被音乐"拍一下"）。

const TRACK_MENU := "res://assets/audio/bgm/main_menu.ogg"
const TRACK_LEVEL := "res://assets/audio/bgm/level_play.ogg"

# 主界面曲是"标题曲"，可以稍微站出来一点；关卡曲是思考时的底噪，压得更低。
const VOLUME_MENU_DB := -10.0
const VOLUME_LEVEL_DB := -17.0
const FADE_TIME := 1.0
const MUTE_DB := -60.0

var music_on := true
var switch_count := 0          # 真正切曲的次数（重启关卡不会增加，调试用）

var _player: AudioStreamPlayer
var _current_path := ""
var _target_db := VOLUME_LEVEL_DB
var _fade: Tween
var _cache := {}


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BGM"
	add_child(_player)
	# 兜底：正常情况下靠音频流自身的 loop 无缝循环，这里只是防止某天循环设置失效后彻底没声。
	_player.finished.connect(_replay_current)


# ---------------- 对外接口 ----------------

func play_menu() -> void:
	_play(TRACK_MENU, VOLUME_MENU_DB)


func play_level() -> void:
	_play(TRACK_LEVEL, VOLUME_LEVEL_DB)


## 淡出并停掉当前音乐（例如回到主菜单前想静一下、或做特殊演出时用）
func stop(fade := true) -> void:
	_current_path = ""
	if _player == null:
		return
	_kill_fade()
	if not fade or not _player.playing:
		_player.stop()
		return
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", MUTE_DB, FADE_TIME * 0.7)
	_fade.tween_callback(_player.stop)


func set_music_on(on: bool) -> void:
	music_on = on
	_reapply_volume()


func is_playing_menu() -> bool:
	return _current_path == TRACK_MENU


## 当前曲目路径（空串 = 没在放）；调试与测试用
func current_track() -> String:
	return _current_path


func playback_position() -> float:
	return _player.get_playback_position() if _player != null and _player.playing else 0.0


# ---------------- 内部 ----------------

func _play(path: String, db: float) -> void:
	if _player == null:
		return
	# 同一首已经在放 → 什么都不做（重开关卡 / 换关时音乐保持连续）
	if _current_path == path and _player.playing:
		_target_db = db
		_reapply_volume()
		return

	var stream := _load_stream(path)
	if stream == null:
		return

	_current_path = path
	_target_db = db
	switch_count += 1
	_kill_fade()
	print("[ReverseBox] BGM 切换 → ", path.get_file(), "（", db, " dB）")

	if _player.playing:
		# 换曲：先把旧曲压下去，再换流淡入
		var next := stream
		_fade = create_tween()
		_fade.tween_property(_player, "volume_db", MUTE_DB, FADE_TIME * 0.5)
		_fade.tween_callback(func() -> void:
			_player.stream = next
			_player.play()
			_fade_to_target())
	else:
		_player.stream = stream
		_player.volume_db = MUTE_DB
		_player.play()
		_fade_to_target()


func _fade_to_target() -> void:
	if not music_on:
		_player.volume_db = MUTE_DB
		return
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", _target_db, FADE_TIME)


func _reapply_volume() -> void:
	if _player == null or not _player.playing:
		return
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", _target_db if music_on else MUTE_DB, FADE_TIME * 0.4)


func _replay_current() -> void:
	if _current_path == "":
		return
	_player.play()
	_fade_to_target()


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null


func _load_stream(path: String) -> AudioStream:
	var stream: AudioStream = _cache.get(path)
	if stream != null:
		return stream
	if not ResourceLoader.exists(path):
		push_warning("[Music] 找不到音频文件：" + path)
		return null
	stream = load(path)
	# 循环开关写在代码里，不依赖导入面板的勾选状态
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_cache[path] = stream
	return stream
