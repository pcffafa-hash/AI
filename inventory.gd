extends Node
## INVENTAR für Silent Head (Godot 4)
## - Tasche mit 12 Slots + Schnellleiste mit 4 Slots
## - Verschieben: ziehen (Drag & Drop) ODER Gegenstand antippen und danach das Ziel antippen
## - Rechtsklick: Tasche <-> Schnellleiste, Doppelklick: ausrüsten
## - Öffnen: Taste I oder TAB (oder INV-Button). Schließen: I / TAB / ESC / neben das Fenster klicken
## - Detailansicht, Herstellen (Rezepte), Sortieren, Heilen
## Die Schnittstelle zu main.gd / player.gd / touch.gd / minimap.gd ist unverändert.

const GRID_SLOTS := 12
const HOTBAR_SLOTS := 4
const SLOT_SIZE := 76.0
const MUTED := Color(0.66, 0.66, 0.6)

const ITEM_ORDER := ["axe", "pickaxe", "shovel", "ladder", "wood", "iron_ore", "stone", "iron_ingot", "fish", "fishing_rod", "armor", "workbench", "anvil", "furnace"]
const ITEM_INFO := {
	"axe": {"name": "Axt", "short": "AXT", "kind": "tool", "icon": "axe",
		"desc": "Zum Holzfällen. In der Schnellleiste ausrüsten, dann vor einem Baum E drücken."},
	"shovel": {"name": "Holzschaufel", "short": "SCHAUFEL", "kind": "tool", "icon": "shovel",
		"desc": "Zum Graben. Wiederholtes Graben vertieft das Loch."},
	"ladder": {"name": "Leiter", "short": "LEITER", "kind": "tool", "icon": "ladder",
		"desc": "Platziere sie mit dem Benutzen-Knopf. An Leitern kannst du hoch- und hinunterklettern; mit E kannst du sie wieder aufnehmen."},
	"fish": {"name": "Fisch", "short": "FISCH", "kind": "resource", "icon": "fish",
		"desc": "Frisch gefangen aus einer Pfütze oder einem Teich. Ideal zum Essen oder zum Handeln."},
	"pickaxe": {"name": "Spitzhacke", "short": "HACKE", "kind": "tool", "icon": "pickaxe",
		"desc": "Holzwerkzeug zum Abbauen von Felsen. In der Schnellleiste ausrüsten und damit auf einen Felsen schlagen."},
	"wood": {"name": "Holz", "short": "HOLZ", "kind": "resource", "icon": "wood",
		"desc": "Rohstoff aus gefällten Bäumen. Wird zum Bauen gebraucht."},
	"iron_ore": {"name": "Eisenerz", "short": "ERZ", "kind": "resource", "icon": "iron_ore",
		"desc": "Kann im Schmelzofen zu Eisenbarren verarbeitet werden."},
	"stone": {"name": "Stein", "short": "STEIN", "kind": "resource", "icon": "stone",
		"desc": "Baumaterial für den Schmelzofen."},
	"iron_ingot": {"name": "Eisenbarren", "short": "EISEN", "kind": "resource", "icon": "iron_ingot",
		"desc": "Geschmolzenes Eisen für Amboss, Pistole und Rüstung."},
	"workbench": {"name": "Werkbank", "short": "WERKBANK", "kind": "building", "icon": "workbench",
		"desc": "Öffnen, um Amboss, Schmelzofen und Angel herzustellen."},
	"anvil": {"name": "Amboss", "short": "AMBOSS", "kind": "building", "icon": "anvil",
		"desc": "Werkzeugstation für Pistolen und Rüstungen."},
	"furnace": {"name": "Schmelzofen", "short": "OFEN", "kind": "building", "icon": "furnace",
		"desc": "Öffnen, um Eisenerz zu Eisenbarren zu schmelzen."},
	"fishing_rod": {"name": "Angel", "short": "ANGEL", "kind": "tool", "icon": "fishing_rod",
		"desc": "Eine gefertigte Angel. Kann über die Schnellleiste ausgewählt werden."},
	"armor": {"name": "Rüstung", "short": "RÜSTUNG", "kind": "armor", "icon": "armor",
		"desc": "Anlegen, um 30 % weniger Schaden zu erleiden."}}
const KIND_COLOR := {
	"weapon": Color(0.9, 0.58, 0.22),
	"tool": Color(0.62, 0.7, 0.76),
	"armor": Color(0.28, 0.62, 0.64),
	"resource": Color(0.62, 0.45, 0.25),
	"building": Color(0.4, 0.62, 0.78)}
const KIND_NAME := {"weapon": "Waffe", "tool": "Werkzeug", "armor": "Rüstung", "resource": "Rohstoff", "building": "Bauwerk"}
const KIND_RANK := {"weapon": 0, "tool": 1, "armor": 1, "resource": 2, "building": 3}
## Rezepte: "cost" = Item -> Menge. Neue Rezepte hier eintragen und in _craft() einen Zweig ergänzen.
const RECIPES := [
	{"id": "workbench", "name": "Werkbank", "station": "", "cost": {"wood": 4}},
	{"id": "pickaxe", "name": "Holz-Spitzhacke", "station": "workbench", "cost": {"wood": 6}},
	{"id": "shovel", "name": "Holzschaufel", "station": "workbench", "cost": {"wood": 5}},
	{"id": "ladder", "name": "Leiter", "station": "workbench", "cost": {"wood": 6}},
	{"id": "anvil", "name": "Amboss", "station": "workbench", "unique": true, "cost": {"iron_ingot": 4, "wood": 2}},
	{"id": "furnace", "name": "Schmelzofen", "station": "workbench", "unique": true, "cost": {"stone": 8, "iron_ore": 2, "wood": 3}},
	{"id": "fishing_rod", "name": "Angel", "station": "workbench", "cost": {"wood": 3}},
	{"id": "iron_ingot", "name": "Eisenbarren x2", "station": "furnace", "cost": {"iron_ore": 2, "wood": 1}},
	{"id": "pistol", "name": "Pistole", "station": "anvil", "cost": {"iron_ingot": 5, "wood": 2}},
	{"id": "armor", "name": "Rüstung", "station": "anvil", "unique": true, "cost": {"iron_ingot": 7, "wood": 1}}]

var main
var player
var inventory_button: Button
var inventory_root: Control
var inv_panel: PanelContainer   # Fenster (wird bei kleinem Bildschirm verkleinert)
var inv_holder: Control         # Platzhalter für die zentrierte, skalierte Größe
var _ui_dirty := false

var slot_widgets: Array = []        # 0..11 = Tasche, 12..15 = Schnellleiste
var grid_title: Label
var detail_icon: Slot
var detail_name: Label
var detail_kind: Label
var detail_desc: Label
var equip_button: Button
var move_button: Button
var recipe_rows: Array = []
var crafting_title: Label
var health_label: Label
var heal_button: Button
var message_label: Label
var message_id := 0
var craft_search: LineEdit
var recipe_preview_name: Label
var recipe_preview_cost: Label
var craft_button: Button
var selected_recipe: Dictionary = {}

var grid: Array[String] = []        # Inhalt der Tasche ("" = leer)
var hotbar: Array[String] = []      # Inhalt der Schnellleiste
var selected_slot := -1
var active_quickbar_slot := 0
var items := {"axe": 0, "wood": 0, "iron_ore": 0, "stone": 0, "iron_ingot": 0,
	"fish": 0, "workbench": 0, "anvil": 0, "furnace": 0, "fishing_rod": 0, "armor": 0, "pickaxe": 0,
	"shovel": 0, "ladder": 0}
var is_open := false
var is_touch := false
var _built := false
var _last_weapon := -1
var crafting_station := ""
var station_position := Vector3.ZERO
var armor_equipped := false

# ------------------------------------------------------------------ Aufbau
func setup(main_node, ui: CanvasLayer, hud_root: Control, touch_mode: bool) -> void:
	main = main_node
	player = main.player
	is_touch = touch_mode
	_clear_slots()
	_build_button(hud_root)
	_build_window(ui)
	_built = true
	refresh()

func _clear_slots() -> void:
	grid.clear()
	hotbar.clear()
	for _i in GRID_SLOTS:
		grid.append("")
	for _i in HOTBAR_SLOTS:
		hotbar.append("")

func _build_button(hud_root: Control) -> void:
	inventory_button = Button.new()
	inventory_button.text = "INV" if is_touch else "INV [I]"
	inventory_button.custom_minimum_size = Vector2(84, 36)
	inventory_button.focus_mode = Control.FOCUS_NONE
	inventory_button.pressed.connect(open)
	var normal := _box(Color(0.16, 0.18, 0.15), Color(0.58, 0.55, 0.44), 18, 2, 8, 2)
	var hover := _box(Color(0.27, 0.3, 0.23), Color(0.7, 0.66, 0.52), 18, 2, 8, 2)
	inventory_button.add_theme_stylebox_override("normal", normal)
	inventory_button.add_theme_stylebox_override("hover", hover)
	inventory_button.add_theme_stylebox_override("pressed", normal)
	inventory_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hud_root.add_child(inventory_button)
	inventory_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	inventory_button.offset_left = -102.0
	inventory_button.offset_right = -18.0
	set_map_expanded(false)

func _build_window(ui: CanvasLayer) -> void:
	inventory_root = Control.new()
	inventory_root.process_mode = Node.PROCESS_MODE_ALWAYS
	inventory_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(inventory_root)
	_set_full_rect(inventory_root)
	inventory_root.hide()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.02, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	inventory_root.add_child(dim)
	_set_full_rect(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_root.add_child(center)
	_set_full_rect(center)

	inv_holder = Control.new()
	inv_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(inv_holder)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.12, 0.125, 0.11, 0.98), Color(0.48, 0.45, 0.38), 10, 3, 20, 16))
	inv_holder.add_child(panel)
	inv_panel = panel
	get_viewport().size_changed.connect(_fit_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)

	# Kopfzeile
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)
	var title := _label(header, "INVENTAR", 28, Color(0.9, 0.86, 0.74))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_touch:
		_label(header, "I / TAB / ESC = schließen", 12, Color(0.55, 0.55, 0.5))
	_button(header, "X", close, 48)
	layout.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	layout.add_child(body)

	# Linke Spalte: Tasche + Schnellleiste
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	var grid_header := HBoxContainer.new()
	left.add_child(grid_header)
	grid_title = _label(grid_header, "TASCHE", 14, MUTED)
	grid_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(grid_header, "SORTIEREN", sort_grid, 0, 30)
	var grid_box := GridContainer.new()
	grid_box.columns = 4
	grid_box.add_theme_constant_override("h_separation", 6)
	grid_box.add_theme_constant_override("v_separation", 6)
	left.add_child(grid_box)
	for slot_index in GRID_SLOTS:
		_make_slot(grid_box, slot_index)
	_label(left, "SCHNELLLEISTE", 14, MUTED)
	var hotbar_box := HBoxContainer.new()
	hotbar_box.add_theme_constant_override("separation", 6)
	left.add_child(hotbar_box)
	for slot_index in HOTBAR_SLOTS:
		_make_slot(hotbar_box, GRID_SLOTS + slot_index)

	# Rechte Spalte: Details, Herstellen, Zustand
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_label(right, "DETAILS", 14, MUTED)
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(0, 220)
	detail_panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.085, 0.075), Color(0.33, 0.32, 0.28), 6, 2, 12, 10))
	right.add_child(detail_panel)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	detail_panel.add_child(detail_box)
	var detail_head := HBoxContainer.new()
	detail_head.add_theme_constant_override("separation", 12)
	detail_box.add_child(detail_head)
	detail_icon = Slot.new(-1, 64.0)
	detail_icon.plain = true
	detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_head.add_child(detail_icon)
	var detail_titles := VBoxContainer.new()
	detail_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_head.add_child(detail_titles)
	detail_name = _label(detail_titles, "", 22, Color(0.92, 0.88, 0.76))
	detail_kind = _label(detail_titles, "", 13, MUTED)
	detail_desc = _label(detail_box, "", 14, Color(0.78, 0.78, 0.73))
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(290, 0)
	detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var detail_buttons := HBoxContainer.new()
	detail_buttons.add_theme_constant_override("separation", 8)
	detail_box.add_child(detail_buttons)
	equip_button = _button(detail_buttons, "AUSRÜSTEN", _equip_selected)
	equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_button = _button(detail_buttons, "IN SCHNELLLEISTE", _move_selected)
	move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	crafting_title = _label(right, "HERSTELLEN", 14, MUTED)
	craft_search = LineEdit.new()
	craft_search.placeholder_text = "Gegenstand suchen"
	craft_search.text_changed.connect(_on_recipe_search_changed)
	right.add_child(craft_search)
	var recipe_scroll := ScrollContainer.new()
	recipe_scroll.custom_minimum_size = Vector2(0, 130)
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(recipe_scroll)
	var recipe_list := VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_scroll.add_child(recipe_list)
	for recipe in RECIPES:
		var recipe_button := _button(recipe_list, String(recipe["name"]), _select_recipe.bind(recipe))
		recipe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		recipe_button.toggle_mode = true
		recipe_rows.append({"recipe": recipe, "button": recipe_button})
	var recipe_preview := VBoxContainer.new()
	recipe_preview.add_theme_constant_override("separation", 4)
	right.add_child(recipe_preview)
	recipe_preview_name = _label(recipe_preview, "Rezept auswählen", 16, Color(0.9, 0.86, 0.74))
	recipe_preview_cost = _label(recipe_preview, "", 13)
	recipe_preview_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	craft_button = _button(recipe_preview, "HERSTELLEN", _craft_selected)
	craft_button.disabled = true

	_label(right, "ZUSTAND", 14, MUTED)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 10)
	right.add_child(health_row)
	health_label = _label(health_row, "", 15)
	health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_button = _button(health_row, "HEILEN", _heal, 96)

	# Fußzeile
	message_label = _label(layout, "", 14, Color(1.0, 0.84, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	message_label.custom_minimum_size = Vector2(0, 20)
	message_label.modulate.a = 0.0
	var hint := "Gegenstand antippen und dann ein Ziel antippen – oder direkt ziehen." if is_touch else "Ziehen oder anklicken · Rechtsklick: Tasche / Schnellleiste · Doppelklick: ausrüsten"
	_label(layout, hint, 12, Color(0.55, 0.55, 0.5), HORIZONTAL_ALIGNMENT_CENTER)

func _make_slot(parent: Node, index: int) -> void:
	var slot := Slot.new(index, SLOT_SIZE)
	slot.clicked.connect(_on_slot_clicked)
	slot.activated.connect(_primary_action)
	slot.secondary.connect(_quick_move)
	slot.dropped.connect(_move_entry)
	parent.add_child(slot)
	slot_widgets.append(slot)

func _set_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _box(bg: Color, border: Color, radius := 6, border_width := 2, margin_h := 10.0, margin_v := 5.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb

func _label(parent: Node, text: String, size: int, color := Color(0.81, 0.81, 0.77), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = align
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, min_width := 0.0, min_height := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	var height := min_height if min_height > 0.0 else (48.0 if is_touch else 40.0)
	button.custom_minimum_size = Vector2(min_width, height)
	button.focus_mode = Control.FOCUS_NONE
	var accent := Color(0.58, 0.55, 0.44)
	button.add_theme_stylebox_override("normal", _box(Color(0.16, 0.18, 0.15), accent, 6, 2, 12, 5))
	button.add_theme_stylebox_override("hover", _box(Color(0.26, 0.29, 0.21), accent.lightened(0.2), 6, 2, 12, 5))
	button.add_theme_stylebox_override("pressed", _box(Color(0.32, 0.35, 0.23), accent.lightened(0.3), 6, 2, 12, 5))
	button.add_theme_stylebox_override("disabled", _box(Color(0.1, 0.105, 0.095), Color(0.26, 0.26, 0.23), 6, 2, 12, 5))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.42, 0.38))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

# ------------------------------------------------------------------ Gegenstände
func count_item(item_id: String) -> int:
	return int(items.get(item_id, 0))

func add_item(item_id: String, amount: int = 1) -> void:
	items[item_id] = count_item(item_id) + amount
	refresh()

func remove_item(item_id: String, amount: int = 1) -> bool:
	if count_item(item_id) < amount:
		return false
	items[item_id] = count_item(item_id) - amount
	refresh()
	return true

func reset() -> void:
	items = {"axe": 0, "wood": 0, "iron_ore": 0, "stone": 0, "iron_ingot": 0,
		"fish": 0, "workbench": 0, "anvil": 0, "furnace": 0, "fishing_rod": 0, "armor": 0,
		"pickaxe": 0, "shovel": 0, "ladder": 0}
	_clear_slots()
	selected_slot = -1
	active_quickbar_slot = 0
	_last_weapon = -1
	crafting_station = ""
	armor_equipped = false
	refresh()

func _weapon_index_for_entry(entry: String) -> int:
	if not entry.begins_with("weapon:"):
		return -1
	var weapon_id := entry.trim_prefix("weapon:")
	var slots: Array = player.weapon_system.weapon_slots
	for slot_index in slots.size():
		if String(slots[slot_index]["id"]) == weapon_id:
			return slot_index
	return -1

func _weapon_short(weapon_id: String) -> String:
	if weapon_id == "minigun":
		return "M-GUN"
	var winfo: Dictionary = player.weapon_system.WEAPON_INFO.get(weapon_id, {})
	return String(winfo.get("name", weapon_id.to_upper()))

## Alle Angaben, die ein Slot zum Zeichnen und das Detailfeld zum Anzeigen brauchen.
func _entry_info(entry: String) -> Dictionary:
	if entry == "":
		return {"entry": ""}
	if entry.begins_with("weapon:"):
		var weapon_id := entry.trim_prefix("weapon:")
		var winfo: Dictionary = player.weapon_system.WEAPON_INFO.get(weapon_id, {})
		var weapon_index := _weapon_index_for_entry(entry)
		var ammo := 0
		if weapon_index >= 0:
			ammo = int(player.weapon_system.weapon_slots[weapon_index]["ammo"])
		var capacity := maxi(1, int(winfo.get("capacity", 1)))
		var pellets := int(winfo.get("pellets", 1))
		var damage := float(winfo.get("damage", 1.0))
		var damage_text := ("%d × %.1f" % [pellets, damage]) if pellets > 1 else ("%.1f" % damage)
		var rate := 1.0 / maxf(0.01, float(winfo.get("cooldown", 1.0)))
		var desc := "Schaden: %s\nMagazin: %d / %d\nFeuerrate: %.1f pro Sekunde\nNachladen: %.1f Sekunden" % [damage_text, ammo, capacity, rate, float(winfo.get("reload", 1.0))]
		return {
			"entry": entry,
			"title": String(winfo.get("name", weapon_id)).to_lower().capitalize(),
			"short": _weapon_short(weapon_id),
			"kind": "weapon",
			"color": KIND_COLOR["weapon"],
			"icon": weapon_id,
			"count": "%d/%d" % [ammo, capacity],
			"frac": float(ammo) / float(capacity),
			"desc": desc,
			"equippable": true}
	var data: Dictionary = ITEM_INFO.get(entry, {})
	if data.is_empty():
		return {"entry": entry, "title": entry, "short": entry.to_upper(), "kind": "resource",
			"color": KIND_COLOR["resource"], "icon": "", "count": "", "frac": -1.0, "desc": "", "equippable": false}
	var kind := String(data["kind"])
	return {
		"entry": entry,
		"title": String(data["name"]),
		"short": String(data["short"]),
		"kind": kind,
		"color": KIND_COLOR[kind],
		"icon": String(data["icon"]),
		"count": "x%d" % count_item(entry),
		"frac": -1.0,
		"desc": String(data["desc"]),
		"equippable": kind == "tool" or kind == "armor"}

# ------------------------------------------------------------------ Slots verwalten
func _get_entry_at(slot_index: int) -> String:
	if slot_index < 0:
		return ""
	if slot_index < GRID_SLOTS:
		return grid[slot_index]
	if slot_index < GRID_SLOTS + HOTBAR_SLOTS:
		return hotbar[slot_index - GRID_SLOTS]
	return ""

func _set_entry_at(slot_index: int, entry: String) -> void:
	if slot_index < GRID_SLOTS:
		grid[slot_index] = entry
	else:
		hotbar[slot_index - GRID_SLOTS] = entry

func _first_free(list: Array[String]) -> int:
	for slot_index in list.size():
		if list[slot_index] == "":
			return slot_index
	return -1

func _available_entries() -> Array[String]:
	var list: Array[String] = []
	for item_id in ITEM_ORDER:
		if count_item(String(item_id)) > 0:
			list.append(String(item_id))
	for weapon in player.weapon_system.weapon_slots:
		list.append("weapon:" + String(weapon["id"]))
	return list

## Gleicht den Inhalt mit dem tatsächlichen Besitz ab: Verschwundenes raus, Neues rein.
## Waffen und die Axt landen bevorzugt in der Schnellleiste, alles andere in der Tasche.
func refresh() -> void:
	if not _built or player == null or player.weapon_system == null:
		return
	var available := _available_entries()
	var seen := {}
	for slot_index in hotbar.size():
		var entry := hotbar[slot_index]
		if entry == "":
			continue
		if not available.has(entry) or seen.has(entry):
			hotbar[slot_index] = ""
		else:
			seen[entry] = true
	for slot_index in grid.size():
		var entry := grid[slot_index]
		if entry == "":
			continue
		if not available.has(entry) or seen.has(entry):
			grid[slot_index] = ""
		else:
			seen[entry] = true
	for entry in available:
		if seen.has(entry):
			continue
		var target := -1
		if entry.begins_with("weapon:") or entry in ["axe", "pickaxe", "shovel", "ladder", "fishing_rod"]:
			target = _first_free(hotbar)
			if target >= 0:
				hotbar[target] = entry
				continue
		target = _first_free(grid)
		if target >= 0:
			grid[target] = entry
			continue
		target = _first_free(hotbar)
		if target >= 0:
			hotbar[target] = entry
	if selected_slot >= 0 and _get_entry_at(selected_slot) == "":
		selected_slot = -1
	_sync_active_weapon()
	_update_ui()

## Hält die aktive Schnellleisten-Position mit der tatsächlich gehaltenen Waffe synchron
## (z. B. beim Durchschalten mit dem Mausrad oder nach dem Aufheben einer Waffe).
func _sync_active_weapon(force := false) -> void:
	var weapon_system = player.weapon_system
	var weapon_index: int = weapon_system.active_weapon_slot
	if not force and weapon_index == _last_weapon:
		return
	_last_weapon = weapon_index
	if weapon_index < 0 or weapon_index >= weapon_system.weapon_slots.size():
		return
	var slot_index := hotbar.find("weapon:" + String(weapon_system.weapon_slots[weapon_index]["id"]))
	if slot_index >= 0:
		active_quickbar_slot = slot_index

func _process(_delta: float) -> void:
	if not _built or player == null or player.weapon_system == null:
		return
	if is_open and not get_tree().paused:
		close()   # z. B. Pause-Menü wurde währenddessen geschlossen
		return
	if player.weapon_system.active_weapon_slot != _last_weapon:
		_sync_active_weapon()
		_update_ui()

# ------------------------------------------------------------------ Schnellleiste (von main.gd / player.gd genutzt)
func quickbar_entry(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= hotbar.size():
		return ""
	return hotbar[slot_index]

func quickbar_label(slot_index: int) -> String:
	var entry := quickbar_entry(slot_index)
	if entry == "":
		return "%d  -" % (slot_index + 1)
	if entry.begins_with("weapon:"):
		return "%d  %s" % [slot_index + 1, _weapon_short(entry.trim_prefix("weapon:"))]
	var data: Dictionary = ITEM_INFO.get(entry, {})
	return "%d  %s" % [slot_index + 1, String(data.get("short", entry.to_upper()))]

func is_quickbar_active(slot_index: int) -> bool:
	var entry := quickbar_entry(slot_index)
	if entry == "":
		return false
	var weapon_index := _weapon_index_for_entry(entry)
	if weapon_index >= 0:
		return weapon_index == player.weapon_system.active_weapon_slot
	return active_quickbar_slot == slot_index

func activate_quickbar_slot(slot_index: int) -> void:
	var entry := quickbar_entry(slot_index)
	if entry == "":
		return
	if player.driving or player.transitioning:
		return
	active_quickbar_slot = slot_index
	var weapon_index := _weapon_index_for_entry(entry)
	if weapon_index >= 0:
		if weapon_index != player.weapon_system.active_weapon_slot:   # erneutes Wählen bricht das Nachladen nicht ab
			player.weapon_system.equip_weapon(weapon_index)
		_last_weapon = weapon_index
	else:
		main.toast("%s gewählt" % String(_entry_info(entry)["title"]))
	_update_ui()

# ------------------------------------------------------------------ Bedienung
func _on_slot_clicked(slot_index: int) -> void:
	if selected_slot < 0:
		if _get_entry_at(slot_index) != "":
			selected_slot = slot_index
			main.play_sfx("click", -6.0)
		_update_ui()
	elif selected_slot == slot_index:
		selected_slot = -1
		_update_ui()
	else:
		_move_entry(selected_slot, slot_index)

func _move_entry(from_index: int, to_index: int, keep_selected := false) -> void:
	var total := GRID_SLOTS + HOTBAR_SLOTS
	var moving := _get_entry_at(from_index)
	if from_index == to_index or from_index < 0 or to_index < 0 or from_index >= total or to_index >= total or moving == "":
		selected_slot = -1
		_update_ui()
		return
	var active_entry := hotbar[active_quickbar_slot] if active_quickbar_slot >= 0 else ""
	var target_entry := _get_entry_at(to_index)
	_set_entry_at(from_index, target_entry)
	_set_entry_at(to_index, moving)
	if active_entry != "" and hotbar.has(active_entry):
		active_quickbar_slot = hotbar.find(active_entry)
	elif active_entry != "":
		active_quickbar_slot = -1   # das ausgerüstete Item liegt jetzt in der Tasche
		_sync_active_weapon(true)
	selected_slot = to_index if keep_selected else -1
	main.play_sfx("click")
	_update_ui()

## Rechtsklick / Button: Tasche <-> Schnellleiste
func _quick_move(slot_index: int) -> void:
	if _get_entry_at(slot_index) == "":
		return
	var target := -1
	if slot_index < GRID_SLOTS:
		var free_hotbar := _first_free(hotbar)
		if free_hotbar >= 0:
			target = GRID_SLOTS + free_hotbar
	else:
		target = _first_free(grid)
	if target < 0:
		_message("Kein freier Platz.")
		return
	_move_entry(slot_index, target, true)

## Doppelklick: ausrüsten, wenn möglich, sonst verschieben
func _primary_action(slot_index: int) -> void:
	var entry := _get_entry_at(slot_index)
	if entry == "":
		return
	if bool(_entry_info(entry).get("equippable", false)):
		_equip_entry(entry)
	else:
		_quick_move(slot_index)

func _equip_selected() -> void:
	_equip_entry(_get_entry_at(selected_slot))

func _equip_entry(entry: String) -> void:
	if entry == "":
		return
	if entry == "armor":
		armor_equipped = not armor_equipped
		_message("Rüstung angelegt." if armor_equipped else "Rüstung abgelegt.")
		_update_ui()
		return
	if player.driving or player.transitioning:
		_message("Im Auto nicht möglich.")
		return
	var hotbar_index := hotbar.find(entry)
	if hotbar_index < 0:
		var free_hotbar := _first_free(hotbar)
		if free_hotbar < 0:
			_message("Schnellleiste voll – tausche den Gegenstand mit einem Slot dort.")
			return
		var source := grid.find(entry)
		if source >= 0:
			grid[source] = ""
		hotbar[free_hotbar] = entry
		hotbar_index = free_hotbar
	selected_slot = GRID_SLOTS + hotbar_index
	main.play_sfx("click")
	activate_quickbar_slot(hotbar_index)

func _move_selected() -> void:
	if selected_slot >= 0:
		_quick_move(selected_slot)

func sort_grid() -> void:
	var entries: Array[String] = []
	for entry in grid:
		if entry != "":
			entries.append(entry)
	entries.sort_custom(_sort_entries)
	for slot_index in GRID_SLOTS:
		grid[slot_index] = entries[slot_index] if slot_index < entries.size() else ""
	selected_slot = -1
	main.play_sfx("click")
	_update_ui()

func _sort_entries(a: String, b: String) -> bool:
	var info_a := _entry_info(a)
	var info_b := _entry_info(b)
	var rank_a: int = KIND_RANK.get(String(info_a["kind"]), 9)
	var rank_b: int = KIND_RANK.get(String(info_b["kind"]), 9)
	if rank_a != rank_b:
		return rank_a < rank_b
	return String(info_a["title"]) < String(info_b["title"])

func _heal() -> void:
	var before: float = player.hp
	player.heal()
	if player.hp > before:
		_message("Verbandskasten benutzt  (+%d HP)" % int(round(player.hp - before)))
	_update_ui()

func _can_craft(recipe: Dictionary) -> bool:
	var station := String(recipe.get("station", ""))
	if station != crafting_station:
		return false
	if crafting_station == "" and String(recipe.get("id", "")) != "workbench":
		return false
	if bool(recipe.get("unique", false)) and count_item(String(recipe["id"])) > 0:
		return false
	var cost: Dictionary = recipe["cost"]
	for item_id in cost:
		if count_item(String(item_id)) < int(cost[item_id]):
			return false
	return true

func craft_workbench() -> void:
	for recipe in RECIPES:
		if String(recipe["id"]) == "workbench":
			_craft(recipe)

func _select_recipe(recipe: Dictionary) -> void:
	selected_recipe = recipe
	_update_crafting()

func _craft_selected() -> void:
	if not selected_recipe.is_empty():
		_craft(selected_recipe)

func _on_recipe_search_changed(_text: String) -> void:
	_update_crafting()

func _craft(recipe: Dictionary) -> void:
	if not _can_craft(recipe):
		_message("Nicht genug Material.")
		return
	var recipe_id := String(recipe["id"])
	if recipe_id == "workbench" and player.driving:
		_message("Steig zuerst aus dem Auto aus.")
		return
	if recipe_id == "pistol" and not player.can_pickup_weapon("pistol"):
		_message("Waffeninventar voll – maximal vier Waffen.")
		return
	for item_id in recipe["cost"]:
		remove_item(String(item_id), int(recipe["cost"][item_id]))
	var place_pos: Vector3 = station_position if station_position != Vector3.ZERO else player.global_position
	match recipe_id:
		"workbench":
			var forward: Vector3 = player.global_transform.basis * Vector3(0, 0, -2.1)
			var workbench_pos: Vector3 = player.global_position + forward if station_position == Vector3.ZERO else station_position
			main.world.build_workbench(workbench_pos, player.rotation.y)
			add_item("workbench")
		"anvil":
			var anvil_pos: Vector3 = place_pos + Vector3(1.7, 0, 0) if station_position != Vector3.ZERO else player.global_position + Vector3(1.7, 0, 0)
			main.world.build_station("anvil", anvil_pos)
			add_item("anvil")
		"furnace":
			var furnace_pos: Vector3 = place_pos + Vector3(-1.7, 0, 0) if station_position != Vector3.ZERO else player.global_position + Vector3(-1.7, 0, 0)
			main.world.build_station("furnace", furnace_pos)
			add_item("furnace")
		"iron_ingot":
			add_item("iron_ingot", 2)
		"pistol":
			player.pickup_weapon("pistol")
		"fishing_rod":
			add_item("fishing_rod")
		"pickaxe":
			add_item("pickaxe")
		"shovel":
			add_item("shovel")
		"ladder":
			add_item("ladder")
		"armor":
			add_item("armor")
	main.world_dirty = true
	main.play_sfx("click")
	main.toast("%s hergestellt" % String(recipe["name"]))
	refresh()
	if recipe_id == "workbench":
		close()

func _message(text: String) -> void:
	message_id += 1
	var id := message_id
	message_label.text = text
	message_label.modulate.a = 1.0
	await get_tree().create_timer(2.6).timeout
	if id == message_id and is_instance_valid(message_label):
		message_label.modulate.a = 0.0

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# ------------------------------------------------------------------ Anzeige
func _update_ui() -> void:
	if not _built or slot_widgets.is_empty():
		return
	# Geschlossen: keine Widget-Arbeit (spart bei jedem Aufheben/Herstellen Zeit). Beim Öffnen wird neu gezeichnet.
	if not is_open:
		_ui_dirty = true
		return
	_ui_dirty = false
	var used := 0
	for slot_index in GRID_SLOTS:
		var entry := grid[slot_index]
		if entry != "":
			used += 1
		slot_widgets[slot_index].set_info(_entry_info(entry), "", selected_slot == slot_index, false)
	for hotbar_index in HOTBAR_SLOTS:
		var entry := hotbar[hotbar_index]
		var widget_index := GRID_SLOTS + hotbar_index
		slot_widgets[widget_index].set_info(_entry_info(entry), str(hotbar_index + 1),
			selected_slot == widget_index, entry != "" and is_quickbar_active(hotbar_index))
	grid_title.text = "TASCHE  %d/%d" % [used, GRID_SLOTS]
	_update_detail()
	_update_crafting()
	health_label.text = "HP %d / 100   ·   Verbände: %d" % [maxi(0, ceili(player.hp)), player.heals]
	heal_button.disabled = player.heals <= 0 or player.hp >= 100.0 or not player.alive
	_fit_panel()

## Passt das Fenster an kleine Bildschirme an (wird sonst oben/unten abgeschnitten).
func _fit_panel() -> void:
	if inv_panel == null or inv_holder == null or inventory_root == null or not is_open:
		return
	inv_panel.reset_size()
	var need := inv_panel.get_combined_minimum_size()
	var avail := inventory_root.size - Vector2(16, 16)
	if need.x <= 0.0 or need.y <= 0.0 or avail.x <= 0.0 or avail.y <= 0.0:
		return
	var k := clampf(minf(avail.x / need.x, avail.y / need.y), 0.5, 1.0)
	inv_panel.pivot_offset = Vector2.ZERO
	inv_panel.scale = Vector2(k, k)
	inv_holder.custom_minimum_size = need * k

func _update_detail() -> void:
	var entry := _get_entry_at(selected_slot)
	if entry == "":
		detail_icon.set_info({"entry": ""}, "", false, false)
		detail_name.text = "Nichts gewählt"
		detail_kind.text = ""
		detail_desc.text = "Tippe einen Gegenstand an oder ziehe ihn auf einen anderen Slot.\nDie Schnellleiste erreichst du im Spiel mit den Tasten 1–4."
		equip_button.hide()
		move_button.hide()
		return
	var info := _entry_info(entry)
	var in_hotbar := selected_slot >= GRID_SLOTS
	detail_icon.set_info(info, "", false, false)
	detail_name.text = String(info["title"])
	detail_kind.text = "%s  ·  %s" % [String(KIND_NAME.get(String(info["kind"]), "")), "Schnellleiste" if in_hotbar else "Tasche"]
	detail_desc.text = String(info["desc"])
	equip_button.visible = bool(info.get("equippable", false))
	equip_button.text = "ABLEGEN" if entry == "armor" and armor_equipped else "ANLEGEN" if entry == "armor" else "AUSRÜSTEN"
	move_button.visible = true
	move_button.text = "IN DIE TASCHE" if in_hotbar else "IN SCHNELLLEISTE"

func _update_crafting() -> void:
	var station_names := {"workbench": "WERKBANK", "anvil": "AMBOSS", "furnace": "SCHMELZOFEN"}
	crafting_title.text = "HERSTELLEN" if crafting_station == "" else "HERSTELLEN · %s" % String(station_names.get(crafting_station, crafting_station.to_upper()))
	var search_text := craft_search.text.strip_edges().to_lower() if craft_search != null else ""
	var first_visible_recipe: Dictionary = {}
	for row in recipe_rows:
		var recipe: Dictionary = row["recipe"]
		var matches_station := String(recipe.get("station", "")) == crafting_station
		var matches_search := String(recipe["name"]).to_lower().contains(search_text)
		var recipe_button: Button = row["button"]
		recipe_button.visible = matches_station and matches_search
		recipe_button.button_pressed = recipe == selected_recipe
		if recipe_button.visible and first_visible_recipe.is_empty():
			first_visible_recipe = recipe
	if selected_recipe.is_empty() or String(selected_recipe.get("station", "")) != crafting_station or not String(selected_recipe.get("name", "")).to_lower().contains(search_text):
		selected_recipe = first_visible_recipe
	if selected_recipe.is_empty():
		recipe_preview_name.text = "Kein Rezept gefunden"
		recipe_preview_cost.text = ""
		craft_button.disabled = true
		return
	recipe_preview_name.text = String(selected_recipe["name"])
	var parts := PackedStringArray()
	var can_afford := true
	for item_id in selected_recipe["cost"]:
		var item_name := String(ITEM_INFO[String(item_id)]["name"])
		var have := count_item(String(item_id))
		var required := int(selected_recipe["cost"][item_id])
		parts.append("%s  %d/%d" % [item_name, have, required])
		can_afford = can_afford and have >= required
	recipe_preview_cost.text = "Benötigt: " + " · ".join(parts)
	recipe_preview_cost.add_theme_color_override("font_color", Color(0.6, 0.85, 0.55) if can_afford else Color(0.85, 0.5, 0.45))
	craft_button.disabled = not _can_craft(selected_recipe)

func set_map_expanded(expanded: bool) -> void:
	if inventory_button == null:
		return
	inventory_button.offset_top = 390.0 if expanded else 222.0
	inventory_button.offset_bottom = 426.0 if expanded else 258.0

# ------------------------------------------------------------------ Öffnen / Schließen
func _input(event: InputEvent) -> void:
	if not _built:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_I or event.keycode == KEY_TAB):
		if is_open:
			close()
			get_viewport().set_input_as_handled()
		elif player.alive and not main.get_tree().paused:
			open()
			get_viewport().set_input_as_handled()

func open() -> void:
	if is_open or not player.alive or main.get_tree().paused:
		return
	is_open = true
	selected_slot = -1
	message_label.modulate.a = 0.0
	inventory_root.show()
	refresh()
	_fit_panel()
	call_deferred("_fit_panel")
	main.get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_station(station: String, position: Vector3) -> void:
	crafting_station = station
	station_position = position
	selected_recipe = {}
	if craft_search != null:
		craft_search.clear()
	open()

func close() -> void:
	if not is_open:
		return
	is_open = false
	selected_slot = -1
	crafting_station = ""
	station_position = Vector3.ZERO
	selected_recipe = {}
	inventory_root.hide()
	main.get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_touch else Input.MOUSE_MODE_CAPTURED

# ------------------------------------------------------------------ Slot-Widget
## Ein Inventar-Slot: zeichnet Icon, Name, Menge, Munitionsbalken und kann gezogen / abgelegt werden.
class Slot extends Control:
	signal clicked(index: int)
	signal activated(index: int)
	signal secondary(index: int)
	signal dropped(from_index: int, to_index: int)

	var index := 0
	var info := {}
	var badge := ""
	var selected := false
	var active := false
	var hovered := false
	var plain := false            # nur Icon (für die Detailansicht)
	var pressed_here := false
	var double_hit := false
	var _box := StyleBoxFlat.new()

	func _init(slot_index := 0, slot_size := 76.0) -> void:
		index = slot_index
		custom_minimum_size = Vector2(slot_size, slot_size)
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		hovered = on
		queue_redraw()

	func set_info(new_info: Dictionary, new_badge: String, is_selected: bool, is_active: bool) -> void:
		info = new_info
		badge = new_badge
		selected = is_selected
		active = is_active
		modulate.a = 1.0
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				pressed_here = true
				double_hit = event.double_click
				modulate.a = 1.0
			else:
				if pressed_here and Rect2(Vector2.ZERO, size).has_point(event.position):
					if double_hit:
						activated.emit(index)
					else:
						clicked.emit(index)
				pressed_here = false
				double_hit = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			secondary.emit(index)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if String(info.get("entry", "")) == "":
			return null
		pressed_here = false
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ghost = get_script().new(index, size.x)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.size = size
		ghost.position = -size * 0.5
		ghost.set_info(info, badge, true, false)
		ghost.modulate.a = 0.85
		holder.add_child(ghost)
		set_drag_preview(holder)
		modulate.a = 0.35
		return {"inv_slot": index}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("inv_slot")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		dropped.emit(int(data["inv_slot"]), index)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			pressed_here = false
			hovered = false
			modulate.a = 1.0
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var entry := String(info.get("entry", ""))
		var accent: Color = info.get("color", Color(0.4, 0.4, 0.36))
		var bg := Color(0.075, 0.08, 0.07)
		var border := Color(0.27, 0.27, 0.24)
		var border_w := 2
		if entry != "":
			bg = Color(0.1, 0.105, 0.095).lerp(accent, 0.14)
			border = accent.darkened(0.3)
		if hovered and not plain:
			bg = bg.lightened(0.12)
			border = border.lightened(0.25)
		if active:
			border = Color(0.5, 0.9, 0.45)
			border_w = 3
		if selected:
			border = Color(1.0, 0.84, 0.4)
			border_w = 3
		_box.bg_color = bg
		_box.border_color = border
		_box.set_border_width_all(border_w)
		_box.set_corner_radius_all(6)
		draw_style_box(_box, rect)
		if plain:
			if entry != "":
				_draw_icon(String(info.get("icon", "")), Rect2(Vector2(9, 9), size - Vector2(18, 18)))
			return
		if entry == "":
			if badge != "":
				_text(Vector2(0, size.y * 0.5 + 8), badge, 22, Color(1, 1, 1, 0.14), HORIZONTAL_ALIGNMENT_CENTER, size.x)
			return
		var icon_size := size.x * 0.53
		_draw_icon(String(info.get("icon", "")), Rect2(Vector2((size.x - icon_size) * 0.5, size.y * 0.18), Vector2(icon_size, icon_size)))
		_text(Vector2(0, size.y - 11), String(info.get("short", "")), 11, Color(0.9, 0.88, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		var count := String(info.get("count", ""))
		if count != "":
			_text(Vector2(0, 15), count, 12, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6)
		if badge != "":
			_text(Vector2(6, 15), badge, 13, Color(1.0, 0.84, 0.4))
		var frac := float(info.get("frac", -1.0))
		if frac >= 0.0:
			var bar := Rect2(Vector2(6, size.y - 7), Vector2(size.x - 12, 3))
			draw_rect(bar, Color(0, 0, 0, 0.6))
			var fill := Color(0.5, 0.85, 0.4) if frac > 0.3 else Color(0.9, 0.3, 0.2)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)), fill)

	func _text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, pos, text, align, width, font_size, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, align, width, font_size, color)

	# --- Icons (Einheitsquadrat 0..1 wird auf das Rechteck gelegt)
	func _pt(r: Rect2, x: float, y: float) -> Vector2:
		return r.position + Vector2(x, y) * r.size

	func _r(r: Rect2, x1: float, y1: float, x2: float, y2: float, c: Color) -> void:
		draw_rect(Rect2(_pt(r, x1, y1), Vector2(x2 - x1, y2 - y1) * r.size), c)

	func _l(r: Rect2, x1: float, y1: float, x2: float, y2: float, c: Color, w: float) -> void:
		draw_line(_pt(r, x1, y1), _pt(r, x2, y2), c, w)

	func _poly(r: Rect2, pts: Array, c: Color) -> void:
		var packed := PackedVector2Array()
		for p in pts:
			packed.append(_pt(r, float(p[0]), float(p[1])))
		draw_colored_polygon(packed, c)

	func _draw_icon(icon: String, r: Rect2) -> void:
		var steel := Color(0.74, 0.78, 0.8)
		var dark := Color(0.34, 0.36, 0.4)
		var wood := Color(0.55, 0.36, 0.18)
		match icon:
			"axe":
				_l(r, 0.22, 0.95, 0.68, 0.14, wood, 5.0)
				_poly(r, [[0.48, 0.12], [0.88, 0.0], [0.98, 0.4], [0.64, 0.36]], steel)
			"pickaxe":
				_l(r, 0.5, 0.93, 0.5, 0.33, wood, 5.0)
				_l(r, 0.2, 0.24, 0.8, 0.24, wood, 5.0)
				_l(r, 0.2, 0.24, 0.1, 0.08, wood, 4.0)
				_l(r, 0.8, 0.24, 0.9, 0.08, wood, 4.0)
			"shovel":
				_l(r, 0.48, 0.94, 0.58, 0.24, wood, 5.0)
				_poly(r, [[0.38, 0.18], [0.78, 0.14], [0.84, 0.39], [0.48, 0.45]], steel)
			"ladder":
				_l(r, 0.25, 0.95, 0.25, 0.05, wood, 4.0)
				_l(r, 0.75, 0.95, 0.75, 0.05, wood, 4.0)
				for rung in 4:
					var y := 0.2 + rung * 0.2
					_l(r, 0.25, y, 0.75, y, wood, 4.0)
			"wood":
				for row in 3:
					var y := 0.68 - row * 0.3
					_r(r, 0.06, y, 0.82, y + 0.28, Color(0.42, 0.27, 0.13))
					draw_circle(_pt(r, 0.82, y + 0.14), r.size.y * 0.14, Color(0.8, 0.62, 0.38))
					draw_arc(_pt(r, 0.82, y + 0.14), r.size.y * 0.07, 0.0, TAU, 12, Color(0.55, 0.38, 0.2), 1.5)
			"workbench":
				_r(r, 0.04, 0.3, 0.96, 0.46, wood.lightened(0.2))
				_r(r, 0.12, 0.46, 0.2, 0.92, wood)
				_r(r, 0.8, 0.46, 0.88, 0.92, wood)
				_r(r, 0.2, 0.68, 0.8, 0.76, wood.darkened(0.15))
				_r(r, 0.3, 0.12, 0.5, 0.3, steel)
				_l(r, 0.62, 0.3, 0.7, 0.08, wood, 3.0)
			"iron_ore":
				_poly(r, [[0.12, 0.72], [0.2, 0.32], [0.45, 0.12], [0.8, 0.28], [0.92, 0.68], [0.68, 0.9], [0.28, 0.88]], dark.lightened(0.35))
				_l(r, 0.28, 0.42, 0.5, 0.25, steel, 2.0)
			"stone":
				_poly(r, [[0.08, 0.74], [0.23, 0.36], [0.46, 0.2], [0.78, 0.31], [0.94, 0.72], [0.68, 0.88], [0.28, 0.9]], dark.lightened(0.2))
			"iron_ingot":
				_poly(r, [[0.12, 0.7], [0.22, 0.36], [0.78, 0.36], [0.9, 0.7], [0.72, 0.84], [0.28, 0.84]], steel)
				_l(r, 0.26, 0.43, 0.72, 0.43, Color.WHITE, 2.0)
			"anvil":
				_r(r, 0.36, 0.38, 0.64, 0.83, dark)
				_poly(r, [[0.12, 0.23], [0.78, 0.23], [0.98, 0.08], [0.98, 0.35], [0.72, 0.48], [0.28, 0.48]], steel)
			"furnace":
				_r(r, 0.16, 0.08, 0.84, 0.9, dark.lightened(0.18))
				_r(r, 0.3, 0.42, 0.7, 0.78, dark)
				_poly(r, [[0.38, 0.72], [0.43, 0.53], [0.52, 0.65], [0.6, 0.48], [0.66, 0.72]], Color(1.0, 0.38, 0.08))
			"fishing_rod":
				_l(r, 0.2, 0.88, 0.76, 0.12, wood, 3.0)
				_l(r, 0.76, 0.12, 0.91, 0.05, steel, 1.5)
				_l(r, 0.91, 0.05, 0.9, 0.32, steel, 1.0)
			"armor":
				_poly(r, [[0.22, 0.15], [0.38, 0.25], [0.5, 0.2], [0.62, 0.25], [0.78, 0.15], [0.9, 0.32], [0.74, 0.55], [0.68, 0.9], [0.32, 0.9], [0.26, 0.55], [0.1, 0.32]], steel)
			"shotgun":
				_l(r, 0.04, 0.38, 0.76, 0.38, steel, 3.0)
				_l(r, 0.04, 0.5, 0.76, 0.5, steel, 3.0)
				_r(r, 0.34, 0.54, 0.56, 0.64, wood)
				_poly(r, [[0.62, 0.32], [0.98, 0.42], [0.9, 0.72], [0.62, 0.58]], wood)
			"pistol":
				_r(r, 0.1, 0.26, 0.86, 0.5, steel)
				_poly(r, [[0.52, 0.5], [0.8, 0.5], [0.72, 0.9], [0.46, 0.9]], wood)
				_r(r, 0.18, 0.5, 0.4, 0.58, dark)
			"rifle":
				_r(r, 0.02, 0.4, 0.8, 0.5, dark)
				_r(r, 0.3, 0.32, 0.62, 0.42, steel)
				_r(r, 0.4, 0.5, 0.5, 0.8, steel)
				_poly(r, [[0.7, 0.34], [0.98, 0.42], [0.92, 0.72], [0.7, 0.56]], wood)
			"minigun":
				_r(r, 0.42, 0.28, 0.76, 0.64, dark)
				_l(r, 0.04, 0.36, 0.42, 0.36, steel, 3.0)
				_l(r, 0.04, 0.46, 0.42, 0.46, steel, 3.0)
				_l(r, 0.04, 0.56, 0.42, 0.56, steel, 3.0)
				_r(r, 0.76, 0.42, 0.96, 0.52, wood)
			_:
				_r(r, 0.2, 0.2, 0.8, 0.8, dark)
