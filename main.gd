extends Node3D
## SILENT HEAD – Godot-4-Version von V7.9
## Welt, Story, HUD, Menüs und Audio werden hier aufgebaut.

const PlayerScript = preload("res://player.gd")
const EnemyScript = preload("res://enemy.gd")
const MinimapScript = preload("res://minimap.gd")
const SfxGen = preload("res://sfx.gd")
const TouchScript = preload("res://touch.gd")
const WorldScript = preload("res://world.gd")
const CityScript = preload("res://city.gd")
const InventoryScript = preload("res://inventory.gd")

const HALF := 200.0
const ROAD_W := 7.0
const SCENE_POS := Vector3(0, 0, -150)
const START_POS := Vector3(0, 0, 140)
## Story-Beats auf dem Weg: [z-Position, Text, Sprecher, Dauer] – feuert, sobald der Spieler diese z-Marke passiert.
const BEATS := [
	[125.0, "Kein Wind. Kein Vogel. Nur meine eigenen Schritte.", "me", 3.5],
	[102.0, "Ein Auto im Graben. Die Scheinwerfer flackern. Niemand drin…", "me", 4.0],
	[75.0, "Hier drüben! Ich bin verletzt!", "jonas", 3.5],
	[62.0, "Das ist nicht Jonas. Jonas klingt nicht so… hohl.", "me", 4.2],
	[48.0, "Blut auf dem Asphalt. Eine Spur… sie führt zur Sägemühle.", "me", 4.2],
	[-30.0, "…lauf.", "mia", 2.8],
	[-70.0, "Mia?! MIA, WO BIST DU?!", "me", 3.0],
	[-112.0, "Hinter der Mühle brennt Licht. Jemand war hier.", "me", 3.6]]
const FOG_DAY := Color(0.45, 0.52, 0.48)
const FOG_NIGHT := Color(0.08, 0.11, 0.1)
const SUB0 := "Die Straße ist leer. Der Nebel wird dichter. Irgendwo zwischen den Bäumen wartet etwas auf dich."

var player
var is_touch := OS.has_feature("mobile")
var touch_ui
var env: Environment
var sun: DirectionalLight3D
var ambient: AudioStreamPlayer
var dusk := 0.0
var dusk_t := 0.0
var run_id := 0
var state := "menu"
var level := 1
var obj_text := ""
var tree_pos: Array = []
var rock_pos: Array = []
var pickups: Array = []
var world
var world_dirty := false
var beat_i := 0
var sfx_cache := {}
var tts_voice := ""
var tts_on := true
var minion_t := 8.0
var kills := 0
var search_target = null
var sub_id := 0
var toast_id := 0
var cross_id := 0
var banner_tw: Tween
var cfg := ConfigFile.new()
var developer_mode := false

# UI
var ui: CanvasLayer
var hud_root: Control
var menu_root: Control
var pause_root: Control
var settings_root: Control
var hp_lbl: Label
var hp_bar: ProgressBar
var hp_fill: StyleBoxFlat
var stam_bar: ProgressBar
var ammo_lbl: Label
var abil_lbl: Label
var weapon_buttons: Array[Button] = []
var minimap
var inventory_system
var info_lbl: Label
var sub_lbl: Label
var call_lbl: Label
var toast_lbl: Label
var fps_lbl: Label
var cross: ColorRect
var hurt_rect: ColorRect
var banner_box: VBoxContainer
var banner_t: Label
var banner_s: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var menu_sub: Label
var start_btn: Button
var agb_check: CheckBox
var sens_slider: HSlider
var vol_slider: HSlider
var tts_check: CheckBox
var vsync_check: CheckBox
var scale_slider: HSlider
var developer_check: CheckBox
var city_start_btn: Button
var dlg_agb: AcceptDialog
var dlg_ds: AcceptDialog

# ------------------------------------------------------------------ Setup
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	cfg.load("user://settings.cfg")
	_build_env()
	_build_world()
	_build_player()
	if PlayerScript.LIMIT < HALF - 4.0:
		push_warning("player.gd: LIMIT (%s) ist kleiner als die Welt (%s) – bitte auf %s setzen (auch die 109.0 in enemy.gd)." % [PlayerScript.LIMIT, HALF, HALF - 3.0])
	_build_ui()
	_init_tts()
	ambient = AudioStreamPlayer.new()
	ambient.stream = SfxGen.make(2.0, 48.0, 48.0, 0.08, 0.0, 0.35, true)
	ambient.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ambient)
	_apply_settings()

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_DAY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.76, 0.84)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = FOG_DAY
	env.fog_density = 0.05
	env.fog_sky_affect = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_color = Color(0.75, 0.82, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = not is_touch
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)

func _build_world() -> void:
	world = CityScript.new() if level == 2 else WorldScript.new()
	add_child(world)
	world.build(is_touch)
	tree_pos = world.tree_pos
	rock_pos = world.rock_pos
	world.lore_found.connect(_on_lore_found)
	world.power_restored.connect(_on_power_restored)
	world.story_complete.connect(_on_story_complete)
	world.chicken_clucked.connect(_on_chicken_clucked)

func _build_player() -> void:
	player = PlayerScript.new()
	player.main = self
	add_child(player)
	player.position = START_POS

# ------------------------------------------------------------------ UI
func _lbl(parent: Node, text: String, size := 16, col := Color(0.81, 0.81, 0.77), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	parent.add_child(l)
	return l

func _bar(parent: Node, w: float, h: float, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0
	b.max_value = 100
	b.value = 100
	b.custom_minimum_size = Vector2(w, h)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.07)
	bg.border_color = Color(0.47, 0.47, 0.47)
	bg.set_border_width_all(1)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	parent.add_child(b)
	return b

func _btn(parent: Node, text: String, cb: Callable, minw := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(minw, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _centered_panel(root: Control, dim: float) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	root.add_child(bg)
	_full(bg)
	var cc := CenterContainer.new()
	root.add_child(cc)
	_full(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	cc.add_child(vb)
	return vb

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)

	# ---- HUD
	hud_root = Control.new()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_root)
	_full(hud_root)
	hud_root.hide()
	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.7, 0, 0, 0)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hurt_rect)
	_full(hurt_rect)

	fps_lbl = _lbl(hud_root, "FPS --", 14, Color(0.62, 0.71, 0.6))
	fps_lbl.position = Vector2(16, 12)

	var stats := VBoxContainer.new()
	stats.custom_minimum_size = Vector2(240, 0)
	hud_root.add_child(stats)
	hp_lbl = _lbl(stats, "100 HP", 20)
	hp_bar = _bar(stats, 230, 12, Color(0.54, 0.11, 0.11))
	hp_fill = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	stam_bar = _bar(stats, 230, 8, Color(0.24, 0.48, 0.31))
	ammo_lbl = _lbl(stats, "2 / 2", 22)
	abil_lbl = _lbl(stats, "Q Dash   G Blitz   H Med", 13)
	var weapon_bar := HBoxContainer.new()
	weapon_bar.add_theme_constant_override("separation", 4)
	stats.add_child(weapon_bar)
	for slot_index in 4:
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(68, 34)
		slot_button.add_theme_font_size_override("font_size", 12)
		slot_button.pressed.connect(_select_weapon_slot.bind(slot_index))
		weapon_bar.add_child(slot_button)
		weapon_buttons.append(slot_button)
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)

	minimap = MinimapScript.new()
	minimap.main = self
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(minimap)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	minimap.offset_left = -197.0
	minimap.offset_right = -47.0
	minimap.offset_top = 16.0
	minimap.offset_bottom = 166.0
	minimap.expanded_changed.connect(_on_map_expanded)

	info_lbl = _lbl(hud_root, "", 16, Color(0.81, 0.81, 0.77), HORIZONTAL_ALIGNMENT_RIGHT)
	info_lbl.custom_minimum_size = Vector2(300, 40)
	info_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	info_lbl.position.y = 176

	call_lbl = _lbl(hud_root, "", 16, Color(0.75, 0.91, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	call_lbl.custom_minimum_size = Vector2(400, 30)
	call_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	call_lbl.hide()

	toast_lbl = _lbl(hud_root, "", 15, Color(0.87, 0.87, 0.87), HORIZONTAL_ALIGNMENT_CENTER)
	toast_lbl.custom_minimum_size = Vector2(500, 24)
	toast_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	toast_lbl.position.y = 80
	toast_lbl.modulate.a = 0.0

	sub_lbl = _lbl(hud_root, "", 19, Color(0.93, 0.93, 0.93), HORIZONTAL_ALIGNMENT_CENTER)
	sub_lbl.custom_minimum_size = Vector2(620, 50)
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)
	sub_lbl.modulate.a = 0.0

	cross = ColorRect.new()
	cross.color = Color(0.81, 0.81, 0.77, 0.67)
	cross.custom_minimum_size = Vector2(6, 6)
	hud_root.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

	touch_ui = TouchScript.new()
	touch_ui.main = self
	touch_ui.player = player
	touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(touch_ui)
	_full(touch_ui)
	touch_ui.visible = is_touch

	banner_box = VBoxContainer.new()
	banner_box.custom_minimum_size = Vector2(900, 0)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(banner_box)
	banner_t = _lbl(banner_box, "", 64, Color(0.75, 0.09, 0.09), HORIZONTAL_ALIGNMENT_CENTER)
	banner_s = _lbl(banner_box, "", 16, Color(0.8, 0.75, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	banner_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	banner_box.position.y = 150
	banner_box.modulate.a = 0.0

	boss_box = VBoxContainer.new()
	boss_box.custom_minimum_size = Vector2(560, 0)
	hud_root.add_child(boss_box)
	_lbl(boss_box, "☠  SILENT HEAD  ☠", 22, Color(0.91, 0.85, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	boss_bar = _bar(boss_box, 560, 20, Color(0.8, 0.12, 0.1))
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 36)
	boss_box.hide()

	# ---- Hauptmenü
	menu_root = Control.new()
	ui.add_child(menu_root)
	_full(menu_root)
	var vb := _centered_panel(menu_root, 0.92)
	_lbl(vb, "EINE NACHT IM WALD · KEINER HÖRT DICH", 13, Color(0.71, 0.62, 0.51))
	_lbl(vb, "SILENT HEAD", 84, Color(0.89, 0.87, 0.82))
	menu_sub = _lbl(vb, SUB0, 17, Color(0.82, 0.8, 0.75))
	menu_sub.custom_minimum_size = Vector2(620, 60)
	menu_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ctl := _lbl(vb, ("HANDY: STICK LINKS · WISCHEN = UMSEHEN · BUTTONS RECHTS" if is_touch else "WASD · MAUS · KLICK = SCHUSS · R = NACHLADEN · SHIFT = SPRINT · SPACE = SPRUNG\nQ = DASH · G = BLITZ · H = MED · L = LAMPE · E = DURCHSUCHEN · ESC = PAUSE"), 12, Color(0.6, 0.6, 0.56))
	ctl.add_theme_constant_override("outline_size", 0)
	agb_check = CheckBox.new()
	agb_check.text = "Ich akzeptiere die AGBs & die Datenschutzerklärung"
	agb_check.toggled.connect(func(on: bool):
		start_btn.disabled = not on
		city_start_btn.disabled = not on
		cfg.set_value("game", "agb", on)
		cfg.save("user://settings.cfg"))
	vb.add_child(agb_check)
	start_btn = _btn(vb, "SPIELEN", start_game, 270)
	start_btn.disabled = true
	start_btn.custom_minimum_size = Vector2(270, 52)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	_btn(hb, "EINSTELLUNGEN", func(): _open_settings(menu_root))
	_btn(hb, "AGBs", func(): dlg_agb.popup_centered(Vector2i(640, 420)))
	_btn(hb, "DATENSCHUTZ", func(): dlg_ds.popup_centered(Vector2i(640, 380)))

	# ---- Pause
	pause_root = Control.new()
	ui.add_child(pause_root)
	_full(pause_root)
	pause_root.hide()
	var pv := _centered_panel(pause_root, 0.8)
	_lbl(pv, "PAUSE", 48, Color(0.72, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	_btn(pv, "WEITER", func(): set_pause(false), 240)
	_btn(pv, "EINSTELLUNGEN", func(): _open_settings(pause_root), 240)
	_btn(pv, "HAUPTMENÜ", func(): end_game(SUB0, "SPIELEN"), 240)

	# ---- Einstellungen
	settings_root = Control.new()
	ui.add_child(settings_root)
	_full(settings_root)
	settings_root.hide()
	var sv := _centered_panel(settings_root, 0.95)
	_lbl(sv, "EINSTELLUNGEN", 36, Color(0.72, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	_lbl(sv, "Maus-Empfindlichkeit", 15)
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.5
	sens_slider.max_value = 5.0
	sens_slider.step = 0.1
	sens_slider.value = 2.2
	sens_slider.custom_minimum_size = Vector2(320, 24)
	sens_slider.value_changed.connect(func(v: float):
		player.sens = v
		cfg.set_value("game", "sens", v)
		cfg.save("user://settings.cfg"))
	sv.add_child(sens_slider)
	_lbl(sv, "Lautstärke", 15)
	vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = 0.8
	vol_slider.custom_minimum_size = Vector2(320, 24)
	vol_slider.value_changed.connect(func(v: float):
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		cfg.set_value("game", "vol", v)
		cfg.save("user://settings.cfg"))
	sv.add_child(vol_slider)
	tts_check = CheckBox.new()
	tts_check.text = "Gesprochene Dialoge (System-Stimme)"
	tts_check.button_pressed = true
	tts_check.toggled.connect(func(on: bool):
		tts_on = on
		cfg.set_value("game", "tts", on)
		cfg.save("user://settings.cfg"))
	sv.add_child(tts_check)
	vsync_check = CheckBox.new()
	vsync_check.text = "VSync (aus = höhere FPS, z. B. 120 Hz)"
	vsync_check.button_pressed = true
	vsync_check.toggled.connect(func(on: bool):
		_set_vsync(on)
		cfg.set_value("game", "vsync", on)
		cfg.save("user://settings.cfg"))
	sv.add_child(vsync_check)
	_lbl(sv, "3D-Auflösung (100 % = volle Qualität, niedriger = mehr FPS)", 15)
	scale_slider = HSlider.new()
	scale_slider.min_value = 0.5
	scale_slider.max_value = 1.0
	scale_slider.step = 0.05
	scale_slider.value = 1.0
	scale_slider.custom_minimum_size = Vector2(320, 24)
	scale_slider.value_changed.connect(func(v: float):
		_set_res_scale(v)
		cfg.set_value("game", "res_scale", v)
		cfg.save("user://settings.cfg"))
	sv.add_child(scale_slider)
	developer_check = CheckBox.new()
	developer_check.text = "Entwicklermodus"
	developer_check.toggled.connect(func(on: bool):
		developer_mode = on
		city_start_btn.visible = on
		cfg.set_value("game", "developer_mode", on)
		cfg.save("user://settings.cfg"))
	sv.add_child(developer_check)
	city_start_btn = _btn(sv, "STADT DIREKT STARTEN", _start_city_for_development, 240)
	city_start_btn.visible = false
	city_start_btn.disabled = true
	_btn(sv, "ZURÜCK", _close_settings, 240)

	# ---- Rechtstexte
	dlg_agb = AcceptDialog.new()
	dlg_agb.title = "Allgemeine Geschäftsbedingungen"
	dlg_agb.dialog_text = "§1 Geltungsbereich\nDiese AGBs gelten für das kostenlose Spiel „SILENT HEAD“. Mit dem Start akzeptierst du diese Bedingungen.\n\n§2 Nutzung\nDas Spiel wird unentgeltlich zu privaten, nicht-kommerziellen Zwecken bereitgestellt. Weiterverbreitung, Veränderung oder kommerzielle Nutzung ohne schriftliche Zustimmung ist nicht gestattet.\n\n§3 Keine Gewährleistung\nDas Spiel wird „wie besehen“ bereitgestellt. Für Datenverlust, Geräte- oder Gehörschäden wird keine Haftung übernommen. Das Spiel enthält plötzliche Geräusche und Schreckmomente – Kopfhörer in moderater Lautstärke verwenden.\n\n§4 Änderungen\nÄnderungen dieser AGBs werden an dieser Stelle veröffentlicht.\n\n§5 Salvatorische Klausel\nSollte eine Bestimmung unwirksam sein, bleibt die Wirksamkeit der übrigen unberührt. Es gilt deutsches Recht."
	dlg_agb.process_mode = Node.PROCESS_MODE_ALWAYS
	dlg_agb.exclusive = true
	add_child(dlg_agb)
	dlg_ds = AcceptDialog.new()
	dlg_ds.title = "Datenschutzerklärung"
	dlg_ds.dialog_text = "Dieses Spiel läuft vollständig lokal auf deinem Gerät. Es werden keine Daten an Server übertragen, keine Analyse- oder Werbe-Tools eingesetzt und keine Profile erstellt.\n\nLokale Speicherung\nGespeichert werden ausschließlich deine Einstellungen (Empfindlichkeit, Lautstärke, Sprachausgabe, VSync, AGB-Zustimmung) in einer Datei im Benutzerordner des Spiels. Du kannst sie jederzeit löschen.\n\nSprachausgabe\nDie Sprachausgabe nutzt die Text-to-Speech-Funktion deines Betriebssystems."
	dlg_ds.process_mode = Node.PROCESS_MODE_ALWAYS
	dlg_ds.exclusive = true
	add_child(dlg_ds)

	inventory_system = InventoryScript.new()
	add_child(inventory_system)
	inventory_system.setup(self, ui, hud_root, is_touch)

func _apply_settings() -> void:
	var sens: float = cfg.get_value("game", "sens", 2.2)
	var vol: float = cfg.get_value("game", "vol", 0.8)
	tts_on = cfg.get_value("game", "tts", true)
	sens_slider.value = sens
	vol_slider.value = vol
	tts_check.button_pressed = tts_on
	var vs: bool = cfg.get_value("game", "vsync", true)
	vsync_check.button_pressed = vs
	_set_vsync(vs)
	var rs: float = cfg.get_value("game", "res_scale", 1.0)
	scale_slider.value = rs
	_set_res_scale(rs)
	player.sens = sens
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	if cfg.get_value("game", "agb", false):
		agb_check.button_pressed = true
	developer_mode = cfg.get_value("game", "developer_mode", false)
	developer_check.button_pressed = developer_mode
	city_start_btn.visible = developer_mode
	city_start_btn.disabled = not agb_check.button_pressed

func _start_city_for_development() -> void:
	if not developer_mode or not agb_check.button_pressed:
		return
	level = 2
	world_dirty = true
	start_game()

## VSync an: Bildrate folgt dem Display. Aus: keine Begrenzung (nutzt z. B. 120 Hz voll aus).
func _set_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

## Rendert nur die 3D-Welt in geringerer Auflösung (HUD bleibt scharf). 1.0 = volle Qualität.
func _set_res_scale(v: float) -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(v, 0.5, 1.0)

var _settings_from: Control
func _open_settings(from: Control) -> void:
	_settings_from = from
	from.hide()
	settings_root.show()

func _close_settings() -> void:
	settings_root.hide()
	if _settings_from:
		_settings_from.show()

func _init_tts() -> void:
	var v := DisplayServer.tts_get_voices_for_language("de")
	if v.size() > 0:
		tts_voice = v[0]

# ------------------------------------------------------------------ Audio / Feedback
func _stream(n: String) -> AudioStreamWAV:
	if sfx_cache.has(n):
		return sfx_cache[n]
	var s: AudioStreamWAV
	match n:
		"shot": s = SfxGen.make(0.55, 280.0, 45.0, 0.8, 6.0, 1.0)
		"crack": s = SfxGen.make(0.14, 3000.0, 1500.0, 1.0, 18.0, 1.0)
		"pump": s = SfxGen.make(0.25, 700.0, 200.0, 0.7, 9.0)
		"click": s = SfxGen.make(0.06, 2500.0, 2500.0, 0.9, 30.0, 0.5)
		"dry": s = SfxGen.make(0.05, 160.0, 80.0, 0.5, 30.0, 0.6)
		"hurt": s = SfxGen.make(0.35, 180.0, 70.0, 0.7, 8.0, 0.9)
		"roar": s = SfxGen.make(1.6, 200.0, 50.0, 0.55, 1.8, 0.9)
		"scream": s = SfxGen.make(1.3, 600.0, 1500.0, 0.35, 2.2, 0.8)
		"ring": s = SfxGen.make(0.6, 760.0, 1000.0, 0.0, 1.0, 0.5)
		"hangup": s = SfxGen.make(0.5, 425.0, 425.0, 0.0, 1.5, 0.5)
		"boom": s = SfxGen.make(0.5, 90.0, 35.0, 0.2, 5.0, 1.0)
		"step": s = SfxGen.make(0.3, 64.0, 26.0, 0.1, 8.0, 1.0)
		"heart": s = SfxGen.make(0.15, 55.0, 38.0, 0.0, 10.0, 1.0)
		"cluck": s = SfxGen.make(0.13, 520.0, 170.0, 0.82, 11.0, 0.65)
		"death": s = SfxGen.make(1.1, 170.0, 32.0, 0.6, 3.0, 0.8)
		"grenade": s = SfxGen.make(0.6, 2800.0, 400.0, 0.5, 5.0, 0.9)
		"dash": s = SfxGen.make(0.25, 900.0, 300.0, 0.9, 8.0, 0.6)
		_: s = SfxGen.make(0.1, 500.0, 300.0, 0.5, 20.0)
	sfx_cache[n] = s
	return s

func play_sfx(n: String, vol_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(n)
	p.volume_db = vol_db
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func say(txt: String, who: String) -> void:
	if not tts_on or tts_voice == "":
		return
	var pitch: float = {"jonas": 0.85, "mia": 1.4, "me": 0.75, "tobi": 1.1, "boss": 0.3}.get(who, 1.0)
	var rate := 0.7 if who == "boss" else 1.0
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(txt, tts_voice, 90, pitch, rate)

func hush() -> void:
	if tts_voice != "":
		DisplayServer.tts_stop()

func shake(v: float) -> void:
	player.shake = maxf(player.shake, v)

func sub(txt: String, sec := 3.2) -> void:
	sub_id += 1
	var id := sub_id
	sub_lbl.text = txt
	sub_lbl.modulate.a = 1.0
	await get_tree().create_timer(sec, false).timeout
	if id == sub_id:
		sub_lbl.modulate.a = 0.0

func toast(msg: String) -> void:
	toast_id += 1
	var id := toast_id
	toast_lbl.text = msg
	toast_lbl.modulate.a = 1.0
	await get_tree().create_timer(1.5, false).timeout
	if id == toast_id:
		toast_lbl.modulate.a = 0.0

func banner(t: String, s: String, sec := 3.0) -> void:
	banner_t.text = t
	banner_s.text = s
	banner_box.modulate.a = 0.0
	if banner_tw:
		banner_tw.kill()
	banner_tw = create_tween()
	banner_tw.tween_property(banner_box, "modulate:a", 1.0, 0.4)
	banner_tw.tween_interval(sec)
	banner_tw.tween_property(banner_box, "modulate:a", 0.0, 0.6)

func hitmarker() -> void:
	cross_id += 1
	var id := cross_id
	cross.color = Color(1, 0.29, 0.29)
	await get_tree().create_timer(0.12, false).timeout
	if id == cross_id:
		cross.color = Color(0.81, 0.81, 0.77, 0.67)

func flash_hurt() -> void:
	hurt_rect.color = Color(0.7, 0, 0, 0.5)
	create_tween().tween_property(hurt_rect, "color:a", 0.0, 0.25)

func flash_white() -> void:
	hurt_rect.color = Color(1, 1, 1, 0.9)
	create_tween().tween_property(hurt_rect, "color:a", 0.0, 0.5)

# ------------------------------------------------------------------ Spielfluss
func _input(event: InputEvent) -> void:
	if inventory_system != null and inventory_system.is_open:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			inventory_system.close()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and (player.alive or get_tree().paused):
			if settings_root.visible:
				_close_settings()
			else:
				set_pause(not get_tree().paused)
		elif event.keycode == KEY_E and player.alive and not get_tree().paused:
			if player.driving:
				player.exit_car()
			elif player.can_enter_car():
				player.enter_car()
			else:
				_try_search()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and player and player.alive and not get_tree().paused:
		set_pause(true)

func set_pause(p: bool) -> void:
	get_tree().paused = p
	pause_root.visible = p
	if not p:
		settings_root.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (p or is_touch) else Input.MOUSE_MODE_CAPTURED
	if p:
		hush()

func start_game() -> void:
	run_id += 1
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for p in pickups:
		p.queue_free()
	pickups.clear()
	if world_dirty:
		world.queue_free()
		_build_world()
		world_dirty = false
	kills = 0
	minion_t = 8.0
	dusk = 0.0
	dusk_t = 0.0
	player.reset(CityScript.START_POS if level == 2 else START_POS)
	inventory_system.reset()
	inventory_system.close()
	menu_root.hide()
	settings_root.hide()
	pause_root.hide()
	hud_root.show()
	boss_box.hide()
	sub_lbl.modulate.a = 0.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_touch else Input.MOUSE_MODE_CAPTURED
	ambient.play()
	if level == 2:
		state = "city"
		obj_text = "Finde Hinweise über die Stadt und ihre Vergangenheit."
		dusk = 1.0
		dusk_t = 1.0
		_dusk_applied = -1.0
		banner("KAPITEL II", "Die Stadt", 4.0)
		sub("Jonas ist hier. Irgendwo in dieser Stadt.", 4.0)
	else:
		_start_story()

func end_game(text: String, btn := "NOCHMAL") -> void:
	run_id += 1
	if level == 2:
		world_dirty = true
	state = "menu"
	player.alive = false
	inventory_system.close()
	hush()
	ambient.stop()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud_root.hide()
	pause_root.hide()
	settings_root.hide()
	menu_sub.text = text
	start_btn.text = btn
	menu_root.show()

func on_player_died() -> void:
	play_sfx("roar")
	end_game("Silent Head hat dich erwischt. Jetzt ist es still.")

func win() -> void:
	run_id += 1
	var id := run_id
	state = "won"
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	banner("KAPITEL I", "Die Stille ist gebrochen", 3.5)
	sub("Doch dann klingelt dein Handy. Auf dem Display: Jonas.", 4.0)
	if await _wait(4.0, id) and player.alive:
		level = 2
		world_dirty = true
		player.set_physics_process(true)
		start_game()

func _wait(sec: float, id: int) -> bool:
	await get_tree().create_timer(sec, false).timeout
	return id == run_id

# ------------------------------------------------------------------ Story
func _line(txt: String, who: String, dur := 4.8) -> void:
	var names := {"jonas": "Jonas", "mia": "Mia", "tobi": "Tobi", "boss": "Silent Head"}
	if names.has(who):
		sub("%s: „%s“" % [names[who], txt], dur)
	else:
		sub(txt, dur)
	say(txt, who)

func _start_story() -> void:
	var id := run_id
	state = "call"
	obj_text = "…"
	call_lbl.show()
	call_lbl.text = "📞 Jonas ruft an…"
	play_sfx("ring")
	if not await _wait(2.2, id): return
	call_lbl.text = "📞 Jonas · verbunden"
	play_sfx("click")
	if not await _wait(0.4, id): return
	_line("Wo steckst du? Wir stehen an der Sägemühle. Tobi hat sich getraut, dreimal Silent Head zu sagen.", "jonas")
	if not await _wait(6.4, id): return
	_line("Der hat keinen Mund. Aber er hört alles. Jeden Atemzug. Jeden Schritt.", "tobi")
	if not await _wait(6.0, id): return
	_line("Habt ihr das gemerkt? Nichts. Gar nichts. Die Vögel sind weg.", "jonas")
	if not await _wait(5.4, id): return
	_line("Da ist jemand hinter uns. Jonas… bleib ruhig. Dreh dich nicht um.", "mia")
	if not await _wait(5.0, id): return
	hush()
	sub("AAAAAAAAH!! NEIN— BITTE—!!", 2.5)
	play_sfx("scream")
	dusk_t = 1.0
	if not await _wait(1.8, id): return
	play_sfx("hangup")
	call_lbl.text = "📞 Anruf beendet"
	sub("…Hallo? Jonas? Mia? TOBI?!", 3.0)
	say("Hallo? Jonas? Mia? Tobi?", "me")
	if not await _wait(2.2, id): return
	call_lbl.hide()
	if not await _wait(1.0, id): return
	_begin_walk(false)

func _begin_walk(skipped: bool) -> void:
	run_id += 1
	state = "walk"
	obj_text = "Lauf die Straße entlang. Irgendwo vorn liegt die Sägemühle."
	call_lbl.hide()
	if skipped:
		_line("Die Verbindung reißt ab… ich muss zu ihnen. Die Straße runter…", "me", 4.0)
	else:
		banner("KAPITEL I", "Die Waldstraße", 3.2)
		sub("Ich muss zu ihnen. Die Straße runter…", 3.5)
	beat_i = BEATS.size() if skipped else 0

func _found_scene() -> void:
	run_id += 1
	var id := run_id
	state = "found"
	obj_text = ""
	_line("Da liegt jemand.", "me", 3.0)
	if not await _wait(3.2, id): return
	_line("Jonas? Mia? Tobi? Nein. Nein, nein, nein.", "me", 4.2)
	if not await _wait(5.0, id): return
	sub("Mias Handy. Letzte Nachricht, an mich: „ER KLINGT WIE JEDER. ANTWORTE NICHT.“", 5.4)
	say("Mias Handy. Letzte Nachricht, an mich. Er klingt wie jeder. Antworte nicht.", "me")
	if not await _wait(6.8, id): return
	_spawn_boss()

func _spawn_boss() -> void:
	var back: Vector3 = player.global_transform.basis.z
	var pos: Vector3 = player.global_position + back * 12.0
	pos.x = clampf(pos.x, -HALF + 2.0, HALF - 2.0)
	pos.z = clampf(pos.z, -HALF + 2.0, HALF - 2.0)
	pos.y = 0.0
	var e = EnemyScript.new()
	add_child(e)
	e.setup(false, self, player, pos)
	e.died.connect(_on_enemy_died)
	e.phase_changed.connect(_on_boss_phase)
	if world.power_on:
		e.speed *= 0.8
		get_tree().create_timer(4.5, false).timeout.connect(func(): sub("Das Licht macht ihn langsamer. Mias Polaroid hatte recht.", 4.0))
	state = "fight"
	obj_text = "Silent Head. Schieß!"
	play_sfx("roar")
	get_tree().create_timer(1.9, false).timeout.connect(func(): shake(2.2))
	banner("SILENT HEAD", "Der Stumme aus dem Nebel", 3.8)
	_line("Hier drüben… ich bin’s.", "boss", 3.6)
	flash_hurt()

func _spawn_minion(pos: Vector3) -> void:
	var e = EnemyScript.new()
	add_child(e)
	e.setup(true, self, player, pos)
	e.died.connect(_on_enemy_died)

func _on_enemy_died(e) -> void:
	kills += 1
	if e.minion:
		if randf() < 0.4:
			_spawn_pickup(e.global_position.x, e.global_position.z)
		sub("Das kleine Ding zerfällt zu Staub…", 2.5)
		return
	state = "won"
	obj_text = ""
	sub("Er bewegt sich nicht mehr…", 4.0)
	banner("ÜBERLEBT", "Die Stille ist gebrochen", 3.4)
	say("Es ist vorbei.", "me")
	for m in get_tree().get_nodes_in_group("enemies"):
		if m.minion and not m.dying:
			m.kill()
	var id := run_id
	if await _wait(3.5, id) and player.alive:
		win()

func _on_boss_phase(_b, n: int) -> void:
	shake(2.4)
	player.hp = minf(100.0, player.hp + 20.0)
	_drop_meds(2 if n == 2 else 3)
	if n == 2:
		banner("ER WIRD WÜTEND", "Verbandskästen im Gras – nimm sie!", 3.2)
		_line("Dein Atem. Ist so laut.", "boss", 3.5)
	else:
		banner("SEIN WAHNSINN", "Jetzt oder nie.", 3.2)
		_line("Schweig. Für. Immer.", "boss", 3.5)
	play_sfx("roar")

func _drop_meds(n: int) -> void:
	for i in n:
		for k in 8:
			var x: float = player.global_position.x + randf_range(-3.5, 3.5)
			var z: float = player.global_position.z + randf_range(-3.5, 3.5)
			if absf(x) < HALF - 2.0 and absf(z) < HALF - 2.0:
				_spawn_pickup(x, z)
				break

func _spawn_pickup(x: float, z: float) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.28, 0.28)
	m.mesh = bm
	var mat := _mat(Color(0.25, 0.88, 0.44))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.position = Vector3(x, 0.4, z)
	add_child(m)
	pickups.append(m)

func _try_search() -> void:
	if search_target == null:
		return
	var target_kind := String(search_target.get("kind", ""))
	if target_kind == "fish":
		if inventory_system.quickbar_entry(inventory_system.active_quickbar_slot) != "fishing_rod":
			toast("Wähle die Angel in der Schnellleiste, um zu fischen.")
			return
		var r: Dictionary = world.use(search_target)
		search_target = null
		if not r["ok"]:
			if r["msg"] != "":
				toast(r["msg"])
			return
		world_dirty = true
		play_sfx("click")
		if r.get("give", {}).has("item"):
			inventory_system.add_item(String(r["give"]["item"]))
			inventory_system.refresh()
		if r.get("msg", "") != "":
			toast(r["msg"])
		return
	if target_kind in ["tree", "log"]:
		if inventory_system.count_item("axe") < 1 or inventory_system.quickbar_entry(inventory_system.active_quickbar_slot) != "axe":
			toast("Wähle die Axt in der Schnellleiste, um Holz abzubauen.")
			return
		if target_kind == "log":
			var log_result: int = world.hit_log(int(search_target["log_index"]))
			search_target = null
			if log_result > 0:
				inventory_system.add_item("wood", log_result)
				world_dirty = true
				play_sfx("click")
				toast("+%d Holz" % log_result)
			else:
				toast("Stamm abbauen: %d/3 Hiebe" % -log_result)
			return
		var tree_index := int(search_target["tree_index"])
		var wood_gained: int = world.chop_tree(tree_index, player.global_position)
		search_target = null
		if wood_gained > 0:
			inventory_system.add_item("wood", wood_gained)
			world_dirty = true
			play_sfx("click")
			toast("+%d Holz" % wood_gained)
			inventory_system.refresh()
		else:
			toast("Baum fällen: %d/4 Hiebe" % world.tree_chop_hits(tree_index))
		return
	if target_kind in ["workbench", "anvil", "furnace"]:
		var station_position := Vector3(float(search_target["x"]), 0.0, float(search_target["z"]))
		search_target = null
		inventory_system.open_station(target_kind, station_position)
		play_sfx("click")
		return
	if target_kind == "rock":
		if inventory_system.quickbar_entry(inventory_system.active_quickbar_slot) != "pickaxe":
			toast("Wähle die Spitzhacke und schlage damit auf den Felsen.")
			return
		player.shoot()
		return
	if String(search_target.get("kind", "")) == "weapon":
		var weapon_id := String(search_target.get("loot", ""))
		if not player.can_pickup_weapon(weapon_id):
			toast("Inventar voll: maximal vier Waffen")
			return
	var r: Dictionary = world.use(search_target)
	search_target = null
	if not r["ok"]:
		if r["msg"] != "":
			toast(r["msg"])
			sub(r["msg"], 3.0)
		return
	world_dirty = true
	play_sfx("click")
	var g: Dictionary = r["give"]
	var msg: String = r["msg"]
	if g.has("weapon"):
		player.pickup_weapon(String(g["weapon"]))
	if g.has("item"):
		inventory_system.add_item(String(g["item"]))
	if g.has("heal"):
		player.heals += int(g["heal"])
	if g.has("ammo"):
		player.refill_active_ammo()
		player.gren_cd = 0.0
		msg = "Munition gefunden – aktive Waffe aufgefüllt"
	if g.has("hp"):
		player.hp = minf(100.0, player.hp + float(g["hp"]))
		msg = "Am Feuer gerastet  +%d HP" % int(g["hp"])
	if msg != "":
		toast(msg)
	inventory_system.refresh()
	var txt: String = r["text"]
	if txt != "":
		sub(txt, clampf(float(txt.length()) * 0.075, 4.0, 14.0))
		say(txt, "me")

func _on_chicken_clucked() -> void:
	play_sfx("cluck", -5.0)
	get_tree().create_timer(0.16, false).timeout.connect(func(): play_sfx("cluck", -5.0))

func _on_lore_found(_id: int, _text: String) -> void:
	play_sfx("click", -4.0)

func _select_weapon_slot(slot_index: int) -> void:
	inventory_system.activate_quickbar_slot(slot_index)

func _on_power_restored() -> void:
	play_sfx("boom", -6.0)
	shake(1.0)
	banner("STROM", "Die Lampen brennen. Licht macht ihn langsamer.", 3.4)
	if state == "walk":
		obj_text = "Folge der Straße. Das Licht ist auf deiner Seite."

func _on_story_complete() -> void:
	player.heals = maxi(player.heals, 3)
	banner("DIE GANZE WAHRHEIT", "Heinrich Vogt hörte zu – und hat nie aufgehört.", 4.5)

# ------------------------------------------------------------------ Update
var _dusk_applied := -1.0
var _hud_next := 0
var _near_t := 0.0
var _hp_tier := -1
var _slot_cache := {}

func _process(delta: float) -> void:
	if state == "menu" or get_tree().paused or not player.alive:
		return
	# Dämmerung
	dusk += (dusk_t - dusk) * minf(1.0, delta * 0.045)
	if state == "call" and dusk_t < 1.0:
		dusk_t = maxf(dusk_t, 0.15)
	if absf(dusk - _dusk_applied) > 0.0015:
		_dusk_applied = dusk
		var fc := FOG_DAY.lerp(FOG_NIGHT, dusk)
		env.background_color = fc
		env.fog_light_color = fc
		env.fog_density = 0.05 + 0.03 * dusk
		env.ambient_light_energy = 0.9 - 0.6 * dusk
		sun.light_energy = 1.0 - 0.75 * dusk

	var pp: Vector3 = player.global_position
	world.update(pp, dusk, delta)
	var dscene := Vector2(pp.x - SCENE_POS.x, pp.z - SCENE_POS.z).length()
	if state == "call" and dscene < 15.0:
		run_id += 1
		hush()
		dusk_t = 1.0
		_begin_walk(true)
	elif state == "walk" and dscene < 11.0:
		_found_scene()
	if state == "walk":
		while beat_i < BEATS.size() and pp.z < BEATS[beat_i][0]:
			var bt: Array = BEATS[beat_i]
			_line(bt[1], bt[2], bt[3])
			beat_i += 1

	# Boss-Diener
	var boss = null
	var minions := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.minion:
			if not e.dying:
				minions += 1
		elif not e.dying:
			boss = e
	if state == "fight" and boss != null and boss.intro <= 0.0:
		minion_t -= delta
		if minion_t <= 0.0:
			minion_t = 4.5 if boss.phase >= 3 else 6.5
			if boss.hp < boss.max_hp * 0.85 and minions < 2:
				var a := randf() * TAU
				var r := randf_range(2.0, 3.5)
				_spawn_minion(boss.global_position + Vector3(sin(a) * r, 0, cos(a) * r))
				play_sfx("roar", -6.0)
				shake(1.2)
				sub("RAAAWR!! (klein, aber laut)", 2.2)

	# Pickups
	for i in range(pickups.size() - 1, -1, -1):
		var p: MeshInstance3D = pickups[i]
		p.rotation.y += delta * 2.0
		if Vector2(p.position.x - pp.x, p.position.z - pp.z).length() < 1.0:
			player.heals += 1
			toast("+1 Verbandskasten")
			play_sfx("click")
			p.queue_free()
			pickups.remove_at(i)

	# Objekte in Reichweite (Notizen, Kisten, Leichen, Generator, Feuer …)
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.08
		var near: Dictionary = world.nearest(pp, 2.4)
		if near.is_empty():
			search_target = null
		else:
			search_target = near

	_update_hud(boss)

func _update_hud(boss) -> void:
	var now := Time.get_ticks_msec()
	if now < _hud_next:
		return
	_hud_next = now + 66
	# FPS + Diagnose: DC = Draw-Calls, Tri = Dreiecke (Tausend), CPU/Phys = Zeit pro Frame in ms
	fps_lbl.text = "FPS %d  DC %d  Tri %dk  CPU %.1f  Phys %.1f" % [
		Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	var hp := maxi(0, ceili(player.hp))
	hp_bar.value = hp
	hp_lbl.text = "%d HP" % hp
	var tier := 0 if hp > 50 else (1 if hp > 25 else 2)
	if tier != _hp_tier:
		_hp_tier = tier
		hp_fill.bg_color = [Color(0.54, 0.11, 0.11), Color(0.69, 0.34, 0.11), Color(0.82, 0.13, 0.13)][tier]
	stam_bar.value = player.stam
	ammo_lbl.text = player.weapon_ammo_label()
	for slot_index in weapon_buttons.size():
		var slot_button := weapon_buttons[slot_index]
		var lbl: String = inventory_system.quickbar_label(slot_index)
		var dis: bool = inventory_system.quickbar_entry(slot_index) == ""
		var act: bool = inventory_system.is_quickbar_active(slot_index)
		var sig := "%s|%s|%s" % [lbl, dis, act]
		if _slot_cache.get(slot_index, "") != sig:
			_slot_cache[slot_index] = sig
			slot_button.text = lbl
			slot_button.disabled = dis
			slot_button.add_theme_color_override("font_color", Color(1.0, 0.83, 0.42) if act else Color(0.82, 0.84, 0.8))
	var ab := func(k: String, n: String, cd: float) -> String:
		return "%s %s %ds" % [k, n, ceili(cd)] if cd > 0.0 else "%s %s ✓" % [k, n]
	abil_lbl.text = ab.call("Q", "Dash", player.dash_cd) + "   " + ab.call("G", "Blitz", player.gren_cd) + "   H Med ×%d" % player.heals
	var hint := ""
	if player.driving:
		hint = "\nW/S fahren · A/D lenken · Shift Turbo %s · E aussteigen" % ("an" if player.speed_mode else "aus")
	elif player.can_enter_car():
		hint = "\nE = Rotes Auto fahren"
	elif search_target != null:
		hint = "\nE = " + world.hint_for(search_target)
	var funde := ""
	if world.journal.size() > 0:
		funde = "\nFunde %d/%d" % [world.journal.size(), world.lore_total()]
	info_lbl.text = obj_text + hint + funde
	if boss != null and boss.max_hp > 0.0:
		boss_box.show()
		boss_bar.value = maxf(0.0, boss.hp / boss.max_hp * 100.0)
	else:
		boss_box.hide()

func _on_map_expanded(expanded: bool) -> void:
	minimap.custom_minimum_size = Vector2(300, 300) if expanded else Vector2(150, 150)
	minimap.offset_left = -347.0 if expanded else -197.0
	minimap.offset_right = -47.0
	minimap.offset_top = 80.0 if expanded else 16.0
	minimap.offset_bottom = 380.0 if expanded else 166.0
	info_lbl.position.y = 390.0 if expanded else 176.0
	inventory_system.set_map_expanded(expanded)
