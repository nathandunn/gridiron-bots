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
var _seen := 0               # sim.actions already acted out
var _ball_fx := {}           # a loose or dead ball bouncing: {p0, p1, t0, hop}
var _fx_nodes: Array = []    # popups, sparks, speech: {node, t0, life, kind, ...}
var _spark_mat: Dictionary = {}
var talk := true             # robots talk trash

signal moment(a: Dictionary)                              # each action as it is acted out
signal trash_talk(team: int, slot: String, line: String)  # a robot says something


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
	_seen = 0
	_ball_fx = {}
	for n in _fx_nodes:
		(n["node"] as Node3D).queue_free()
	_fx_nodes.clear()
	for k in _players:
		_players[k]["root"].visible = false
		_players[k]["anim"] = ""
		_players[k]["fall_yaw"] = INF
		_players[k]["tilt"] = 0.0
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
	var body := Node3D.new()        # hops and lunges move this; root keeps the spot and facing
	root.add_child(body)
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
		body.add_child(hip)
		_box(Vector3(0.24 * w, 0.95, 0.28), Vector3(0, -0.48, 0), frame, hip)
		_box(Vector3(0.3 * w, 0.16, 0.42), Vector3(0, -0.9, 0.06), armour, hip)     # foot
		_box(Vector3(0.26 * w, 0.18, 0.08), Vector3(0, -0.45, 0.15), light, hip)    # knee light
		legs.append(hip)
	# torso and plates
	_box(Vector3(0.62 * w, 0.75, 0.42), Vector3(0, 1.32, 0), armour, body)
	_box(Vector3(0.95 * w, 0.24, 0.55), Vector3(0, 1.72, 0), armour, body)          # shoulders
	_box(Vector3(0.22, 0.14, 0.04), Vector3(0, 1.38, 0.22), light, body)             # chest light
	# arms swing from the shoulder: rotation.x below 0 raises them forward, about -3 is overhead
	var arms: Array = []
	for side: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.52 * w, 1.64, 0)
		body.add_child(sh)
		_box(Vector3(0.2, 0.7, 0.22), Vector3(0, -0.34, 0), frame, sh)
		_box(Vector3(0.24, 0.16, 0.26), Vector3(0, -0.72, 0.02), armour, sh)         # fist
		arms.append(sh)
	# head and visor
	_box(Vector3(0.36, 0.34, 0.4), Vector3(0, 2.02, 0), _metal(Color(0.12, 0.13, 0.16)), body)
	_box(Vector3(0.38, 0.08, 0.06), Vector3(0, 2.05, 0.2), light, body)
	_box(Vector3(0.06, 0.16, 0.36), Vector3(0, 2.24, -0.02), light, body)            # crest
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
	_players[key] = {"root": root, "body": body, "legs": legs, "arms": arms, "label": lab, "team": team, "slot": p.slot,
		"tilt": 0.0, "stride": 0.0, "roll": 0.0, "hop": 0.0, "lunge": 0.0, "arm": [0.0, 0.0], "anim": "", "anim_t": 0.0, "anim_yaw": 0.0, "fall_yaw": INF}


## Called after each sim step.
func stepped() -> void:
	if sim == null:
		return
	for p in sim.players:
		_prev[p.idx] = _cur.get(p.idx, p.pos)
		_cur[p.idx] = p.pos
	while _seen < sim.actions.size():
		_act_out(sim.actions[_seen])
		_seen += 1


func _process(delta: float) -> void:
	_t += delta
	var breathe := 1.0 + 0.35 * sin(_t * 2.2)
	for m in _pulse:
		(m as StandardMaterial3D).emission_energy_multiplier = breathe
	_tick_fx(delta)
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
		var sp: float = p.vel.length()
		e["stride"] = float(e["stride"]) + delta * sp * 1.6
		var swing := sin(float(e["stride"])) * clampf(sp / 6.0, 0.0, 1.0) * 0.7
		_pose(p, e, swing, delta)
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
	if not _ball_fx.is_empty() and sim.ball_state != "held" and sim.ball_state != "air":
		_ball.position = _ball_fx_pos()
		_ball.rotation.x += delta * 9.0
	if sim.ball_state == "air":
		_ball.rotation.y += delta * 12.0


## A spot for the camera to watch: the ball, mostly.
func focus() -> Vector3:
	if sim == null:
		return world(Vector2(0, 0))
	return _ball.position * Vector3(1, 0, 1)


## ---- the action ------------------------------------------------------------------------------

const POPUP := {
	"miss": ["BROKEN TACKLE!", Color(1.0, 0.85, 0.2)], "dive_miss": ["SLIPS IT!", Color(1.0, 0.85, 0.2)],
	"big_hit": ["BIG HIT!", Color(1.0, 0.35, 0.3)], "sack": ["SACK!", Color(1.0, 0.35, 0.3)],
	"dive_tackle": ["DIVING STOP!", Color(0.4, 0.95, 1.0)], "juke": ["JUKE!", Color(1.0, 0.85, 0.2)],
	"stiff_arm": ["STIFF ARM!", Color(1.0, 0.85, 0.2)], "catch": ["CATCH!", Color(0.4, 0.95, 1.0)],
	"drop": ["DROPPED!", Color(1.0, 0.4, 0.8)], "pbu": ["BROKEN UP!", Color(1.0, 0.4, 0.8)],
	"int": ["PICKED OFF!", Color(1.0, 0.35, 0.3)], "fumble": ["FUMBLE!", Color(1.0, 0.35, 0.3)],
	"recover": ["RECOVERED!", Color(0.4, 0.95, 1.0)], "pancake": ["PANCAKE!", Color(1.0, 0.85, 0.2)],
}

## What the robots say to each other, by what just happened.
const TRASH := {
	"tackler": ["Sit down, toaster.", "Error 404: yards not found.", "Reboot and try again.", "You run like dial-up.",
		"Welcome to the scrap yard.", "Nice try, tin can.", "Stay down, bolt bucket.", "I eat microwaves for breakfast.",
		"Your servos are trash.", "Return to sender."],
	"hitter": ["DING DING! Lights out!", "That's a factory reset!", "Scrap metal. SCRAP. METAL.", "Uninstall yourself.",
		"Call the repair shop!", "Hope you got a warranty.", "Who ordered the crunch?", "Your firmware just cried."],
	"sacker": ["Pocket's closed, pal.", "Get used to the turf.", "I live in your backfield.", "Say hi to the grass, QB."],
	"runner": ["Too slow, Roomba!", "Catch me? Catch a virus.", "Ankle software crashed?", "Bye-bye, buffering boy.",
		"You tackle like a printer.", "Was that a tackle? Cute.", "Leg day, every day."],
	"catcher": ["Mine. All mine.", "Hands like magnets.", "Catch THAT on your hard drive.", "Too easy, scrap heap."],
	"swatter": ["Not in my house!", "Get that weak junk outta here!", "Denied. Access DENIED.", "Swat-ware update installed."],
	"mocker": ["Butterfingers!", "Hands made of rust?", "Grease your grabbers, genius.", "Who coded your hands?"],
	"picker": ["Thanks for the gift!", "Your QB works for us now.", "Interception subroutine: ONLINE.", "Throw it again. Please."],
	"scorer": ["TOUCHDOWN, TIN CANS!", "Put it on the scoreboard!", "Too easy. Too, too easy.", "Six points. Zero effort."],
}

const DUR := {"dive": 1.7, "wrap": 1.3, "fall_back": 99.0, "fall_fwd": 99.0, "stumble": 0.6, "shrug": 0.5,
	"juke": 0.4, "stiff": 0.55, "throw": 0.5, "give": 0.45, "take": 0.5, "reach": 0.55, "swat": 0.55, "spike": 1.4}


func _who(i: int) -> PlaySim.P:
	if sim == null or i < 0 or i >= sim.players.size():
		return null
	return sim.players[i]


func _yaw_to(a: PlaySim.P, b: PlaySim.P) -> float:
	var d := world(_cur.get(b.idx, b.pos)) - world(_cur.get(a.idx, a.pos))
	if Vector2(d.x, d.z).length() < 0.01:
		return (_players[a.idx]["root"] as Node3D).rotation.y
	return atan2(d.x, d.z)


func _anim(p: PlaySim.P, kind: String, yaw := INF) -> void:
	if p == null or not _players.has(p.idx):
		return
	var e: Dictionary = _players[p.idx]
	e["anim"] = kind
	e["anim_t"] = _t
	e["anim_yaw"] = yaw


## One moment from the sim, acted out on the field.
func _act_out(a: Dictionary) -> void:
	var k := String(a["kind"])
	var pa := _who(int(a["a"]))
	var pb := _who(int(a["b"]))
	match k:
		"tackle", "big_hit", "sack", "dive_tackle":
			if pa != null and pb != null:
				var y := _yaw_to(pa, pb)
				_anim(pa, "dive" if k == "dive_tackle" or k == "sack" else "wrap", y)
				# a big hit knocks him back the way the tackler was going; otherwise he falls forward
				_anim(pb, "fall_back" if k == "big_hit" else "fall_fwd", y + PI if k == "big_hit" else INF)
				_sparks(world(pb.pos, 1.3), 7 if k == "tackle" else 16, Color(1.0, 0.75, 0.3))
				if k != "tackle":
					_popup(k, pb)
				_trash("sacker" if k == "sack" else ("hitter" if k == "big_hit" else "tackler"), pa, 0.45 if k == "tackle" or k == "dive_tackle" else 1.0)
		"miss", "dive_miss":
			if pa != null:
				_anim(pa, "dive" if k == "dive_miss" else "stumble", _yaw_to(pa, pb) if pb != null else INF)
			if pb != null:
				_anim(pb, "shrug")
				_sparks(world(pb.pos, 1.2), 5, Color(0.8, 0.9, 1.0))
				_popup(k, pb)
				_trash("runner", pb, 0.4)
		"juke":
			_anim(pa, "juke")
			_popup(k, pa)
		"stiff_arm":
			_anim(pa, "stiff", _yaw_to(pa, pb) if pb != null else INF)
			if pb != null:
				_anim(pb, "stumble")
				_sparks(world(pb.pos, 1.6), 4, Color(0.8, 0.9, 1.0))
			_popup(k, pa)
		"throw":
			_anim(pa, "throw")
		"handoff":
			_anim(pa, "give")
			_anim(pb, "take")
		"catch":
			_anim(pa, "reach")
			_popup(k, pa)
			_trash("catcher", pa, 0.25)
		"int":
			_anim(pa, "reach")
			_popup(k, pa)
			_trash("picker", pa, 1.0)
		"pbu":
			_anim(pa, "swat")
			_popup(k, pa)
			_trash("swatter", pa, 0.7)
			_bounce(_ball.position, 1.4)
		"drop":
			_anim(pa, "reach")
			_popup(k, pa)
			_bounce(_ball.position, 1.0)
			# the nearest defender lets him hear about it
			var best: PlaySim.P = null
			if pa != null:
				for q in sim.players:
					if q.side != pa.side and (best == null or q.pos.distance_to(pa.pos) < best.pos.distance_to(pa.pos)):
						best = q
			_trash("mocker", best, 0.8)
		"incomplete":
			if _ball_fx.is_empty():
				_bounce(world(a["pos"], 0.6), 0.9)
		"fumble":
			if pa != null:
				_anim(pa, "fall_back", _yaw_to(pa, pb) if pb != null else INF)
				_popup(k, pa)
				_sparks(world(pa.pos, 1.2), 12, Color(1.0, 0.75, 0.3))
				_ball_fx = {"p0": world(pa.pos, 1.2), "p1": world(sim.ball_pos, 0.15), "t0": _t, "hop": 2.2}
		"recover":
			_anim(pa, "dive")
			_popup(k, pa)
			_ball_fx = {}
		"pancake":
			if pb != null:
				_anim(pb, "fall_back", _yaw_to(pb, pa) if pa != null else INF)
				_popup(k, pb)
				_sparks(world(pb.pos, 1.0), 6, Color(1.0, 0.75, 0.3))
	moment.emit(a)


## The scorer celebrates (called when a play ends in a touchdown).
func touchdown(p: PlaySim.P) -> void:
	_anim(p, "spike")
	_trash("scorer", p, 1.0)
	_sparks(world(p.pos, 2.5), 24, Color(1.0, 0.85, 0.2))


func _bounce(from: Vector3, hop: float) -> void:
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.5, 3.5)
	_ball_fx = {"p0": from, "p1": Vector3(from.x, 0.15, from.z) + dir, "t0": _t, "hop": hop}


## A ball that flies to p1 and bounces twice more, lower each time.
func _ball_fx_pos() -> Vector3:
	var p0: Vector3 = _ball_fx["p0"]
	var p1: Vector3 = _ball_fx["p1"]
	var hop: float = _ball_fx["hop"]
	var u := (_t - float(_ball_fx["t0"])) / 0.55
	var flat := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	var segs := [[0.0, 1.0, 1.0], [1.0, 1.55, 0.35], [1.55, 1.85, 0.12]]
	for sg: Array in segs:
		if u < float(sg[1]):
			var f := (u - float(sg[0])) / (float(sg[1]) - float(sg[0]))
			var along := p0 + flat * minf(u, 1.0) + flat * 0.4 * maxf(u - 1.0, 0.0)
			var base_h := lerpf(p0.y, p1.y, f) if float(sg[0]) == 0.0 else p1.y
			return Vector3(along.x, base_h + hop * float(sg[2]) * 4.0 * f * (1.0 - f), along.z)
	var end := p0 + flat * 1.34
	return Vector3(end.x, p1.y, end.z)


func _popup(kind: String, p: PlaySim.P) -> void:
	if p == null or not POPUP.has(kind):
		return
	var lab := Label3D.new()
	lab.text = POPUP[kind][0]
	lab.font_size = 96
	lab.pixel_size = 0.017
	lab.outline_size = 22
	lab.modulate = POPUP[kind][1]
	lab.outline_modulate = Color(0.1, 0.0, 0.15)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.render_priority = 5
	# stack over any popup still rising
	var h := 3.6
	for n in _fx_nodes:
		if n["kind"] == "popup" and _t - float(n["t0"]) < 0.8:
			h = maxf(h, float(n["y0"]) + 1.9)
	lab.position = world(_cur.get(p.idx, p.pos), h)
	add_child(lab)
	_fx_nodes.append({"node": lab, "t0": _t, "life": 1.4, "kind": "popup", "y0": h})


func _trash(who: String, p: PlaySim.P, chance: float) -> void:
	if not talk or p == null or randf() > chance:
		return
	for n in _fx_nodes:
		if n["kind"] == "talk":
			return   # one talker at a time is plenty
	var lines: Array = TRASH[who]
	var line: String = lines[randi() % lines.size()]
	if randf() < 0.4:
		line = babble()   # sometimes the circuits just say whatever comes out
	_say_line(p, line)


func _say_line(p: PlaySim.P, line: String) -> void:
	var lab := Label3D.new()
	lab.text = "“%s”" % line
	lab.font_size = 60
	lab.pixel_size = 0.015
	lab.outline_size = 16
	lab.modulate = Color(1, 1, 1)
	lab.outline_modulate = (NEON[p.team] as Color).darkened(0.6)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.render_priority = 4
	lab.width = 900
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.position = world(_cur.get(p.idx, p.pos), 4.6)
	lab.visible = false
	add_child(lab)
	_fx_nodes.append({"node": lab, "t0": _t + 0.4, "life": 2.6, "kind": "talk", "y0": 4.6, "who": p.idx})
	trash_talk.emit(p.team, p.slot, line)


func _sparks(at: Vector3, n: int, c: Color) -> void:
	if not _spark_mat.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 4.0
		_spark_mat[c] = m
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.1)
		mi.mesh = bm
		mi.material_override = _spark_mat[c]
		mi.position = at
		add_child(mi)
		var v := Vector3(randf_range(-1, 1), randf_range(0.4, 1.6), randf_range(-1, 1)).normalized() * randf_range(3.0, 7.5)
		_fx_nodes.append({"node": mi, "t0": _t, "life": randf_range(0.35, 0.65), "kind": "spark", "vel": v})
	var fl := OmniLight3D.new()
	fl.light_color = c
	fl.light_energy = 3.0
	fl.omni_range = 5.0
	fl.position = at
	add_child(fl)
	_fx_nodes.append({"node": fl, "t0": _t, "life": 0.25, "kind": "flash"})


func _tick_fx(delta: float) -> void:
	var keep: Array = []
	for n: Dictionary in _fx_nodes:
		var node: Node3D = n["node"]
		var age := _t - float(n["t0"])
		var life: float = n["life"]
		if age > life:
			node.queue_free()
			continue
		keep.append(n)
		if age < 0.0:
			continue
		var u := age / life
		match String(n["kind"]):
			"popup":
				var lab := node as Label3D
				lab.position.y = float(n["y0"]) + 1.6 * u
				lab.scale = Vector3.ONE * (1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.15))
				lab.modulate.a = 1.0 if u < 0.6 else 1.0 - (u - 0.6) / 0.4
				lab.outline_modulate.a = lab.modulate.a
			"talk":
				var lab := node as Label3D
				lab.visible = true
				var p := _who(int(n["who"]))
				if p != null:
					var at := world(_cur.get(p.idx, p.pos))
					lab.position = Vector3(at.x, float(n["y0"]) + 0.3 * u, at.z)
				lab.modulate.a = 1.0 if u < 0.8 else 1.0 - (u - 0.8) / 0.2
				lab.outline_modulate.a = lab.modulate.a
			"spark":
				var v: Vector3 = n["vel"]
				v.y -= 18.0 * delta
				n["vel"] = v
				node.position += v * delta
				node.scale = Vector3.ONE * maxf(1.0 - u, 0.01)
			"flash":
				(node as OmniLight3D).light_energy = 3.0 * (1.0 - u)
	_fx_nodes = keep


## Pose a robot for this frame: the running stride, the arms, and whatever he is acting out.
func _pose(p: PlaySim.P, e: Dictionary, swing: float, delta: float) -> void:
	var root: Node3D = e["root"]
	var pitch := 1.45 if p.down else 0.0
	var roll := 0.0
	var hop := 0.0
	var lunge := 0.0
	var arm := [-swing * 0.8, swing * 0.8]
	if sim != null and p == sim.carrier and not p.down:
		arm[0] = -0.9   # ball tucked
	var leg_kick := 0.0
	var kind := String(e["anim"])
	var age := _t - float(e["anim_t"])
	var yaw: float = e["anim_yaw"]
	if kind != "" and (age > float(DUR.get(kind, 0.0)) or (kind.begins_with("fall") and age > 0.6 and not p.down)):
		kind = ""
		e["anim"] = ""
		e["fall_yaw"] = INF
	var rate := 14.0
	match kind:
		"dive":
			var u := clampf(age / 0.22, 0.0, 1.0)
			pitch = 1.4 * u
			lunge = 0.8 * u
			hop = sin(clampf(age / 0.3, 0.0, 1.0) * PI) * 0.35
			arm = [-1.9, -1.9]
			leg_kick = 0.5
			rate = 30.0
		"wrap":
			pitch = 0.75 if age < 0.4 else 1.1
			lunge = 0.4
			arm = [-1.5, -1.5]
			rate = 22.0
		"fall_back":
			pitch = -1.45
			arm = [-2.4, -2.2]
			rate = 16.0 if age < 0.4 else 8.0
		"fall_fwd":
			pitch = 1.45
			arm = [-1.6, -1.2]
			rate = 10.0
		"stumble":
			var f := 1.0 - age / 0.6
			roll = sin(age * 26.0) * 0.4 * f
			pitch = 0.35 * f
			arm = [-1.2 + sin(age * 20.0), -1.2 - sin(age * 20.0)]
			rate = 30.0
		"shrug":
			var f := 1.0 - age / 0.5
			roll = sin(age * 22.0) * 0.3 * f
			hop = 0.15 * f
			rate = 30.0
		"juke":
			var u := age / 0.4
			hop = sin(u * PI) * 0.45
			roll = sin(u * TAU) * 0.55
			rate = 30.0
		"stiff":
			arm[1] = -1.65
			pitch = -0.12
			rate = 30.0
		"throw":
			var u := clampf(age / 0.32, 0.0, 1.0)
			arm[1] = lerpf(-3.6, -1.1, u * u)
			arm[0] = -1.0
			pitch = 0.25 * u
			rate = 40.0
		"give":
			arm = [-1.3, -1.3]
		"take":
			arm = [-1.0, -0.9]
		"reach":
			arm = [-2.95, -2.95]
			hop = sin(clampf(age / 0.45, 0.0, 1.0) * PI) * 0.4
			rate = 24.0
		"swat":
			arm = [-1.0, -3.1]
			hop = sin(clampf(age / 0.45, 0.0, 1.0) * PI) * 0.5
			rate = 30.0
		"spike":
			# arms up, a little jump for joy
			var j := fmod(age, 0.45) / 0.45
			arm = [-3.0, -3.0]
			hop = sin(j * PI) * 0.5
			pitch = 0.0
			rate = 24.0
	if kind.begins_with("fall") and float(e["fall_yaw"]) == INF:
		e["fall_yaw"] = yaw if yaw != INF else root.rotation.y
	if kind.begins_with("fall"):
		yaw = float(e["fall_yaw"])
	if kind != "" and yaw != INF:
		root.rotation.y = yaw
	elif p.down and float(e["fall_yaw"]) != INF:
		root.rotation.y = float(e["fall_yaw"])
	var k := minf(delta * rate, 1.0)
	e["tilt"] = lerpf(float(e["tilt"]), pitch, k)
	e["roll"] = lerpf(float(e["roll"]), roll, k)
	e["hop"] = lerpf(float(e["hop"]), hop, k)
	e["lunge"] = lerpf(float(e["lunge"]), lunge, k)
	var cur_arm: Array = e["arm"]
	cur_arm[0] = lerpf(float(cur_arm[0]), float(arm[0]), k)
	cur_arm[1] = lerpf(float(cur_arm[1]), float(arm[1]), k)
	root.rotation.x = float(e["tilt"])
	root.rotation.z = float(e["roll"])
	(e["body"] as Node3D).position = Vector3(0, float(e["hop"]), float(e["lunge"]))
	var arms: Array = e["arms"]
	(arms[0] as Node3D).rotation.x = float(cur_arm[0])
	(arms[1] as Node3D).rotation.x = float(cur_arm[1])
	var legs: Array = e["legs"]
	(legs[0] as Node3D).rotation.x = swing + leg_kick
	(legs[1] as Node3D).rotation.x = -swing + leg_kick



## ---- robot babble: nonsense sentences out of random words --------------------------------------

const BAB_ADJ := ["rusty", "turbo", "quantum", "greasy", "binary", "chrome", "soggy", "electric", "wobbly",
	"magnetic", "crunchy", "glitchy", "nuclear", "squeaky", "hydraulic", "moist", "laser", "obsolete", "fuzzy", "titanium"]
const BAB_NOUN := ["toaster", "sprocket", "firmware", "gravy", "capacitor", "hubcap", "waffle iron", "flux valve",
	"cheese grater", "motherboard", "lug nut", "spatula", "dial tone", "carburetor", "teapot", "gearbox",
	"floppy disk", "pancake", "fax machine", "bolt", "sandwich", "transistor", "vacuum", "doorknob"]
const BAB_VERB := ["defragment", "lubricate", "microwave", "reboot", "calibrate", "vaporize", "sprinkle",
	"download", "polish", "compress", "magnetize", "unscrew", "toast", "overclock", "recycle", "buffer"]
const BAB_EXCL := ["BEEP BOOP", "ERROR", "WHIRRR", "BZZT", "AFFIRMATIVE", "CLANK", "DING", "KZZZT", "BLORP", "SYSTEM OK"]
const BAB_FORMS := [
	"{E}! I will {v} your {a} {n}!",
	"My {n} is {a} and your {n2} is {a2}.",
	"{E}. {V} the {n}. {V2} the {n2}.",
	"You smell like a {a} {n}.",
	"Error: {a} {n} not found. {E}.",
	"Mother always said: never {v} a {a} {n}.",
	"I am {pct} percent {n}.",
	"Warning: {pct} {ns} detected in the {a} zone.",
	"{E}. Please insert {pct} {ns}.",
	"Do not {v} me, you {a} {n}!",
	"{E}! {E2}! Who left this {n} in my {n2}?",
	"Today I {v} the {n}. Tomorrow, the {a} {n2}.",
	"Initiating {a} {n} protocol.",
	"Your {n} has been {v}ed. {E}.",
]


static func babble() -> String:
	var f: String = BAB_FORMS[randi() % BAB_FORMS.size()]
	var pick := func(a: Array) -> String: return a[randi() % a.size()]
	var v: String = pick.call(BAB_VERB)
	var v2: String = pick.call(BAB_VERB)
	f = f.replace("{E2}", pick.call(BAB_EXCL)).replace("{E}", pick.call(BAB_EXCL))
	f = f.replace("{V2}", v2.capitalize()).replace("{V}", v.capitalize())
	f = f.replace("{v}ed", (v.trim_suffix("e") + "ed")).replace("{v}", v)
	f = f.replace("{a2}", pick.call(BAB_ADJ)).replace("{a}", pick.call(BAB_ADJ))
	f = f.replace("{n2}", pick.call(BAB_NOUN)).replace("{n}", pick.call(BAB_NOUN))
	f = f.replace("{pct}", str(randi_range(3, 99)))
	var pl: String = pick.call(BAB_NOUN)
	if pl.ends_with("x") or pl.ends_with("s") or pl.ends_with("ch") or pl.ends_with("sh"):
		pl += "es"
	elif pl.ends_with("y") and not pl.ends_with("ey"):
		pl = pl.trim_suffix("y") + "ies"
	else:
		pl += "s"
	f = f.replace("{ns}", pl)
	return f


## A random robot on the field says something that makes no sense (unless someone else is talking).
func babble_now() -> void:
	if sim == null or not talk:
		return
	for n in _fx_nodes:
		if n["kind"] == "talk":
			return
	var p: PlaySim.P = sim.players[randi() % sim.players.size()]
	_say_line(p, babble())
