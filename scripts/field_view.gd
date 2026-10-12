class_name FieldView
extends Node3D
## The stadium and the players, drawn from a PlaySim. World units are yards: x across the field,
## z along it with Red's goal line at z = -50 and Blue's at z = +50 (Red attacks +z).

const HALF_W := 26.667
const COLORS := [Color(0.80, 0.16, 0.14), Color(0.17, 0.36, 0.85)]
const TRIM := [Color(0.98, 0.86, 0.3), Color(0.92, 0.94, 0.98)]

var _players := {}           # idx -> {root, body, helmet, label, ring}
var _ball: MeshInstance3D
var _los: MeshInstance3D
var _sticks: MeshInstance3D
var _mats := {}
var sim: PlaySim = null
var poss := 0                # who has the ball (0 Red, 1 Blue)
var yl := 25.0               # the offense's yard line
var _prev := {}              # idx -> Vector2 (last step), for smoothing
var _cur := {}
var alpha := 1.0             # how far between the last two steps


func _ready() -> void:
	_build_field()
	_ball = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.16
	bm.height = 0.32
	_ball.mesh = bm
	_ball.scale = Vector3(1, 1, 1.7)
	_ball.material_override = _mat(Color(0.48, 0.24, 0.1))
	add_child(_ball)
	_los = _line(Color(0.25, 0.55, 1.0, 0.85))
	_sticks = _line(Color(1.0, 0.85, 0.1, 0.9))


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var key := "%s%s" % [c.to_html(), unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, c: Color, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(c, unshaded)
	add_child(mi)
	return mi


func _line(c: Color) -> MeshInstance3D:
	var mi := _box(Vector3(HALF_W * 2.0, 0.02, 0.18), Vector3(0, 0.03, 0), c, true)
	return mi


func _build_field() -> void:
	# the ground around the field
	_box(Vector3(100, 0.1, 160), Vector3(0, -0.08, 0), Color(0.17, 0.33, 0.17))
	# five-yard stripes of grass
	for i in 20:
		var shade := Color(0.22, 0.52, 0.22) if i % 2 == 0 else Color(0.2, 0.47, 0.2)
		_box(Vector3(HALF_W * 2.0, 0.02, 5.0), Vector3(0, -0.01, -47.5 + i * 5.0), shade)
	# end zones
	for t in 2:
		var z := -55.0 if t == 0 else 55.0
		_box(Vector3(HALF_W * 2.0, 0.02, 10.0), Vector3(0, -0.005, z), COLORS[t].darkened(0.25))
		var lab := Label3D.new()
		lab.text = ["RED", "BLUE"][t]
		lab.font_size = 600
		lab.pixel_size = 0.012
		lab.outline_size = 0
		lab.modulate = Color(1, 1, 1, 0.55)
		lab.rotation = Vector3(-PI / 2, PI if t == 1 else 0.0, 0)
		lab.position = Vector3(0, 0.03, z)
		add_child(lab)
	# lines every five yards, numbers every ten
	for i in 21:
		var z := -50.0 + i * 5.0
		_box(Vector3(HALF_W * 2.0, 0.03, 0.15 if i % 2 == 0 else 0.1), Vector3(0, 0.0, z), Color(0.95, 0.95, 0.95), true)
		if i % 2 == 0 and i > 0 and i < 20:
			var n := 50 - absi(50 - i * 5)
			for side: float in [-1.0, 1.0]:
				var lab := Label3D.new()
				lab.text = str(n)
				lab.font_size = 180
				lab.pixel_size = 0.012
				lab.modulate = Color(1, 1, 1, 0.8)
				lab.rotation = Vector3(-PI / 2, PI / 2 * side, 0)
				lab.position = Vector3(side * (HALF_W - 6.0), 0.03, z)
				add_child(lab)
	# hash marks
	for i in 101:
		var z := -50.0 + i
		for hx: float in [-3.08, 3.08, -HALF_W + 0.5, HALF_W - 0.5]:
			_box(Vector3(0.5, 0.03, 0.07), Vector3(hx, 0.0, z), Color(0.95, 0.95, 0.95), true)
	# sidelines and end lines
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 0.035, 120), Vector3(sx * (HALF_W + 0.15), 0.0, 0), Color.WHITE, true)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(HALF_W * 2.0 + 0.6, 0.035, 0.3), Vector3(0, 0.0, sz * 60.15), Color.WHITE, true)
	# goal posts
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * 60.0
		_box(Vector3(0.25, 3.3, 0.25), Vector3(0, 1.65, z), Color(0.95, 0.85, 0.2))
		_box(Vector3(6.2, 0.2, 0.2), Vector3(0, 3.3, z), Color(0.95, 0.85, 0.2))
		for px in [-3.0, 3.0]:
			_box(Vector3(0.2, 7.0, 0.2), Vector3(px, 6.8, z), Color(0.95, 0.85, 0.2))
	# a grandstand on each side so the field doesn't float
	for sx: float in [-1.0, 1.0]:
		for r in 6:
			_box(Vector3(2.0, 1.0 + r * 1.2, 110), Vector3(sx * (HALF_W + 9.0 + r * 2.0), 0.5 + r * 0.6, 0), Color(0.24, 0.25, 0.3).lightened(r * 0.03))


## Where a play-frame point is in the world.
func world(p: Vector2, h := 0.0) -> Vector3:
	var a := yl + p.y                 # yards from the offense's own goal line
	if poss == 0:
		return Vector3(p.x, h, a - 50.0)
	return Vector3(-p.x, h, 50.0 - a)


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
	mi.position = Vector3(0, 0.03, a - 50.0)


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
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.42 if big else 0.34
	cm.height = 1.75
	body.mesh = cm
	body.position = Vector3(0, 0.88, 0)
	body.material_override = _mat(COLORS[team])
	root.add_child(body)
	var helmet := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.27
	hm.height = 0.54
	helmet.mesh = hm
	helmet.position = Vector3(0, 1.88, 0)
	helmet.material_override = _mat(TRIM[team])
	root.add_child(helmet)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.62 if big else 0.5, 0.18, 0.62 if big else 0.5)
	stripe.mesh = sm
	stripe.position = Vector3(0, 1.15, 0)
	stripe.material_override = _mat(TRIM[team])
	root.add_child(stripe)
	var lab := Label3D.new()
	lab.text = p.slot
	lab.visible = not (p.group in ["OL", "DL"])
	lab.font_size = 52
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 2.75, 0)
	lab.outline_size = 10
	lab.no_depth_test = true
	lab.modulate = Color(1, 1, 1, 0.92)
	root.add_child(lab)
	_players[key] = {"root": root, "body": body, "label": lab, "team": team, "slot": p.slot, "tilt": 0.0}


## Called after each sim step.
func stepped() -> void:
	if sim == null:
		return
	for p in sim.players:
		_prev[p.idx] = _cur.get(p.idx, p.pos)
		_cur[p.idx] = p.pos


func _process(delta: float) -> void:
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
		# down men tip over; the ball carrier glows a little
		var want := 1.45 if p.down else 0.0
		e["tilt"] = lerpf(float(e["tilt"]), want, minf(delta * 10.0, 1.0))
		root.rotation.x = float(e["tilt"])
		var lab: Label3D = e["label"]
		lab.modulate = Color(1, 0.95, 0.4) if p == sim.carrier else Color(1, 1, 1, 0.85)
	# the ball
	var bp := sim.ball_pos
	var h := sim.ball_h
	if sim.ball_state == "held" and sim.carrier != null:
		var a2: Vector2 = _prev.get(sim.carrier.idx, sim.carrier.pos)
		var b2: Vector2 = _cur.get(sim.carrier.idx, sim.carrier.pos)
		bp = a2.lerp(b2, clampf(alpha, 0.0, 1.0)) + sim.carrier.face * 0.35
		h = 1.1 if not sim.carrier.down else 0.25
	_ball.position = world(bp, h)
	if sim.ball_state == "air":
		_ball.rotation.y += delta * 12.0


## A spot for the camera to watch: the ball, mostly.
func focus() -> Vector3:
	if sim == null:
		return world(Vector2(0, 0))
	return _ball.position * Vector3(1, 0, 1)
