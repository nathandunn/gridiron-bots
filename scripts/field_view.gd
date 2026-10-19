class_name FieldView
extends Node3D
## The arena and the robots, drawn from a PlaySim. World units are yards: x across the field,
## z along it with Red's goal line at z = -50 and Blue's at z = +50 (Red attacks +z).
##
## The look is a neon robot-football arena: a dark steel field with glowing lines, lit rails and
## walls, light towers, and armoured robots with visor lights in team colours.

const HALF_W := 26.667
## Team colours (the HUD uses these too): a hot red-orange and an electric blue.
const COLORS := [Color(1.0, 0.28, 0.2), Color(0.22, 0.6, 1.0)]
const NEON := [Color(1.0, 0.35, 0.25), Color(0.3, 0.75, 1.0)]
const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const YELLOW := Color(1.0, 0.85, 0.2)
const STEEL := Color(0.16, 0.18, 0.22)

var _players := {}           # idx -> {root, legs, label, ...}
var _ball: MeshInstance3D
var _ball_light: OmniLight3D
var _los: MeshInstance3D
var _sticks: MeshInstance3D
var _mats := {}
var sim: PlaySim = null
var poss := 0                # who has the ball (0 Red, 1 Blue)
var yl := 25.0               # the offense's yard line
var _prev := {}              # idx -> Vector2 (last step), for smoothing
var _cur := {}
var alpha := 1.0             # how far between the last two steps
var _t := 0.0
var _pulse: Array = []       # emissive materials that breathe


func _ready() -> void:
	_build_field()
	_ball = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.18
	bm.height = 0.36
	_ball.mesh = bm
	_ball.scale = Vector3(1, 1, 1.7)
	_ball.material_override = _glow(Color(1.0, 0.6, 0.15), 3.0)
	add_child(_ball)
	_ball_light = OmniLight3D.new()
	_ball_light.light_color = Color(1.0, 0.6, 0.2)
	_ball_light.light_energy = 0.9
	_ball_light.omni_range = 3.0
	_ball.add_child(_ball_light)
	_los = _line(CYAN, 2.5)
	_sticks = _line(YELLOW, 2.5)


## ---- materials -------------------------------------------------------------------------------

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var key := "m%s%s" % [c.to_html(), unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Brushed metal: dark, a little shine.
func _metal(c: Color) -> StandardMaterial3D:
	var key := "x%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.75
	m.roughness = 0.35
	_mats[key] = m
	return m


## Light that glows.
func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g%s%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi


func _line(c: Color, energy: float) -> MeshInstance3D:
	return _box(Vector3(HALF_W * 2.0, 0.03, 0.22), Vector3(0, 0.04, 0), _glow(c, energy))


## ---- the arena -------------------------------------------------------------------------------

func _build_field() -> void:
	# the arena floor beyond the field
	_box(Vector3(140, 0.1, 190), Vector3(0, -0.1, 0), _metal(Color(0.07, 0.08, 0.1)))
	# the field: dark steel plates in five-yard bands
	for i in 20:
		var shade := Color(0.12, 0.14, 0.19) if i % 2 == 0 else Color(0.1, 0.12, 0.16)
		_box(Vector3(HALF_W * 2.0, 0.04, 5.0), Vector3(0, -0.02, -47.5 + i * 5.0), _metal(shade))
	# end zones: team light, with chevrons
	for t in 2:
		var z := -55.0 if t == 0 else 55.0
		_box(Vector3(HALF_W * 2.0, 0.04, 10.0), Vector3(0, -0.015, z), _mat(COLORS[t].darkened(0.6)))
		var dir := -1.0 if t == 0 else 1.0
		for k in 5:
			var cz := z - dir * 3.5 + dir * k * 1.6
			for side: float in [-1.0, 1.0]:
				var ch := _box(Vector3(6.0, 0.02, 0.35), Vector3(side * (HALF_W - 5.0), 0.03, cz), _glow(NEON[t], 1.4))
				ch.rotation.y = side * dir * 0.5
		var lab := Label3D.new()
		lab.text = ["RED", "BLUE"][t]
		lab.font_size = 600
		lab.pixel_size = 0.012
		lab.outline_size = 0
		lab.modulate = NEON[t].lightened(0.3)
		lab.rotation = Vector3(-PI / 2, PI if t == 1 else 0.0, 0)
		lab.position = Vector3(0, 0.04, z)
		add_child(lab)
	# glowing yard lines every five yards, numbers every ten
	for i in 21:
		var z := -50.0 + i * 5.0
		var goal := i == 0 or i == 20
		_box(Vector3(HALF_W * 2.0, 0.03, 0.22 if goal else (0.14 if i % 2 == 0 else 0.08)), Vector3(0, 0.0, z),
			_glow(YELLOW if goal else CYAN, 2.2 if goal else (0.9 if i % 2 == 0 else 0.5)))
		if i % 2 == 0 and i > 0 and i < 20:
			var n := 50 - absi(50 - i * 5)
			for side: float in [-1.0, 1.0]:
				var lab := Label3D.new()
				lab.text = str(n)
				lab.font_size = 180
				lab.pixel_size = 0.012
				lab.modulate = Color(0.55, 0.95, 1.0, 0.75)
				lab.rotation = Vector3(-PI / 2, PI / 2 * side, 0)
				lab.position = Vector3(side * (HALF_W - 6.0), 0.03, z)
				add_child(lab)
	# hash marks: small lights
	var hash_mat := _glow(Color(0.45, 0.85, 1.0, 0.7), 0.6)
	for i in range(1, 100):
		var z := -50.0 + i
		for hx: float in [-3.08, 3.08]:
			_box(Vector3(0.45, 0.02, 0.06), Vector3(hx, 0.0, z), hash_mat)
	# lit rails along the sidelines and end lines
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.25, 0.25, 120.6), Vector3(sx * (HALF_W + 0.4), 0.13, 0), _glow(MAGENTA, 2.4))
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0 + 1.0, 0.25, 0.25), Vector3(0, 0.13, sz * 60.4), _glow(MAGENTA, 2.4))
	# the arena wall: steel, a light strip along the top, lit panels
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.6, 3.2, 128), Vector3(sx * (HALF_W + 4.0), 1.6, 0), _metal(STEEL))
		_box(Vector3(0.65, 0.18, 128), Vector3(sx * (HALF_W + 4.0), 3.25, 0), _glow(CYAN, 2.0))
		for k in 12:
			var pz := -55.0 + k * 10.0
			var panel := _box(Vector3(0.1, 1.2, 6.5), Vector3(sx * (HALF_W + 3.68), 1.5, pz), _glow(NEON[k % 2].darkened(0.25), 1.2))
			_pulse.append(panel.material_override)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0 + 8.6, 3.2, 0.6), Vector3(0, 1.6, sz * 64.0), _metal(STEEL))
		_box(Vector3(HALF_W * 2.0 + 8.6, 0.18, 0.65), Vector3(0, 3.25, sz * 64.0), _glow(CYAN, 2.0))
	# goal posts in neon
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * 60.0
		var gm := _glow(YELLOW, 2.0)
		_box(Vector3(0.25, 3.3, 0.25), Vector3(0, 1.65, z), gm)
		_box(Vector3(6.2, 0.2, 0.2), Vector3(0, 3.3, z), gm)
		for px: float in [-3.0, 3.0]:
			_box(Vector3(0.2, 7.0, 0.2), Vector3(px, 6.8, z), gm)
	# stands: dark tiers with rows of crowd lights
	for sx: float in [-1.0, 1.0]:
		for r in 7:
			var x := sx * (HALF_W + 7.0 + r * 2.2)
			var h := 3.6 + r * 1.3
			_box(Vector3(2.2, h, 126), Vector3(x, h * 0.5, 0), _metal(Color(0.09, 0.1, 0.13).lightened(r * 0.015)))
			_box(Vector3(2.0, 0.08, 120), Vector3(x, h + 0.05, 0), _glow([CYAN, MAGENTA, NEON[0], NEON[1]][r % 4].darkened(0.55), 1.0))
	# light towers at the corners
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base := Vector3(sx * (HALF_W + 24.0), 0, sz * 58.0)
			_box(Vector3(0.8, 26.0, 0.8), base + Vector3(0, 13.0, 0), _metal(STEEL))
			var head := _box(Vector3(5.0, 2.2, 0.6), base + Vector3(0, 26.5, 0), _glow(Color(0.95, 0.97, 1.0), 3.0))
			head.look_at_from_position(head.position, Vector3(0, 0, 0), Vector3.UP)


## Where a play-frame point is in the world.
func world(p: Vector2, h := 0.0) -> Vector3:
	var a := yl + p.y                 # yards from the offense's own goal line
	# the camera stands behind the offense, so the play's right (+x) must be the screen's right:
	# looking down +z, screen right is world -x
	if poss == 0:
		return Vector3(-p.x, h, a - 50.0)
	return Vector3(p.x, h, 50.0 - a)


## The direction the offense attacks, in the world.
func attack_dir() -> float:
	return 1.0 if poss == 0 else -1.0


func set_play(s: PlaySim, possession: int, yard_line: float, to_go: float) -> void:
	sim = s
	poss = possession
	yl = yard_line
	_prev.clear()
	_cur.clear()
	for k in _players:
		_players[k]["root"].visible = false
	if s == null:
		_ball.visible = false
		_place_line(_los, yard_line)
		_place_line(_sticks, minf(yard_line + to_go, 100.0))
		return
	_ball.visible = true
	for p in s.players:
		_ensure_player(p)
		_players[p.idx]["root"].visible = true
		_prev[p.idx] = p.pos
		_cur[p.idx] = p.pos
	_place_line(_los, yard_line)
	_place_line(_sticks, minf(yard_line + to_go, 100.0))
	_sticks.visible = yard_line + to_go < 100.0


func _place_line(mi: MeshInstance3D, offense_yl: float) -> void:
	var a := offense_yl if poss == 0 else 100.0 - offense_yl
	mi.position = Vector3(0, 0.04, a - 50.0)


## ---- the robots ------------------------------------------------------------------------------

## One robot: armoured legs, a torso in team colour with big shoulder plates, a head with a
## glowing visor and a chest light. Linemen are heavier; backs and receivers leaner.
func _ensure_player(p: PlaySim.P) -> void:
	var team := p.team
	var key := p.idx
	if _players.has(key):
		var e: Dictionary = _players[key]
		if e["team"] == team and e["slot"] == p.slot:
			return
		(e["root"] as Node3D).queue_free()
	var root := Node3D.new()
	add_child(root)
	var big := p.group in ["OL", "DL"]
	var lean := p.group in ["WR", "CB", "RB", "S"]
	var w := 1.25 if big else (0.9 if lean else 1.05)
	var armour := _metal(COLORS[team].darkened(0.15))
	var frame := _metal(Color(0.22, 0.24, 0.28))
	var light := _glow(NEON[team], 2.6)
	# legs pivot at the hip so they can stride
	var legs: Array = []
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.2 * w, 0.95, 0)
		root.add_child(hip)
		_box(Vector3(0.24 * w, 0.95, 0.28), Vector3(0, -0.48, 0), frame, hip)
		_box(Vector3(0.3 * w, 0.16, 0.42), Vector3(0, -0.9, 0.06), armour, hip)     # foot
		_box(Vector3(0.26 * w, 0.18, 0.08), Vector3(0, -0.45, 0.15), light, hip)    # knee light
		legs.append(hip)
	# torso and plates
	_box(Vector3(0.62 * w, 0.75, 0.42), Vector3(0, 1.32, 0), armour, root)
	_box(Vector3(0.95 * w, 0.24, 0.55), Vector3(0, 1.72, 0), armour, root)          # shoulders
	_box(Vector3(0.22, 0.14, 0.04), Vector3(0, 1.38, 0.22), light, root)             # chest light
	# arms
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 0.7, 0.22), Vector3(side * 0.52 * w, 1.3, 0), frame, root)
	# head and visor
	_box(Vector3(0.36, 0.34, 0.4), Vector3(0, 2.02, 0), _metal(Color(0.12, 0.13, 0.16)), root)
	_box(Vector3(0.38, 0.08, 0.06), Vector3(0, 2.05, 0.2), light, root)
	_box(Vector3(0.06, 0.16, 0.36), Vector3(0, 2.24, -0.02), light, root)            # crest
	var lab := Label3D.new()
	lab.text = p.slot
	lab.visible = not big
	lab.font_size = 52
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 2.85, 0)
	lab.outline_size = 10
	lab.no_depth_test = true
	lab.modulate = NEON[team].lightened(0.4)
	root.add_child(lab)
	_players[key] = {"root": root, "legs": legs, "label": lab, "team": team, "slot": p.slot, "tilt": 0.0, "stride": 0.0}


## Called after each sim step.
func stepped() -> void:
	if sim == null:
		return
	for p in sim.players:
		_prev[p.idx] = _cur.get(p.idx, p.pos)
		_cur[p.idx] = p.pos


func _process(delta: float) -> void:
	_t += delta
	var breathe := 1.0 + 0.35 * sin(_t * 2.2)
	for m in _pulse:
		(m as StandardMaterial3D).emission_energy_multiplier = breathe
	if sim == null:
		return
	for p in sim.players:
		var e: Dictionary = _players.get(p.idx, {})
		if e.is_empty():
			continue
		var a: Vector2 = _prev.get(p.idx, p.pos)
		var b: Vector2 = _cur.get(p.idx, p.pos)
		var pos := a.lerp(b, clampf(alpha, 0.0, 1.0))
		var root: Node3D = e["root"]
		root.position = world(pos)
		var f: Vector2 = p.face
		if p.vel.length() > 0.4:
			f = p.vel.normalized()
		var fw := world(pos + f) - world(pos)
		if fw.length() > 0.01:
			root.rotation.y = atan2(fw.x, fw.z)
		# down robots tip over
		var want := 1.45 if p.down else 0.0
		e["tilt"] = lerpf(float(e["tilt"]), want, minf(delta * 10.0, 1.0))
		root.rotation.x = float(e["tilt"])
		# stride with speed
		var sp: float = p.vel.length()
		e["stride"] = float(e["stride"]) + delta * sp * 1.6
		var swing := sin(float(e["stride"])) * clampf(sp / 6.0, 0.0, 1.0) * 0.7
		var legs: Array = e["legs"]
		(legs[0] as Node3D).rotation.x = swing
		(legs[1] as Node3D).rotation.x = -swing
		var lab: Label3D = e["label"]
		lab.modulate = YELLOW if p == sim.carrier else NEON[p.team].lightened(0.4)
	# the ball
	var bp := sim.ball_pos
	var h := sim.ball_h
	if sim.ball_state == "held" and sim.carrier != null:
		var a2: Vector2 = _prev.get(sim.carrier.idx, sim.carrier.pos)
		var b2: Vector2 = _cur.get(sim.carrier.idx, sim.carrier.pos)
		bp = a2.lerp(b2, clampf(alpha, 0.0, 1.0)) + sim.carrier.face * 0.4
		h = 1.25 if not sim.carrier.down else 0.25
	_ball.position = world(bp, h)
	if sim.ball_state == "air":
		_ball.rotation.y += delta * 12.0


## A spot for the camera to watch: the ball, mostly.
func focus() -> Vector3:
	if sim == null:
		return world(Vector2(0, 0))
	return _ball.position * Vector3(1, 0, 1)
