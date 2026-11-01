extends Control
## Touch-Steuerung: Stick (linke Seite), Wischen = Umsehen, Buttons rechts.
## Schnellleiste (1-4) und INV sind hier eigene Multitouch-Buttons, damit sie auch
## funktionieren, während der andere Finger den Stick hält. FAHREN/RAUS hat einen
## eigenen Platz und teilt sich keinen Button mit NUTZEN.

var main
var player
var touches := {}          # Finger-Index -> {"kind": "stick"/"look"/"btn", "name": String}
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_id := -1
var gui_hidden := false
const STICK_R := 70.0

func _selected_tool() -> String:
	if main == null or main.inventory_system == null:
		return ""
	var entry: String = main.inventory_system.quickbar_entry(main.inventory_system.active_quickbar_slot)
	return entry if entry in ["axe", "pickaxe", "shovel", "ladder", "fishing_rod"] else ""

var _btn_cache := {}
var _btn_hash := 0
var _next_btn := 0
var _dirty := true

## Liefert die zwischengespeicherten Buttons (wird nur bei Änderungen neu aufgebaut).
func _buttons() -> Dictionary:
	if _btn_cache.is_empty():
		_refresh_buttons()
	return _btn_cache

func _refresh_buttons() -> void:
	if main == null or player == null:
		return
	var d := _build_buttons()
	var act := 0
	if main.inventory_system != null:
		for i in 4:
			if main.inventory_system.is_quickbar_active(i):
				act |= 1 << i
	var h := hash([d.hash(), act])
	if h != _btn_hash or _btn_cache.is_empty():
		_btn_hash = h
		_btn_cache = d
		_dirty = true

func _build_buttons() -> Dictionary:
	var w := size.x
	var h := size.y
	var selected_tool := _selected_tool()
	var fire_label := "FEUER"
	if selected_tool != "":
		fire_label = "HAUEN"
	if selected_tool == "fishing_rod":
		fire_label = "ANGELN"
	elif selected_tool == "shovel":
		fire_label = "GRABEN"
	elif selected_tool == "ladder":
		fire_label = "LEITER"
	if main.search_target != null:
		var target_kind := String(main.search_target.get("kind", ""))
		if selected_tool == "axe" and target_kind in ["tree", "log"]:
			fire_label = "HACKEN"
		elif selected_tool == "pickaxe" and target_kind == "rock":
			fire_label = "ABBAUEN"
		elif target_kind == "fish":
			fire_label = "FISCHEN"
	var d := {
		"fire": [Vector2(w - 110, h - 120), 62.0, fire_label, Color(0.6, 0.1, 0.1)],
		"reload": [Vector2(w - 245, h - 85), 38.0, "LADEN", Color(0.4, 0.4, 0.4)],
		"heal": [Vector2(w - 325, h - 85), 34.0, "MED", Color(0.1, 0.45, 0.2)],
		"lamp": [Vector2(w - 400, h - 85), 30.0, "LAMPE", Color(0.5, 0.45, 0.2)],
		"sprint": [Vector2(w - 85, h - 250), 42.0, "SPRINT", Color(0.1, 0.35, 0.2)],
		"dash": [Vector2(w - 185, h - 215), 38.0, "DASH", Color(0.15, 0.2, 0.45)],
		"gren": [Vector2(w - 275, h - 190), 38.0, "BLITZ", Color(0.45, 0.35, 0.1)],
		"jump": [Vector2(w - 330, h - 285), 38.0, "SPRUNG", Color(0.15, 0.4, 0.45)],
		"pause": [Vector2(w - 235, 45), 28.0, "II", Color(0.3, 0.3, 0.3)]}
	var inv = main.inventory_system
	if inv != null:
		d["inv"] = [Vector2(w - 310, 45), 30.0, "INV", Color(0.35, 0.33, 0.25)]
		if not player.driving:
			for slot_index in 4:
				var label: String = inv.quickbar_label(slot_index).get_slice("  ", 1)
				d["slot%d" % slot_index] = [Vector2(w * 0.5 + (slot_index - 1.5) * 74.0, h - 40), 31.0, label, Color(0.3, 0.32, 0.26)]
	# NUTZEN (Tür, Kiste, Baum, ...) – eigener Button, unabhängig vom Auto
	if main.search_target != null and not player.driving:
		var target_kind := String(main.search_target.get("kind", ""))
		if not ((selected_tool == "axe" and target_kind in ["tree", "log"]) or (selected_tool == "pickaxe" and target_kind == "rock")):
			var use_label := "WERKBANK" if target_kind == "workbench" else "AMBOSS" if target_kind == "anvil" else "OFEN" if target_kind == "furnace" else "LEITER" if target_kind == "ladder" else "ÖFFNEN" if target_kind == "door" else "NEHMEN" if target_kind == "weapon" else "HACKEN" if target_kind == "tree" else "SPITZHACKE" if target_kind == "rock" else "FISCHEN" if target_kind == "fish" else "NUTZEN"
			d["use"] = [Vector2(w - 120, h - 345), 42.0, use_label, Color(0.2, 0.2, 0.5)]
	# FAHREN / RAUS – immer am selben, eigenen Platz
	if player.driving:
		d["car"] = [Vector2(w - 235, h - 345), 42.0, "RAUS", Color(0.45, 0.25, 0.12)]
		d["boost"] = [Vector2(w - 120, h - 345), 38.0, "BOOST" if not player.speed_mode else "TURBO", Color(0.4, 0.25, 0.08)]
		d["view"] = [Vector2(w - 120, h - 445), 36.0, "AUSSEN" if main.world.car.first_person_view else "INNEN", Color(0.2, 0.35, 0.4)]
	elif player.can_enter_car():
		d["car"] = [Vector2(w - 235, h - 345), 42.0, "FAHREN", Color(0.45, 0.25, 0.12)]
	return d

func _hit_button(p: Vector2) -> String:
	_refresh_buttons()
	var b := _buttons()
	var best := ""
	var best_d := INF
	for k in b:
		var dist := p.distance_to(b[k][0])
		if dist <= b[k][1] + 10.0 and dist < best_d:
			best = k
			best_d = dist
	return best

func _press(name: String) -> void:
	if name.begins_with("slot"):
		main.inventory_system.activate_quickbar_slot(int(name.substr(4)))
		return
	match name:
		"fire": player.touch_fire = true
		"sprint": player.touch_sprint = true
		"reload": player.reload()
		"dash": player.dash()
		"jump": player.jump()
		"gren": player.grenade()
		"heal": player.heal()
		"lamp": player.toggle_flash()
		"use": main._try_search()
		"inv": main.inventory_system.open()
		"car": player.exit_car() if player.driving else player.enter_car()
		"boost": player.toggle_speed_mode()
		"view": player.toggle_car_camera()
		"pause": main.set_pause(true)

func _release(name: String) -> void:
	match name:
		"fire": player.touch_fire = false
		"sprint": player.touch_sprint = false

func release_all() -> void:
	touches.clear()
	_dirty = true
	stick_id = -1
	player.touch_move = Vector2.ZERO
	player.touch_fire = false
	player.touch_sprint = false

func _input(event: InputEvent) -> void:
	if not visible or main == null:
		return
	if get_tree().paused or not player.alive:
		if not touches.is_empty():
			release_all()
		return
	if event is InputEventScreenTouch:
		_dirty = true
		if event.pressed:
			var btn := _hit_button(event.position)
			if btn != "":
				touches[event.index] = {"kind": "btn", "name": btn}
				_press(btn)
			elif event.position.x < size.x * 0.4 and stick_id == -1:
				stick_id = event.index
				stick_origin = event.position
				stick_pos = event.position
				touches[event.index] = {"kind": "stick", "name": ""}
			else:
				touches[event.index] = {"kind": "look", "name": ""}
		else:
			if touches.has(event.index):
				var t = touches[event.index]
				if t["kind"] == "btn":
					_release(t["name"])
				elif t["kind"] == "stick":
					stick_id = -1
					player.touch_move = Vector2.ZERO
				touches.erase(event.index)
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		var t = touches[event.index]
		if t["kind"] == "stick":
			_dirty = true
			stick_pos = event.position
			var v: Vector2 = (event.position - stick_origin) / STICK_R
			if v.length() > 1.0:
				v = v.normalized()
				stick_pos = stick_origin + v * STICK_R
			player.touch_move = v
		elif t["kind"] == "look":
			player.look(event.relative)

func _process(_d: float) -> void:
	if not visible:
		return
	_hide_gui_duplicates()
	var now := Time.get_ticks_msec()
	if now >= _next_btn:
		_next_btn = now + 66
		_refresh_buttons()
	if _dirty:
		_dirty = false
		queue_redraw()

## Die alten GUI-Buttons (Schnellleiste unten links, INV) reagieren nicht, solange ein Finger
## den Stick hält. Auf dem Handy werden sie durch die Buttons hier ersetzt.
func _hide_gui_duplicates() -> void:
	if gui_hidden or main == null or main.inventory_system == null or main.inventory_system.inventory_button == null:
		return
	gui_hidden = true
	for weapon_button in main.weapon_buttons:
		weapon_button.hide()
	main.inventory_system.inventory_button.hide()

func _draw() -> void:
	if main == null:
		return
	var font := ThemeDB.fallback_font
	var b := _buttons()
	var held := {}
	for k in touches:
		if touches[k]["kind"] == "btn":
			held[touches[k]["name"]] = true
	for k in b:
		var c: Vector2 = b[k][0]
		var r: float = b[k][1]
		var col: Color = b[k][3]
		var a := 0.55 if held.has(k) else 0.3
		if k.begins_with("slot"):
			var slot_index := int(k.substr(4))
			var entry: String = main.inventory_system.quickbar_entry(slot_index)
			var is_active: bool = entry != "" and main.inventory_system.is_quickbar_active(slot_index)
			if entry == "":
				a = 0.12
			elif is_active:
				a = 0.6
			draw_circle(c, r, Color(col.r, col.g, col.b, a))
			draw_arc(c, r, 0.0, TAU, 32, Color(1.0, 0.83, 0.42, 0.95) if is_active else Color(0.8, 0.8, 0.77, 0.5), 3.0 if is_active else 2.0)
			draw_string(font, c + Vector2(-r, -3), str(slot_index + 1), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, Color(0.9, 0.9, 0.85, 0.95))
			draw_string(font, c + Vector2(-r, 15), String(b[k][2]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, Color(0.85, 0.85, 0.8, 0.9))
			continue
		draw_circle(c, r, Color(col.r, col.g, col.b, a))
		draw_arc(c, r, 0.0, TAU, 32, Color(0.8, 0.8, 0.77, 0.5), 2.0)
		draw_string(font, c + Vector2(-r, 5), b[k][2], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, Color(0.85, 0.85, 0.8, 0.9))
	if stick_id != -1:
		draw_arc(stick_origin, STICK_R, 0.0, TAU, 40, Color(0.8, 0.8, 0.77, 0.4), 2.0)
		draw_circle(stick_pos, 28.0, Color(0.8, 0.8, 0.77, 0.4))
