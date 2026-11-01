extends CharacterBody3D
## Silent Head (Boss) und kleine Diener (Minions).
## Neu: kein Festhängen mehr (Ausweichen + Durchgleiten), große Welt (Teleport-Blinzeln),
## Nähe-Grusel (Herzschlag, Lampen-Flackern, Stimmen der Freunde), ausgehängter Kiefer,
## Nebelschwaden, texturierte Haut, Sägeblatt im Rücken.

signal died(e)
signal phase_changed(e, n)

const VOICES := [
	["Hier drüben… ich bin’s.", "jonas"],
	["Dreh dich nicht um.", "mia"],
	["Tobi? Tobi, bist du das? …Hallo?", "tobi"],
	["Ich höre dich atmen.", "boss"],
	["Lauf nicht. Er hört jeden Schritt.", "mia"],
	["Hilf mir… bitte… es tut so weh.", "jonas"]]

static var _texes := {}

var main
var player
var minion := false
var hp := 170.0
var max_hp := 170.0
var speed := 3.6
var s := 1.45
var cool := 0.0
var stagger := 0.0
var charge := 0.0
var charge_hit := false
var dying := false
var phase := 1
var atk_t := 5.0
var walk_t := 0.0
var intro := 2.6
var flash := 0.0
var step_t := 0.0
var phase0 := 0.0
var t := 0.0

# Bewegung / Anti-Festhängen
var steer_t := 0.0
var steer_side := 1.0
var stuck_chk := 0.4
var stuck_n := 0
var last_pos := Vector3.ZERO
var phase_t := 0.0
var glitch_t := 0.0
# Grusel
var blink_t := 8.0
var far_t := 0.0
var heart_t := 0.0
var voice_t := 12.0
var roar_t := 0.0
var twitch_t := 1.5
var head_target := 0.0
var flash_dirty := false
var vehicle_airborne := false
var vehicle_velocity := Vector3.ZERO

var vis: Node3D
var head: Node3D
var jaw: Node3D
var mouth: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var body_m: MeshInstance3D
var glow: OmniLight3D
var col: CollisionShape3D
var cap: CapsuleShape3D
var xarms: Array = []
var coat_mat: StandardMaterial3D

func setup(is_minion: bool, m, p, pos: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	main = m
	player = p
	minion = is_minion
	position = pos
	last_pos = pos
	phase0 = randf() * 10.0
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1
	if minion:
		s = 0.45
		hp = 40.0
		max_hp = 40.0
		speed = 3.5
		intro = 1.2
		if randf() < 0.35:
			hp = 22.0
			max_hp = 22.0
			speed = 5.4
			s = 0.36
	else:
		s = 1.45
		hp = 170.0
		max_hp = 170.0
		speed = 3.6
		intro = 2.6
	_build()

func _exit_tree() -> void:
	_restore_flash()

func _restore_flash() -> void:
	if flash_dirty and is_instance_valid(player) and player.flash != null:
		player.flash.light_energy = 5.0
	flash_dirty = false

# ------------------------------------------------------------------ Bau
func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## Haut/Stoff mit Rausch-Textur (Textur wird zwischen allen Gegnern geteilt).
func _tmat(key: String, c1: Color, c2: Color, scale := 1.4) -> StandardMaterial3D:
	if not _texes.has(key):
		var n := FastNoiseLite.new()
		n.frequency = 0.045
		n.fractal_octaves = 3
		var g := Gradient.new()
		g.colors = PackedColorArray([c1, c2])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		var tx := NoiseTexture2D.new()
		tx.noise = n
		tx.color_ramp = g
		tx.width = 128
		tx.height = 128
		tx.seamless = true
		_texes[key] = tx
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texes[key]
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = 0.9
	return m

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c

func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

func _sphere(r: float) -> SphereMesh:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 14
	sp.rings = 8
	return sp

func _limb(parent: Node3D, pos: Vector3, mesh: Mesh, mat: Material, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	_mesh(pivot, mesh, mat, Vector3(0, -length / 2.0, 0))
	return pivot

## z-Position der Schädeloberfläche (Ellipsoid) für aufgesetzte Details.
func _skull_z(x: float, y: float) -> float:
	return sqrt(maxf(0.0, 0.09 - x * x - (y / 1.5) * (y / 1.5))) + 0.004

func _build() -> void:
	vis = Node3D.new()
	vis.scale = Vector3.ONE * s
	if not minion:
		vis.rotation.x = 0.1   # gebückt, lauernd
	add_child(vis)
	coat_mat = _tmat("coat", Color(0.012, 0.012, 0.018), Color(0.08, 0.08, 0.09))
	var skin := _tmat("skin", Color(0.4, 0.43, 0.38), Color(0.68, 0.7, 0.63))
	var head_mat := _tmat("head", Color(0.5, 0.52, 0.46), Color(0.8, 0.82, 0.74))
	var eye_mat := _mat(Color(1.0, 0.1, 0.1), true)
	var socket_mat := _mat(Color(0.02, 0.01, 0.01), true)
	var bone := _mat(Color(0.72, 0.69, 0.6))
	var wound := _mat(Color(0.21, 0.02, 0.03), true)
	var dark := _mat(Color(0.02, 0.0, 0.0))

	body_m = _mesh(vis, _cyl(0.18, 0.3, 1.7), coat_mat, Vector3(0, 0.95, 0))
	_mesh(vis, _box(0.9, 0.14, 0.22), coat_mat, Vector3(0, 1.8, 0.05))
	_mesh(vis, _cyl(0.05, 0.07, 0.6, 6), skin, Vector3(0, 2.0, 0.12))

	head = Node3D.new()
	head.position = Vector3(0, 2.45, 0.2)
	vis.add_child(head)
	var skull := _mesh(head, _sphere(0.3), head_mat, Vector3.ZERO)
	skull.scale = Vector3(1, 1.5, 1)
	for sx in [-1.0, 1.0]:
		var sock := _mesh(head, _sphere(0.07), socket_mat, Vector3(sx * 0.1, 0.12, 0.26))
		sock.scale = Vector3(1, 1.3, 0.65)
		_mesh(head, _sphere(0.03), eye_mat, Vector3(sx * 0.1, 0.12, 0.285))
		var horn := _mesh(head, _cyl(0.0, 0.065, 0.25, 5), bone, Vector3(sx * 0.19, 0.4, 0.02))
		horn.rotation.z = -sx * 0.48
	# Zugenähte Narbe über der Stirn
	for i in 5:
		var y := 0.16 + i * 0.07
		var st := _mesh(head, _box(0.1, 0.012, 0.012), dark, Vector3(-0.07, y, _skull_z(-0.07, y)))
		st.rotation.z = randf_range(-0.5, 0.5)
	mouth = _mesh(head, _sphere(0.14), wound, Vector3(0, -0.26, 0.2))
	mouth.scale = Vector3(1.25, 0.15, 0.4)
	for i in 4:
		var x := (i - 1.5) * 0.065
		var up := _mesh(head, _cyl(0.0, 0.023, 0.075, 5), bone, Vector3(x, -0.235, 0.235))
		up.rotation.x = PI
	# Ausgehängter Kiefer (klappt auf und zu)
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.22, 0.08)
	head.add_child(jaw)
	_mesh(jaw, _box(0.3, 0.05, 0.26), bone, Vector3(0, -0.06, 0.15))
	for i in 4:
		var x2 := (i - 1.5) * 0.065
		_mesh(jaw, _cyl(0.0, 0.023, 0.075, 5), bone, Vector3(x2, -0.015, 0.25))

	var arm_mesh := _box(0.06, 1.1, 0.06)
	arm_l = _limb(vis, Vector3(-0.45, 1.8, 0.15), arm_mesh, coat_mat, 1.1)
	arm_r = _limb(vis, Vector3(0.45, 1.8, 0.15), arm_mesh, coat_mat, 1.1)
	arm_l.rotation = Vector3(-0.2, 0, 0.08)
	arm_r.rotation = Vector3(-0.2, 0, -0.08)
	for a in [arm_l, arm_r]:
		for i in 4:
			var f := _mesh(a, _box(0.018, 0.4, 0.018), skin, Vector3((i - 1.5) * 0.03, -1.3, 0))
			f.rotation.z = (i - 1.5) * 0.18
	var leg_mesh := _box(0.09, 0.9, 0.09)
	leg_l = _limb(vis, Vector3(-0.13, 0.9, 0), leg_mesh, coat_mat, 0.9)
	leg_r = _limb(vis, Vector3(0.13, 0.9, 0), leg_mesh, coat_mat, 0.9)
	for i in 7:
		var a := float(i) / 7.0 * TAU
		var st2 := _mesh(vis, _box(0.09, randf_range(0.5, 1.0), 0.02), coat_mat, Vector3(cos(a) * 0.3, 0.35, sin(a) * 0.3))
		st2.rotation.y = -a

	if not minion:
		glow = OmniLight3D.new()
		glow.light_color = Color(1.0, 0.16, 0.1)
		glow.light_energy = 3.0
		glow.omni_range = 12.0
		glow.position = Vector3(0, 2.4, 0.6)
		vis.add_child(glow)
		_build_boss_extras(bone, eye_mat)

	col = CollisionShape3D.new()
	cap = CapsuleShape3D.new()
	col.shape = cap
	add_child(col)
	_apply_scale()

func _build_boss_extras(bone: Material, eye_mat: Material) -> void:
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var c := _mesh(head, _cyl(0.0, 0.04, 0.26, 4), coat_mat, Vector3(cos(a) * 0.2, 0.52, sin(a) * 0.2))
		c.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
	for i in 5:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.22 - i * 0.012
		tm.outer_radius = 0.25 - i * 0.012
		var rb := _mesh(vis, tm, bone, Vector3(0, 0.55 + i * 0.17, 0))
		rb.rotation.x = 0.0
	for p in [Vector3(-0.15, 0.2, 0.26), Vector3(0.15, 0.2, 0.26), Vector3(-0.07, 0.3, 0.28), Vector3(0.07, 0.3, 0.28)]:
		_mesh(head, _sphere(0.03), eye_mat, p)
	for sd in [-1.0, 1.0]:
		var xa := _limb(vis, Vector3(sd * 0.3, 1.75, 0.1), _box(0.05, 1.0, 0.05), coat_mat, 1.0)
		xa.rotation.z = sd * 0.35
		xarms.append(xa)
	# Rostiges Sägeblatt steckt im Rücken (Sägemühle!)
	var rust := _tmat("rust", Color(0.28, 0.13, 0.07), Color(0.55, 0.33, 0.17), 1.2)
	var blade := _mesh(vis, _cyl(0.42, 0.42, 0.025, 18), rust, Vector3(0.18, 1.7, -0.3))
	blade.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	for i in 12:
		var a2 := float(i) / 12.0 * TAU
		var tooth := _mesh(blade, _box(0.08, 0.03, 0.07), rust, Vector3(cos(a2) * 0.43, 0.0, sin(a2) * 0.43))
		tooth.rotation.y = -a2
	# Schwarzer Nebel um ihn herum
	var ps := CPUParticles3D.new()
	ps.amount = 22
	ps.lifetime = 2.4
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.55
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 30.0
	ps.initial_velocity_min = 0.3
	ps.initial_velocity_max = 0.8
	ps.gravity = Vector3.ZERO
	ps.local_coords = false
	var pm := _sphere(0.16)
	pm.radial_segments = 6
	pm.rings = 3
	ps.mesh = pm
	var pmat := _mat(Color(0.0, 0.0, 0.0, 0.4), true)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ps.material_override = pmat
	ps.position = Vector3(0, 1.2, 0)
	vis.add_child(ps)

func _apply_scale() -> void:
	vis.scale = Vector3.ONE * s
	cap.radius = 0.4 * s
	cap.height = 2.9 * s
	col.position.y = 1.45 * s

# ------------------------------------------------------------------ Schaden
func stun(sec: float) -> void:
	stagger = sec

func take_damage(dmg: float) -> void:
	if dying or intro > 0.0:
		return
	hp -= dmg
	flash = 0.2
	stagger = maxf(stagger, 0.12)
	head_target = randf_range(-1.1, 1.1)
	if hp <= 0.0:
		die()

func hit_by_vehicle(direction: Vector3, impact_speed: float) -> void:
	if dying or intro > 0.0:
		return
	take_damage(maxf(35.0, impact_speed * 7.0))
	if dying:
		return
	vehicle_velocity = direction.normalized() * clampf(impact_speed, 9.0, 16.0) + Vector3.UP * 6.0
	vehicle_airborne = true
	stagger = maxf(stagger, 0.8)

func kill() -> void:
	hp = 0.0
	die(true)

func die(silent := false) -> void:
	if dying:
		return
	dying = true
	collision_layer = 0
	_restore_flash()
	if glow:
		glow.light_energy = 0.0
	main.play_sfx("death")
	var tw := create_tween()
	tw.tween_property(vis, "rotation:x", -1.55, 1.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(arm_l, "rotation:x", -2.4, 1.0)
	tw.parallel().tween_property(arm_r, "rotation:x", -2.2, 1.0)
	tw.parallel().tween_property(jaw, "rotation:x", 1.0, 1.0)
	if not silent:
		died.emit(self)
	get_tree().create_timer(15.0, false).timeout.connect(queue_free)

# ------------------------------------------------------------------ Verhalten
func _physics_process(delta: float) -> void:
	if dying:
		return
	t += delta
	# Treffer-Aufleuchten
	coat_mat.emission_enabled = flash > 0.0
	if flash > 0.0:
		coat_mat.emission = Color(0.45, 0.13, 0.13)
		flash -= delta
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, delta * (14.0 if minion else 7.0)))
	# Kopf zuckt unregelmäßig zur Seite
	twitch_t -= delta
	if twitch_t <= 0.0:
		twitch_t = randf_range(0.8, 3.0)
		head_target = randf_range(-0.9, 0.9) if randf() < 0.55 else 0.0
	head.rotation.y = move_toward(head.rotation.y, head_target, delta * 7.0)
	head.rotation.z = sin(t * 2.0 + phase0) * 0.2
	# Spawn-Flackern + Gebrüll
	if intro > 0.0:
		intro -= delta
		vis.visible = true
		jaw.rotation.x = 0.55 + absf(sin(t * 26.0)) * 0.5
		mouth.scale.y = 0.15 + jaw.rotation.x * 0.8
		head.rotation.x = randf_range(-0.12, 0.12)
		return
	head.rotation.x = 0.0
	# Glitch (nach Teleport / beim Durchgleiten)
	if glitch_t > 0.0:
		glitch_t -= delta
	if phase_t > 0.0:
		phase_t -= delta
		if phase_t <= 0.0:
			collision_mask = 1
			last_pos = position
	vis.visible = true
	# Kiefer: im Leerlauf leicht offen, beim Brüllen weit
	if roar_t > 0.0:
		roar_t -= delta
	var jt := 0.1 + 0.08 * sin(t * 1.3 + phase0)
	if charge > 0.0 or roar_t > 0.0:
		jt = 0.85
	jaw.rotation.x = lerpf(jaw.rotation.x, jt, minf(1.0, delta * 8.0))
	mouth.scale.y = 0.15 + jaw.rotation.x * 0.8
	if not player.alive:
		_restore_flash()
		return
	if vehicle_airborne:
		vehicle_velocity.y -= 18.0 * delta
		velocity = Vector3(vehicle_velocity.x, 0.0, vehicle_velocity.z)
		move_and_slide()
		vehicle_velocity.x = velocity.x
		vehicle_velocity.z = velocity.z
		vehicle_velocity.x = move_toward(vehicle_velocity.x, 0.0, delta * 5.0)
		vehicle_velocity.z = move_toward(vehicle_velocity.z, 0.0, delta * 5.0)
		position.y += vehicle_velocity.y * delta
		var lim: float = main.HALF - 3.0
		position.x = clampf(position.x, -lim, lim)
		position.z = clampf(position.z, -lim, lim)
		if position.y <= 0.0:
			position.y = 0.0
			vehicle_airborne = false
			vehicle_velocity = Vector3.ZERO
		return
	for i in xarms.size():
		xarms[i].rotation.x = -0.5 + sin(t * 3.0 + i * 2.0) * 0.45
	if not minion:
		_boss_logic(delta)
		_stalk(d, delta)
	if charge > 0.0:
		charge -= delta
	if stagger > 0.0:
		stagger -= delta
		return
	var reach := 1.4 if minion else 2.0
	reach *= maxf(1.0, s * 0.8)
	if d > reach:
		var sp := speed * (0.8 + maxf(0.0, sin(t * 1.7 + phase0)) * 0.9) * (3.4 if charge > 0.0 else 1.0)
		_chase(to, d, sp, delta)
		walk_t += delta * speed * 2.2
		var sw := sin(walk_t)
		arm_l.rotation.x = -0.2 + sw * 0.55
		arm_r.rotation.x = -0.2 - sw * 0.55
		leg_l.rotation.x = sw * 0.5
		leg_r.rotation.x = -sw * 0.5
		body_m.position.y = 0.95 + absf(cos(walk_t)) * 0.06
		if not minion:
			step_t -= delta
			if step_t <= 0.0:
				step_t = 0.62
				var k := clampf(1.0 - d / 14.0, 0.0, 1.0)
				if k > 0.0:
					main.play_sfx("step", linear_to_db(k))
					main.shake(0.45 * k)
	else:
		cool -= delta
		var atk := sin(t * 18.0) * 0.25
		arm_l.rotation.x = -2.1 + atk
		arm_r.rotation.x = -2.1 - atk
		leg_l.rotation.x = 0.0
		leg_r.rotation.x = 0.0
		if charge > 0.0 and not charge_hit:
			charge_hit = true
			charge = 0.0
			player.hurt(34.0)
			main.shake(2.0)
		elif cool <= 0.0:
			cool = 0.7 if minion else 0.9
			roar_t = 0.35
			player.hurt(12.0 if minion else 22.0 + phase * 6.0)

## Läuft auf den Spieler zu. Hängt er fest (Baum, Fels, Haus), weicht er seitlich aus;
## hilft das nicht, gleitet er einen Moment durch alles hindurch.
func _chase(to: Vector3, d: float, sp: float, delta: float) -> void:
	var dir := to / d
	if steer_t > 0.0:
		steer_t -= delta
		dir = dir.rotated(Vector3.UP, steer_side * 1.0)
	velocity = dir * sp
	velocity.y = 0.0
	move_and_slide()
	position.y = 0.0
	var lim: float = main.HALF - 3.0
	position.x = clampf(position.x, -lim, lim)
	position.z = clampf(position.z, -lim, lim)
	stuck_chk -= delta
	if stuck_chk <= 0.0:
		stuck_chk = 0.4
		var moved := Vector2(position.x - last_pos.x, position.z - last_pos.z).length()
		last_pos = position
		if phase_t <= 0.0 and moved < sp * 0.4 * 0.35:
			stuck_n += 1
			steer_side = 1.0 if randf() < 0.5 else -1.0
			steer_t = 0.9
			if stuck_n >= 3:
				stuck_n = 0
				phase_t = 1.6
				collision_mask = 0
		elif moved > sp * 0.4 * 0.6:
			stuck_n = 0

## Boss-Grusel: taucht auf, wenn er zu weit weg ist, blinzelt näher, Herzschlag, Lampenflackern, Stimmen.
func _stalk(d: float, delta: float) -> void:
	if d > 55.0:
		far_t += delta
		if far_t > 4.0:
			far_t = 0.0
			_blink_near(34.0)
	else:
		far_t = 0.0
	if phase >= 2 and d > 7.0 and d < 32.0 and charge <= 0.0:
		blink_t -= delta
		if blink_t <= 0.0:
			blink_t = randf_range(6.0, 10.0) if phase == 2 else randf_range(4.0, 7.0)
			_blink_near(maxf(3.5, d - randf_range(5.0, 7.0)))
	if d < 16.0:
		var k := 1.0 - d / 16.0
		heart_t -= delta
		if heart_t <= 0.0:
			heart_t = lerpf(1.0, 0.38, k)
			main.play_sfx("heart", linear_to_db(clampf(k + 0.2, 0.05, 1.0)))
		if player.flash != null:
			flash_dirty = true
			player.flash.light_energy = 5.0 * (0.12 if randf() < k * 0.35 else 1.0)
		main.shake(0.15 * k)
	elif flash_dirty:
		_restore_flash()
	if main.state == "fight":
		voice_t -= delta
		if voice_t <= 0.0:
			voice_t = randf_range(12.0, 20.0)
			var v: Array = VOICES.pick_random()
			main._line(v[0], v[1], 3.2)

func _blink_near(dist: float) -> void:
	var pp: Vector3 = player.global_position
	var away := global_position - pp
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(0, 0, 1)
	var ang := atan2(away.x, away.z) + randf_range(-0.8, 0.8)
	var lim: float = main.HALF - 3.0
	var np := pp + Vector3(sin(ang), 0.0, cos(ang)) * dist
	np.x = clampf(np.x, -lim, lim)
	np.z = clampf(np.z, -lim, lim)
	position = Vector3(np.x, 0.0, np.z)
	last_pos = position
	glitch_t = 0.35
	phase_t = maxf(phase_t, 0.5)
	collision_mask = 0
	flash = 0.2
	main.play_sfx("crack", -4.0)
	main.shake(0.7)

# ------------------------------------------------------------------ Boss-Angriffe
func _boss_logic(delta: float) -> void:
	var ratio := hp / max_hp
	if phase == 1 and ratio < 0.66:
		phase = 2
		speed *= 1.15
		phase_changed.emit(self, 2)
	elif phase == 2 and ratio < 0.33:
		phase = 3
		speed *= 1.15
		s = 1.75
		_apply_scale()
		glow.light_energy = 6.0
		phase_changed.emit(self, 3)
	if phase >= 2:
		atk_t -= delta
		if atk_t <= 0.0:
			atk_t = 5.0 if phase >= 3 else 7.0
			_boss_attack()

func _boss_attack() -> void:
	var opts := ["shock", "charge"]
	if phase >= 3:
		opts.append_array(["slam", "slam"])
	var k: String = opts.pick_random()
	match k:
		"shock": _shock()
		"charge": _charge()
		"slam": _slam()

func _shock() -> void:
	main.sub("⚠ Er holt tief Luft…", 1.1)
	roar_t = 1.3
	get_tree().create_timer(1.1, false).timeout.connect(_shock_hit)

func _shock_hit() -> void:
	if dying or not player.alive:
		return
	main.shake(2.6)
	main.play_sfx("roar")
	main.flash_hurt()
	if player.global_position.distance_to(global_position) < 11.0:
		player.hurt(20.0)

func _charge() -> void:
	main.sub("⚠ Er stürmt auf dich zu!", 1.2)
	roar_t = 1.0
	get_tree().create_timer(0.9, false).timeout.connect(_charge_go)

func _charge_go() -> void:
	if dying:
		return
	charge = 1.6
	charge_hit = false
	main.play_sfx("roar")

func _slam() -> void:
	main.sub("⚠ Knochen brechen aus dem Boden!", 1.3)
	var pp: Vector3 = player.global_position
	var centers := [pp, pp + Vector3(3, 0, 2), pp + Vector3(-3, 0, -2)]
	for i in 3:
		var c: Vector3 = centers[i]
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.0
		cm.bottom_radius = 2.0
		cm.height = 0.02
		m.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.07, 0.0, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.top_level = true
		m.position = Vector3(c.x, 0.07, c.z)
		add_child(m)
		get_tree().create_timer(1.2 + i * 0.25, false).timeout.connect(_slam_hit.bind(m, c))

func _slam_hit(m: Node3D, c: Vector3) -> void:
	m.queue_free()
	if dying or not player.alive:
		return
	main.shake(1.8)
	main.play_sfx("boom")
	var dd := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
	if dd < 2.1:
		player.hurt(30.0)
