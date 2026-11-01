extends Node

const WEAPON_INFO := {
	"shotgun": {"name": "FLINTE", "capacity": 2, "reload": 1.3, "cooldown": 0.75, "pellets": 9, "spread": 0.045, "damage": 1.0},
	"pistol": {"name": "PISTOLE", "capacity": 12, "reload": 1.0, "cooldown": 0.34, "pellets": 1, "spread": 0.01, "damage": 4.5},
	"rifle": {"name": "GEWEHR", "capacity": 30, "reload": 1.4, "cooldown": 0.16, "pellets": 1, "spread": 0.014, "damage": 1.8},
	"minigun": {"name": "MINIGUN", "capacity": 120, "reload": 2.2, "cooldown": 0.08, "pellets": 1, "spread": 0.025, "damage": 0.7}}

var player
var main
var weapon_slots: Array[Dictionary] = []
var active_weapon_slot := 0
var shells := 2
var reloading := 0.0
var cool := 0.0
var recoil := 0.0
var gun: Node3D
var muzzle: OmniLight3D
var weapon_visuals: Dictionary = {}
var axe_visual: Node3D
var pickaxe_visual: Node3D
var shovel_visual: Node3D
var ladder_visual: Node3D
var fishing_rod_visual: Node3D
var axe_swing_t := 0.0
var pickaxe_swing_t := 0.0

func setup(player_node) -> void:
	player = player_node
	main = player.main
	weapon_slots = [{"id": "shotgun", "ammo": 2}]
	muzzle = OmniLight3D.new()
	muzzle.position = Vector3(0.2, -0.1, -1.0)
	muzzle.omni_range = 12.0
	muzzle.light_color = Color(1.0, 0.67, 0.27)
	muzzle.light_energy = 0.0
	player.cam.add_child(muzzle)
	_build_guns()

func _gun_mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _build_guns() -> void:
	gun = Node3D.new()
	gun.position = Vector3(0.22, -0.2, -0.35)
	gun.rotation.y = 0.04
	player.cam.add_child(gun)
	var shotgun := Node3D.new()
	gun.add_child(shotgun)
	weapon_visuals["shotgun"] = shotgun
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.2, 0.21, 0.23)
	metal.metallic = 0.7
	metal.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.23, 0.13)
	wood.roughness = 0.85
	for side in [-0.025, 0.025]:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.025
		barrel.bottom_radius = 0.025
		barrel.height = 0.9
		barrel.radial_segments = 8
		var barrel_mesh := _gun_mesh(shotgun, barrel, metal, Vector3(side, 0, -0.45))
		barrel_mesh.rotation.x = PI / 2.0
	var stock := BoxMesh.new()
	stock.size = Vector3(0.09, 0.12, 0.4)
	_gun_mesh(shotgun, stock, wood, Vector3(0, -0.04, 0.05))
	var pump := BoxMesh.new()
	pump.size = Vector3(0.1, 0.07, 0.22)
	_gun_mesh(shotgun, pump, wood, Vector3(0, -0.05, -0.4))
	_build_axe(gun)
	_build_pickaxe(gun)
	_build_shovel(gun)
	_build_ladder(gun)
	_build_fishing_rod(gun)
	var pistol := Node3D.new()
	gun.add_child(pistol)
	weapon_visuals["pistol"] = pistol
	var pistol_body := BoxMesh.new()
	pistol_body.size = Vector3(0.14, 0.13, 0.34)
	_gun_mesh(pistol, pistol_body, metal, Vector3(0, 0.0, -0.34))
	var pistol_grip := BoxMesh.new()
	pistol_grip.size = Vector3(0.1, 0.2, 0.13)
	_gun_mesh(pistol, pistol_grip, wood, Vector3(0, -0.14, -0.19))
	var rifle := Node3D.new()
	gun.add_child(rifle)
	weapon_visuals["rifle"] = rifle
	var rifle_body := BoxMesh.new()
	rifle_body.size = Vector3(0.16, 0.16, 0.55)
	_gun_mesh(rifle, rifle_body, metal, Vector3(0, -0.04, -0.3))
	var rifle_barrel := BoxMesh.new()
	rifle_barrel.size = Vector3(0.055, 0.055, 0.55)
	_gun_mesh(rifle, rifle_barrel, metal, Vector3(0, 0.0, -0.83))
	var rifle_stock := BoxMesh.new()
	rifle_stock.size = Vector3(0.13, 0.13, 0.32)
	_gun_mesh(rifle, rifle_stock, wood, Vector3(0, -0.04, 0.12))
	var minigun := Node3D.new()
	gun.add_child(minigun)
	weapon_visuals["minigun"] = minigun
	var minigun_body := BoxMesh.new()
	minigun_body.size = Vector3(0.24, 0.2, 0.38)
	_gun_mesh(minigun, minigun_body, metal, Vector3(0, -0.02, -0.3))
	for barrel_index in 3:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.025
		barrel.bottom_radius = 0.025
		barrel.height = 0.72
		barrel.radial_segments = 8
		var barrel_mesh := _gun_mesh(minigun, barrel, metal, Vector3((barrel_index - 1) * 0.075, 0.0, -0.78))
		barrel_mesh.rotation.x = PI / 2.0
	for weapon_id in weapon_visuals:
		weapon_visuals[weapon_id].visible = weapon_id == "shotgun"
	_update_held_visual()

func _build_axe(parent: Node3D) -> void:
	axe_visual = Node3D.new()
	axe_visual.position = Vector3(0.04, -0.02, -0.28)
	axe_visual.scale = Vector3.ONE * 0.82
	axe_visual.rotation.z = -0.22
	axe_visual.visible = false
	parent.add_child(axe_visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.18, 0.09)
	wood.roughness = 0.88
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.12, 0.09, 0.07)
	grip.roughness = 0.95
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.29, 0.34, 0.35)
	steel.metallic = 0.72
	steel.roughness = 0.3
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.72, 0.76, 0.72)
	edge.metallic = 0.82
	edge.roughness = 0.22
	var handle := CylinderMesh.new()
	handle.top_radius = 0.027
	handle.bottom_radius = 0.045
	handle.height = 0.82
	handle.radial_segments = 8
	_gun_mesh(axe_visual, handle, wood, Vector3(0, -0.06, 0))
	var wrap := CylinderMesh.new()
	wrap.top_radius = 0.032
	wrap.bottom_radius = 0.032
	wrap.height = 0.16
	wrap.radial_segments = 8
	_gun_mesh(axe_visual, wrap, grip, Vector3(0, -0.32, 0))
	var socket := BoxMesh.new()
	socket.size = Vector3(0.16, 0.25, 0.14)
	_gun_mesh(axe_visual, socket, steel, Vector3(-0.04, 0.34, 0))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.25, 0.32, 0.09)
	var blade_mesh := _gun_mesh(axe_visual, blade, steel, Vector3(-0.21, 0.36, 0))
	blade_mesh.rotation.z = 0.2
	var cutting_edge := BoxMesh.new()
	cutting_edge.size = Vector3(0.055, 0.3, 0.095)
	var edge_mesh := _gun_mesh(axe_visual, cutting_edge, edge, Vector3(-0.35, 0.36, 0))
	edge_mesh.rotation.z = 0.2

func _axe_equipped() -> bool:
	return _held_tool_id() == "axe"

func _held_tool_id() -> String:
	if main == null or main.inventory_system == null:
		return ""
	var entry: String = main.inventory_system.quickbar_entry(main.inventory_system.active_quickbar_slot)
	return entry if entry in ["axe", "pickaxe", "shovel", "ladder", "fishing_rod"] else ""

func _build_pickaxe(parent: Node3D) -> void:
	pickaxe_visual = Node3D.new()
	pickaxe_visual.position = Vector3(0.04, -0.02, -0.28)
	pickaxe_visual.scale = Vector3.ONE * 0.78
	pickaxe_visual.rotation.z = -0.2
	pickaxe_visual.visible = false
	parent.add_child(pickaxe_visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.38, 0.23, 0.12)
	wood.roughness = 0.9
	var dark_wood := StandardMaterial3D.new()
	dark_wood.albedo_color = Color(0.2, 0.12, 0.07)
	dark_wood.roughness = 0.95
	var handle := CylinderMesh.new()
	handle.top_radius = 0.028
	handle.bottom_radius = 0.045
	handle.height = 0.78
	handle.radial_segments = 8
	_gun_mesh(pickaxe_visual, handle, wood, Vector3(0, -0.08, 0))
	var head := BoxMesh.new()
	head.size = Vector3(0.55, 0.12, 0.13)
	_gun_mesh(pickaxe_visual, head, dark_wood, Vector3(0, 0.3, 0))
	var point := CylinderMesh.new()
	point.top_radius = 0.0
	point.bottom_radius = 0.065
	point.height = 0.24
	point.radial_segments = 5
	var point_left := _gun_mesh(pickaxe_visual, point, wood, Vector3(-0.34, 0.3, 0))
	point_left.rotation.z = -PI / 2.0
	var point_right := _gun_mesh(pickaxe_visual, point, wood, Vector3(0.34, 0.3, 0))
	point_right.rotation.z = PI / 2.0

func _build_shovel(parent: Node3D) -> void:
	shovel_visual = Node3D.new()
	shovel_visual.position = Vector3(0.04, -0.02, -0.28)
	shovel_visual.scale = Vector3.ONE * 0.78
	shovel_visual.rotation.z = -0.2
	shovel_visual.visible = false
	parent.add_child(shovel_visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.38, 0.23, 0.12)
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.48, 0.38, 0.25)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.035
	handle.bottom_radius = 0.045
	handle.height = 0.82
	handle.radial_segments = 8
	_gun_mesh(shovel_visual, handle, wood, Vector3(0, -0.06, 0))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.38, 0.28, 0.08)
	var blade_mesh := _gun_mesh(shovel_visual, blade, blade_mat, Vector3(0, 0.4, 0))
	blade_mesh.rotation.z = -0.12

func _build_ladder(parent: Node3D) -> void:
	ladder_visual = Node3D.new()
	ladder_visual.position = Vector3(0.04, -0.02, -0.3)
	ladder_visual.scale = Vector3.ONE * 0.36
	ladder_visual.visible = false
	parent.add_child(ladder_visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.16)
	for side in [-0.38, 0.38]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.1, 1.8, 0.1)
		_gun_mesh(ladder_visual, rail, wood, Vector3(side, 0, 0))
	for rung_index in 5:
		var rung := BoxMesh.new()
		rung.size = Vector3(0.84, 0.08, 0.1)
		_gun_mesh(ladder_visual, rung, wood, Vector3(0, -0.7 + rung_index * 0.35, 0))

func _build_fishing_rod(parent: Node3D) -> void:
	fishing_rod_visual = Node3D.new()
	fishing_rod_visual.position = Vector3(0.05, -0.03, -0.32)
	fishing_rod_visual.rotation.z = -0.38
	fishing_rod_visual.visible = false
	parent.add_child(fishing_rod_visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.38, 0.24, 0.13)
	wood.roughness = 0.88
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.72, 0.75, 0.67)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.042
	handle.bottom_radius = 0.05
	handle.height = 0.22
	handle.radial_segments = 8
	_gun_mesh(fishing_rod_visual, handle, wood, Vector3(0, -0.35, 0))
	var rod := CylinderMesh.new()
	rod.top_radius = 0.008
	rod.bottom_radius = 0.022
	rod.height = 0.92
	rod.radial_segments = 6
	var rod_mesh := _gun_mesh(fishing_rod_visual, rod, wood, Vector3(0, 0.18, 0))
	rod_mesh.rotation.z = -0.12
	var line := CylinderMesh.new()
	line.top_radius = 0.003
	line.bottom_radius = 0.003
	line.height = 0.36
	line.radial_segments = 4
	var line_mesh := _gun_mesh(fishing_rod_visual, line, line_mat, Vector3(-0.13, 0.69, 0))
	line_mesh.rotation.z = -0.35

func _update_held_visual() -> void:
	var held_tool := _held_tool_id()
	var active_id := String(weapon_slots[active_weapon_slot]["id"])
	axe_visual.visible = held_tool == "axe"
	pickaxe_visual.visible = held_tool == "pickaxe"
	shovel_visual.visible = held_tool == "shovel"
	ladder_visual.visible = held_tool == "ladder"
	fishing_rod_visual.visible = held_tool == "fishing_rod"
	for weapon_id in weapon_visuals:
		weapon_visuals[weapon_id].visible = held_tool == "" and weapon_id == String(weapon_slots[active_weapon_slot]["id"])

func reset() -> void:
	weapon_slots = [{"id": "shotgun", "ammo": 2}]
	active_weapon_slot = 0
	shells = 2
	reloading = 0.0
	cool = 0.0
	recoil = 0.0
	gun.visible = true
	gun.position = Vector3(0.22, -0.2, -0.35)
	_update_held_visual()

func can_pickup_weapon(weapon_id: String) -> bool:
	if not WEAPON_INFO.has(weapon_id):
		return false
	if weapon_slots.size() < 4:
		return true
	for weapon in weapon_slots:
		if String(weapon["id"]) == weapon_id:
			return true
	return false

func pickup_weapon(weapon_id: String) -> bool:
	if not can_pickup_weapon(weapon_id):
		return false
	for slot_index in weapon_slots.size():
		if String(weapon_slots[slot_index]["id"]) == weapon_id:
			weapon_slots[slot_index]["ammo"] = int(WEAPON_INFO[weapon_id]["capacity"])
			equip_weapon(slot_index)
			return true
	var capacity := int(WEAPON_INFO[weapon_id]["capacity"])
	weapon_slots.append({"id": weapon_id, "ammo": capacity})
	equip_weapon(weapon_slots.size() - 1)
	return true

func equip_weapon(slot_index: int) -> void:
	if player.driving or player.transitioning or slot_index < 0 or slot_index >= weapon_slots.size():
		return
	active_weapon_slot = slot_index
	shells = int(weapon_slots[active_weapon_slot]["ammo"])
	reloading = 0.0
	cool = 0.0
	var active_id := String(weapon_slots[active_weapon_slot]["id"])
	for weapon_id in weapon_visuals:
		weapon_visuals[weapon_id].visible = weapon_id == active_id

func cycle_weapon(direction: int) -> void:
	if weapon_slots.size() < 2 or player.driving or player.transitioning:
		return
	equip_weapon(posmod(active_weapon_slot + direction, weapon_slots.size()))

func weapon_slot_label(slot_index: int) -> String:
	if slot_index >= weapon_slots.size():
		return "%d  -" % (slot_index + 1)
	var weapon_id := String(weapon_slots[slot_index]["id"])
	var label := "M-GUN" if weapon_id == "minigun" else String(WEAPON_INFO[weapon_id]["name"])
	return "%d  %s" % [slot_index + 1, label]

func ammo_label() -> String:
	var weapon: Dictionary = weapon_slots[active_weapon_slot]
	var info: Dictionary = WEAPON_INFO[String(weapon["id"])]
	var status := "%s  %d/%d" % [info["name"], int(weapon["ammo"]), int(info["capacity"])]
	return status + ("  lädt…" if reloading > 0.0 else "")

func refill_active_ammo() -> void:
	var capacity := int(_active_weapon_info()["capacity"])
	weapon_slots[active_weapon_slot]["ammo"] = capacity
	shells = capacity
	reloading = 0.0

func _active_weapon_info() -> Dictionary:
	return WEAPON_INFO[String(weapon_slots[active_weapon_slot]["id"])]

func update(delta: float, movement_amount: float) -> void:
	_update_held_visual()
	cool = maxf(0.0, cool - delta)
	if player.touch_fire or (not main.is_touch and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		shoot()
	axe_swing_t = maxf(0.0, axe_swing_t - delta * 3.5)
	var swing_progress := 1.0 - axe_swing_t
	axe_visual.rotation.z = -0.22 - sin(swing_progress * PI) * 1.25
	pickaxe_swing_t = maxf(0.0, pickaxe_swing_t - delta * 3.5)
	pickaxe_visual.rotation.z = -0.2 - sin((1.0 - pickaxe_swing_t) * PI) * 1.2
	recoil = maxf(0.0, recoil - delta * 5.0)
	gun.position.z = -0.35 + recoil * 0.12
	gun.position.y = -0.2 + sin(player.bob * 0.5) * 0.006
	gun.position.x = 0.22 + sin(player.bob) * 0.014 * movement_amount
	gun.rotation.z = sin(player.bob * 0.5) * 0.035 * movement_amount
	var reload_tilt := 0.0
	if reloading > 0.0:
		reloading -= delta
		var reload_length := float(_active_weapon_info()["reload"])
		reload_tilt = 0.5 * sin(clampf((reload_length - reloading) / reload_length, 0.0, 1.0) * PI)
		if reloading <= 0.0:
			var capacity := int(_active_weapon_info()["capacity"])
			weapon_slots[active_weapon_slot]["ammo"] = capacity
			shells = capacity
	gun.rotation.x = recoil * 0.25 + reload_tilt

func shoot() -> void:
	var held_tool := _held_tool_id()
	if held_tool == "axe":
		_swing_axe()
		return
	if held_tool == "pickaxe":
		_swing_pickaxe()
		return
	if held_tool == "shovel":
		_swing_shovel()
		return
	if held_tool == "ladder":
		_place_ladder()
		return
	if held_tool == "fishing_rod":
		return
	if cool > 0.0 or reloading > 0.0:
		return
	var weapon: Dictionary = weapon_slots[active_weapon_slot]
	var weapon_id := String(weapon["id"])
	var info: Dictionary = WEAPON_INFO[weapon_id]
	if int(weapon["ammo"]) <= 0:
		main.play_sfx("dry")
		cool = 0.3
		reload()
		return
	weapon["ammo"] = int(weapon["ammo"]) - 1
	shells = int(weapon["ammo"])
	cool = float(info["cooldown"])
	recoil = 1.0
	main.play_sfx("shot")
	main.play_sfx("crack")
	muzzle.light_energy = 6.0
	get_tree().create_timer(0.06, false).timeout.connect(func(): muzzle.light_energy = 0.0)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var origin: Vector3 = player.cam.global_position
	var basis: Basis = player.cam.global_transform.basis
	var damage := {}
	var chicken_hit := false
	var chickens_hit_this_shot: Dictionary = {}
	for _pellet in int(info["pellets"]):
		var spread := float(info["spread"])
		var direction := (-basis.z + basis.x * randf_range(-spread, spread) + basis.y * randf_range(-spread, spread)).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 30.0, 3, [player.get_rid()])
		query.collide_with_areas = true
		var result := space.intersect_ray(query)
		if result.is_empty():
			continue
		var collider = result.collider
		if collider != null and collider.is_in_group("chicken_hitboxes"):
			var chicken_id: int = collider.get_instance_id()
			if not chickens_hit_this_shot.has(chicken_id):
				chickens_hit_this_shot[chicken_id] = true
				chicken_hit = main.world.hit_chicken(collider) or chicken_hit
			continue
		if collider != null and collider.has_method("take_damage"):
			var headshot: bool = (result.position.y - collider.global_position.y) > 2.0 * collider.s
			damage[collider] = damage.get(collider, 0.0) + float(info["damage"]) * (1.5 if headshot else 1.0)
	for target in damage:
		target.take_damage(damage[target])
	if damage.size() > 0 or chicken_hit:
		main.hitmarker()
	if int(weapon["ammo"]) == 0:
		get_tree().create_timer(0.5, false).timeout.connect(_reload_if_same_weapon.bind(active_weapon_slot, weapon_id))

func _swing_axe() -> void:
	if cool > 0.0:
		return
	cool = 0.55
	axe_swing_t = 1.0
	main.play_sfx("crack")
	if main.search_target != null and String(main.search_target.get("kind", "")) in ["tree", "log"]:
		main._try_search()
		return
	var origin: Vector3 = player.cam.global_position
	var direction: Vector3 = -player.cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.6, 3, [player.get_rid()])
	query.collide_with_areas = true
	var result: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider = result.collider
	if collider != null and collider.is_in_group("chicken_hitboxes"):
		if main.world.hit_chicken(collider):
			main.hitmarker()
	elif collider != null and collider.has_method("take_damage"):
		collider.take_damage(28.0)
		main.hitmarker()

func _swing_pickaxe() -> void:
	if cool > 0.0:
		return
	cool = 0.55
	pickaxe_swing_t = 1.0
	main.play_sfx("crack")
	if main.search_target != null and String(main.search_target.get("kind", "")) == "rock":
		var loot: String = main.world.hit_rock(int(main.search_target["rock_index"]))
		if loot != "":
			main.inventory_system.add_item(loot)
			main.world_dirty = true
			main.toast("+1 %s" % String(main.inventory_system.ITEM_INFO[loot]["name"]))
		else:
			var hits: int = main.world.rock_mine_hits(int(main.search_target["rock_index"]))
			main.toast("Fels abbauen: %d/3 Hiebe" % hits)
		return
	var origin: Vector3 = player.cam.global_position
	var direction: Vector3 = -player.cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.4, 3, [player.get_rid()])
	var result: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider = result.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(18.0)
			main.hitmarker()

func _swing_shovel() -> void:
	if cool > 0.0:
		return
	cool = 0.7
	var depth: float = main.world.dig_ground(player.global_position, player.rotation.y)
	main.toast("Loch: %.1f m tief" % depth)

func _place_ladder() -> void:
	if cool > 0.0:
		return
	if main.inventory_system.count_item("ladder") < 1:
		main.toast("Du brauchst eine Leiter aus der Werkbank.")
		return
	var forward: Vector3 = -player.global_transform.basis.z
	var place_position: Vector3 = player.global_position + forward * 1.2
	if main.world.place_ladder(place_position, player.rotation.y):
		main.inventory_system.remove_item("ladder")
		main.world_dirty = true
		main.toast("Leiter platziert · E zum Abbauen")
		cool = 0.8

func _reload_if_same_weapon(slot_index: int, weapon_id: String) -> void:
	if active_weapon_slot == slot_index and String(weapon_slots[slot_index]["id"]) == weapon_id:
		reload()

func reload() -> void:
	if not player.alive or player.driving or player.transitioning or reloading > 0.0:
		return
	var info := _active_weapon_info()
	if int(weapon_slots[active_weapon_slot]["ammo"]) >= int(info["capacity"]):
		return
	reloading = float(info["reload"])
	main.play_sfx("click")
	get_tree().create_timer(0.45, false).timeout.connect(func(): main.play_sfx("click"))
	get_tree().create_timer(0.9, false).timeout.connect(func(): main.play_sfx("pump"))
