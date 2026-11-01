extends Node3D

const START_POSITION := Vector3(5.4, 0.0, 98.0)
const START_ROTATION := 0.12
const MAX_STEP_HEIGHT := 0.8
const STEP_INCREMENT := 0.2
const CRASH_MIN_SPEED := 18.0

var world
var game
var visual: Node3D
var car_collision: CollisionShape3D
var car_lights: Array[SpotLight3D] = []
var wheels: Array[MeshInstance3D] = []
var doors: Array[Node3D] = []
var speed := 0.0
var speed_mode := false
var first_person_view := false
var door_side := 1.0
var runover_cooldowns: Dictionary = {}
var anim_time := 0.0

func setup(world_node: Node) -> void:
	world = world_node
	game = world_node.get_parent()
	position = START_POSITION
	rotation.y = START_ROTATION
	visual = Node3D.new()
	add_child(visual)
	var body: StandardMaterial3D = world.tmat("metal", Color(0.6, 0.1, 0.1), 0.6, 0.35)
	world.box(visual, Vector3(1.9, 0.75, 4.3), Vector3(0, 0.75, 0), body)
	world.box(visual, Vector3(1.7, 0.65, 2.2), Vector3(0, 1.45, -0.2), world.mat(Color(0.05, 0.08, 0.1), 0.1))
	var handle_mat: StandardMaterial3D = world.mat(Color(0.58, 0.58, 0.52), 0.35)
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 0.94, 1.05, -0.65)
		visual.add_child(hinge)
		world.box(hinge, Vector3(0.1, 0.72, 1.35), Vector3(side * 0.035, 0, 0.65), body)
		world.box(hinge, Vector3(0.035, 0.05, 0.22), Vector3(side * 0.09, 0.12, 0.52), handle_mat)
		doors.append(hinge)
	var tire: StandardMaterial3D = world.mat(Color(0.03, 0.03, 0.03))
	for side in [-1.0, 1.0]:
		for wheel_z in [-1.4, 1.4]:
			var wheel: MeshInstance3D = world.cyl(visual, 0.38, 0.38, 0.25, Vector3(side, 0.38, wheel_z), tire, 10, Vector3(0, 0, PI / 2.0))
			wheels.append(wheel)
	var headlight_material: StandardMaterial3D = world.mat(Color(1.0, 0.95, 0.7), 0.5, true)
	for side in [-1.0, 1.0]:
		world.box(visual, Vector3(0.4, 0.18, 0.08), Vector3(side * 0.65, 0.85, -2.17), headlight_material)
	world.flick.append({"m": headlight_material, "base": Color(1.0, 0.95, 0.7), "ph": 0.5, "mode": 1})
	for side in [-1.0, 1.0]:
		var car_light := SpotLight3D.new()
		car_light.position = Vector3(side * 0.65, 0.85, -2.2)
		car_light.spot_range = 30.0
		car_light.spot_angle = 35.0
		car_light.light_energy = 4.5
		car_light.light_color = Color(1.0, 0.92, 0.7)
		add_child(car_light)
		car_lights.append(car_light)
	var car_body := StaticBody3D.new()
	add_child(car_body)
	car_collision = CollisionShape3D.new()
	var car_shape := BoxShape3D.new()
	car_shape.size = Vector3(1.9, 1.8, 4.3)
	car_collision.shape = car_shape
	car_collision.position.y = 0.9
	car_body.add_child(car_collision)
	world._crate(Vector3(5.7, 0, 101.2), 0.3, "ammo")
	world.add_interact("radio", Vector3(3.0, 0, 98.0), world.NOTES[9])
	world.blocks.append({"p": Vector2(5.4, 98.0), "s": Vector2(2.0, 4.4), "c": Color(0.7, 0.2, 0.2), "round": false})

func can_enter(player) -> bool:
	if not player.alive or player.driving or player.transitioning:
		return false
	return Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() < 4.5

func enter(player) -> void:
	if not can_enter(player):
		return
	door_side = signf((player.global_position - global_position).dot(global_transform.basis.x))
	if is_zero_approx(door_side):
		door_side = 1.0
	animate_door(true)
	player.transitioning = true
	player.driving = true
	speed = 0.0
	player.position = global_position
	player.rotation.y = rotation.y
	player.player_collision.set_deferred("disabled", true)
	var player_car_shape := BoxShape3D.new()
	player_car_shape.size = Vector3(1.9, 1.8, 4.3)
	player.player_collision.shape = player_car_shape
	player.player_collision.set_deferred("disabled", false)
	player.collision_mask = 1 | 2
	car_collision.set_deferred("disabled", true)
	player.flash.hide()
	player.main.toast("W/S fahren · A/D lenken · Shift Turbo · C Ansicht · E aussteigen")
	var tween: Tween = player.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player.cam, "position", player.car_camera_position, 0.55)
	tween.tween_property(player.cam, "rotation", Vector3(-0.3, 0.0, 0.0), 0.55)
	tween.tween_property(player.weapon_system.gun, "position:y", -1.0, 0.4)
	tween.chain().tween_callback(_finish_enter.bind(player))

func exit(player) -> void:
	if not player.driving or player.transitioning:
		return
	animate_door(true)
	player.transitioning = true
	player.driving = false
	first_person_view = false
	speed = 0.0
	player.velocity = Vector3.ZERO
	player.player_collision.set_deferred("disabled", true)
	player.player_collision.shape = player.walk_shape
	player.player_collision.set_deferred("disabled", false)
	player.collision_mask = 1 | 2
	car_collision.set_deferred("disabled", false)
	player.position = global_position + global_transform.basis * Vector3(door_side * 1.65, 0.0, 0.0)
	player.rotation.y = rotation.y
	player.weapon_system.gun.show()
	player.weapon_system.gun.position.y = -1.0
	player.main.toast("Ausgestiegen")
	var tween: Tween = player.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player.cam, "position", Vector3(0.0, 1.65, 0.0), 0.55)
	tween.tween_property(player.cam, "rotation", Vector3(player.pitch, 0.0, 0.0), 0.55)
	tween.tween_property(player.weapon_system.gun, "position", Vector3(0.22, -0.2, -0.35), 0.4)
	tween.chain().tween_callback(_finish_exit.bind(player))

func _finish_enter(player) -> void:
	animate_door(false)
	player.weapon_system.gun.hide()
	player.transitioning = false

func _finish_exit(player) -> void:
	animate_door(false)
	player.flash.show()
	player.transitioning = false

func drive(player, delta: float) -> void:
	for enemy_id in runover_cooldowns.keys():
		runover_cooldowns[enemy_id] = float(runover_cooldowns[enemy_id]) - delta
		if runover_cooldowns[enemy_id] <= 0.0:
			runover_cooldowns.erase(enemy_id)
	var direction: Vector3 = player._input_dir()
	var throttle := clampf(-direction.z, -1.0, 1.0)
	var steering := clampf(direction.x, -1.0, 1.0)
	var target_speed := throttle * ((24.0 if speed_mode else 16.0) if throttle >= 0.0 else (9.0 if speed_mode else 6.0))
	var acceleration := (15.0 if speed_mode else 11.0) if absf(throttle) > 0.05 else 5.5
	speed = move_toward(speed, target_speed, acceleration * delta)
	if absf(speed) > 0.1:
		player.rotation.y -= steering * clampf(absf(speed) / 5.0, 0.2, 1.0) * delta * 0.9 * signf(speed)
	_align_to_step_surface(player)
	var drive_velocity: Vector3 = player.global_transform.basis * Vector3(0.0, 0.0, -speed)
	var start_transform: Transform3D = player.global_transform
	player.velocity = drive_velocity
	player.move_and_slide()
	var wall_collision := false
	var destroyed_roots := {}
	for collision_index in player.get_slide_collision_count():
		var collision: KinematicCollision3D = player.get_slide_collision(collision_index)
		var collider = collision.get_collider()
		if collider != null and collider.is_in_group("enemies") and absf(speed) > 5.0:
			var enemy_id: int = collider.get_instance_id()
			if not runover_cooldowns.has(enemy_id) and (collider.has_method("hit_by_vehicle") or collider.has_method("take_damage")):
				var impact_direction: Vector3 = -player.global_transform.basis.z * signf(speed)
				if collider.has_method("hit_by_vehicle"):
					collider.call("hit_by_vehicle", impact_direction, absf(speed))
				else:
					collider.call("take_damage", maxf(35.0, absf(speed) * 7.0))
				runover_cooldowns[enemy_id] = 0.8
		elif collider != null and collision.get_normal().y < 0.5:
			wall_collision = true
			if speed_mode and absf(speed) >= CRASH_MIN_SPEED and collider.is_in_group("breakable_building"):
				var crash_root: Variant = collider.get_meta("crash_root", null)
				if is_instance_valid(crash_root):
					var root_id: int = crash_root.get_instance_id()
					if not destroyed_roots.has(root_id) and _destroy_building(collider):
						destroyed_roots[root_id] = true
	if wall_collision and destroyed_roots.is_empty():
		_try_step_up(player, start_transform, drive_velocity, delta)
	_align_to_step_surface(player)
	global_position = player.global_position
	rotation.y = player.rotation.y
	animate(speed, steering, delta)

func _try_step_up(player, start_transform: Transform3D, drive_velocity: Vector3, delta: float) -> bool:
	var forward_motion := drive_velocity * delta
	for step_index in range(1, int(MAX_STEP_HEIGHT / STEP_INCREMENT) + 1):
		var step_height := STEP_INCREMENT * float(step_index)
		if player.test_move(start_transform, Vector3.UP * step_height):
			continue
		var raised_transform := start_transform
		raised_transform.origin.y += step_height
		if player.test_move(raised_transform, forward_motion):
			continue
		player.global_transform = raised_transform
		player.velocity = drive_velocity
		player.move_and_slide()
		return true
	return false

func _align_to_step_surface(player) -> void:
	var base_y: float = player.global_position.y
	var ray_start: Vector3 = player.global_position + Vector3.UP * (MAX_STEP_HEIGHT + 0.1)
	var ray_end: Vector3 = player.global_position - Vector3.UP * (MAX_STEP_HEIGHT + 0.1)
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		player.global_position.y = 0.0
		return
	var surface_y: float = hit["position"].y
	var surface_normal: Vector3 = hit["normal"]
	if surface_normal.y > 0.6 and absf(surface_y - base_y) <= MAX_STEP_HEIGHT + 0.05:
		player.global_position.y = surface_y
	elif base_y > 0.0:
		player.global_position.y = 0.0

func _destroy_building(collider: Node) -> bool:
	var building_root: Variant = collider.get_meta("crash_root", null)
	if not is_instance_valid(building_root):
		return false
	for building_body in get_tree().get_nodes_in_group("breakable_building"):
		if building_body.get_meta("crash_root", null) == building_root:
			building_body.queue_free()
	building_root.queue_free()
	game.toast("Haus zerstört!")
	return true

func animate(speed_value: float, steering: float, delta: float) -> void:
	anim_time += delta
	var amount := clampf(absf(speed_value) / 16.0, 0.0, 1.0)
	visual.position.y = sin(anim_time * 18.0) * 0.025 * amount
	visual.rotation.z = lerpf(visual.rotation.z, -steering * 0.035 * amount, minf(1.0, delta * 5.0))
	for wheel_index in wheels.size():
		var wheel: MeshInstance3D = wheels[wheel_index]
		wheel.rotation.x -= speed_value * delta / 0.38
		wheel.rotation.y = steering * 0.28 if wheel_index % 2 == 0 else 0.0

func animate_door(open: bool) -> void:
	var door_index := 1 if door_side > 0.0 else 0
	for i in doors.size():
		var angle := door_side * 0.95 if open and i == door_index else 0.0
		create_tween().tween_property(doors[i], "rotation:y", angle, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func toggle_speed_mode() -> void:
	speed_mode = not speed_mode
	game.toast("Turbo an" if speed_mode else "Turbo aus")

func toggle_camera(player) -> void:
	if not player.driving or player.transitioning:
		return
	first_person_view = not first_person_view
	var target_position: Vector3 = Vector3(0.0, 1.55, -1.4) if first_person_view else player.car_camera_position
	var target_rotation := Vector3(-0.08, 0.0, 0.0) if first_person_view else Vector3(-0.3, 0.0, 0.0)
	var tween: Tween = player.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player.cam, "position", target_position, 0.35)
	tween.tween_property(player.cam, "rotation", target_rotation, 0.35)
	game.toast("Innenansicht" if first_person_view else "Außenansicht")

func update_lights(world_time: float) -> void:
	var energy := 4.5 if sin(world_time * 9.0) * sin(world_time * 4.1) > -0.7 else 0.4
	for car_light in car_lights:
		car_light.light_energy = energy

func reset_vehicle() -> void:
	position = START_POSITION
	rotation = Vector3(0.0, START_ROTATION, 0.0)
	first_person_view = false
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	car_collision.set_deferred("disabled", false)
	speed = 0.0
	speed_mode = false
	runover_cooldowns.clear()
	for door in doors:
		door.rotation.y = 0.0
	for wheel in wheels:
		wheel.rotation = Vector3(0.0, 0.0, PI / 2.0)
