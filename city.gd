extends Node3D
## SILENT HEAD – STADT-MAP (Ersatz für world.gd)

const CarScript = preload("res://car.gd")

signal item_given(kind: String, amount: int)
signal lore_found(id: int, text: String)
signal story_complete
signal power_restored
signal chicken_clucked

const HALF := 320.0
const ROAD_W := 7.0
const SCENE_POS := Vector3(0, 0, -150)
const START_POS := Vector3(0, 0, 140)
const GRID := 80.0
const SIDEWALK := 3.2

const CABINS := [Vector3(-30, 75, 0.0), Vector3(34, -10, 0.0), Vector3(-38, -85, 0.0)]
const NOTES := [
	"Zeitung: „Die Innenstadt stirbt. Nach dem Unfall im Hochhaus 7 will keiner mehr hier wohnen – dabei ist der Kaffee im Erdgeschoss der beste der Stadt.“",
	"Zettel an der Café-Tür: „Antworte nie, wenn dich jemand beim Namen ruft. Auch nicht, wenn es klingt wie der Barista unten.“",
	"Tagebuch: „Er sitzt immer am Fenster. Er trinkt keinen Kaffee. Er hört nur zu. Mit meiner Stimme bestellt er jedes Mal das Gleiche.“",
	"Notizblock: „Dreimal Silent Head sagen, haha. Wir waren im 12. Stock. Jonas hat gefilmt. Das Video ist leer. Nur Atmen.“",
	"Polizeinotiz: „Schrot hilft. Zielt auf den Kopf. In der Gasse am Brunnen ist er zuletzt gesehen worden – nie geradeaus laufen.“",
	"Zeitungsausschnitt, 1987: „Hochhaus 7: Bauarbeiter Heinrich V. nach Sturz aus dem 12. Stock verstummt. Kiefer zertrümmert. Seither hört man nachts jemanden im Treppenhaus atmen.“",
	"Smartphone, letzte Aufnahme: Kaffeedampf, Neonlicht, dann eine Stimme direkt am Mikrofon: „Er lernt, wie wir klingen. Er sagt nur, was er schon gehört hat.“",
	"Gedenktafel am Brunnen: „HEINRICH VOGT 1951–1987. Er hörte zu, bis niemand mehr zuhören wollte.“ Das Wasser im Brunnen ist rot.",
	"Polaroid am Café-Tisch: vier Jugendliche beim Kaffee, hinter ihnen im Fenster eine Gestalt. Rückseite, Mias Schrift: „Lärm macht ihn wütend. Licht macht ihn langsam.“",
	"Autoradio: Rauschen, dann Jonas atemlos: „Mia sagt, wir müssen zum Hochhaus 7. Der Generator braucht Benzin – im Café am Platz steht ein Kanister. Wenn die Lichter brennen, wird er langsamer. Hörst du? Langsamer—“ Dann nur Atmen."]
const CABIN_NOTES := [1, 2, 5]
const CABIN_LOOT := ["heal", "ammo", "fuel"]
const GRAVE_POS := Vector3(-95.0, 0.0, -40.0)
const HINTS := {
	"note": "Lesen", "crate": "Durchsuchen", "corpse": "Durchsuchen",
	"generator": "Generator starten", "campfire": "Kaffee trinken",
	"radio": "Zuhören", "grave": "Gedenktafel lesen", "camera": "Überwachung ansehen",
	"door": "Tür öffnen", "weapon": "Waffe nehmen", "item": "Gegenstand nehmen",
	"fish": "Im Brunnen angeln", "log": "Kiste durchsuchen"}
const WEAPON_NAMES := {"pistol": "Pistole", "rifle": "Gewehr", "minigun": "Minigun"}
const ITEM_NAMES := {"axe": "Axt", "iron_ore": "Eisenerz", "stone": "Stein"}

var rng := RandomNumberGenerator.new()
var touch := false
var tree_pos: Array = []
var tree_version := 0
var rock_pos: Array = []
var blocks: Array = []
var interacts: Array = []
var clearings: Array = []
var lamp_pos: Array = []
var lamp_lights: Array = []
var flick: Array = []
var car
var pedestrians: Array[Dictionary] = []
var traffic_lights: Array = []
var fishing_spots: Array = []
var pond_center := Vector3(55.0, 0.0, 60.0)
var pond_radius := 11.0
var journal: Array = []
var power_on := false
var fuel := 0
var gen_light: OmniLight3D
var grave_light: OmniLight3D
var lamp_broken: Array = []
var tex_cache := {}
var mat_cache := {}
var t := 0.0
var lamp_t := 0.0
var _lamp_e := -1.0
var phys: Node3D
var sky_root: Node3D
var moon: MeshInstance3D
var moon_mat: StandardMaterial3D
var star_mat: StandardMaterial3D
var dust: CPUParticles3D
var dust_mat: StandardMaterial3D

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
	return _add_mesh(parent, c, m, pos, rot)

func ball(parent: Node, r: float, pos: Vector3, m: Material, seg := 10) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(2, int(seg * 0.5))
	return _add_mesh(parent, s, m, pos)

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
	return Vector2(rng.randf_range(-HALF + margin, HALF - margin), rng.randf_range(-HALF + margin, HALF - margin))

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
			"fish": col = Color(0.4, 0.85, 1.0)
		var mk := ball(self, 0.07, pos + Vector3(0, 1.15, 0), mat(col, 1.0, true), 6)
		mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker = mk
	interacts.append({"x": pos.x, "z": pos.z, "done": false, "kind": kind, "text": text, "loot": loot, "marker": marker, "y0": pos.y + 1.15, "ph": pos.x + pos.z})

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
	return best

func hint_for(it: Dictionary) -> String:
	if it.get("kind", "") == "weapon":
		return String(WEAPON_NAMES.get(String(it.get("loot", "")), "Waffe")) + " nehmen"
	if it.get("kind", "") == "item":
		return String(ITEM_NAMES.get(String(it.get("loot", "")), "Gegenstand")) + " nehmen"
	return HINTS.get(it.get("kind", ""), "Benutzen")

func lore_total() -> int:
	return NOTES.size()

# Stubs (Stadt hat keine Bäume/Felsen)
func chop_tree(_i: int, _p := Vector3.ZERO) -> int: return 0
func tree_chop_hits(_i: int) -> int: return 0
func hit_log(_i: int) -> int: return 0
func hit_rock(_i: int) -> String: return ""
func rock_mine_hits(_i: int) -> int: return 0
func hit_chicken(_a: Area3D) -> bool: return false
func dig_ground(p: Vector3, _yaw: float) -> float: return dig_depth_at(p)
func dig_depth_at(_pos: Vector3) -> float: return 0.0
func place_ladder(_p: Vector3, _y: float) -> bool: return false
func ladder_near(_p: Vector3, _r := 0.9) -> Dictionary: return {}

func _crate(pos: Vector3, yaw := 0.0, loot := "heal") -> void:
	var c := box(self, Vector3(0.8, 0.55, 0.55), pos + Vector3(0, 0.28, 0), tmat("planks", Color(0.62, 0.45, 0.28), 0.6), Vector3(0, yaw, 0))
	box(c, Vector3(0.86, 0.08, 0.6), Vector3(0, 0.3, 0), tmat("planks", Color(0.4, 0.28, 0.16), 0.6))
	solid(pos + Vector3(0, 0.28, 0), Vector3(0.8, 0.55, 0.55), yaw)
	add_interact("crate", pos, "", loot)

func _weapon_display(parent: Node3D, weapon_id: String, pos: Vector3) -> void:
	var metal := mat(Color(0.16, 0.18, 0.18), 0.5)
	var wood := mat(Color(0.28, 0.18, 0.12), 0.8)
	var model := Node3D.new()
	model.position = pos
	parent.add_child(model)
	box(model, Vector3(0.75, 0.12, 0.12), Vector3(0, 0, 0), metal)
	box(model, Vector3(0.35, 0.15, 0.15), Vector3(-0.45, 0, 0), wood)
	box(model, Vector3(0.13, 0.22, 0.12), Vector3(-0.12, -0.16, 0), wood)
	add_interact("weapon", parent.global_transform * Vector3(pos.x, 0, -1.45), "", weapon_id)
	# ------------------------------------------------------------------ Aufbau
func build(is_touch: bool) -> void:
	touch = is_touch
	rng.seed = 7
	phys = Node3D.new()
	add_child(phys)
	clearings = [
		Vector3(SCENE_POS.x, SCENE_POS.z, 13.0),
		Vector3(START_POS.x, START_POS.z, 7.0),
		Vector3(0, 0, 20.0),
		Vector3(pond_center.x, pond_center.z, pond_radius + 5.0),
		Vector3(GRAVE_POS.x, GRAVE_POS.z, 7.0)]
	for c in CABINS:
		clearings.append(Vector3(c.x, c.y, 12.0))
	_ground()
	_road_network()
	_sidewalks()
	_crosswalks()
	_skyscrapers()
	for i in CABINS.size():
		var c: Vector3 = CABINS[i]
		_coffee_shop(c.x, c.y, CABIN_NOTES[i], CABIN_LOOT[i])
	_plaza()
	_park()
	_streetlamps()
	_traffic_lights()
	_parked_cars()
	_trash_bins()
	_hydrants()
	_subway_entrance()
	_pedestrians_v2()
	_car()
	_crime_scene()
	_memorial()
	_sky()
	_particles()
	#_more_towers_disabled
	_tower_plazas()
	_spawn_interior_npcs()

func _ground() -> void:
	var gm := mat(Color.WHITE)
	gm.albedo_texture = _noise_tex(0.03, [Color(0.16, 0.17, 0.18), Color(0.22, 0.22, 0.23), Color(0.19, 0.2, 0.21)])
	gm.uv1_scale = Vector3(14, 14, 1)
	gm.normal_enabled = true
	gm.normal_texture = _normal_tex(0.06, 5.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0 + 80.0, HALF * 2.0 + 80.0)
	ground.mesh = pm
	ground.material_override = gm
	add_child(ground)

func _road_network() -> void:
	var asphalt := tmat("concrete", Color(0.28, 0.29, 0.3), 0.35)
	var line_mat := mat(Color(0.85, 0.75, 0.2), 0.8, true)
	var length := HALF * 2.0
	var ns_road := MeshInstance3D.new()
	var ns_pm := PlaneMesh.new()
	ns_pm.size = Vector2(ROAD_W, length)
	ns_road.mesh = ns_pm
	ns_road.material_override = asphalt
	ns_road.position.y = 0.02
	add_child(ns_road)
	var z := -HALF
	while z < HALF:
		if absf(z) > ROAD_W * 0.6:
			var ew := MeshInstance3D.new()
			var ew_pm := PlaneMesh.new()
			ew_pm.size = Vector2(length, ROAD_W)
			ew.mesh = ew_pm
			ew.material_override = asphalt
			ew.position = Vector3(0, 0.02, z)
			add_child(ew)
		z += GRID
	var dash := BoxMesh.new()
	dash.size = Vector3(0.2, 0.01, 2.4)
	var dmm := make_mm(dash, line_mat, 160, false, null, 0.0, Vector3.ZERO, false)
	for k in 160:
		dmm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, -HALF + k * 2.5)))

func _sidewalks() -> void:
	var walk := tmat("concrete", Color(0.55, 0.55, 0.5), 0.5)
	var length := HALF * 2.0
	for side in [-1.0, 1.0]:
		box(self, Vector3(SIDEWALK, 0.12, length), Vector3(side * (ROAD_W / 2.0 + SIDEWALK / 2.0), 0.06, 0), walk)
		solid(Vector3(side * (ROAD_W / 2.0 + SIDEWALK / 2.0), 0.06, 0), Vector3(SIDEWALK, 0.12, length))

func _crosswalks() -> void:
	var stripe := mat(Color(0.85, 0.85, 0.8), 0.9)
	var z := -HALF + 30.0
	while z < HALF:
		for k in 6:
			box(self, Vector3(0.5, 0.012, 2.6), Vector3(-ROAD_W / 2.0 + k * 1.4, 0.03, z), stripe)
		z += GRID
func _skyscrapers() -> void:
	var glass := mat(Color(0.14, 0.2, 0.26), 0.25)
	var glass_lit := mat(Color(1.0, 0.85, 0.55), 0.4, true)
	var concrete := tmat("concrete", Color(0.6, 0.6, 0.58), 0.35)
	var neon_cols := [Color(0.9, 0.2, 0.6), Color(0.2, 0.8, 0.9), Color(0.9, 0.6, 0.15)]
	var towers := [
		[Vector3(-40, 0, -40), Vector3(12, 45, 12), neon_cols[0]],
		[Vector3(45, 0, -20), Vector3(10, 38, 14), neon_cols[1]],
		[Vector3(-55, 0, 30), Vector3(14, 52, 14), neon_cols[2]],
		[Vector3(55, 0, 55), Vector3(11, 42, 11), neon_cols[0]],
		[Vector3(-30, 0, 100), Vector3(10, 30, 12), neon_cols[1]],
		[Vector3(30, 0, 95), Vector3(12, 34, 10), neon_cols[2]],
		[Vector3(-70, 0, -95), Vector3(13, 48, 13), neon_cols[0]],
		[Vector3(70, 0, -100), Vector3(11, 40, 15), neon_cols[1]]]
	for tower in towers:
		var pos: Vector3 = tower[0]
		var sz: Vector3 = tower[1]
		var neon: Color = tower[2]
		var tower_root := Node3D.new()
		add_child(tower_root)
		box(tower_root, sz, pos + Vector3(0, sz.y / 2.0, 0), concrete)
		var floors := int(sz.y / 3.0)
		for f in floors:
			var fy := 2.0 + f * 3.0
			if fy > sz.y - 2.0:
				break
			var fmat := glass_lit if rng.randf() < 0.35 else glass
			box(tower_root, Vector3(sz.x - 0.5, 1.4, 0.15), pos + Vector3(0, fy, -sz.z / 2.0 - 0.1), fmat)
			box(tower_root, Vector3(0.15, 1.4, sz.z - 0.5), pos + Vector3(-sz.x / 2.0 - 0.1, fy, 0), fmat)
			box(tower_root, Vector3(0.15, 1.4, sz.z - 0.5), pos + Vector3(sz.x / 2.0 + 0.1, fy, 0), fmat)
		box(tower_root, Vector3(sz.x + 0.4, 0.6, sz.z + 0.4), pos + Vector3(0, sz.y + 0.3, 0), concrete)
		var sign_mat := mat(neon, 0.4, true)
		box(tower_root, Vector3(sz.x * 0.8, 0.8, 0.15), pos + Vector3(0, sz.y * 0.6, -sz.z / 2.0 - 0.05), sign_mat)
		flick.append({"m": sign_mat, "base": neon, "ph": pos.x * 0.1, "mode": 1})
		box(tower_root, Vector3(2.5, 3.2, 0.2), pos + Vector3(0, 1.6, -sz.z / 2.0 - 0.15), mat(Color(0.2, 0.15, 0.12), 0.7))
		box(tower_root, Vector3(2.8, 0.15, 0.25), pos + Vector3(0, 3.3, -sz.z / 2.0 - 0.15), mat(Color(1.0, 0.85, 0.4), 0.5, true))
		solid(pos + Vector3(0, sz.y / 2.0, 0), sz, 0.0, tower_root)
		blocks.append({"p": Vector2(pos.x, pos.z), "s": Vector2(sz.x, sz.z), "c": Color(0.3, 0.35, 0.45), "round": false})

func _coffee_shop(x: float, z: float, note_i: int, loot: String) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, 0, z)
	add_child(g)
	var wall := tmat("concrete", Color(0.75, 0.7, 0.62), 0.4)
	var wood := tmat("planks", Color(0.5, 0.35, 0.22), 0.5)
	_cafe_walls_vis(g, wall)
	var glass := mat(Color(0.3, 0.4, 0.5), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.55
	box(g, Vector3(6.5, 2.2, 0.1), Vector3(0, 1.6, 3.05), glass)
	box(g, Vector3(1.2, 2.4, 0.12), Vector3(-2.8, 1.2, 3.05), mat(Color(0.35, 0.22, 0.14)))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position = Vector3(0, 2.5, 0)
	g.add_child(light)
	flick.append({"m": glass, "base": Color(1.0, 0.85, 0.5), "ph": x * 0.3, "mode": 0})
	box(g, Vector3(5.5, 1.1, 1.0), Vector3(0, 0.55, -1.5), wood)
	box(g, Vector3(6.0, 0.15, 1.1), Vector3(0, 1.15, -1.5), tmat("concrete", Color(0.4, 0.4, 0.42), 0.3))
	var metal := mat(Color(0.7, 0.72, 0.75), 0.3)
	box(g, Vector3(0.9, 0.7, 0.6), Vector3(-1.8, 1.5, -1.5), metal)
	var ember := mat(Color(0.9, 0.4, 0.1), 1.0, true)
	box(g, Vector3(0.15, 0.15, 0.15), Vector3(-1.8, 1.9, -1.5), ember)
	flick.append({"m": ember, "base": Color(0.9, 0.4, 0.1), "ph": z * 0.1, "mode": 0})
	box(g, Vector3(1.6, 0.8, 0.7), Vector3(1.8, 1.5, -1.5), mat(Color(0.6, 0.5, 0.3), 0.5))
	for tx in [-2.5, 0.0, 2.5]:
		_tableset(g, Vector3(tx, 0, 4.5), x + tx)
	add_interact("note", g.transform * Vector3(0, 0, 2.0), NOTES[note_i])
	_crate(g.transform * Vector3(-3.2, 0, 5.5), 0.0, loot)
	_weapon_display(g, "pistol", Vector3(3.0, 1.2, 2.7))
	solid(Vector3(x, 2, z), Vector3(8, 4, 6), 0.0, g)
	blocks.append({"p": Vector2(x, z), "s": Vector2(8, 6), "c": Color(0.7, 0.6, 0.5), "round": false})

func _cafe_walls_vis(parent: Node, wall: Material) -> void:
	box(parent, Vector3(8.0, 4.0, 0.2), Vector3(0, 2.0, -2.9), wall)
	box(parent, Vector3(0.2, 4.0, 5.8), Vector3(-3.9, 2.0, 0), wall)
	box(parent, Vector3(0.2, 4.0, 5.8), Vector3(3.9, 2.0, 0), wall)
	box(parent, Vector3(0.5, 4.0, 0.2), Vector3(-3.75, 2.0, 2.9), wall)
	box(parent, Vector3(0.5, 4.0, 0.2), Vector3(3.75, 2.0, 2.9), wall)
	box(parent, Vector3(7.0, 0.5, 0.2), Vector3(0, 3.75, 2.9), wall)

func _spawn_interior_npcs() -> void:
	var shirt_colors := [Color(0.25, 0.42, 0.62), Color(0.55, 0.2, 0.16), Color(0.22, 0.48, 0.3)]
	var skin := mat(Color(0.8, 0.65, 0.55), 0.7)
	for i in CABINS.size():
		var cafe_pos: Vector3 = CABINS[i]
		var npc := Node3D.new()
		npc.position = Vector3(cafe_pos.x + 1.7, 0, cafe_pos.y + 0.4)
		add_child(npc)
		var shirt := mat(shirt_colors[i % shirt_colors.size()], 0.8)
		cyl(npc, 0.18, 0.22, 1.0, Vector3(0, 1.1, 0), shirt, 8)
		ball(npc, 0.15, Vector3(0, 1.75, 0), skin, 10)

func _tableset(parent: Node, at: Vector3, _seed_f: float) -> void:
	var wood := mat(Color(0.4, 0.25, 0.15), 0.8)
	cyl(parent, 0.55, 0.55, 0.06, at + Vector3(0, 0.78, 0), wood, 12)
	cyl(parent, 0.06, 0.06, 0.78, at + Vector3(0, 0.39, 0), wood, 6)
	for sx in [-1.0, 1.0]:
		box(parent, Vector3(0.45, 0.05, 0.45), at + Vector3(sx * 0.9, 0.48, 0), wood)
		box(parent, Vector3(0.45, 0.5, 0.05), at + Vector3(sx * 1.1, 0.75, 0), wood)
	for sx in [-0.3, 0.3]:
		cyl(parent, 0.08, 0.06, 0.1, at + Vector3(sx, 0.86, 0), mat(Color(0.95, 0.92, 0.85), 0.4), 10)
		if rng.randf() < 0.6:
			var steam := ball(parent, 0.03, at + Vector3(sx, 0.95, 0), mat(Color(0.9, 0.9, 0.9, 0.3), 1.0, true), 6)
			steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cyl(parent, 1.4, 1.4, 0.05, at + Vector3(0, 2.4, 0), mat(Color(0.7, 0.2, 0.2), 0.8), 12)
	cyl(parent, 0.05, 0.05, 2.4, at + Vector3(0, 1.2, 0), mat(Color(0.3, 0.3, 0.3)), 6)
func _plaza() -> void:
	var stone := tmat("concrete", Color(0.6, 0.58, 0.55), 0.4)
	var plaza := cyl(self, 18, 18, 0.02, Vector3(0, 0.02, 0), stone, 32)
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cyl(self, 6.0, 6.0, 0.6, Vector3(0, 0.3, 0), stone, 24)
	var water := mat(Color(0.1, 0.25, 0.35), 0.05)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color.a = 0.65
	cyl(self, 5.7, 5.7, 0.05, Vector3(0, 0.62, 0), water, 24)
	cyl(self, 0.5, 0.7, 3.0, Vector3(0, 1.8, 0), stone, 8)
	ball(self, 0.9, Vector3(0, 3.4, 0), stone, 12)
	solid_cyl(Vector3(0, 0.3, 0), 6.0, 0.6)
	fishing_spots.append({"x": 0.0, "z": 0.0, "radius": 6.7})
	add_interact("fish", Vector3(7.1, 0, 0), "", "fish")
	for i in 4:
		var a := float(i) / 4.0 * TAU + PI / 4.0
		var sp := Vector3(cos(a) * 11.0, 0, sin(a) * 11.0)
		box(self, Vector3(2.5, 0.9, 1.5), sp + Vector3(0, 0.45, 0), tmat("planks", Color(0.55, 0.4, 0.25), 0.5))
		box(self, Vector3(2.7, 0.1, 1.7), sp + Vector3(0, 0.95, 0), mat(Color(0.8, 0.2, 0.2) if i % 2 == 0 else Color(0.2, 0.5, 0.8), 0.8))
		for j in 3:
			ball(self, 0.12, sp + Vector3(-0.7 + j * 0.7, 1.05, 0), mat(Color(0.9, 0.3, 0.2) if j % 2 == 0 else Color(0.95, 0.75, 0.2), 0.6), 8)
	for i in 4:
		var a := float(i) / 4.0 * TAU + PI / 8.0
		var bp := Vector3(cos(a) * 14.0, 0, sin(a) * 14.0)
		box(self, Vector3(1.8, 0.08, 0.5), bp + Vector3(0, 0.5, 0), mat(Color(0.4, 0.28, 0.18)), Vector3(0, a + PI / 2.0, 0))
		box(self, Vector3(1.8, 0.5, 0.08), bp + Vector3(0, 0.75, 0), mat(Color(0.4, 0.28, 0.18)), Vector3(0, a + PI / 2.0, 0))
	for i in 6:
		var a := float(i) / 6.0 * TAU + PI / 6.0
		_tableset(self, Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), float(i))
	blocks.append({"p": Vector2(0, 0), "s": Vector2(36, 36), "c": Color(0.5, 0.5, 0.55), "round": true})

func _park() -> void:
	var c := pond_center
	var grass := mat(Color(0.15, 0.3, 0.12), 0.9)
	cyl(self, pond_radius + 12.0, pond_radius + 12.0, 0.015, c + Vector3(0, 0.01, 0), grass, 32)
	var water := mat(Color(0.05, 0.15, 0.2), 0.05)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color.a = 0.7
	cyl(self, pond_radius, pond_radius, 0.05, c + Vector3(0, 0.08, 0), water, 28)
	solid_cyl(c + Vector3(0, 0.8, 0), pond_radius, 1.6)
	fishing_spots.append({"x": c.x, "z": c.z, "radius": pond_radius + 0.7})
	add_interact("fish", c + Vector3(pond_radius + 1.1, 0, 0), "", "fish")
	var reed := mat(Color(0.2, 0.35, 0.15), 0.9)
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var r := pond_radius + 0.5 + rng.randf_range(-0.2, 0.8)
		cyl(self, 0.03, 0.04, 0.8, c + Vector3(cos(a) * r, 0.4, sin(a) * r), reed, 5)
	for i in 8:
		var a := float(i) / 8.0 * TAU + 0.3
		var r := pond_radius + 6.0 + rng.randf_range(0, 3)
		var tp := c + Vector3(cos(a) * r, 0, sin(a) * r)
		cyl(self, 0.15, 0.28, 4.5, tp + Vector3(0, 2.25, 0), tmat("bark", Color(0.4, 0.28, 0.18), 0.7), 8)
		ball(self, 1.8, tp + Vector3(0, 5.0, 0), mat(Color(0.15, 0.35, 0.15), 0.9), 10)
		solid(tp + Vector3(0, 2.0, 0), Vector3(0.6, 4.0, 0.6))
	for i in 4:
		var a := float(i) / 4.0 * TAU
		var bp := c + Vector3(cos(a) * (pond_radius + 2.5), 0, sin(a) * (pond_radius + 2.5))
		box(self, Vector3(1.8, 0.08, 0.5), bp + Vector3(0, 0.5, 0), mat(Color(0.4, 0.28, 0.18)))
		box(self, Vector3(1.8, 0.5, 0.08), bp + Vector3(0, 0.75, 0), mat(Color(0.4, 0.28, 0.18)))
	add_interact("note", c + Vector3(-pond_radius - 1.5, 0, 0), NOTES[8])

func _streetlamps() -> void:
	var pole := tmat("metal", Color(0.22, 0.22, 0.24), 0.8, 0.6)
	var i := 0
	var z := 160.0
	while z > -160.0:
		for side in [-1.0, 1.0]:
			var x: float = float(side) * (ROAD_W / 2.0 + 1.0)
			cyl(self, 0.07, 0.11, 5.5, Vector3(x, 2.75, z), pole, 6)
			var head := mat(Color(1.0, 0.85, 0.55), 0.5, true)
			box(self, Vector3(0.4, 0.15, 0.4), Vector3(x - side * 0.2, 5.5, z), head)
			solid(Vector3(x, 2.75, z), Vector3(0.25, 5.5, 0.25))
			var broken := (i % 5 == 2)
			flick.append({"m": head, "base": Color(1.0, 0.85, 0.55), "ph": float(i) * 1.7, "mode": 1 if broken else 0, "lamp": true})
			if not broken:
				lamp_pos.append(Vector3(x - side * 0.2, 5.2, z))
			else:
				lamp_broken.append(Vector3(x - side * 0.2, 5.2, z))
		i += 1
		z -= 20.0
	for k in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.5)
		l.omni_range = 18.0
		l.light_energy = 2.0
		l.visible = false
		add_child(l)
		lamp_lights.append(l)

func _traffic_lights() -> void:
	var pole := tmat("metal", Color(0.2, 0.2, 0.22), 0.7, 0.6)
	var z := -60.0
	while z < 200.0:
		for side in [-1.0, 1.0]:
			var x: float = float(side) * (ROAD_W / 2.0 + 2.0)
			cyl(self, 0.06, 0.08, 3.5, Vector3(x, 1.75, z), pole, 6)
			box(self, Vector3(0.4, 0.9, 0.3), Vector3(x - side * 0.2, 3.0, z), mat(Color(0.15, 0.15, 0.15)))
			var green := mat(Color(0.1, 1.0, 0.3), 1.0, true)
			var red := mat(Color(1.0, 0.1, 0.1), 1.0, true)
			ball(self, 0.08, Vector3(x - side * 0.2, 3.25, z + 0.16), red, 8)
			ball(self, 0.08, Vector3(x - side * 0.2, 2.75, z + 0.16), green, 8)
			traffic_lights.append({"red": red, "green": green, "phase": z * 0.05})
		z += 120.0
func _parked_cars() -> void:
	var colors := [Color(0.15, 0.2, 0.4), Color(0.4, 0.05, 0.05), Color(0.15, 0.15, 0.15), Color(0.6, 0.6, 0.55)]
	for i in 10:
		var z := -HALF + 20.0 + i * 40.0
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (ROAD_W / 2.0 + 2.5)
		var col: Color = colors[i % colors.size()]
		box(self, Vector3(1.9, 0.7, 4.2), Vector3(x, 0.7, z), mat(col, 0.4))
		box(self, Vector3(1.7, 0.6, 2.2), Vector3(x, 1.4, z - 0.2), mat(Color(0.1, 0.1, 0.12), 0.2))
		solid(Vector3(x, 1.0, z), Vector3(1.9, 1.8, 4.3))
		blocks.append({"p": Vector2(x, z), "s": Vector2(2.0, 4.4), "c": col, "round": false})

func _trash_bins() -> void:
	var metal := mat(Color(0.25, 0.3, 0.28), 0.5)
	for i in 20:
		var z := -HALF + 15.0 + i * 20.0
		var x := -ROAD_W / 2.0 - 1.5 if i % 2 == 0 else ROAD_W / 2.0 + 1.5
		cyl(self, 0.35, 0.3, 0.9, Vector3(x, 0.45, z), metal, 8)
		cyl(self, 0.38, 0.38, 0.05, Vector3(x, 0.92, z), metal, 8)

func _hydrants() -> void:
	var red := mat(Color(0.75, 0.1, 0.08), 0.5)
	for i in 8:
		var z := -HALF + 40.0 + i * 50.0
		var x := ROAD_W / 2.0 + 1.8
		cyl(self, 0.15, 0.18, 0.7, Vector3(x, 0.35, z), red, 8)
		cyl(self, 0.1, 0.1, 0.1, Vector3(x, 0.75, z), red, 8)
		box(self, Vector3(0.4, 0.08, 0.08), Vector3(x, 0.55, z), red)

func _subway_entrance() -> void:
	var c := Vector3(35, 0, 80)
	var stone := tmat("concrete", Color(0.5, 0.5, 0.5), 0.4)
	box(self, Vector3(4, 0.02, 3), c + Vector3(0, 0.03, 0), mat(Color(0.02, 0.02, 0.03)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			cyl(self, 0.04, 0.04, 1.2, c + Vector3(sx * 2.0, 0.6, sz * 1.5), stone, 6)
		box(self, Vector3(0.06, 0.06, 3.0), c + Vector3(sx * 2.0, 1.1, 0), stone)
	var sign_mat := mat(Color(0.9, 0.2, 0.2), 0.6)
	box(self, Vector3(1.5, 0.5, 0.1), c + Vector3(0, 2.0, -1.5), sign_mat)
	add_interact("note", c + Vector3(0, 0, -2.0), NOTES[0])

func _pedestrians() -> void:
	var shirt_cols := [Color(0.3, 0.35, 0.6), Color(0.6, 0.2, 0.2), Color(0.2, 0.5, 0.3), Color(0.7, 0.6, 0.2)]
	var skin := mat(Color(0.8, 0.65, 0.55), 0.7)
	for i in 18:
		var x := rng.randf_range(-HALF + 20, HALF - 20)
		var z := rng.randf_range(-HALF + 20, HALF - 20)
		if absf(x) < ROAD_W / 2.0 + 5.0:
			continue
		var root := Node3D.new()
		root.position = Vector3(x, 0, z)
		add_child(root)
		var shirt := mat(shirt_cols[i % shirt_cols.size()], 0.8)
		cyl(root, 0.18, 0.22, 1.0, Vector3(0, 1.1, 0), shirt, 8)
		ball(root, 0.15, Vector3(0, 1.75, 0), skin, 10)
		for sx in [-0.08, 0.08]:
			cyl(root, 0.06, 0.06, 0.9, Vector3(sx, 0.45, 0), mat(Color(0.15, 0.15, 0.2)), 6)
		for sx in [-0.22, 0.22]:
			cyl(root, 0.05, 0.05, 0.75, Vector3(sx, 1.15, 0), shirt, 6)
		cyl(root, 0.06, 0.05, 0.1, Vector3(0.28, 0.85, 0.1), mat(Color(0.95, 0.92, 0.85), 0.4), 8)
		pedestrians.append({"node": root, "home": Vector3(x, 0, z), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.2, 0.5)})

func _car() -> void:
	car = CarScript.new()
	add_child(car)
	car.setup(self)

func _crime_scene() -> void:
	var defs := [
		[Vector3(-1.3, 0, -0.5), 0.4, Color(0.54, 0.16, 0.16), "Jonas. Hand umklammert das Handy. In der Jackentasche: Verbandszeug.", "heal"],
		[Vector3(1.1, 0, 1.0), -0.7, Color(0.16, 0.35, 0.54), "Mia. Sie hat bis zuletzt geschwiegen. In ihrer Tasche: Schrotpatronen.", "ammo"],
		[Vector3(0.1, 0, -2.0), 2.4, Color(0.23, 0.48, 0.23), "Tobi. Kaffeetasse neben ihm. Auf der Tischplatte steht: HALLO.", "heal"]]
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
		ball(g, 0.15, Vector3(0, 0.15, -0.55), mat(Color(0.72, 0.6, 0.53)))
		add_child(g)
		add_interact("corpse", SCENE_POS + d[0], d[3], d[4])
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

func _memorial() -> void:
	var p := GRAVE_POS
	var stone := tmat("concrete", Color(0.6, 0.6, 0.62), 0.5, 0.95)
	box(self, Vector3(2.5, 0.3, 2.5), p + Vector3(0, 0.15, 0), stone)
	box(self, Vector3(1.8, 2.2, 0.2), p + Vector3(0, 1.4, -1.0), stone)
	var inscription := mat(Color(0.7, 0.8, 1.0), 1.0, true)
	box(self, Vector3(1.4, 0.1, 0.05), p + Vector3(0, 1.8, -1.11), inscription)
	box(self, Vector3(1.2, 0.06, 0.05), p + Vector3(0, 1.5, -1.11), inscription)
	cyl(self, 0.5, 0.4, 0.3, p + Vector3(0, 0.45, 0.6), mat(Color(0.5, 0.35, 0.25), 0.9), 8)
	var fl := mat(Color(0.9, 0.2, 0.3), 0.8)
	for k in 5:
		var a := float(k) / 5.0 * TAU
		ball(self, 0.12, p + Vector3(cos(a) * 0.3, 0.7, sin(a) * 0.3 + 0.6), fl, 6)
	grave_light = OmniLight3D.new()
	grave_light.light_color = Color(0.55, 0.7, 1.0)
	grave_light.omni_range = 6.0
	grave_light.light_energy = 0.6
	grave_light.position = p + Vector3(0, 1.5, 0)
	add_child(grave_light)
	solid(p + Vector3(0, 0.5, 0), Vector3(2.5, 1.0, 2.5))
	add_interact("grave", p + Vector3(0, 0, -2.0), NOTES[7])
	blocks.append({"p": Vector2(p.x, p.z), "s": Vector2(4, 4), "c": Color(0.6, 0.7, 0.9), "round": false})
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

# ------------------------------------------------------------------ Texturen
func _gen_tex(kind: String) -> ImageTexture:
	if tex_cache.has(kind):
		return tex_cache[kind]
	var S := 64 if touch else 128
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
					var pw := maxi(1, S / 8)
					var pl := floori(float(x) / float(pw))
					var grain: float = a.get_pixel(x, (pl * 17) % S).r
					var v := 0.55 + 0.3 * grain + 0.14 * n2 + 0.05 * float((pl * 37) % 7)
					if x % pw == 0:
						v *= 0.35
					c = Color(v, v * 0.92, v * 0.8)
				"bark":
					var ridge := sin(float(x) / float(S) * TAU * 8.0 + n1 * 4.0)
					var v := 0.5 + 0.25 * (ridge * 0.5 + 0.5) + 0.2 * n2
					c = Color(v, v * 0.9, v * 0.8)
				"concrete":
					var v := 0.66 + 0.2 * n2 + 0.1 * n1
					if (x * 7 + y * 13) % 23 == 0:
						v *= 0.72
					c = Color(v, v, v * 0.97)
				"metal":
					var sc := float((y * 131) % 17) / 17.0
					var v := 0.58 + 0.12 * sc + 0.2 * n2
					c = Color(v * 0.95, v, v * 1.05)
				"needles":
					var v := 0.55 + 0.35 * n2 + 0.1 * n1
					c = Color(v * 0.85, v, v * 0.8)
				_:
					c = Color(n1, n1, n1)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	tex_cache[kind] = tx
	return tx

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
	# ------------------------------------------------------------------ Generator
func _generator() -> void:
	var g := Node3D.new()
	g.position = Vector3(35, 0, 76)
	add_child(g)
	box(g, Vector3(1.5, 1.0, 0.9), Vector3(0, 0.55, 0), tmat("metal", Color(0.75, 0.2, 0.12), 0.8, 0.5))
	box(g, Vector3(1.0, 0.5, 0.95), Vector3(0, 0.3, 0), tmat("metal", Color(0.15, 0.15, 0.16), 0.8))
	cyl(g, 0.07, 0.07, 0.7, Vector3(0.5, 1.3, 0.2), tmat("metal", Color(0.3, 0.3, 0.3), 0.8), 6)
	var lamp_mat := mat(Color(1.0, 0.1, 0.05), 0.5, true)
	box(g, Vector3(0.14, 0.14, 0.06), Vector3(-0.5, 0.95, 0.47), lamp_mat)
	gen_light = OmniLight3D.new()
	gen_light.light_color = Color(1.0, 0.85, 0.55)
	gen_light.omni_range = 14.0
	gen_light.light_energy = 2.3
	gen_light.position = Vector3(0, 1.8, 0.5)
	gen_light.visible = false
	g.add_child(gen_light)
	solid(Vector3(35, 0.55, 76), Vector3(1.5, 1.1, 0.9))
	add_interact("generator", Vector3(35, 0, 77.4))

# ------------------------------------------------------------------ Benutzen
func use(it: Dictionary) -> Dictionary:
	var res := {"ok": false, "msg": "", "text": "", "give": {}}
	if it.is_empty() or it["done"]:
		return res
	var kind: String = it["kind"]
	match kind:
		"weapon":
			res["give"] = {"weapon": String(it["loot"])}
			res["msg"] = WEAPON_NAMES.get(String(it["loot"]), "Waffe") + " aufgenommen"
		"fish":
			res["give"] = {"item": "fish"}
			res["msg"] = "Fisch gefangen"
		"item":
			res["give"] = {"item": String(it["loot"])}
			res["msg"] = ITEM_NAMES.get(String(it["loot"]), "Gegenstand") + " aufgenommen"
		"generator":
			if fuel < 1:
				res["msg"] = "Der Tank ist leer. Irgendwo in einem Café steht ein Kanister…"
				return res
			fuel -= 1
			_power_on()
			res["msg"] = "Der Generator springt an. Neonlicht flutet die Straße."
		"campfire":
			res["give"] = {"hp": 35}
			res["msg"] = "Du trinkst einen Kaffee. Für einen Moment ist es fast still."
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
					res["msg"] = "Benzinkanister – der Generator im U-Bahn-Schacht braucht ihn."
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
	if gen_light != null:
		gen_light.visible = true
	power_restored.emit()

# ------------------------------------------------------------------ Crafting-Stubs (nur damit inventory.gd nicht crasht)
func build_workbench(_pos: Vector3, _yaw: float) -> void:
	_crate(_pos, _yaw, "heal")
func build_station(kind: String, pos: Vector3) -> void:
	add_interact(kind, pos)

# ------------------------------------------------------------------ Update
func update(pp: Vector3, dusk: float, delta: float) -> void:
	t += delta
	if sky_root != null:
		sky_root.position = pp
	var a := clampf((dusk - 0.2) * 1.6, 0.0, 1.0)
	if star_mat != null:
		star_mat.albedo_color.a = a
	if moon_mat != null:
		moon_mat.albedo_color.a = a
	if moon != null:
		moon.visible = a > 0.02
	if dust_mat != null:
		dust_mat.albedo_color.a = 0.25 + 0.55 * dusk
	if dust != null:
		dust.global_position = pp + Vector3(0, 2.5, 0)
	for ped in pedestrians:
		var home: Vector3 = ped["home"]
		var phase: float = float(ped["phase"])
		var spd: float = float(ped["speed"])
		var node: Node3D = ped["node"]
		node.position.x = home.x + sin(t * spd + phase) * 3.0
		node.position.z = home.z + cos(t * spd * 0.8 + phase) * 3.0
		var dx := cos(t * spd + phase) * spd
		var dz := -sin(t * spd * 0.8 + phase) * spd * 0.8
		if absf(dx) + absf(dz) > 0.01:
			node.rotation.y = atan2(-dx, -dz)
	for tl in traffic_lights:
		var p := fmod(t + float(tl["phase"]), 6.0)
		var is_green := p < 3.0
		var red_m: StandardMaterial3D = tl["red"]
		var green_m: StandardMaterial3D = tl["green"]
		red_m.emission_enabled = not is_green
		red_m.emission = Color(1.0, 0.1, 0.1) if not is_green else Color.BLACK
		green_m.emission_enabled = is_green
		green_m.emission = Color(0.1, 1.0, 0.3) if is_green else Color.BLACK
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
	if grave_light != null:
		grave_light.light_energy = 0.55 + 0.2 * sin(t * 7.0) * sin(t * 3.1)
	if gen_light != null and gen_light.visible:
		gen_light.light_energy = 2.3 + 0.2 * sin(t * 31.0)
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
# ------------------------------------------------------------------ MONSTER & STORY
const EnemyScript = preload("res://enemy.gd")
var _hunters_spawned := false
var _beats_played := 0

const CITY_BEATS := [
	[Vector3(0, 0, 120), "Die Stadt… verlassen. Lichter brennen, aber niemand ist auf der Straße.", "me", 3.5],
	[Vector3(0, 0, 80), "Kaffeedampf aus den Cafés. Die Tassen dampfen noch. Wo sind die Menschen?", "me", 4.0],
	[Vector3(0, 0, 30), "Da ist eine Gestalt am Brunnen. Kein Mund. Sie bewegt sich nicht. Noch nicht.", "me", 4.5],
	[Vector3(0, 0, -30), "Du riechst wie dein Freund. Nach Angst. Nach Blut.", "boss", 4.0],
	[Vector3(0, 0, -100), "Silent Head. Heinrich Vogt. Ich weiß jetzt, wer er war. Ich weiß, wie er endet.", "me", 4.5],
	[Vector3(0, 0, -140), "Die Gedenktafel am Brunnen. Sie blutet. Ich muss den Generator starten.", "me", 4.0]]

func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	var m = get_parent()
	if m == null or m.state == "menu":
		return
	var p = m.player
	if p == null or not p.alive:
		return
	if not _hunters_spawned:
		_hunters_spawned = true
		_spawn_hunters(m, p)
	_animate_crowd(_delta)
	_check_story(m, p)

func _spawn_hunters(m: Node, p: Node) -> void:
	var spots := [
		Vector3(-80, 0, -80), Vector3(80, 0, -80),
		Vector3(-80, 0, 80), Vector3(80, 0, 80)]
	for sp in spots:
		var e = EnemyScript.new()
		add_child(e)
		e.setup(true, m, p, sp)
		e.hp = 100.0
		e.max_hp = 100.0
		e.speed = 4.5
		e.s = 0.7
		e._apply_scale()
		m.toast("⚠ Etwas bewegt sich im Schatten…")

func _check_story(m: Node, p: Node) -> void:
	while _beats_played < CITY_BEATS.size():
		var b: Array = CITY_BEATS[_beats_played]
		var target: Vector3 = b[0]
		var dist := Vector2(p.global_position.x - target.x, p.global_position.z - target.z).length()
		if dist < 15.0 and m.has_method("_line"):
			m._line(b[1], b[2], b[3])
			_beats_played += 1
		else:
			break
# ------------------------------------------------------------------ MEHR TÜRME
func _more_towers() -> void:
	var cols := [Color(0.4, 0.45, 0.55), Color(0.55, 0.45, 0.35), Color(0.35, 0.5, 0.55)]
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	for i in 16:
		var a := float(i) / 16.0 * TAU
		var r := rng2.randf_range(120, 280)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var too_close := false
		for b in blocks:
			if Vector2(b["p"].x - pos.x, b["p"].y - pos.z).length() < 25.0:
				too_close = true
				break
		if too_close:
			continue
		var h := rng2.randf_range(25, 60)
		var sz := rng2.randf_range(8, 14)
		var col: Color = cols[i % cols.size()]
		box(self, Vector3(sz, h, sz), pos + Vector3(0, h / 2.0, 0), tmat("concrete", col, 0.35))
		var floors := int(h / 3.0)
		var lit := rng2.randf() < 0.4
		for f in floors:
			var fy := 2.0 + f * 3.0
			if fy > h - 2.0:
				break
			var fm: StandardMaterial3D = mat(Color(1.0, 0.85, 0.55), 0.4, true) if lit and rng2.randf() < 0.5 else mat(Color(0.14, 0.2, 0.26), 0.25)
			box(self, Vector3(sz - 0.4, 1.2, 0.12), pos + Vector3(0, fy, -sz / 2.0 - 0.06), fm)
			box(self, Vector3(0.12, 1.2, sz - 0.4), pos + Vector3(-sz / 2.0 - 0.06, fy, 0), fm)
			box(self, Vector3(0.12, 1.2, sz - 0.4), pos + Vector3(sz / 2.0 + 0.06, fy, 0), fm)
		box(self, Vector3(2.5, 3.2, 0.2), pos + Vector3(0, 1.6, -sz / 2.0 - 0.15), mat(Color(0.15, 0.1, 0.08), 0.7))
		box(self, Vector3(2.8, 0.15, 0.25), pos + Vector3(0, 3.3, -sz / 2.0 - 0.15), mat(Color(1.0, 0.85, 0.4), 0.5, true))
		cyl(self, 0.05, 0.08, 6.0, pos + Vector3(0, h + 3.0, 0), tmat("metal", Color(0.3, 0.3, 0.32), 0.8), 4)
		var antenna_led := mat(Color(1.0, 0.1, 0.1), 1.0, true)
		ball(self, 0.15, pos + Vector3(0, h + 6.1, 0), antenna_led, 6)
		flick.append({"m": antenna_led, "base": Color(1.0, 0.1, 0.1), "ph": i, "mode": 2})
		solid(pos + Vector3(0, h / 2.0, 0), Vector3(sz, h, sz))
		blocks.append({"p": Vector2(pos.x, pos.z), "s": Vector2(sz, sz), "c": col, "round": false})
# ------------------------------------------------------------------ Plazas um Türme
func _tower_plazas() -> void:
	var pave := tmat("concrete", Color(0.62, 0.6, 0.55), 0.9)
	var curb := mat(Color(0.35, 0.33, 0.3), 0.9)
	var plant := mat(Color(0.15, 0.3, 0.12), 0.9)
	var pot := mat(Color(0.4, 0.28, 0.18), 0.7)
	for b in blocks:
		var sz: Vector2 = b["s"]
		if sz.x < 6.0 or sz.y < 6.0:
			continue
		var p2: Vector2 = b["p"]
		var psize := sz + Vector2(8, 8)

		box(self, Vector3(psize.x, 0.04, psize.y), Vector3(p2.x, 0.04, p2.y), pave)
		for side in [-1.0, 1.0]:
			box(self, Vector3(psize.x + 0.4, 0.14, 0.3), Vector3(p2.x, 0.07, p2.y + side * psize.y / 2.0), curb)
			box(self, Vector3(0.3, 0.14, psize.y + 0.4), Vector3(p2.x + side * psize.x / 2.0, 0.07, p2.y), curb)
		for c in 4:
			var ca := float(c) / 4.0 * TAU + 0.5
			var cpos := Vector3(p2.x + cos(ca) * (psize.x / 2.0 - 0.5), 0, p2.y + sin(ca) * (psize.y / 2.0 - 0.5))
			cyl(self, 0.4, 0.3, 0.6, cpos + Vector3(0, 0.3, 0), pot, 8)
			ball(self, 0.5, cpos + Vector3(0, 0.85, 0), plant, 8)
# ------------------------------------------------------------------ Passanten mit Hunden
var _phrases := ["Schöner Abend…", "Hast du das gehört?", "Es ist so still hier.", "Wo ist eigentlich alle hin?", "Der Kaffee hier ist der beste.", "Komm, wir gehen heim.", "Was ist das für ein Geräusch?"]

func _pedestrians_v2() -> void:
	var shirt_cols := [Color(0.3, 0.35, 0.6), Color(0.6, 0.2, 0.2), Color(0.2, 0.5, 0.3), Color(0.7, 0.6, 0.2), Color(0.4, 0.2, 0.4), Color(0.9, 0.5, 0.1)]
	var skin := mat(Color(0.8, 0.65, 0.55), 0.7)
	for i in 40:
		var x := rng.randf_range(-HALF + 30, HALF - 30)
		var z := rng.randf_range(-HALF + 30, HALF - 30)
		if absf(x) < ROAD_W / 2.0 + 6.0:
			continue
		var root := Node3D.new()
		root.position = Vector3(x, 0, z)
		add_child(root)
		var shirt := mat(shirt_cols[i % shirt_cols.size()], 0.8)
		cyl(root, 0.18, 0.22, 1.0, Vector3(0, 1.1, 0), shirt, 8)
		ball(root, 0.15, Vector3(0, 1.75, 0), skin, 10)
		var legs := []
		for sx in [-0.08, 0.08]:
			var leg := cyl(root, 0.06, 0.06, 0.9, Vector3(sx, 0.45, 0), mat(Color(0.15, 0.15, 0.2)), 6)
			legs.append(leg)
		var arms := []
		for sx in [-0.22, 0.22]:
			var arm := cyl(root, 0.05, 0.05, 0.75, Vector3(sx, 1.15, 0), shirt, 6)
			arms.append(arm)
		cyl(root, 0.06, 0.05, 0.1, Vector3(0.28, 0.85, 0.1), mat(Color(0.95, 0.92, 0.85), 0.4), 8)
		var dog_node = null
		if rng.randf() < 0.6:
			dog_node = _make_dog(root)
		var label := Label3D.new()
		label.text = _phrases[i % _phrases.size()]
		label.font_size = 32
		label.outline_size = 8
		label.modulate = Color(1, 1, 1, 0)
		label.position = Vector3(0, 2.3, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(label)
		pedestrians.append({"node": root, "home": Vector3(x, 0, z), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.2, 0.5), "legs": legs, "arms": arms, "dog": dog_node, "label": label, "label_t": rng.randf_range(3.0, 10.0)})
# ------------------------------------------------------------------ Plazas um Türme
func _make_dog(parent: Node3D) -> Node3D:
	var dog := Node3D.new()
	dog.position = Vector3(0.6, 0, 0.3)
	parent.add_child(dog)
	var fur := mat(Color(0.4, 0.28, 0.18), 0.9)
	box(dog, Vector3(0.35, 0.3, 0.7), Vector3(0, 0.35, 0), fur)
	box(dog, Vector3(0.25, 0.22, 0.3), Vector3(0, 0.55, 0.35), fur)
	box(dog, Vector3(0.05, 0.05, 0.3), Vector3(0, 0.55, 0.65), fur)
	for sx in [-0.12, 0.12]:
		for sz in [-0.2, 0.2]:
			cyl(dog, 0.05, 0.05, 0.35, Vector3(sx, 0.18, sz), fur, 5)
	return dog
func _animate_crowd(delta: float) -> void:
	var m = get_parent()
	if m == null or m.player == null:
		return
	var pp = m.player.global_position
	for p in pedestrians:
		var node: Node3D = p["node"]
		if absf(node.position.x - pp.x) > 60.0 or absf(node.position.z - pp.z) > 60.0:
			continue
		var stride := t * 3.0 + float(p["phase"])
		var legs: Array = p["legs"]
		var arms: Array = p["arms"]
		if legs.size() >= 2:
			legs[0].rotation.x = sin(stride) * 0.5
			legs[1].rotation.x = -sin(stride) * 0.5
		if arms.size() >= 2:
			arms[0].rotation.x = -sin(stride) * 0.4
			arms[1].rotation.x = sin(stride) * 0.4
		var dog = p["dog"]
		if dog != null:
			dog.position.y = absf(sin(stride * 1.5)) * 0.05
		var label: Label3D = p["label"]
		var d2p := Vector2(node.position.x - pp.x, node.position.z - pp.z).length()
		var target_a := 1.0 if d2p < 15.0 else 0.0
		label.modulate.a = move_toward(label.modulate.a, target_a, delta * 2.0)
		p["label_t"] = float(p["label_t"]) - delta
		if p["label_t"] <= 0.0 and d2p < 15.0:
			p["label_t"] = rng.randf_range(5.0, 12.0)
			label.text = _phrases.pick_random()
