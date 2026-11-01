extends CharacterBody3D
## Spieler: Bewegung, Sprint, Dash, Schrotflinte, Blitz-Granate, Verbandskasten.

const LIMIT := 317.0
const JUMP_FORCE := 9.0
const JUMP_GRAVITY := 20.0
const WeaponScript = preload("res://weapons.gd")

var main
var hp := 100.0
var stam := 100.0
var dash_cd := 0.0
var gren_cd := 0.0
var inv := 0.0
var dash_t := 0.0
var dash_v := Vector3.ZERO
var jump_velocity := 0.0
var heals := 2
var med_t := 0.0
var alive := false
var sens := 2.2
var shake := 0.0
var bob := 0.0
var pitch := 0.0
var hb := 0.0
var sprinting := false
var touch_move := Vector2.ZERO
var touch_fire := false
var touch_sprint := false
var driving := false
var transitioning := false
var player_collision: CollisionShape3D
var walk_shape: Shape3D
var car_camera_position := Vector3(0.0, 3.8, 7.0)
var cam: Camera3D
var flash: SpotLight3D
var weapon_system

var weapon_slots: Array[Dictionary]:
	get:
		return weapon_system.weapon_slots

var active_weapon_slot: int:
	get:
		return weapon_system.active_weapon_slot

var speed_mode: bool:
	get:
		return main.world.car.speed_mode if main != null and main.world.car != null else false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4
	collision_mask = 1 | 2
	player_collision = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	player_collision.shape = cap
	player_collision.position.y = 0.9
	walk_shape = cap
	add_child(player_collision)

	cam = Camera3D.new()
	cam.position.y = 1.65
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 260.0
	add_child(cam)
	cam.make_current()

	flash = SpotLight3D.new()
	flash.position = Vector3(0.2, -0.1, 0.0)
	flash.spot_range = 28.0
	flash.spot_angle = 28.0
	flash.spot_attenuation = 0.6
	flash.light_energy = 5.0
	cam.add_child(flash)
	weapon_system = WeaponScript.new()
	add_child(weapon_system)
	weapon_system.setup(self)

func reset(pos: Vector3) -> void:
	driving = false
	transitioning = false
	weapon_system.reset()
	if main.world.car != null:
		main.world.car.reset_vehicle()
	collision_layer = 4
	collision_mask = 1 | 2
	player_collision.shape = walk_shape
	player_collision.set_deferred("disabled", false)
	flash.visible = true
	position = pos
	rotation = Vector3.ZERO
	pitch = 0.0
	cam.rotation = Vector3.ZERO
	hp = 100.0
	stam = 100.0
	dash_cd = 0.0
	gren_cd = 0.0
	inv = 0.0
	dash_t = 0.0
	jump_velocity = 0.0
	heals = 2
	med_t = 0.0
	shake = 0.0
	velocity = Vector3.ZERO
	touch_move = Vector2.ZERO
	touch_fire = false
	touch_sprint = false
	flash.visible = true
	alive = true

func _unhandled_input(event: InputEvent) -> void:
	if not alive or transitioning:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.0022 * (sens / 2.2)
		rotation.y -= event.relative.x * k
		pitch = clampf(pitch - event.relative.y * k, -1.2, 1.2)
		cam.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if driving:
			if event.keycode == KEY_SHIFT:
				toggle_speed_mode()
			elif event.keycode == KEY_C:
				toggle_car_camera()
			return
		match event.keycode:
			KEY_SPACE: jump()
			KEY_1: main.inventory_system.activate_quickbar_slot(0)
			KEY_2: main.inventory_system.activate_quickbar_slot(1)
			KEY_3: main.inventory_system.activate_quickbar_slot(2)
			KEY_4: main.inventory_system.activate_quickbar_slot(3)
			KEY_R: weapon_system.reload()
			KEY_Q: dash()
			KEY_G: grenade()
			KEY_H: heal()
			KEY_L: toggle_flash()
	elif event is InputEventMouseButton and event.pressed and not driving:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			weapon_system.cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			weapon_system.cycle_weapon(1)

func _input_dir() -> Vector3:
	var d := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): d.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): d.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1.0
	d += Vector3(touch_move.x, 0.0, touch_move.y)
	return d

func look(rel: Vector2) -> void:
	var k := 0.006 * (sens / 2.2)
	rotation.y -= rel.x * k
	pitch = clampf(pitch - rel.y * k, -1.2, 1.2)
	cam.rotation.x = pitch

func toggle_flash() -> void:
	flash.visible = not flash.visible
	main.toast("Taschenlampe AN" if flash.visible else "Taschenlampe AUS")

func jump() -> void:
	if not alive or driving or transitioning:
		return
	var floor_y: float = main.world.dig_depth_at(global_position)
	if global_position.y <= floor_y + 0.05:
		jump_velocity = JUMP_FORCE

func _physics_process(delta: float) -> void:
	if not alive or transitioning:
		return
	if driving:
		main.world.car.drive(self, delta)
		return
	dash_cd = maxf(0.0, dash_cd - delta)
	gren_cd = maxf(0.0, gren_cd - delta)
	inv = maxf(0.0, inv - delta)
	med_t += delta
	if med_t >= 8.0:
		med_t = 0.0
		if heals < 3:
			heals += 1
			main.toast("+1 Verbandskasten")

	var dir := _input_dir()
	if dir.length() > 1.0:
		dir = dir.normalized()
	var l := dir.length()
	sprinting = (Input.is_key_pressed(KEY_SHIFT) or touch_sprint) and l > 0.05 and stam > 1.0
	if sprinting:
		stam = maxf(0.0, stam - 24.0 * delta)
	else:
		stam = minf(100.0, stam + 15.0 * delta)
	var sp := 5.7 if sprinting else 3.6
	var wish := global_transform.basis * dir
	wish.y = 0.0
	var nearby_ladder: Dictionary = main.world.ladder_near(global_position)
	var climbing_input := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or absf(touch_move.y) > 0.3
	if not nearby_ladder.is_empty() and climbing_input:
		velocity = Vector3.ZERO
		jump_velocity = 0.0
	elif dash_t > 0.0:
		dash_t -= delta
		velocity = dash_v * 20.0
	else:
		velocity = wish * sp
	if nearby_ladder.is_empty():
		var floor_y: float = main.world.dig_depth_at(global_position)
		if jump_velocity > 0.0 or position.y > floor_y:
			jump_velocity -= JUMP_GRAVITY * delta
			velocity.y = jump_velocity
		else:
			jump_velocity = 0.0
			velocity.y = 0.0
	else:
		jump_velocity = 0.0
		velocity.y = 0.0
	move_and_slide()
	position.x = clampf(position.x, -LIMIT, LIMIT)
	position.z = clampf(position.z, -LIMIT, LIMIT)
	var ladder: Dictionary = main.world.ladder_near(global_position)
	if ladder.is_empty():
		var floor_y: float = main.world.dig_depth_at(global_position)
		if position.y <= floor_y:
			position.y = floor_y
			jump_velocity = 0.0
	else:
		var climb_direction := 0.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or touch_move.y < -0.3:
			climb_direction = 1.0
		elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or touch_move.y > 0.3:
			climb_direction = -1.0
		var ladder_depth: float = float(ladder.get("depth", 0.0))
		position.y = clampf(position.y + climb_direction * 2.2 * delta, -ladder_depth, 0.0)

	if l > 0.05:
		bob += delta * (13.0 if sprinting else 9.0)
	cam.position.y = 1.65 + sin(bob) * 0.035 * l
	var tfov := 92.0 if dash_t > 0.0 else (80.0 if sprinting else 72.0)
	cam.fov = lerpf(cam.fov, tfov, minf(1.0, delta * 6.0))
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		cam.h_offset = randf_range(-1.0, 1.0) * 0.07 * shake
		cam.v_offset = randf_range(-1.0, 1.0) * 0.07 * shake
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

	if hp < 35.0:
		hb -= delta
		if hb <= 0.0:
			hb = 0.75 + (hp / 35.0) * 0.5
			main.play_sfx("heart")
	else:
		hb = 0.0
	weapon_system.update(delta, l)

func can_enter_car() -> bool:
	if not alive or driving or transitioning or main.world.car == null:
		return false
	return main.world.car.can_enter(self)

func can_pickup_weapon(weapon_id: String) -> bool:
	return weapon_system.can_pickup_weapon(weapon_id)

func pickup_weapon(weapon_id: String) -> bool:
	return weapon_system.pickup_weapon(weapon_id)

func equip_weapon(slot_index: int) -> void:
	weapon_system.equip_weapon(slot_index)

func cycle_weapon(direction: int) -> void:
	weapon_system.cycle_weapon(direction)

func weapon_slot_label(slot_index: int) -> String:
	return weapon_system.weapon_slot_label(slot_index)

func weapon_ammo_label() -> String:
	return weapon_system.ammo_label()

func refill_active_ammo() -> void:
	weapon_system.refill_active_ammo()

func enter_car() -> void:
	if main.world.car != null:
		main.world.car.enter(self)

func exit_car() -> void:
	if main.world.car != null:
		main.world.car.exit(self)

func toggle_speed_mode() -> void:
	if driving and main.world.car != null:
		main.world.car.toggle_speed_mode()

func toggle_car_camera() -> void:
	if driving and main.world.car != null:
		main.world.car.toggle_camera(self)

func shoot() -> void:
	weapon_system.shoot()

func reload() -> void:
	weapon_system.reload()

func dash() -> void:
	if not alive or dash_cd > 0.0:
		return
	var d := _input_dir()
	if d.length() < 0.1:
		d = Vector3(0, 0, -1)
	var w := global_transform.basis * d.normalized()
	w.y = 0.0
	dash_v = w.normalized()
	dash_t = 0.22
	dash_cd = 3.0
	inv = 0.4
	main.play_sfx("dash")

func grenade() -> void:
	if not alive or gren_cd > 0.0:
		return
	gren_cd = 14.0
	main.flash_white()
	main.play_sfx("grenade")
	shake = 1.2
	main.toast("Leuchtgranate!")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dying:
			continue
		if e.global_position.distance_to(global_position) > 12.0:
			continue
		e.take_damage(40.0 if e.minion else 10.0)
		e.stun(3.0 if e.minion else 1.6)

func heal() -> void:
	if not alive or heals <= 0 or hp >= 100.0:
		return
	heals -= 1
	hp = minf(100.0, hp + 40.0)
	main.play_sfx("click")
	main.toast("Verbandskasten +40 HP")

func hurt(n: float) -> void:
	if not alive or inv > 0.0:
		return
	var damage := n
	if main.inventory_system != null and main.inventory_system.armor_equipped:
		damage *= 0.7
	hp -= damage
	main.play_sfx("hurt")
	main.flash_hurt()
	if hp <= 0.0:
		hp = 0.0
		alive = false
		main.on_player_died()
