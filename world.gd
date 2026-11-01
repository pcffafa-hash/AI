extends Node3D
## Baut die große Spielwelt von SILENT HEAD: Boden, Straße, Wald, Gebäude, Deko, Himmel.

const CarScript = preload("res://car.gd")

## Spieler hat ein Objekt benutzt und etwas bekommen (kind: "heal", "ammo", "fuel", "hp").
signal item_given(kind: String, amount: int)
## Eine Notiz / ein Fund wurde gelesen (id = Index in NOTES).
signal lore_found(id: int, text: String)
signal story_complete
signal power_restored
signal chicken_clucked

const HALF := 200.0
const ROAD_W := 7.0
const SCENE_POS := Vector3(0, 0, -150)
const START_POS := Vector3(0, 0, 140)
## x, z, Drehung der Hütten
const CABINS := [Vector3(-30, 75, 1.82), Vector3(34, -10, -1.77), Vector3(-38, -85, 1.42)]
const NOTES := [
	"Betriebsbuch der Sägemühle: „Seit Dienstag ist es zu still. Kein Specht, kein Wind. Die Säge läuft – und ich höre sie nicht.“",
	"Zettel an der Tür: „Antworte nie, wenn dich jemand beim Namen ruft. Auch nicht, wenn es klingt wie deine Mutter.“",
	"Tagebuch: „Er hat keinen Mund – und trotzdem hat er gerade meinen Namen gesagt. Mit meiner Stimme.“",
	"Tobis Notizblock: „Dreimal Silent Head sagen, haha. Jonas hat gefilmt. Das Video ist leer. Nur Atmen.“",
	"Jägernotiz: „Schrot hilft. Zielt auf den Kopf. Und lauf quer, wenn er tief Luft holt – nie geradeaus.“",
	"Zeitungsausschnitt, 1987: „Sägemühle Vogt: Vorarbeiter Heinrich V. nach Unfall verstummt. Das Sägeblatt zerschmetterte seinen Kiefer. Die Ärzte sprechen von einem Wunder, dass er überlebte. Seither hört man nachts jemanden im Wald atmen.“",
	"Jonas’ Kamera, letzte Aufnahme: Nebel, schweres Atmen, dann Tobis Stimme direkt an der Linse, flüsternd: „Er lernt, wie wir klingen. Er sagt nur, was er schon gehört hat.“",
	"Handgeschnitzte Grabtafel: „HEINRICH VOGT 1951–1987. Er hörte zu, bis niemand mehr zuhören wollte.“ Die Erde ist frisch aufgewühlt – von innen.",
	"Polaroid unter einem Stein am Teich: vier Jugendliche am Feuer, hinter ihnen im Nebel eine Gestalt. Auf der Rückseite, in Mias Schrift: „Lärm macht ihn wütend. Licht macht ihn langsam. Merk dir das.“",
	"Autoradio, Rauschen. Dazwischen Jonas, atemlos: „Mia sagt, wir müssen zur Mühle. Der Generator braucht Benzin – im letzten Haus an der Straße steht ein Kanister. Wenn die Lampen brennen, wird er langsamer. Hörst du? Langsamer—“ Dann nur noch Atmen."]
## Welche Notiz in welcher Hütte liegt, und was in deren Kiste steckt.
const CABIN_NOTES := [1, 2, 5]
const CABIN_LOOT := ["heal", "ammo", "fuel"]
const GRAVE_POS := Vector3(-95.0, 0.0, -40.0)
const HINTS := {
	"note": "Lesen", "crate": "Durchsuchen", "corpse": "Durchsuchen",
	"generator": "Generator starten", "campfire": "Am Feuer rasten",
	"radio": "Zuhören", "grave": "Grab untersuchen", "camera": "Aufnahme ansehen",
	"door": "Tür öffnen", "weapon": "Waffe nehmen", "item": "Gegenstand nehmen",
	"tree": "Mit Axt Holz hacken", "workbench": "Werkbank öffnen",
	"anvil": "Amboss benutzen", "furnace": "Schmelzofen benutzen",
	"fish": "Fischen", "log": "Mit Axt Holz sammeln",
	"ladder": "Leiter benutzen oder abbauen"}
const WEAPON_NAMES := {"pistol": "Pistole", "rifle": "Gewehr", "minigun": "Minigun"}
const ITEM_NAMES := {"axe": "Axt", "iron_ore": "Eisenerz", "stone": "Stein"}

var rng := RandomNumberGenerator.new()
var touch := false
var tree_pos: Array = []
var choppable_trees: Array[Dictionary] = []
var forest_chunks: Array = []   # pro Waldkachsel: trunk/cones/center (für Culling)
var tree_version := 0           # +1 sobald ein Baum gefällt wird (Minimap-Cache)
const FOREST_CELL := 50.0
var forest_trunk: MultiMesh
var forest_cones: Array[MultiMesh] = []
var forest_trunk_visual: MultiMeshInstance3D
var forest_cone_visuals: Array[MultiMeshInstance3D] = []
var rock_pos: Array = []
var rock_mines: Array[Dictionary] = []
var rock_multimesh: MultiMesh
var fallen_logs: Array[Dictionary] = []
var dig_sites: Array[Dictionary] = []
var ladders: Array[Dictionary] = []
var blocks: Array = []
var interacts: Array = []
var clearings: Array = []
var lamp_pos: Array = []
var lamp_lights: Array = []
var flick: Array = []
var fire_light: OmniLight3D
var car
var chickens: Array[Dictionary] = []
var fishing_spots: Array = []
var fish_models: Array[Dictionary] = []
var fish_mesh: ArrayMesh
var fish_material: StandardMaterial3D
var phys: Node3D
var saw: Node3D
var sky_root: Node3D
var moon: MeshInstance3D
var moon_mat: StandardMaterial3D
var star_mat: StandardMaterial3D
var dust: CPUParticles3D
var dust_mat: StandardMaterial3D
var t := 0.0
var lamp_t := 0.0
var _lamp_e := -1.0
var tex_cache := {}
var mat_cache := {}
var power_on := false
var fuel := 0
var gen_light: OmniLight3D
var gen_lamp: StandardMaterial3D
var grave_light: OmniLight3D
var lamp_broken: Array = []
var win_flick: Dictionary = {}
var journal: Array = []

# ------------------------------------------------------------------ Helfer
func mat(c: Color, rough := 0.9, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _add_mesh(parent: Node, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, m, pos, rot)

func cyl(parent: Node, top: float, bottom: float, h: float, pos: Vector3, m: Material, seg := 8, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _add_mesh(parent, c, m, pos, rot)

func ball(parent: Node, r: float, pos: Vector3, m: Material, seg := 10) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(2, int(seg * 0.5))
	return _add_mesh(parent, s, m, pos)

## Satteldach: Firstrichtung = lokale x-Achse.
func roof(parent: Node, len_x: float, wid_z: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var p := PrismMesh.new()
	p.size = Vector3(wid_z, h, len_x)
	return _add_mesh(parent, p, m, pos, Vector3(0.0, PI / 2.0, 0.0))

func solid(pos: Vector3, size: Vector3, yaw := 0.0, crash_root: Node3D = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	phys.add_child(sb)
	if crash_root != null:
		sb.add_to_group("breakable_building")
		sb.set_meta("crash_root", crash_root)
	return sb

func solid_cyl(pos: Vector3, r: float, h: float) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	sb.add_child(cs)
	phys.add_child(sb)

func make_mm(mesh: Mesh, m: Material, count: int, colors := false, parent: Node = null, vrange := 0.0, at := Vector3.ZERO, shadow := true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.position = at
	if vrange > 0.0:
		mi.visibility_range_end = vrange
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var par: Node = parent if parent != null else self
	par.add_child(mi)
	return mm

func hidden_tf() -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -80, 0))

func spot_ok(x: float, z: float, pad := 0.0) -> bool:
	if absf(x) < ROAD_W / 2.0 + 1.2 + pad:
		return false
	for c in clearings:
		if Vector2(x - c.x, z - c.y).length() < c.z + pad:
			return false
	return true

func rand_spot(pad := 0.0, margin := 6.0) -> Vector2:
	for k in 40:
		var x := rng.randf_range(-HALF + margin, HALF - margin)
		var z := rng.randf_range(-HALF + margin, HALF - margin)
		if spot_ok(x, z, pad):
			return Vector2(x, z)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	return Vector2(side * rng.randf_range(ROAD_W / 2.0 + 3.0, HALF - margin), rng.randf_range(-HALF + margin, HALF - margin))

func add_interact(kind: String, pos: Vector3, text := "", loot := "") -> void:
	var marker = null
	if kind != "corpse":
		var col := Color(0.4, 1.0, 0.55)
		match kind:
			"note": col = Color(1.0, 0.9, 0.35)
			"generator": col = Color(1.0, 0.55, 0.15)
			"campfire": col = Color(1.0, 0.4, 0.2)
			"radio": col = Color(0.4, 0.75, 1.0)
			"grave": col = Color(0.75, 0.6, 1.0)
			"camera": col = Color(1.0, 0.3, 0.3)
			"weapon": col = Color(0.45, 0.85, 1.0)
			"door": col = Color(0.9, 0.65, 0.35)
		var mk := ball(self, 0.07, pos + Vector3(0, 1.15, 0), mat(col, 1.0, true), 6)
		mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker = mk
	interacts.append({"x": pos.x, "z": pos.z, "done": false, "kind": kind, "text": text, "loot": loot, "marker": marker, "y0": pos.y + 1.15, "ph": pos.x + pos.z})

## Nächstes unerledigtes Objekt in Reichweite (leeres Dictionary, wenn keins).
func nearest(pp: Vector3, radius := 2.4) -> Dictionary:
	var best := {}
	var bd := radius * radius
	for it in interacts:
		if it["done"]:
			continue
		var dx: float = it["x"] - pp.x
		var dz: float = it["z"] - pp.z
		var d := dx * dx + dz * dz
		var interact_radius := 3.6 if it.get("kind", "") == "door" else radius
		var interact_distance := interact_radius * interact_radius
		if d < interact_distance and (best.is_empty() or d < bd):
			bd = d
			best = it
	for tree_index in choppable_trees.size():
		var tree: Dictionary = choppable_trees[tree_index]
		if tree["chopped"]:
			continue
		var tree_pos_local: Vector3 = tree["position"]
		var dx := tree_pos_local.x - pp.x
		var dz := tree_pos_local.z - pp.z
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d
			best = {"kind": "tree", "tree_index": tree_index, "x": tree_pos_local.x, "z": tree_pos_local.z, "done": false, "marker": null}
	for rock_index in rock_mines.size():
		var deposit: Dictionary = rock_mines[rock_index]
		if deposit["mined"]:
			continue
		var deposit_pos: Vector3 = deposit["position"]
		var dx := deposit_pos.x - pp.x
		var dz := deposit_pos.z - pp.z
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d
			best = {"kind": "rock", "rock_index": rock_index, "x": deposit_pos.x, "z": deposit_pos.z, "done": false, "marker": null}
	return best

func hint_for(it: Dictionary) -> String:
	if it.get("kind", "") == "weapon":
		return String(WEAPON_NAMES.get(String(it.get("loot", "")), "Waffe")) + " nehmen"
	if it.get("kind", "") == "item":
		return String(ITEM_NAMES.get(String(it.get("loot", "")), "Gegenstand")) + " nehmen"
	return HINTS.get(it.get("kind", ""), "Benutzen")

func chop_tree(tree_index: int, player_position := Vector3.ZERO) -> int:
	if tree_index < 0 or tree_index >= choppable_trees.size():
		return 0
	var tree: Dictionary = choppable_trees[tree_index]
	if tree["chopped"]:
		return 0
	var hits := int(tree.get("hits", 0)) + 1
	tree["hits"] = hits
	if hits < 4:
		return 0
	tree["chopped"] = true
	_spawn_falling_tree(tree, tree["position"], player_position)
	var chunk: Dictionary = forest_chunks[int(tree["chunk"])]
	var slot: int = int(tree["slot"])
	(chunk["trunk"] as MultiMesh).set_instance_transform(slot, hidden_tf())
	for cone in chunk["cones"]:
		(cone as MultiMesh).set_instance_transform(slot, hidden_tf())
	var tree_body: StaticBody3D = tree["body"]
	tree_body.queue_free()
	var pos: Vector3 = tree["position"]
	var stump := CylinderMesh.new()
	stump.top_radius = 0.3
	stump.bottom_radius = 0.38
	stump.height = 0.35
	stump.radial_segments = 8
	_add_mesh(self, stump, tmat("bark", Color(0.55, 0.39, 0.24), 0.65), Vector3(pos.x, 0.175, pos.z))
	if tree_index < tree_pos.size():
		tree_pos[tree_index] = Vector2(9999.0, 9999.0)
		tree_version += 1
	return 2

func tree_chop_hits(tree_index: int) -> int:
	if tree_index < 0 or tree_index >= choppable_trees.size():
		return 0
	return int(choppable_trees[tree_index].get("hits", 0))

func hit_log(log_index: int) -> int:
	if log_index < 0 or log_index >= fallen_logs.size():
		return 0
	var log: Dictionary = fallen_logs[log_index]
	if bool(log["chopped"]):
		return 0
	log["hits"] = int(log["hits"]) + 1
	if int(log["hits"]) < 3:
		fallen_logs[log_index] = log
		return -int(log["hits"])
	log["chopped"] = true
	(log["mesh"] as Node3D).hide()
	(log["body"] as StaticBody3D).queue_free()
	var interact_index: int = int(log["interact_index"])
	var interaction: Dictionary = interacts[interact_index]
	interaction["done"] = true
	if interaction["marker"] != null:
		interaction["marker"].hide()
	fallen_logs[log_index] = log
	return 2

func _spawn_falling_tree(tree: Dictionary, tree_position: Vector3, player_position: Vector3) -> void:
	var falling_tree := Node3D.new()
	falling_tree.position = tree_position
	var away := Vector2(tree_position.x - player_position.x, tree_position.z - player_position.z)
	if away.length_squared() < 0.001:
		away = Vector2.UP
	falling_tree.rotation.y = atan2(away.x, away.y)
	add_child(falling_tree)
	var chunk: Dictionary = forest_chunks[int(tree["chunk"])]
	var slot: int = int(tree["slot"])
	var center: Vector3 = chunk["center"]
	var trunk_mm: MultiMesh = chunk["trunk"]
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mm.mesh
	trunk.material_override = _tinted_forest_material((chunk["trunk_vis"] as MultiMeshInstance3D).material_override as StandardMaterial3D, trunk_mm.get_instance_color(slot))
	var trunk_transform := trunk_mm.get_instance_transform(slot)
	trunk_transform.origin += center - tree_position
	trunk.transform = trunk_transform
	falling_tree.add_child(trunk)
	var cone_mms: Array = chunk["cones"]
	var cone_vis: Array = chunk["cone_vis"]
	for cone_index in cone_mms.size():
		var cmm: MultiMesh = cone_mms[cone_index]
		var cone := MeshInstance3D.new()
		cone.mesh = cmm.mesh
		cone.material_override = _tinted_forest_material((cone_vis[cone_index] as MultiMeshInstance3D).material_override as StandardMaterial3D, cmm.get_instance_color(slot))
		var cone_transform := cmm.get_instance_transform(slot)
		cone_transform.origin += center - tree_position
		cone.transform = cone_transform
		falling_tree.add_child(cone)
	var fall_tween := create_tween()
	fall_tween.tween_property(falling_tree, "rotation:x", PI / 2.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

func _tinted_forest_material(base: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var tinted := base.duplicate() as StandardMaterial3D
	tinted.albedo_color = tinted.albedo_color * tint
	return tinted

func build_workbench(pos: Vector3, yaw: float) -> void:
	var workbench := Node3D.new()
	workbench.position = Vector3(pos.x, 0.0, pos.z)
	workbench.rotation.y = yaw
	add_child(workbench)
	var wood := tmat("planks", Color(0.48, 0.31, 0.18), 0.5)
	box(workbench, Vector3(1.5, 0.16, 0.8), Vector3(0, 0.85, 0), wood)
	for x in [-0.62, 0.62]:
		for z in [-0.28, 0.28]:
			box(workbench, Vector3(0.12, 0.82, 0.12), Vector3(x, 0.42, z), wood)
	solid(workbench.global_position + workbench.transform.basis * Vector3(0, 0.85, 0), Vector3(1.5, 0.16, 0.8), yaw)
	add_interact("workbench", workbench.position)

func build_station(kind: String, pos: Vector3) -> void:
	var station := Node3D.new()
	station.position = Vector3(pos.x, 0.0, pos.z)
	add_child(station)
	if kind == "anvil":
		var iron := tmat("metal", Color(0.2, 0.22, 0.24), 0.75, 0.45)
		for x in [-0.3, 0.3]:
			box(station, Vector3(0.16, 0.62, 0.18), Vector3(x, 0.31, 0), iron)
		box(station, Vector3(0.78, 0.28, 0.48), Vector3(0, 0.72, 0), iron)
		box(station, Vector3(1.0, 0.18, 0.62), Vector3(0, 0.95, 0), iron)
		box(station, Vector3(0.28, 0.13, 0.38), Vector3(0.58, 0.96, 0), iron)
		solid(station.position + Vector3(0, 0.55, 0), Vector3(1.0, 1.1, 0.7))
	else:
		var stone_mat := tmat("stone", Color(0.3, 0.3, 0.29), 0.9)
		var dark := mat(Color(0.035, 0.03, 0.025), 1.0)
		var ember := mat(Color(1.0, 0.25, 0.035), 0.6, true)
		box(station, Vector3(1.1, 1.25, 1.0), Vector3(0, 0.625, 0), stone_mat)
		box(station, Vector3(0.58, 0.48, 0.06), Vector3(0, 0.42, -0.53), dark)
		box(station, Vector3(0.32, 0.18, 0.035), Vector3(0, 0.3, -0.57), ember)
		var fire := OmniLight3D.new()
		fire.light_color = Color(1.0, 0.24, 0.06)
		fire.light_energy = 0.65
		fire.omni_range = 4.0
		fire.position = Vector3(0, 0.45, -0.65)
		station.add_child(fire)
		solid(station.position + Vector3(0, 0.62, 0), Vector3(1.2, 1.25, 1.1))
	add_interact(kind, station.position)

func lore_total() -> int:
	return NOTES.size()

## Spieler benutzt ein Objekt. Rückgabe: {"ok", "msg", "text", "give"}.
## give = {"heal": n, "ammo": n, "fuel": n, "hp": n} – Main verteilt das an den Spieler.
func use(it: Dictionary) -> Dictionary:
	var res := {"ok": false, "msg": "", "text": "", "give": {}}
	if it.is_empty() or it["done"]:
		return res
	var kind: String = it["kind"]
	match kind:
		"door":
			var door = it.get("node")
			if not is_instance_valid(door):
				return res
			door.collision_layer = 0
			door.collision_mask = 0
			var tween := create_tween()
			tween.tween_property(door, "rotation:y", PI / 2.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			res["msg"] = "Die Hüttentür schwingt auf."
		"weapon":
			var weapon_id: String = String(it["loot"])
			res["give"] = {"weapon": weapon_id}
			res["msg"] = WEAPON_NAMES.get(weapon_id, "Waffe") + " aufgenommen"
		"fish":
			res["give"] = {"item": "fish"}
			res["msg"] = "Fisch gefangen"
		"ladder":
			var ladder_index: int = int(it.get("ladder_index", -1))
			if ladder_index >= 0 and ladder_index < ladders.size():
				var ladder_data: Dictionary = ladders[ladder_index]
				ladder_data["removed"] = true
				(ladder_data["node"] as Node3D).queue_free()
				ladders[ladder_index] = ladder_data
				res["give"] = {"item": "ladder"}
				res["msg"] = "Leiter aufgenommen"
		"item":
			var item_id: String = String(it["loot"])
			res["give"] = {"item": item_id}
			res["msg"] = ITEM_NAMES.get(item_id, "Gegenstand") + " aufgenommen"
		"generator":
			if fuel < 1:
				res["msg"] = "Der Tank ist leer. Irgendwo hier muss ein Kanister stehen…"
				return res
			fuel -= 1
			_power_on()
			res["msg"] = "Der Generator springt an. Licht flutet die Straße."
		"campfire":
			res["give"] = {"hp": 35}
			res["msg"] = "Du wärmst dich am Feuer. Für einen Moment ist es fast still."
		"crate", "corpse":
			match String(it["loot"]):
				"heal":
					res["give"] = {"heal": 1}
					res["msg"] = "+1 Verbandskasten"
				"ammo":
					res["give"] = {"ammo": 6}
					res["msg"] = "+6 Schrotpatronen"
				"fuel":
					fuel += 1
					res["give"] = {"fuel": 1}
					res["msg"] = "Benzinkanister gefunden – der Generator an der Mühle braucht ihn."
				_:
					res["msg"] = "Nichts Brauchbares."
			if kind == "corpse":
				res["text"] = it["text"]
		_:
			res["text"] = it["text"]
			var idx := NOTES.find(it["text"])
			if idx >= 0 and not journal.has(idx):
				journal.append(idx)
				res["msg"] = "Fund %d/%d" % [journal.size(), NOTES.size()]
				lore_found.emit(idx, it["text"])
				if journal.size() >= NOTES.size():
					story_complete.emit()
	it["done"] = true
	if it["marker"] != null:
		it["marker"].visible = false
	res["ok"] = true
	for k in res["give"]:
		item_given.emit(k, res["give"][k])
	return res

func _power_on() -> void:
	power_on = true
	for p in lamp_broken:
		lamp_pos.append(p)
	lamp_broken.clear()
	for f in flick:
		if f.get("lamp", false):
			f["mode"] = 0
	if not win_flick.is_empty():
		win_flick["mode"] = 0
		win_flick["base"] = Color(1.0, 0.85, 0.5)
	if gen_light != null:
		gen_light.visible = true
	if gen_lamp != null:
		gen_lamp.albedo_color = Color(0.2, 1.0, 0.3)
	power_restored.emit()

# ------------------------------------------------------------------ Texturen
@warning_ignore("integer_division")
func _gen_tex(kind: String) -> ImageTexture:
	if tex_cache.has(kind):
		return tex_cache[kind]
	var S := 64 if touch else 128
	var pw := floori(float(S) / 8.0)
	var f1 := FastNoiseLite.new()
	f1.seed = 11 + kind.length() * 7
	f1.frequency = 5.0 / float(S)
	f1.fractal_octaves = 3
	var f2 := FastNoiseLite.new()
	f2.seed = 97 + kind.length() * 3
	f2.frequency = 22.0 / float(S)
	var a: Image = f1.get_seamless_image(S, S)
	var b: Image = f2.get_seamless_image(S, S)
	var img := Image.create_empty(S, S, true, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var n1: float = a.get_pixel(x, y).r
			var n2: float = b.get_pixel(x, y).r
			var c := Color.WHITE
			match kind:
				"planks":
					var pl := floori(float(x) / float(pw))
					var lx := x % pw
					var grain: float = a.get_pixel(x, (pl * 17) % S).r
					var v := 0.55 + 0.3 * grain + 0.14 * n2 + 0.05 * float((pl * 37) % 7)
					if lx == 0:
						v *= 0.35
					elif lx == pw - 1:
						v *= 0.8
					if (y + pl * 29) % floori(float(S) / 2.0) < 2:
						v *= 0.45
					c = Color(v, v * 0.92, v * 0.8)
				"shingles":
					var row := y / pw
					var off := (pw / 2) if row % 2 == 1 else 0
					var si := ((x + off) / pw) % 8
					var sx := (x + off) % pw
					var ly := y % pw
					var v := 0.5 + 0.28 * float((row * 53 + si * 31) % 9) / 9.0 + 0.18 * n2
					v *= 0.7 + 0.3 * float(ly) / float(pw)
					if ly >= pw - 2:
						v *= 0.4
					if sx == 0:
						v *= 0.55
					c = Color(v, v, v * 1.02)
				"bark":
					var ridge := sin(float(x) / float(S) * TAU * 8.0 + n1 * 4.0)
					var v := 0.5 + 0.25 * (ridge * 0.5 + 0.5) + 0.2 * n2
					if ridge < -0.85:
						v *= 0.55
					c = Color(v, v * 0.9, v * 0.8)
				"rock":
					var v := 0.62 + 0.3 * n1 + 0.1 * n2
					if absf(n2 - 0.5) < 0.018:
						v *= 0.55
					c = Color(v, v, v * 1.03)
				"concrete":
					var v := 0.66 + 0.2 * n2 + 0.1 * n1
					if (x * 7 + y * 13) % 23 == 0:
						v *= 0.72
					if y % pw == 0:
						v *= 0.85
					c = Color(v, v, v * 0.97)
				"metal":
					var sc := float((y * 131) % 17) / 17.0
					var v := 0.58 + 0.12 * sc + 0.2 * n2
					c = Color(v * 0.95, v, v * 1.05)
				"dirt":
					var v := 0.5 + 0.4 * n1 + 0.2 * n2
					c = Color(v, v * 0.8, v * 0.62)
				"needles":
					var v := 0.55 + 0.35 * n2 + 0.1 * n1
					if (x + y * 2) % 5 == 0:
						v += 0.12
					c = Color(v * 0.85, v, v * 0.8)
				"cloth":
					var w := sin(float(x) / float(S) * TAU * 16.0) * sin(float(y) / float(S) * TAU * 16.0)
					var v := 0.72 + 0.12 * w + 0.1 * n2
					c = Color(v, v, v * 0.95)
				_:
					c = Color(n1, n1, n1)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	tex_cache[kind] = tx
	return tx

## Texturiertes Material (triplanar: Muster pro Meter, egal wie das Mesh skaliert ist).
func tmat(kind: String, tint := Color.WHITE, scale := 0.5, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [kind, tint.to_html(), scale, rough]
	if mat_cache.has(key):
		return mat_cache[key]
	var m := mat(tint, rough)
	m.albedo_texture = _gen_tex(kind)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat_cache[key] = m
	return m

## Wie tmat, aber mit Instanzfarben (für MultiMesh: Bäume, Felsen, Büsche).
func vmat(kind: String, scale := 0.7, rough := 0.9) -> StandardMaterial3D:
	var m := mat(Color.WHITE, rough)
	m.albedo_texture = _gen_tex(kind)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.vertex_color_use_as_albedo = true
	return m

func _normal_tex(freq: float, bump := 4.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 3
	var tx := NoiseTexture2D.new()
	tx.noise = n
	tx.as_normal_map = true
	tx.bump_strength = bump
	tx.seamless = true
	tx.width = 256
	tx.height = 256
	return tx

func _noise_tex(freq: float, cols: Array) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / float(cols.size() - 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	var tx := NoiseTexture2D.new()
	tx.noise = n
	tx.color_ramp = g
	tx.width = 512
	tx.height = 512
	tx.seamless = true
	return tx

# ------------------------------------------------------------------ Aufbau
func build(is_touch: bool) -> void:
	touch = is_touch
	rng.seed = 7
	phys = Node3D.new()
	add_child(phys)
	clearings = [
		Vector3(SCENE_POS.x, SCENE_POS.z, 13.0),
		Vector3(START_POS.x, START_POS.z, 7.0),
		Vector3(-28.0, SCENE_POS.z + 4.0, 14.0),
		Vector3(50.0, -95.0, 11.0),
		Vector3(55.0, 35.0, 15.0),
		Vector3(-75.0, 15.0, 7.0),
		Vector3(5.4, 98.0, 5.0),
		Vector3(GRAVE_POS.x, GRAVE_POS.z, 7.0)]
	for c in CABINS:
		clearings.append(Vector3(c.x, c.y, 8.0))
	_ground()
	_clearing_patches()
	_road()
	_roadblocks()
	_forest()
	_dead_trees()
	_rocks()
	_bushes()
	_logs()
	_fishing_pools()
	_pond()
	_grass()
	_glowshrooms()
	_lamps()
	_mill()
	for i in CABINS.size():
		var c: Vector3 = CABINS[i]
		_cabin(c.x, c.y, c.z, CABIN_NOTES[i], CABIN_LOOT[i])
	_camp()
	_tower()
	_grave()
	_car()
	_fence()
	_blood()
	_crime_scene()
	_sky()
	_particles()

func _ground() -> void:
	var gm := mat(Color.WHITE)
	gm.albedo_texture = _noise_tex(0.03, [Color(0.09, 0.19, 0.07), Color(0.2, 0.34, 0.11), Color(0.28, 0.27, 0.13), Color(0.14, 0.26, 0.09)])
	gm.uv1_scale = Vector3(14, 14, 1)
	gm.normal_enabled = true
	gm.normal_texture = _normal_tex(0.06, 5.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0 + 80.0, HALF * 2.0 + 80.0)
	ground.mesh = pm
	ground.material_override = gm
	add_child(ground)

## Festgetretene Erde unter jeder Lichtung.
func _clearing_patches() -> void:
	var dirt := tmat("dirt", Color(0.5, 0.38, 0.26), 0.25, 1.0)
	for c in clearings:
		var d := cyl(self, c.z * 0.85, c.z * 0.85, 0.004, Vector3(c.x, 0.008, c.y), dirt, 20)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _road_texture() -> ImageTexture:
	var img := Image.create_empty(64, 256, true, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 64:
			var v := 0.17 + rng.randf() * 0.06
			img.set_pixel(x, y, Color(v, v, v + 0.01))
	for k in 26:
		var cx := rng.randi_range(0, 63)
		var cy := rng.randi_range(0, 255)
		var r := rng.randi_range(3, 8)
		var sh := rng.randf_range(0.09, 0.14)
		for yy in range(cy - r, cy + r):
			for xx in range(cx - r, cx + r):
				if Vector2(xx - cx, yy - cy).length() < r:
					img.set_pixel(posmod(xx, 64), posmod(yy, 256), Color(sh, sh, sh + 0.01))
	for k in 9:
		var x := rng.randi_range(4, 59)
		var y := rng.randi_range(0, 255)
		for st in rng.randi_range(25, 70):
			img.set_pixel(posmod(x, 64), posmod(y, 256), Color(0.05, 0.05, 0.06))
			x += rng.randi_range(-1, 1)
			y += 1
	for y in 256:
		for x in range(4, 6):
			if rng.randf() > 0.25:
				img.set_pixel(x, y, Color(0.7, 0.7, 0.66))
		for x in range(58, 60):
			if rng.randf() > 0.25:
				img.set_pixel(x, y, Color(0.7, 0.7, 0.66))
		if y < 110:
			for x in range(31, 33):
				img.set_pixel(x, y, Color(0.8, 0.65, 0.2))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _road() -> void:
	var length := HALF * 2.0 + 40.0
	var sm := mat(Color.WHITE, 1.0)
	sm.albedo_texture = _noise_tex(0.08, [Color(0.22, 0.2, 0.16), Color(0.34, 0.31, 0.25), Color(0.18, 0.17, 0.14)])
	sm.uv1_scale = Vector3(1, 40, 1)
	var sh := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(ROAD_W + 3.0, length)
	sh.mesh = spm
	sh.material_override = sm
	sh.position.y = 0.012
	add_child(sh)
	var rm := mat(Color.WHITE, 0.85)
	rm.albedo_texture = _road_texture()
	rm.uv1_scale = Vector3(1, length / (ROAD_W * 4.0), 1)
	var road := MeshInstance3D.new()
	var rpm := PlaneMesh.new()
	rpm.size = Vector2(ROAD_W, length)
	road.mesh = rpm
	road.material_override = rm
	road.position.y = 0.02
	add_child(road)

func _roadblocks() -> void:
	var conc := tmat("concrete", Color(0.75, 0.75, 0.72), 0.45)
	var stripe := mat(Color(0.85, 0.35, 0.05))
	for zs in [-1.0, 1.0]:
		var z: float = zs * (HALF - 4.0)
		for k in 4:
			var x := -3.2 + k * 2.15
			box(self, Vector3(2.0, 1.0, 0.8), Vector3(x, 0.5, z), conc)
			box(self, Vector3(2.0, 0.12, 0.82), Vector3(x, 1.02, z), stripe)
		solid(Vector3(0, 1.0, z), Vector3(ROAD_W + 2.0, 2.0, 0.9))

func _forest() -> void:
	choppable_trees.clear()
	forest_cones.clear()
	forest_cone_visuals.clear()
	forest_chunks.clear()
	var n_edge := 170 if touch else 260
	var n_in := 380 if touch else 600
	var n := n_edge + n_in
	var cone_defs := [[1.7, 2.7, 1.6], [1.45, 2.4, 2.9], [1.15, 2.15, 4.0], [0.85, 1.9, 5.0]]
	var trunk_c := CylinderMesh.new()
	trunk_c.top_radius = 0.15
	trunk_c.bottom_radius = 0.27
	trunk_c.height = 4.5
	trunk_c.radial_segments = 8
	var vc := vmat("bark", 0.6)
	var vl := vmat("needles", 1.1)
	var cone_meshes: Array[CylinderMesh] = []
	for d in cone_defs:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = d[0]
		cm.height = d[1]
		cm.radial_segments = 9
		cm.rings = 1
		cone_meshes.append(cm)
	var tshape := CylinderShape3D.new()
	tshape.radius = 0.4
	tshape.height = 4.0
	var planned: Array[Dictionary] = []
	var i := 0
	var tries := 0
	while i < n and tries < n * 25:
		tries += 1
		var x := 0.0
		var z := 0.0
		if i < n_edge:
			var band := HALF - 3.0 + rng.randf() * 6.0
			var run := rng.randf_range(-HALF - 6.0, HALF + 6.0)
			var sgn := -1.0 if rng.randf() < 0.5 else 1.0
			if rng.randf() < 0.5:
				x = sgn * band
				z = run
			else:
				z = sgn * band
				x = run
		else:
			var sp := rand_spot(0.8)
			x = sp.x
			z = sp.y
		if not spot_ok(x, z, 0.8):
			continue
		var k := rng.randf_range(0.8, 1.7)
		var hs := rng.randf_range(0.9, 1.25)
		var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * hs, k))
		var trunk_col := Color(0.26, 0.18, 0.11).lerp(Color(0.16, 0.11, 0.08), rng.randf())
		var leaf := Color.from_hsv(rng.randf_range(0.27, 0.4), rng.randf_range(0.5, 0.75), rng.randf_range(0.17, 0.34))
		planned.append({"x": x, "z": z, "k": k, "hs": hs, "bs": bs, "tc": trunk_col, "leaf": leaf})
		var sb := StaticBody3D.new()
		sb.position = Vector3(x, 2.0, z)
		var cs := CollisionShape3D.new()
		cs.shape = tshape
		sb.add_child(cs)
		phys.add_child(sb)
		tree_pos.append(Vector2(x, z))
		choppable_trees.append({"instance": i, "chunk": -1, "slot": -1, "position": Vector3(x, 0.0, z), "body": sb, "chopped": false, "hits": 0})
		i += 1
	# Bäume in 50-m-Kacheln sortieren: Kamera-Culling und Sichtweite greifen dann pro Kachel
	var cells := {}
	var cells_n := int(ceil(HALF * 2.0 / FOREST_CELL))
	for idx in planned.size():
		var pl: Dictionary = planned[idx]
		var key := Vector2i(clampi(int(floor((float(pl["x"]) + HALF) / FOREST_CELL)), 0, cells_n - 1),
			clampi(int(floor((float(pl["z"]) + HALF) / FOREST_CELL)), 0, cells_n - 1))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(idx)
	for key in cells:
		var ids: Array = cells[key]
		var center := Vector3(-HALF + (key.x + 0.5) * FOREST_CELL, 0.0, -HALF + (key.y + 0.5) * FOREST_CELL)
		var tmm: MultiMesh = make_mm(trunk_c, vc, ids.size(), true, null, 140.0, center)
		var tvis := get_child(get_child_count() - 1) as MultiMeshInstance3D
		var cmms: Array[MultiMesh] = []
		var cvis: Array[MultiMeshInstance3D] = []
		for j in 4:
			cmms.append(make_mm(cone_meshes[j], vl, ids.size(), true, null, 140.0, center))
			cvis.append(get_child(get_child_count() - 1) as MultiMeshInstance3D)
		var chunk_id := forest_chunks.size()
		forest_chunks.append({"trunk": tmm, "trunk_vis": tvis, "cones": cmms, "cone_vis": cvis, "center": center})
		for slot in ids.size():
			var tree_index: int = ids[slot]
			var pl: Dictionary = planned[tree_index]
			var lx: float = float(pl["x"]) - center.x
			var lz: float = float(pl["z"]) - center.z
			var k: float = pl["k"]
			var hs: float = pl["hs"]
			var bs: Basis = pl["bs"]
			tmm.set_instance_transform(slot, Transform3D(bs, Vector3(lx, 2.25 * k * hs, lz)))
			tmm.set_instance_color(slot, pl["tc"])
			var leaf: Color = pl["leaf"]
			for j in 4:
				var cd = cone_defs[j]
				cmms[j].set_instance_transform(slot, Transform3D(bs, Vector3(lx, (cd[2] + cd[1] / 2.0) * k * hs, lz)))
				cmms[j].set_instance_color(slot, leaf.lerp(Color(0.05, 0.12, 0.06), j * 0.08))
			choppable_trees[tree_index]["chunk"] = chunk_id
			choppable_trees[tree_index]["slot"] = slot

func _dead_trees() -> void:
	var n := 26 if touch else 44
	var bark := tmat("bark", Color(0.42, 0.38, 0.35), 0.6)
	var tm := CylinderMesh.new()
	tm.top_radius = 0.08
	tm.bottom_radius = 0.25
	tm.height = 5.0
	tm.radial_segments = 6
	var brm := CylinderMesh.new()
	brm.top_radius = 0.0
	brm.bottom_radius = 0.07
	brm.height = 1.6
	brm.radial_segments = 5
	var trunk := make_mm(tm, bark, n)
	var br1 := make_mm(brm, bark, n)
	var br2 := make_mm(brm, bark, n)
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 4.0
	for i in n:
		var sp := rand_spot(1.0)
		var h := rng.randf_range(0.8, 1.3)
		trunk.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, h, 1)), Vector3(sp.x, 2.5 * h, sp.y)))
		for br in [br1, br2]:
			var a := rng.randf() * TAU
			var o := Vector3(cos(a), 0.0, sin(a))
			var perp := Vector3.UP.cross(o).normalized()
			var bb := Basis(perp, rng.randf_range(0.7, 1.1))
			var hy := rng.randf_range(2.6, 4.2) * h
			br.set_instance_transform(i, Transform3D(bb, Vector3(sp.x, hy, sp.y) + (bb * Vector3.UP) * 0.8))
		var sb := StaticBody3D.new()
		sb.position = Vector3(sp.x, 2.0, sp.y)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		sb.add_child(cs)
		phys.add_child(sb)
		tree_pos.append(sp)

func _rocks() -> void:
	rock_mines.clear()
	var n := 60 if touch else 100
	var rsm := SphereMesh.new()
	rsm.radius = 1.0
	rsm.height = 2.0
	rsm.radial_segments = 10
	rsm.rings = 6
	var vc := vmat("rock", 0.5, 0.95)
	vc.normal_enabled = true
	vc.normal_texture = _normal_tex(0.08, 6.0)
	rock_multimesh = make_mm(rsm, vc, n, true)
	var mm := rock_multimesh
	for r in n:
		var sp := rand_spot(1.5)
		var a := rng.randf_range(0.6, 2.2)
		var bb := rng.randf_range(0.4, 1.3)
		var c := rng.randf_range(0.6, 2.2)
		var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(a, bb, c))
		mm.set_instance_transform(r, Transform3D(bs, Vector3(sp.x, bb * 0.45, sp.y)))
		var gv := rng.randf_range(0.34, 0.55)
		mm.set_instance_color(r, Color(gv, gv + 0.01, gv - 0.02))
		var sbr := StaticBody3D.new()
		sbr.position = Vector3(sp.x, 0.8, sp.y)
		var cr := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = maxf(a, c) * 0.85
		cr.shape = ss
		sbr.add_child(cr)
		phys.add_child(sbr)
		rock_pos.append(sp)
		var loot := "iron_ore" if r % 3 == 0 else "stone"
		rock_mines.append({"instance": r, "position": Vector3(sp.x, 0.0, sp.y), "body": sbr, "loot": loot, "hits": 0, "mined": false})

func rock_mine_hits(rock_index: int) -> int:
	if rock_index < 0 or rock_index >= rock_mines.size():
		return 0
	return int(rock_mines[rock_index].get("hits", 0))

func hit_rock(rock_index: int) -> String:
	if rock_index < 0 or rock_index >= rock_mines.size():
		return ""
	var deposit: Dictionary = rock_mines[rock_index]
	if deposit["mined"]:
		return ""
	deposit["hits"] = int(deposit["hits"]) + 1
	if int(deposit["hits"]) < 3:
		return ""
	deposit["mined"] = true
	rock_multimesh.set_instance_transform(int(deposit["instance"]), hidden_tf())
	var body: StaticBody3D = deposit["body"]
	body.queue_free()
	return String(deposit["loot"])

func _dig_wall_mesh(depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	for segment in segments:
		var a0 := float(segment) / float(segments) * TAU
		var a1 := float(segment + 1) / float(segments) * TAU
		var top0 := Vector3(cos(a0) * 1.25, 0.0, sin(a0) * 1.25)
		var top1 := Vector3(cos(a1) * 1.25, 0.0, sin(a1) * 1.25)
		var bottom0 := Vector3(top0.x, -depth, top0.z)
		var bottom1 := Vector3(top1.x, -depth, top1.z)
		surface.add_vertex(top0)
		surface.add_vertex(bottom0)
		surface.add_vertex(top1)
		surface.add_vertex(top1)
		surface.add_vertex(bottom0)
		surface.add_vertex(bottom1)
	surface.generate_normals()
	return surface.commit()

func _refresh_dig_site(site_index: int) -> void:
	var site: Dictionary = dig_sites[site_index]
	var root: Node3D = site["node"]
	for child_name in ["walls", "floor"]:
		var old_child: Node = root.get_node_or_null(NodePath(child_name))
		if old_child != null:
			old_child.free()
	var depth: float = float(site["depth"])
	var walls := MeshInstance3D.new()
	walls.name = "walls"
	walls.mesh = _dig_wall_mesh(depth)
	var dirt_wall := mat(Color(0.25, 0.16, 0.09), 1.0)
	dirt_wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	walls.material_override = dirt_wall
	root.add_child(walls)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.24
	floor_mesh.bottom_radius = 1.24
	floor_mesh.height = 0.08
	floor_mesh.radial_segments = 24
	var floor_node := MeshInstance3D.new()
	floor_node.name = "floor"
	floor_node.mesh = floor_mesh
	floor_node.material_override = tmat("dirt", Color(0.3, 0.19, 0.1), 0.4)
	floor_node.position.y = -depth
	root.add_child(floor_node)
	var ladder_index: int = int(site.get("ladder_index", -1))
	if ladder_index >= 0 and ladder_index < ladders.size() and not bool(ladders[ladder_index].get("removed", false)):
		var ladder_data: Dictionary = ladders[ladder_index]
		var old_ladder: Node3D = ladder_data["node"]
		old_ladder.queue_free()
		var new_ladder := _make_ladder(root.global_position, float(ladder_data["yaw"]), depth)
		ladder_data["node"] = new_ladder
		ladder_data["depth"] = depth
		ladders[ladder_index] = ladder_data
		var ladder_interaction: Dictionary = interacts[int(ladder_data["interact_index"])]
		ladder_interaction["node"] = new_ladder
		interacts[int(ladder_data["interact_index"])] = ladder_interaction
	dig_sites[site_index] = site

func dig_ground(player_position: Vector3, yaw: float) -> float:
	var forward := Vector3(sin(yaw), 0.0, -cos(yaw))
	var target := player_position + forward * 1.5
	var site_index := -1
	for index in dig_sites.size():
		var site: Dictionary = dig_sites[index]
		var center: Vector3 = site["position"]
		if Vector2(center.x - target.x, center.z - target.z).length() < 2.5:
			site_index = index
			break
	if site_index < 0:
		var root := Node3D.new()
		root.position = Vector3(target.x, 0.0, target.z)
		add_child(root)
		var opening := CylinderMesh.new()
		opening.top_radius = 1.25
		opening.bottom_radius = 1.25
		opening.height = 0.025
		opening.radial_segments = 32
		var opening_node := MeshInstance3D.new()
		opening_node.mesh = opening
		opening_node.material_override = mat(Color(0.025, 0.018, 0.012), 1.0)
		opening_node.position.y = 0.015
		root.add_child(opening_node)
		dig_sites.append({"position": root.position, "depth": 0.7, "node": root, "ladder_index": -1})
		site_index = dig_sites.size() - 1
	else:
		var site: Dictionary = dig_sites[site_index]
		site["depth"] = minf(float(site["depth"]) + 0.7, 18.0)
		dig_sites[site_index] = site
	var current_site: Dictionary = dig_sites[site_index]
	_refresh_dig_site(site_index)
	return float(current_site["depth"])

func dig_depth_at(pos: Vector3) -> float:
	for site in dig_sites:
		var center: Vector3 = site["position"]
		if Vector2(center.x - pos.x, center.z - pos.z).length() < 1.15:
			return -float(site["depth"])
	return 0.0

func _make_ladder(pos: Vector3, yaw: float, depth: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = yaw
	add_child(root)
	var wood := tmat("planks", Color(0.42, 0.28, 0.16), 0.6)
	var height := depth + 1.8
	var center_y := (1.8 - depth) * 0.5
	for side in [-0.38, 0.38]:
		cyl(root, 0.055, 0.055, height, Vector3(side, center_y, 0.0), wood, 6)
	var rung_y := -depth
	while rung_y <= 1.6:
		box(root, Vector3(0.82, 0.07, 0.09), Vector3(0, rung_y, 0), wood)
		rung_y += 0.4
	return root

func place_ladder(pos: Vector3, yaw: float) -> bool:
	for ladder in ladders:
		var existing: Vector3 = ladder["position"]
		if not bool(ladder.get("removed", false)) and Vector2(existing.x - pos.x, existing.z - pos.z).length() < 0.9:
			return false
	var ladder_pos := Vector3(pos.x, 0.0, pos.z)
	var depth := 0.0
	var site_index := -1
	for index in dig_sites.size():
		var site: Dictionary = dig_sites[index]
		var center: Vector3 = site["position"]
		if Vector2(center.x - pos.x, center.z - pos.z).length() < 1.8:
			ladder_pos = center
			depth = float(site["depth"])
			site_index = index
			break
	var ladder_node := _make_ladder(ladder_pos, yaw, depth)
	add_interact("ladder", ladder_pos)
	var interact_index := interacts.size() - 1
	interacts[interact_index]["node"] = ladder_node
	var ladder_index := ladders.size()
	interacts[interact_index]["ladder_index"] = ladder_index
	ladders.append({"node": ladder_node, "position": ladder_pos, "yaw": yaw, "depth": depth,
		"removed": false, "interact_index": interact_index})
	if site_index >= 0:
		var site: Dictionary = dig_sites[site_index]
		site["ladder_index"] = ladder_index
		dig_sites[site_index] = site
	return true

func ladder_near(pos: Vector3, radius := 0.9) -> Dictionary:
	for ladder in ladders:
		if bool(ladder.get("removed", false)):
			continue
		var ladder_pos: Vector3 = ladder["position"]
		if Vector2(ladder_pos.x - pos.x, ladder_pos.z - pos.z).length() <= radius:
			return ladder
	return {}

func _bushes() -> void:
	var n := 110 if touch else 220
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var vc := vmat("needles", 1.6)
	var mm := make_mm(sm, vc, n, true, null, 90.0)
	for i in n:
		var sp := rand_spot(0.3)
		var s := rng.randf_range(0.6, 1.5)
		var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
		mm.set_instance_transform(i, Transform3D(bs, Vector3(sp.x, 0.3 * s, sp.y)))
		mm.set_instance_color(i, Color.from_hsv(rng.randf_range(0.2, 0.33), rng.randf_range(0.5, 0.7), rng.randf_range(0.14, 0.28)))

func _logs() -> void:
	fallen_logs.clear()
	var wood := tmat("bark", Color(0.5, 0.36, 0.25), 0.7)
	for i in 14:
		var sp := rand_spot(1.0)
		var yaw := rng.randf() * PI
		var ln := rng.randf_range(3.0, 6.0)
		var lg := cyl(self, 0.38, 0.4, ln, Vector3(sp.x, 0.4, sp.y), wood, 8)
		lg.basis = Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), PI / 2.0)
		var body := solid(Vector3(sp.x, 0.4, sp.y), Vector3(ln, 0.8, 0.8), yaw)
		add_interact("log", Vector3(sp.x, 0.0, sp.y))
		fallen_logs.append({"mesh": lg, "body": body, "hits": 0, "chopped": false,
			"interact_index": interacts.size() - 1})
	var stump := tmat("bark", Color(0.6, 0.45, 0.3), 0.8)
	for i in 18:
		var sp := rand_spot(1.0)
		cyl(self, 0.32, 0.42, 0.5, Vector3(sp.x, 0.25, sp.y), stump, 8)

func _grass() -> void:
	var grass_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	for angle in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.09
		var tip := Vector3(cos(angle + PI / 2.0), 0.0, sin(angle + PI / 2.0)) * 0.035 + Vector3.UP * 0.82
		vertices.append(-side)
		vertices.append(side)
		vertices.append(tip)
		vertices.append(tip)
		vertices.append(side)
		vertices.append(-side)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	grass_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bm := mat(Color.WHITE)
	bm.vertex_color_use_as_albedo = true
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var chunks := 8
	var cs := (HALF * 2.0) / float(chunks)
	var per := 900 if touch else 1800
	for cx in chunks:
		for cz in chunks:
			var center := Vector3(-HALF + (cx + 0.5) * cs, 0.0, -HALF + (cz + 0.5) * cs)
			var mm := make_mm(grass_mesh, bm, per, true, null, 75.0, center, false)
			for g in per:
				var lx := rng.randf_range(-cs / 2.0, cs / 2.0)
				var lz := rng.randf_range(-cs / 2.0, cs / 2.0)
				if absf(center.x + lx) < ROAD_W / 2.0 + 0.3:
					mm.set_instance_transform(g, hidden_tf())
					continue
				var grass_x := center.x + lx
				var grass_z := center.z + lz
				var over_water := false
				for fishing_spot in fishing_spots:
					var spot: Dictionary = fishing_spot
					var dx: float = grass_x - float(spot["x"])
					var dz: float = grass_z - float(spot["z"])
					var exclusion_radius: float = float(spot["radius"]) + 0.8
					if dx * dx + dz * dz < exclusion_radius * exclusion_radius:
						over_water = true
						break
				if over_water:
					mm.set_instance_transform(g, hidden_tf())
					continue
				var gh := rng.randf_range(0.55, 1.8)
				var gb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, gh, 1))
				mm.set_instance_transform(g, Transform3D(gb, Vector3(lx, 0, lz)))
				mm.set_instance_color(g, Color.from_hsv(rng.randf_range(0.22, 0.34), rng.randf_range(0.5, 0.78), rng.randf_range(0.24, 0.48)))

func _glowshrooms() -> void:
	var n := 56
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 3
	var mm := make_mm(sm, mat(Color(0.35, 0.85, 1.0), 1.0, true), n, false, null, 80.0, Vector3.ZERO, false)
	var i := 0
	while i < n:
		var c := rand_spot(1.0)
		for k in 7:
			if i >= n:
				break
			var s := rng.randf_range(0.6, 1.4)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.7, s)), Vector3(c.x + rng.randf_range(-0.8, 0.8), 0.08, c.y + rng.randf_range(-0.8, 0.8))))
			i += 1

# ------------------------------------------------------------------ Straßenlampen
func _lamps() -> void:
	var pole := tmat("metal", Color(0.22, 0.22, 0.24), 0.8, 0.6)
	var i := 0
	var z := 160.0
	while z > -125.0:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (ROAD_W / 2.0 + 1.0)
		cyl(self, 0.07, 0.11, 4.6, Vector3(x, 2.3, z), pole, 6)
		box(self, Vector3(0.9, 0.08, 0.08), Vector3(x - side * 0.45, 4.6, z), pole)
		var hx := x - side * 0.85
		var head := mat(Color(1.0, 0.82, 0.5), 0.5, true)
		box(self, Vector3(0.34, 0.14, 0.34), Vector3(hx, 4.5, z), head)
		solid(Vector3(x, 2.3, z), Vector3(0.25, 4.6, 0.25))
		var broken := (i % 3 == 1)
		flick.append({"m": head, "base": Color(1.0, 0.82, 0.5), "ph": float(i) * 1.7, "mode": 1 if broken else 0, "lamp": true})
		if not broken:
			lamp_pos.append(Vector3(hx, 4.2, z))
		else:
			lamp_broken.append(Vector3(hx, 4.2, z))
		i += 1
		z -= 28.0
	for k in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.omni_range = 17.0
		l.light_energy = 2.0
		l.visible = false
		add_child(l)
		lamp_lights.append(l)

# ------------------------------------------------------------------ Gebäude
func _crate(pos: Vector3, yaw := 0.0, loot := "heal") -> void:
	var c := box(self, Vector3(0.8, 0.55, 0.55), pos + Vector3(0, 0.28, 0), tmat("planks", Color(0.62, 0.45, 0.28), 0.6), Vector3(0, yaw, 0))
	box(c, Vector3(0.86, 0.08, 0.6), Vector3(0, 0.3, 0), tmat("planks", Color(0.4, 0.28, 0.16), 0.6))
	solid(pos + Vector3(0, 0.28, 0), Vector3(0.8, 0.55, 0.55), yaw)
	add_interact("crate", pos, "", loot)

func _mill() -> void:
	var g := Node3D.new()
	g.position = Vector3(-28.0, 0.0, SCENE_POS.z + 4.0)
	add_child(g)
	var wall := tmat("planks", Color(0.5, 0.34, 0.22), 0.3)
	var metal := tmat("metal", Color(0.9, 0.92, 0.95), 0.8, 0.35)
	box(g, Vector3(0.2, 5, 9), Vector3(-6.9, 2.5, 0), wall)
	box(g, Vector3(14, 5, 0.2), Vector3(0, 2.5, -4.4), wall)
	box(g, Vector3(14, 5, 0.2), Vector3(0, 2.5, 4.4), wall)
	box(g, Vector3(0.2, 5, 2.4), Vector3(7.0, 2.5, -3.3), wall)
	box(g, Vector3(0.2, 5, 2.4), Vector3(7.0, 2.5, 3.3), wall)
	box(g, Vector3(0.2, 1.4, 4.2), Vector3(7.0, 4.3, 0), wall)
	roof(g, 15.0, 10.5, 2.8, Vector3(0, 6.4, 0), tmat("shingles", Color(0.3, 0.28, 0.27), 0.5))
	for sz in [-2.1, 2.1]:
		box(g, Vector3(0.2, 3.9, 0.3), Vector3(7.05, 1.95, sz), wall)
	var wm := mat(Color(1.0, 0.6, 0.25), 0.5, true)
	for sz in [-3.2, 3.2]:
		box(g, Vector3(0.12, 0.8, 1.2), Vector3(7.02, 4.0, sz), wm)
	win_flick = {"m": wm, "base": Color(0.6, 0.3, 0.08), "ph": 3.0, "mode": 1}
	flick.append(win_flick)
	cyl(g, 0.5, 0.6, 4.0, Vector3(-4.0, 7.2, 2.0), tmat("concrete", Color(0.6, 0.55, 0.5), 0.5), 8)
	# Kreissäge
	box(g, Vector3(1.0, 0.9, 2.6), Vector3(9.5, 0.45, 6.0), tmat("planks", Color(0.55, 0.38, 0.24), 0.5))
	saw = Node3D.new()
	saw.position = Vector3(9.5, 1.5, 6.0)
	g.add_child(saw)
	var disc := cyl(saw, 1.2, 1.2, 0.06, Vector3.ZERO, metal, 24, Vector3(PI / 2.0, 0.0, 0.0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 12:
		var a := float(k) / 12.0 * TAU
		box(saw, Vector3(0.24, 0.24, 0.08), Vector3(cos(a) * 1.2, sin(a) * 1.2, 0.0), metal, Vector3(0, 0, a))
	solid(g.transform * Vector3(9.5, 0.7, 6.0), Vector3(1.0, 1.4, 2.6), 0.0, g)
	# Holzstapel
	var logm := tmat("bark", Color(0.7, 0.5, 0.32), 0.8)
	for row in [[0.35, [-5.4, -6.1, -6.8]], [0.95, [-5.75, -6.45]], [1.5, [-6.1]]]:
		for zz in row[1]:
			cyl(g, 0.35, 0.35, 5.0, Vector3(2.0, row[0], zz), logm, 8, Vector3(0, 0, PI / 2.0))
	solid(g.transform * Vector3(2.0, 0.9, -6.1), Vector3(5.2, 1.8, 2.2), 0.0, g)
	for wall_piece in [
		[Vector3(-6.9, 2.5, 0), Vector3(0.2, 5, 9)],
		[Vector3(0, 2.5, -4.4), Vector3(14, 5, 0.2)],
		[Vector3(0, 2.5, 4.4), Vector3(14, 5, 0.2)],
		[Vector3(7.0, 2.5, -3.3), Vector3(0.2, 5, 2.4)],
		[Vector3(7.0, 2.5, 3.3), Vector3(0.2, 5, 2.4)],
		[Vector3(7.0, 4.3, 0), Vector3(0.2, 1.4, 4.2)]]:
		solid(g.transform * wall_piece[0], wall_piece[1], 0.0, g)
	_crate(g.transform * Vector3(8.4, 0, -3.4), 0.0, "ammo")
	add_interact("note", g.transform * Vector3(8.4, 0, 2.0), NOTES[0])
	_chicken(g, Vector3(-3.5, 0, -1.5), 0.0)
	_chicken(g, Vector3(-0.5, 0, 1.0), 2.1)
	_chicken(g, Vector3(3.2, 0, -1.1), 4.2)
	_generator(g)
	blocks.append({"p": Vector2(g.position.x, g.position.z), "s": Vector2(14, 9), "c": Color(0.55, 0.38, 0.2), "round": false})

func _chicken(parent: Node3D, at: Vector3, phase: float) -> void:
	var root := Node3D.new()
	root.position = at + Vector3(0, 0.32, 0)
	parent.add_child(root)
	var hit_area := Area3D.new()
	hit_area.collision_layer = 1
	hit_area.collision_mask = 0
	hit_area.add_to_group("chicken_hitboxes")
	root.add_child(hit_area)
	var hit_shape := CollisionShape3D.new()
	var hit_capsule := CapsuleShape3D.new()
	hit_capsule.radius = 0.3
	hit_capsule.height = 0.7
	hit_shape.shape = hit_capsule
	hit_shape.position = Vector3(0, 0.12, -0.1)
	hit_area.add_child(hit_shape)
	var feathers := mat(Color(0.82, 0.76, 0.55), 0.9)
	var dark_feathers := mat(Color(0.55, 0.48, 0.34), 0.9)
	var beak_mat := mat(Color(0.9, 0.48, 0.08), 0.8, true)
	var comb_mat := mat(Color(0.72, 0.08, 0.06), 0.8, true)
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 0.52
	var body := _add_mesh(root, body_mesh, feathers, Vector3.ZERO)
	body.scale = Vector3(1.0, 0.8, 1.25)
	var head_root := Node3D.new()
	head_root.position = Vector3(0, 0.28, -0.25)
	root.add_child(head_root)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.25
	_add_mesh(head_root, head_mesh, feathers, Vector3(0, 0.04, -0.08))
	var eye_mat := mat(Color(0.025, 0.02, 0.015), 0.4, true)
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.035
	eye_mesh.height = 0.07
	for side in [-1.0, 1.0]:
		var eye := _add_mesh(head_root, eye_mesh, eye_mat, Vector3(side * 0.105, 0.075, -0.16))
		eye.scale = Vector3(0.75, 0.75, 0.75)
	var beak := BoxMesh.new()
	beak.size = Vector3(0.12, 0.07, 0.16)
	_add_mesh(head_root, beak, beak_mat, Vector3(0, 0.0, -0.22))
	var comb := SphereMesh.new()
	comb.radius = 0.08
	comb.height = 0.13
	_add_mesh(head_root, comb, comb_mat, Vector3(0, 0.17, -0.07))
	var legs: Array[MeshInstance3D] = []
	for side in [-1.0, 1.0]:
		var wing_mesh := SphereMesh.new()
		wing_mesh.radius = 0.15
		wing_mesh.height = 0.25
		var wing := _add_mesh(root, wing_mesh, dark_feathers, Vector3(side * 0.25, 0.02, 0))
		wing.scale = Vector3(0.6, 0.85, 1.2)
		var leg := cyl(root, 0.025, 0.025, 0.24, Vector3(side * 0.12, -0.24, -0.02), beak_mat, 5)
		legs.append(leg)
	chickens.append({"node": root, "head": head_root, "legs": legs, "hit_area": hit_area, "home": at, "phase": phase, "hits": 0, "call_timer": rng.randf_range(3.0, 7.0)})

func hit_chicken(hit_area: Area3D) -> bool:
	for chicken_index in chickens.size():
		var chicken: Dictionary = chickens[chicken_index]
		if chicken["hit_area"] != hit_area:
			continue
		var chicken_node: Variant = chicken["node"]
		chicken["hits"] = int(chicken["hits"]) + 1
		if int(chicken["hits"]) < 2:
			chicken_node.scale = Vector3(1.15, 0.9, 1.15)
			var hit_tween := create_tween()
			hit_tween.tween_property(chicken_node, "scale", Vector3.ONE, 0.18)
			return true
		chicken_node.hide()
		chicken["hit_area"].set_deferred("monitorable", false)
		chickens.remove_at(chicken_index)
		chicken_node.queue_free()
		return true
	return false

## Generator an der Südwand der Mühle: braucht den Kanister aus der letzten Hütte.
func _generator(g: Node3D) -> void:
	var lp := Vector3(-3.5, 0.0, 6.3)
	box(g, Vector3(1.5, 1.0, 0.9), lp + Vector3(0, 0.55, 0), tmat("metal", Color(0.75, 0.2, 0.12), 0.8, 0.5))
	box(g, Vector3(1.0, 0.5, 0.95), lp + Vector3(0, 0.3, 0), tmat("metal", Color(0.15, 0.15, 0.16), 0.8))
	cyl(g, 0.07, 0.07, 0.7, lp + Vector3(0.5, 1.3, 0.2), tmat("metal", Color(0.3, 0.3, 0.3), 0.8), 6)
	gen_lamp = mat(Color(1.0, 0.1, 0.05), 0.5, true)
	box(g, Vector3(0.14, 0.14, 0.06), lp + Vector3(-0.5, 0.95, 0.47), gen_lamp)
	gen_light = OmniLight3D.new()
	gen_light.light_color = Color(1.0, 0.85, 0.55)
	gen_light.omni_range = 12.0
	gen_light.light_energy = 2.3
	gen_light.position = g.transform * (lp + Vector3(0, 1.8, 0.5))
	gen_light.visible = false
	add_child(gen_light)
	solid(g.transform * (lp + Vector3(0, 0.55, 0)), Vector3(1.5, 1.1, 0.9))
	add_interact("generator", g.transform * (lp + Vector3(0, 0, 1.2)))

func _cabin(x: float, z: float, yaw: float, note_i: int, loot := "heal") -> void:
	var g := Node3D.new()
	g.position = Vector3(x, 0.0, z)
	g.rotation.y = yaw
	add_child(g)
	if note_i == 5:
		_armory_cabin(g, x, z, yaw, note_i, loot)
		return
	var dark := mat(Color(0.06, 0.04, 0.03))
	box(g, Vector3(6.0, 2.6, 4.6), Vector3(0, 1.3, 0), tmat("planks", Color(0.55, 0.37, 0.23), 0.35))
	roof(g, 7.2, 5.8, 1.6, Vector3(0, 3.4, 0), tmat("shingles", Color(0.32, 0.29, 0.27), 0.5))
	box(g, Vector3(1.0, 1.9, 0.12), Vector3(-1.0, 0.95, 2.31), dark)
	var wm := mat(Color(1.0, 0.8, 0.4), 0.5, true)
	box(g, Vector3(1.1, 0.8, 0.12), Vector3(1.4, 1.5, 2.31), wm)
	flick.append({"m": wm, "base": Color(0.55, 0.4, 0.15), "ph": x, "mode": 0})
	box(g, Vector3(3.2, 0.14, 1.4), Vector3(0, 0.07, 3.3), tmat("planks", Color(0.45, 0.3, 0.19), 0.5))
	box(g, Vector3(0.6, 2.4, 0.6), Vector3(-2.2, 3.5, -1.2), tmat("concrete", Color(0.6, 0.55, 0.5), 0.5))
	solid(g.transform * Vector3(0, 1.3, 0), Vector3(6.0, 2.6, 4.6), yaw, g)
	_crate(g.transform * Vector3(2.3, 0, 3.5), yaw, loot)
	add_interact("note", g.transform * Vector3(-1.0, 0, 3.3), NOTES[note_i])
	blocks.append({"p": Vector2(x, z), "s": Vector2(6, 4.6), "c": Color(0.55, 0.38, 0.2), "round": false})

func _armory_cabin(g: Node3D, x: float, z: float, yaw: float, note_i: int, loot: String) -> void:
	var wood := tmat("planks", Color(0.55, 0.37, 0.23), 0.35)
	var dark := mat(Color(0.08, 0.07, 0.06))
	box(g, Vector3(6.0, 0.2, 4.6), Vector3(0, 0.1, 0), wood)
	box(g, Vector3(0.2, 2.6, 4.6), Vector3(-2.9, 1.4, 0), wood)
	box(g, Vector3(0.2, 2.6, 4.6), Vector3(2.9, 1.4, 0), wood)
	box(g, Vector3(6.0, 2.6, 0.2), Vector3(0, 1.4, -2.2), wood)
	box(g, Vector3(1.4, 2.6, 0.2), Vector3(-2.3, 1.4, 2.2), wood)
	box(g, Vector3(3.3, 2.6, 0.2), Vector3(1.35, 1.4, 2.2), wood)
	box(g, Vector3(1.4, 0.7, 0.2), Vector3(-1.0, 2.25, 2.2), wood)
	roof(g, 7.2, 5.8, 1.6, Vector3(0, 3.4, 0), tmat("shingles", Color(0.32, 0.29, 0.27), 0.5))
	for wall in [
		[Vector3(-2.9, 1.4, 0), Vector3(0.2, 2.6, 4.6)],
		[Vector3(2.9, 1.4, 0), Vector3(0.2, 2.6, 4.6)],
		[Vector3(0, 1.4, -2.2), Vector3(6.0, 2.6, 0.2)],
		[Vector3(-2.3, 1.4, 2.2), Vector3(1.4, 2.6, 0.2)],
		[Vector3(1.35, 1.4, 2.2), Vector3(3.3, 2.6, 0.2)],
		[Vector3(-1.0, 2.25, 2.2), Vector3(1.4, 0.7, 0.2)]]:
		solid(g.transform * wall[0], wall[1], yaw, g)
	var door_hinge := AnimatableBody3D.new()
	door_hinge.position = Vector3(-1.7, 0.0, 2.2)
	door_hinge.sync_to_physics = true
	g.add_child(door_hinge)
	box(door_hinge, Vector3(1.4, 1.9, 0.14), Vector3(0.7, 0.95, 0), mat(Color(0.36, 0.22, 0.11), 0.8, true))
	box(door_hinge, Vector3(0.08, 0.08, 0.05), Vector3(1.22, 1.0, 0.1), mat(Color(0.72, 0.58, 0.28), 0.4))
	var door_collision := CollisionShape3D.new()
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(1.4, 1.9, 0.14)
	door_collision.shape = door_shape
	door_collision.position = Vector3(0.7, 0.95, 0)
	door_hinge.add_child(door_collision)
	add_interact("door", g.transform * Vector3(-1.0, 0, 2.9))
	interacts.back()["node"] = door_hinge
	var window_mat := mat(Color(0.36, 0.43, 0.39), 0.35)
	box(g, Vector3(1.0, 0.8, 0.08), Vector3(1.3, 1.55, 2.31), window_mat)
	box(g, Vector3(3.2, 0.14, 1.4), Vector3(0, 0.07, 3.3), wood)
	_crate(g.transform * Vector3(2.3, 0, 3.5), yaw, loot)
	add_interact("note", g.transform * Vector3(0, 0.5, 0.8), NOTES[note_i])
	_weapon_display(g, "pistol", Vector3(-1.7, 1.35, -1.98))
	_weapon_display(g, "rifle", Vector3(0, 1.35, -1.98))
	_weapon_display(g, "minigun", Vector3(1.7, 1.35, -1.98))
	var axe_handle := box(g, Vector3(0.1, 0.8, 0.1), Vector3(2.35, 1.25, -1.98), mat(Color(0.36, 0.22, 0.12), 0.8))
	axe_handle.rotation.z = -0.3
	var axe_head := box(g, Vector3(0.48, 0.22, 0.14), Vector3(2.48, 1.55, -1.98), mat(Color(0.58, 0.62, 0.61), 0.35))
	axe_head.rotation.z = -0.3
	add_interact("item", g.transform * Vector3(2.35, 0, -1.45), "", "axe")
	blocks.append({"p": Vector2(x, z), "s": Vector2(6, 4.6), "c": Color(0.55, 0.38, 0.2), "round": false})

func _weapon_display(parent: Node3D, weapon_id: String, pos: Vector3) -> void:
	var metal := mat(Color(0.16, 0.18, 0.18), 0.5)
	var wood := mat(Color(0.28, 0.18, 0.12), 0.8)
	var model := Node3D.new()
	model.position = pos
	parent.add_child(model)
	box(model, Vector3(0.75, 0.12, 0.12), Vector3(0, 0, 0), metal)
	box(model, Vector3(0.35, 0.15, 0.15), Vector3(-0.45, 0, 0), wood)
	box(model, Vector3(0.13, 0.22, 0.12), Vector3(-0.12, -0.16, 0), wood)
	if weapon_id == "pistol":
		model.scale = Vector3(0.8, 0.8, 0.8)
	elif weapon_id == "minigun":
		for i in 3:
			box(model, Vector3(0.8, 0.045, 0.045), Vector3(0.05, (i - 1) * 0.09, -0.04), metal)
		box(model, Vector3(0.24, 0.22, 0.2), Vector3(-0.05, 0, 0), metal)
	add_interact("weapon", parent.global_transform * Vector3(pos.x, 0, -1.45), "", weapon_id)

func _tent(pos: Vector3, yaw: float, col: Color) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	add_child(g)
	roof(g, 2.8, 2.6, 1.7, Vector3(0, 0.85, 0), tmat("cloth", col, 0.9))
	box(g, Vector3(0.05, 1.1, 0.8), Vector3(1.4, 0.55, 0), mat(Color(0.03, 0.03, 0.03)))
	solid(g.transform * Vector3(0, 0.65, 0), Vector3(2.8, 1.3, 2.4), yaw)

func _camp() -> void:
	var c := Vector3(50.0, 0.0, -95.0)
	_tent(c + Vector3(-4.0, 0, 2.0), 0.5, Color(0.75, 0.35, 0.1))
	_tent(c + Vector3(-3.5, 0, -3.0), -0.4, Color(0.15, 0.3, 0.6))
	var stone := tmat("rock", Color(0.6, 0.6, 0.58), 0.8, 0.95)
	for k in 9:
		var a := float(k) / 9.0 * TAU
		var r := ball(self, 0.22, c + Vector3(cos(a) * 0.9, 0.12, sin(a) * 0.9), stone, 6)
		r.scale = Vector3(1.0, 0.7, 1.0)
	var em := mat(Color(0.9, 0.3, 0.05), 1.0, true)
	cyl(self, 0.7, 0.7, 0.04, c + Vector3(0, 0.05, 0), em, 10)
	flick.append({"m": em, "base": Color(0.9, 0.3, 0.05), "ph": 2.0, "mode": 0})
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.45, 0.12)
	fire_light.omni_range = 9.0
	fire_light.light_energy = 1.2
	fire_light.position = c + Vector3(0, 0.7, 0)
	add_child(fire_light)
	var wood := tmat("planks", Color(0.6, 0.42, 0.28), 0.5)
	cyl(self, 0.2, 0.2, 1.6, c + Vector3(2.0, 0.2, 1.2), wood, 8, Vector3(0, 0, PI / 2.0))
	cyl(self, 0.2, 0.2, 1.6, c + Vector3(-0.6, 0.2, 2.2), wood, 8, Vector3(0, 0, PI / 2.0))
	var flame := mat(Color(1.0, 0.55, 0.1), 1.0, true)
	cyl(self, 0.0, 0.28, 0.8, c + Vector3(0, 0.45, 0), flame, 6)
	flick.append({"m": flame, "base": Color(1.0, 0.55, 0.1), "ph": 1.3, "mode": 0})
	add_interact("campfire", c + Vector3(0, 0, 1.7))
	add_interact("note", c + Vector3(1.8, 0, -1.8), NOTES[3])
	_crate(c + Vector3(2.4, 0, -3.2), 0.0, "heal")
	blocks.append({"p": Vector2(c.x, c.z), "s": Vector2(9, 9), "c": Color(0.75, 0.35, 0.1), "round": true})

func _fish_mesh() -> ArrayMesh:
	if fish_mesh != null:
		return fish_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(0.9, 0.22, 0.16), Vector3.ZERO],
		[Vector3(0.22, 0.16, 0.08), Vector3(-0.52, 0.0, 0.0)],
		[Vector3(0.28, 0.08, 0.06), Vector3(-0.1, -0.12, 0.0)],
		[Vector3(0.1, 0.06, 0.22), Vector3(0.38, 0.0, 0.0)]]
	for part in parts:
		var part_mesh := BoxMesh.new()
		part_mesh.size = part[0]
		surface.append_from(part_mesh, 0, Transform3D(Basis.IDENTITY, part[1]))
	fish_mesh = surface.commit()
	return fish_mesh

func _add_fish_model(parent: Node3D, pos: Vector3, yaw: float = 0.0, scale_: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3(scale_, scale_, scale_)
	parent.add_child(root)
	if fish_material == null:
		fish_material = mat(Color(0.12, 0.38, 0.3), 0.9)
	var fish := MeshInstance3D.new()
	fish.mesh = _fish_mesh()
	fish.material_override = fish_material
	root.add_child(fish)
	return root

## Wasserscheibe: gleiche Optik, aber ohne Schatten-Empfang/-Wurf, ohne unsichtbare Unterseite
## und nur bis zur Nebel-Grenze gezeichnet.
func _water_disc(c: Vector3, radius: float, water: StandardMaterial3D, seg: int) -> void:
	water.disable_receive_shadows = true
	var mi := cyl(self, radius, radius, 0.08, Vector3(c.x, 0.08, c.z), water, seg)
	(mi.mesh as CylinderMesh).cap_bottom = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0

func _fishing_pools() -> void:
	var puddles := [
		Vector3(-35.0, 0.0, -24.0),
		Vector3(18.0, 0.0, 70.0),
		Vector3(-72.0, 0.0, 58.0),
		Vector3(92.0, 0.0, -82.0)
	]
	for pool_index in puddles.size():
		var c: Vector3 = puddles[pool_index]
		var water := mat(Color(0.03, 0.08, 0.1), 0.05)
		water.metallic = 0.25
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.albedo_color.a = 0.62
		var radius := 6.5 + float(pool_index) * 0.8
		_water_disc(c, radius, water, 24)
		solid_cyl(Vector3(c.x, 0.8, c.z), radius, 1.6)
		# Schilf: 8 Halme pro Teich in EINEM Draw-Call (MultiMesh) statt 8 Einzelobjekten
		var reeds := mat(Color(0.18, 0.35, 0.14), 0.8, true)
		var reed_mesh := CylinderMesh.new()
		reed_mesh.top_radius = 0.03
		reed_mesh.bottom_radius = 0.04
		reed_mesh.height = 0.75
		reed_mesh.radial_segments = 6
		reed_mesh.rings = 1
		var reed_mm := make_mm(reed_mesh, reeds, 8, false, null, 100.0, Vector3.ZERO, false)
		for reed in 8:
			var a := float(reed) / 8.0 * TAU + float(pool_index) * 0.7
			var rr := radius * 0.7
			var reed_pos := Vector3(c.x + cos(a) * rr, 0.36, c.z + sin(a) * rr)
			reed_mm.set_instance_transform(reed, Transform3D(Basis.IDENTITY, reed_pos))
		var fish_count := 5 + pool_index
		for fish in fish_count:
			var a := rng.randf() * TAU
			var dist := rng.randf_range(0.8, radius * 0.72)
			var fish_pos := Vector3(c.x + cos(a) * dist, 0.045, c.z + sin(a) * dist)
			var fish_scale := rng.randf_range(0.42, 0.56)
			var fish_root := _add_fish_model(self, fish_pos, a + PI / 2.0, fish_scale)
			fish_models.append({"node": fish_root, "center": c, "angle": a, "radius": dist,
				"speed": rng.randf_range(0.12, 0.28), "scale": fish_scale, "phase": rng.randf_range(0.0, TAU)})
		fishing_spots.append({"x": c.x, "z": c.z, "radius": radius + 0.7})
		add_interact("fish", c + Vector3(radius + 1.1, 0, 0), "", "fish")
		blocks.append({"p": Vector2(c.x, c.z), "s": Vector2(radius * 2.0, radius * 2.0), "c": Color(0.1, 0.25, 0.35), "round": true})

func _pond() -> void:
	var c := Vector3(55.0, 0.0, 35.0)
	var water := mat(Color(0.03, 0.07, 0.09), 0.05)
	water.metallic = 0.25
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color.a = 0.62
	var radius := 14.5
	_water_disc(c, radius, water, 32)
	solid_cyl(Vector3(c.x, 0.8, c.z), radius, 1.6)
	for fish in 12:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(1.0, radius * 0.72)
		var fish_pos := Vector3(c.x + cos(a) * dist, 0.045, c.z + sin(a) * dist)
		var fish_scale := rng.randf_range(0.42, 0.56)
		var fish_root := _add_fish_model(self, fish_pos, a + PI / 2.0, fish_scale)
		fish_models.append({"node": fish_root, "center": c, "angle": a, "radius": dist,
			"speed": rng.randf_range(0.12, 0.28), "scale": fish_scale, "phase": rng.randf_range(0.0, TAU)})
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.04
	cone.height = 1.6
	cone.radial_segments = 4
	cone.rings = 1
	var mm := make_mm(cone, mat(Color(0.2, 0.25, 0.1)), 70, false, null, 90.0, Vector3.ZERO, false)
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(13.5, 16.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1, rng.randf_range(0.6, 1.3), 1)), Vector3(c.x + cos(a) * r, 0.7, c.z + sin(a) * r)))
	fishing_spots.append({"x": c.x, "z": c.z, "radius": radius + 0.7})
	add_interact("fish", c + Vector3(radius + 1.1, 0, 0), "", "fish")
	add_interact("note", c + Vector3(-11.2, 0, 0), NOTES[8])
	blocks.append({"p": Vector2(c.x, c.z), "s": Vector2(radius * 2.0, radius * 2.0), "c": Color(0.1, 0.25, 0.35), "round": true})

func _tower() -> void:
	var p := Vector3(-75.0, 0.0, 15.0)
	var wood := tmat("planks", Color(0.6, 0.42, 0.28), 0.5)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			cyl(self, 0.13, 0.17, 5.2, p + Vector3(sx * 1.3, 2.6, sz * 1.3), wood, 6)
			solid(p + Vector3(sx * 1.3, 2.5, sz * 1.3), Vector3(0.4, 5.0, 0.4))
			cyl(self, 0.08, 0.08, 1.8, p + Vector3(sx * 1.5, 6.3, sz * 1.5), wood, 5)
	for sx in [-1.0, 1.0]:
		box(self, Vector3(0.1, 0.1, 2.6), p + Vector3(sx * 1.3, 2.5, 0), wood)
	for sz in [-1.0, 1.0]:
		box(self, Vector3(2.6, 0.1, 0.1), p + Vector3(0, 2.5, sz * 1.3), wood)
	box(self, Vector3(3.4, 0.2, 3.4), p + Vector3(0, 5.3, 0), wood)
	for sz in [-1.0, 1.0]:
		box(self, Vector3(3.4, 0.9, 0.08), p + Vector3(0, 5.85, sz * 1.65), wood)
	roof(self, 4.0, 4.0, 1.0, p + Vector3(0, 7.7, 0), tmat("shingles", Color(0.3, 0.27, 0.25), 0.5))
	for sx in [-0.35, 0.35]:
		box(self, Vector3(0.06, 5.2, 0.06), p + Vector3(sx, 2.6, 1.7), wood)
	for k in 9:
		box(self, Vector3(0.7, 0.05, 0.05), p + Vector3(0, 0.5 + k * 0.55, 1.7), wood)
	add_interact("note", p + Vector3(0, 0, 3.2), NOTES[4])
	blocks.append({"p": Vector2(p.x, p.z), "s": Vector2(3.5, 3.5), "c": Color(0.55, 0.38, 0.2), "round": false})

func _car() -> void:
	car = CarScript.new()
	add_child(car)
	car.setup(self)

func _fence() -> void:
	var wood := tmat("planks", Color(0.55, 0.4, 0.26), 0.5)
	var postm := BoxMesh.new()
	postm.size = Vector3(0.14, 1.2, 0.14)
	var mm := make_mm(postm, wood, 34)
	var i := 0
	for sx in [-5.8, 5.8]:
		for k in 17:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(sx, 0.6, 150.0 - k * 2.4)))
			i += 1
		for ry in [0.5, 0.95]:
			box(self, Vector3(0.06, 0.1, 39.0), Vector3(sx, ry, 130.8), wood)
		solid(Vector3(sx, 0.6, 130.8), Vector3(0.2, 1.2, 39.0))

# ------------------------------------------------------------------ Grab
func _grave() -> void:
	var p := GRAVE_POS
	var mound := ball(self, 1.0, p, tmat("dirt", Color(0.4, 0.3, 0.22), 0.5, 1.0), 10)
	mound.scale = Vector3(1.0, 0.28, 2.0)
	var wood := tmat("planks", Color(0.5, 0.36, 0.24), 0.5)
	box(self, Vector3(0.14, 1.5, 0.14), p + Vector3(0, 0.75, -2.1), wood)
	box(self, Vector3(0.8, 0.14, 0.14), p + Vector3(0, 1.15, -2.1), wood)
	var stone := tmat("rock", Color(0.8, 0.8, 0.82), 0.5, 0.95)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var st := ball(self, 0.22, p + Vector3(cos(a) * 1.5, 0.1, sin(a) * 2.6), stone, 6)
		st.scale = Vector3(1.0, 0.7, 1.0)
	cyl(self, 0.05, 0.05, 0.22, p + Vector3(0.5, 0.11, -1.8), mat(Color(0.9, 0.88, 0.8), 0.8), 6)
	var fl := mat(Color(0.7, 0.8, 1.0), 1.0, true)
	ball(self, 0.04, p + Vector3(0.5, 0.26, -1.8), fl, 6)
	flick.append({"m": fl, "base": Color(0.7, 0.8, 1.0), "ph": 4.1, "mode": 0})
	grave_light = OmniLight3D.new()
	grave_light.light_color = Color(0.55, 0.7, 1.0)
	grave_light.omni_range = 6.0
	grave_light.light_energy = 0.6
	grave_light.position = p + Vector3(0.5, 0.6, -1.8)
	add_child(grave_light)
	solid(p + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 4.0))
	add_interact("grave", p + Vector3(0, 0, -3.3), NOTES[7])
	blocks.append({"p": Vector2(p.x, p.z), "s": Vector2(5, 7), "c": Color(0.7, 0.6, 0.9), "round": false})

# ------------------------------------------------------------------ Blut & Tatort
func _blood() -> void:
	var blood := mat(Color(0.35, 0.02, 0.02), 0.35)
	var pool := CylinderMesh.new()
	pool.top_radius = 1.0
	pool.bottom_radius = 1.0
	pool.height = 0.01
	pool.radial_segments = 12
	var pts: Array = []
	for i in 30:
		pts.append(Vector3(SCENE_POS.x + (rng.randf() - 0.5) * 4.6, rng.randf_range(0.4, 1.8), SCENE_POS.z + (rng.randf() - 0.5) * 6.0))
	for i in 80:
		pts.append(Vector3((rng.randf() - 0.5) * 1.6, rng.randf_range(0.12, 0.4), 60.0 - i * 2.45))
	for i in 14:
		pts.append(Vector3((rng.randf() - 0.5) * 1.4, rng.randf_range(0.12, 0.4), SCENE_POS.z + 12.0 - i * 0.8))
	var mm := make_mm(pool, blood, pts.size(), false, null, 0.0, Vector3.ZERO, false)
	for i in pts.size():
		var p: Vector3 = pts[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(p.y, 1.0, p.y * rng.randf_range(0.7, 1.5))), Vector3(p.x, 0.04, p.z)))

func _crime_scene() -> void:
	var defs := [
		[Vector3(-1.3, 0, -0.5), 0.4, Color(0.54, 0.16, 0.16), "Jonas. Seine Hand umklammert das Handy. Im Gürtel steckt ein Verbandspäckchen.", "heal"],
		[Vector3(1.1, 0, 1.0), -0.7, Color(0.16, 0.35, 0.54), "Mia. Sie hat bis zuletzt geschwiegen. In ihrer Jacke: Schrotpatronen.", "ammo"],
		[Vector3(0.1, 0, -2.0), 2.4, Color(0.23, 0.48, 0.23), "Tobi. Auf seiner Stirn steht mit Kugelschreiber: HALLO. Im Rucksack: Verbandszeug.", "heal"]]
	for d in defs:
		var g := Node3D.new()
		g.position = SCENE_POS + d[0]
		g.rotation.y = d[1]
		var torso := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.21
		cm.height = 0.85
		torso.mesh = cm
		torso.material_override = mat(d[2])
		torso.rotation.x = PI / 2.0
		torso.position.y = 0.22
		g.add_child(torso)
		var legs := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.15
		lm.height = 0.9
		legs.mesh = lm
		legs.material_override = mat(Color(0.16, 0.21, 0.31))
		legs.rotation.x = PI / 2.0
		legs.position = Vector3(0, 0.17, 0.7)
		g.add_child(legs)
		ball(g, 0.15, Vector3(0, 0.15, -0.55), mat(Color(0.72, 0.6, 0.53)))
		add_child(g)
		add_interact("corpse", SCENE_POS + d[0], d[3], d[4])
	box(self, Vector3(0.45, 0.06, 0.45), SCENE_POS + Vector3(-0.5, 0.05, 2.2), mat(Color(0.78, 0.6, 0.35)), Vector3(0, 0.5, 0))
	box(self, Vector3(0.08, 0.02, 0.15), SCENE_POS + Vector3(0.3, 0.04, 2.5), mat(Color(0.4, 1.0, 0.67), 0.9, true))
	# Jonas' Kamera mit roter Aufnahme-LED
	box(self, Vector3(0.22, 0.16, 0.12), SCENE_POS + Vector3(2.2, 0.08, 2.6), mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.8, 0))
	var rec := mat(Color(1.0, 0.0, 0.0), 1.0, true)
	ball(self, 0.025, SCENE_POS + Vector3(2.12, 0.15, 2.56), rec, 6)
	flick.append({"m": rec, "base": Color(1.0, 0.0, 0.0), "ph": 0.0, "mode": 2})
	add_interact("camera", SCENE_POS + Vector3(2.2, 0, 2.6), NOTES[6])
	var bl := OmniLight3D.new()
	bl.light_color = Color(1, 0.13, 0)
	bl.light_energy = 3.0
	bl.omni_range = 10.0
	bl.position = SCENE_POS + Vector3(0, 1.2, 0)
	add_child(bl)
	blocks.append({"p": Vector2(SCENE_POS.x, SCENE_POS.z), "s": Vector2(10, 10), "c": Color(0.6, 0.05, 0.05), "round": true})

# ------------------------------------------------------------------ Himmel & Partikel
func _sky() -> void:
	sky_root = Node3D.new()
	add_child(sky_root)
	star_mat = mat(Color(1, 1, 0.95, 0.0), 1.0, true)
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.disable_fog = true
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	sm.radial_segments = 4
	sm.rings = 2
	var n := 120 if touch else 260
	var mm := make_mm(sm, star_mat, n, false, sky_root, 0.0, Vector3.ZERO, false)
	for i in n:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.08, 1.0), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.6, 1.5)), v * 215.0))
	moon_mat = mat(Color(0.85, 0.9, 1.0, 0.0), 1.0, true)
	moon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moon_mat.disable_fog = true
	moon = ball(sky_root, 9.0, Vector3(0.35, 0.5, -0.8).normalized() * 200.0, moon_mat, 20)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _particles() -> void:
	dust = CPUParticles3D.new()
	dust.amount = 40 if touch else 90
	dust.lifetime = 8.0
	dust.preprocess = 8.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(24, 3, 24)
	dust.direction = Vector3(1, 0.1, 0.3)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.1
	dust.initial_velocity_max = 0.5
	dust.gravity = Vector3.ZERO
	dust.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 4
	sm.rings = 2
	dust.mesh = sm
	dust_mat = mat(Color(0.85, 1.0, 0.55, 0.3), 1.0, true)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust.material_override = dust_mat
	add_child(dust)

# ------------------------------------------------------------------ Laufende Updates
func update(pp: Vector3, dusk: float, delta: float) -> void:
	t += delta
	sky_root.position = pp
	for fish_data: Dictionary in fish_models:
		var center: Vector3 = fish_data["center"]
		# Weit entfernte Teiche liegen im Nebel – dort keine Fisch-Berechnung
		if absf(center.x - pp.x) > 100.0 or absf(center.z - pp.z) > 100.0:
			continue
		var angle: float = float(fish_data["angle"]) + float(fish_data["speed"]) * t
		var radius: float = float(fish_data["radius"])
		var phase: float = float(fish_data["phase"])
		var fish_root: Node3D = fish_data["node"]
		fish_root.position = Vector3(center.x + cos(angle) * radius,
			0.045 + sin(t * 1.6 + phase) * 0.008, center.z + sin(angle) * radius)
		fish_root.rotation.y = angle + PI / 2.0 + sin(t * 7.0 + phase) * 0.08
	var a := clampf((dusk - 0.2) * 1.6, 0.0, 1.0)
	star_mat.albedo_color.a = a
	moon_mat.albedo_color.a = a
	moon.visible = a > 0.02
	dust_mat.albedo_color.a = 0.25 + 0.55 * dusk
	dust.global_position = pp + Vector3(0, 2.5, 0)
	for chicken_index in range(chickens.size() - 1, -1, -1):
		var chicken: Dictionary = chickens[chicken_index]
		var home: Vector3 = chicken["home"]
		var phase: float = chicken["phase"]
		var chicken_node: Node3D = chicken["node"]
		if not is_instance_valid(chicken_node):
			chickens.remove_at(chicken_index)
			continue
		var stride := t * 1.8 + phase
		chicken_node.position.x = home.x + sin(t * 0.7 + phase) * 0.85
		chicken_node.position.y = 0.32 + absf(sin(stride)) * 0.035
		chicken_node.position.z = home.z + cos(t * 0.55 + phase) * 0.7
		var move_x := cos(t * 0.7 + phase) * 0.595
		var move_z := -sin(t * 0.55 + phase) * 0.385
		chicken_node.rotation.y = atan2(-move_x, -move_z)
		var chicken_head: Variant = chicken["head"]
		if not is_instance_valid(chicken_head):
			chickens.remove_at(chicken_index)
			continue
		var peck := maxf(0.0, sin(t * 2.4 + phase))
		chicken_head.rotation.x = -peck * 0.8
		chicken_head.position.y = 0.28 - peck * 0.36
		var legs: Array = chicken["legs"]
		if legs.size() < 2 or not is_instance_valid(legs[0]) or not is_instance_valid(legs[1]):
			chickens.remove_at(chicken_index)
			continue
		legs[0].rotation.x = sin(stride) * 0.55
		legs[1].rotation.x = -sin(stride) * 0.55
		chicken["call_timer"] = float(chicken["call_timer"]) - delta
		if chicken["call_timer"] <= 0.0:
			var player_distance := Vector2(chicken_node.global_position.x - pp.x, chicken_node.global_position.z - pp.z).length()
			if player_distance < 24.0:
				chicken_clucked.emit()
				chicken["call_timer"] = rng.randf_range(5.0, 9.0)
			else:
				chicken["call_timer"] = rng.randf_range(1.0, 2.0)
	if is_instance_valid(saw):
		saw.rotation.z += delta * 1.2
	for f in flick:
		var b: Color = f["base"]
		var k := 1.0
		if f["mode"] == 1:
			k = 1.0 if sin(t * 7.0 + f["ph"]) * sin(t * 13.0 + f["ph"] * 1.7) > -0.55 else 0.12
		elif f["mode"] == 2:
			k = 1.0 if fmod(t, 1.4) < 0.5 else 0.0
		else:
			k = 0.75 + 0.25 * sin(t * 5.0 + f["ph"]) * sin(t * 2.3 + f["ph"])
		k = roundf(k * 128.0) / 128.0
		var fc := Color(b.r * k, b.g * k, b.b * k)
		if f.has("last") and f["last"] == fc:
			continue
		f["last"] = fc
		f["m"].albedo_color = fc
	if fire_light != null:
		fire_light.light_energy = 1.1 + 0.3 * sin(t * 11.0) + 0.15 * sin(t * 23.0)
	if grave_light != null:
		grave_light.light_energy = 0.55 + 0.2 * sin(t * 7.0) * sin(t * 3.1)
	if gen_light != null and gen_light.visible:
		gen_light.light_energy = 2.3 + 0.2 * sin(t * 31.0)
	if car != null:
		car.update_lights(t)
	for it in interacts:
		if it["marker"] != null and not it["done"]:
			if absf(it["x"] - pp.x) > 70.0 or absf(it["z"] - pp.z) > 70.0:
				continue
			it["marker"].position.y = it["y0"] + sin(t * 2.0 + it["ph"]) * 0.06
	lamp_t -= delta
	if lamp_t <= 0.0:
		lamp_t = 0.3
		var order: Array = lamp_pos.duplicate()
		order.sort_custom(func(p, q): return Vector2(p.x - pp.x, p.z - pp.z).length_squared() < Vector2(q.x - pp.x, q.z - pp.z).length_squared())
		for i in lamp_lights.size():
			var l: OmniLight3D = lamp_lights[i]
			if i < order.size() and Vector2(order[i].x - pp.x, order[i].z - pp.z).length() < 50.0:
				l.position = order[i]
				l.visible = true
			else:
				l.visible = false
	var lamp_e := lerpf(1.2, 2.6, dusk) * (1.3 if power_on else 1.0)
	if absf(lamp_e - _lamp_e) > 0.003:
		_lamp_e = lamp_e
		for l in lamp_lights:
			l.light_energy = lamp_e
