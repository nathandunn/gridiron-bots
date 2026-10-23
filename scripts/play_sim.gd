class_name PlaySim
extends RefCounted
## One play, snap to whistle, in yards and seconds. No nodes: the game runs it headless or the
## view draws it.
##
## Frame: x across the field (absolute, sidelines at +-SIDELINE), y downfield from the line of
## scrimmage, the offense attacking +y. The offense scores at y >= to_goal, is tackled for a
## safety at y <= -own_goal.
##
## Every player is driven by his position brain (rules read ten times a second); whatever the
## brain leaves undecided is played by the engine's default for his assignment, reading the
## brain's dials.

const DT := 1.0 / 30.0
const SIDELINE := 26.67
const BRAIN_EVERY := 0.1
const PLAY_CAP := 14.0
const REACH := 1.3          # catch radius around where the ball comes down
const TACKLE_R := 1.35
const ENGAGE_R := 1.1
const BODY_R := 0.42

## Fixed by position: the game is about the brains, so every team has the same bodies.
const BODY := {
	"QB": {"speed": 7.4, "accel": 7.0, "power": 0.45, "hands": 0.62, "agility": 0.55, "tackle": 0.3},
	"RB": {"speed": 8.9, "accel": 9.5, "power": 0.62, "hands": 0.66, "agility": 0.85, "tackle": 0.3},
	"WR": {"speed": 9.3, "accel": 9.0, "power": 0.36, "hands": 0.84, "agility": 0.8, "tackle": 0.25},
	"TE": {"speed": 8.2, "accel": 8.0, "power": 0.72, "hands": 0.74, "agility": 0.5, "tackle": 0.35},
	"OL": {"speed": 6.4, "accel": 8.0, "power": 0.86, "hands": 0.2, "agility": 0.3, "tackle": 0.3},
	"DL": {"speed": 7.0, "accel": 7.0, "power": 0.82, "hands": 0.22, "agility": 0.46, "tackle": 0.72},
	"LB": {"speed": 8.1, "accel": 8.0, "power": 0.7, "hands": 0.45, "agility": 0.6, "tackle": 0.8},
	"CB": {"speed": 9.2, "accel": 9.0, "power": 0.4, "hands": 0.55, "agility": 0.84, "tackle": 0.58},
	"S": {"speed": 8.8, "accel": 8.5, "power": 0.55, "hands": 0.56, "agility": 0.7, "tackle": 0.7},
}
## Global tuning knobs (set from the command line with --k=name:value,name:value).
static var K := {"tackle": 0.85, "evade": 0.5, "carry_speed": 0.97, "sight": 1.0, "shed": 1.0, "throw_err": 1.8, "catch": 1.0, "pursuit": 1.05}
const QB_ARM := 0.9
const QB_ACC := 0.8

## Where each slot lines up, x from the ball (offense) and y from the line.
const OFFENSE_SPOTS := {
	"C": Vector2(0, -0.7), "LG": Vector2(-1.35, -0.8), "RG": Vector2(1.35, -0.8),
	"LT": Vector2(-2.7, -0.9), "RT": Vector2(2.7, -0.9), "TE": Vector2(4.1, -1.0),
	"WR1": Vector2(-19.0, -0.8), "WR2": Vector2(18.0, -0.8), "WR3": Vector2(-9.0, -1.4),
}
const DEFENSE_SPOTS := {
	"DE1": Vector2(-4.0, 1.0), "DT1": Vector2(-1.1, 1.0), "DT2": Vector2(1.1, 1.0), "DE2": Vector2(4.0, 1.0),
	"OLB1": Vector2(-5.5, 4.5), "MLB": Vector2(0.0, 4.8), "OLB2": Vector2(5.0, 4.5),
	"CB1": Vector2(-19.0, 6.0), "CB2": Vector2(18.0, 6.0), "FS": Vector2(-8.0, 12.0), "SS": Vector2(8.0, 12.0),
}
const ZONE_SPOT := {
	"deep third left": [Vector2(-16, 15), 9.0], "deep third middle": [Vector2(0, 16), 9.0], "deep third right": [Vector2(16, 15), 9.0],
	"deep half left": [Vector2(-11, 15), 11.0], "deep half right": [Vector2(11, 15), 11.0], "deep middle": [Vector2(0, 16), 12.0],
	"flat left": [Vector2(-15, 4), 7.0], "flat right": [Vector2(15, 4), 7.0],
	"hook left": [Vector2(-6, 7), 6.0], "hook middle": [Vector2(0, 8), 6.0], "hook right": [Vector2(6, 7), 6.0],
	"curl left": [Vector2(-11, 9), 6.5], "curl right": [Vector2(11, 9), 6.5], "robber": [Vector2(0, 10), 7.0],
}
const DEEP_ZONES := ["deep third left", "deep third middle", "deep third right", "deep half left", "deep half right", "deep middle"]
const GAP_X := {"inside left": -1.8, "inside right": 1.8, "middle": 0.0, "outside left": -4.8, "outside right": 4.8,
	"sweep left": -7.5, "sweep right": 7.5, "draw": 0.0, "sneak": 0.0}


class P:
	extends RefCounted
	var slot := ""
	var group := ""
	var side := 0          # 0 offense, 1 defense
	var team := 0          # 0 red, 1 blue
	var idx := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var face := Vector2(0, 1)
	var hist: Array = []   # recent positions, newest last (for reaction lag)
	var body := {}
	var brain: Brain = null
	var dial := {}
	var mem := {}
	var assign := {}
	var intent := "assignment"
	var intent_t := 0.0
	var manner := {}       # wrap_up, hit_hard, strip, protect, secure, high_point, lower_shoulder, stiff_arm -> true
	var phase := ""
	var next_think := 0.0
	var last_rule := -1
	# blocking
	var block_target: P = null
	var engaged: P = null          # who I am locked with
	var blockers: Array = []       # (defender) who is on me
	var shed_from: Dictionary = {} # blocker idx -> until
	var stumble_until := 0.0
	var down := false
	var down_until := 0.0
	var tackle_cd := 0.0
	var juke_until := 0.0
	var juke_cd := 0.0
	var stiff_until := 0.0
	var stiff_cd := 0.0
	var slow_until := 0.0
	# routes
	var route: Array = []          # waypoints (absolute)
	var wp := 0
	var route_stop := false
	var route_done := false
	var released := true
	var heading := Vector2(0, 1)
	var steer_t := 0.0
	var cover: P = null
	var zone_anchor := Vector2.ZERO
	var zone_r := 8.0
	var bitten_until := 0.0
	var spd_scale := 1.0

	func spd() -> float:
		return float(body["speed"]) * spd_scale

	func d(k: String) -> float:
		return float(dial.get(k, 0.5))


var rng: RandomNumberGenerator
var players: Array = []
var off: Array = []
var dfn: Array = []
var by_slot := {}            # "o:QB" / "d:CB1" -> P
var t := 0.0
var snapped := false
var over := false
var result := {}
var events: Array = []       # {t, text}
## What happened, moment by moment, for the view to act out: {t, kind, a, b, pos}. a and b are
## player idx (or -1), pos a play-frame point. Kinds: throw, handoff, catch, drop, pbu, int,
## tackle, sack, big_hit, dive_tackle, miss, dive_miss, juke, stiff_arm, fumble, recover,
## incomplete, pancake, shed.
var actions: Array = []


func _fx(kind: String, a: P = null, b: P = null, pos := Vector2.INF) -> void:
	var at := pos
	if at == Vector2.INF:
		at = b.pos if b != null else (a.pos if a != null else ball_pos)
	actions.append({"t": t, "kind": kind, "a": a.idx if a != null else -1, "b": b.idx if b != null else -1, "pos": at})

var off_play: Play
var def_play: Play
var ctx := {}                # down, to_go, yl, score_diff (offense), quarter, clock, ball_x
var to_goal := 50.0
var own_goal := 50.0
var ball_x := 0.0
var sticks := 10.0

# the ball
var ball_state := "presnap"  # presnap / held / air / loose / dead
var carrier: P = null
var ball_pos := Vector2.ZERO
var ball_h := 1.0
var air := {}                # from, to, t0, T, target, thrower, lob
var loose_until := 0.0
var thrown := false
var handed := false
var handoff_t := -1.0
var crossed_los := false
var scrambling := false
var qb_runner := false
var reads: Array = []
var read_idx := 0
var read_t := 0.0
var pass_play := true
var carry_slot := ""
var air_target: P = null
var stat := {}               # for the box score
var tally := {}              # "team:brain" -> {line: count}


func setup(off_team: Dictionary, def_team: Dictionary, op: Play, dp: Play, c: Dictionary, r: RandomNumberGenerator) -> void:
	rng = r
	off_play = op
	def_play = dp
	ctx = c
	var yl: float = c["yl"]
	to_goal = 100.0 - yl
	own_goal = yl
	ball_x = c.get("ball_x", 0.0)
	sticks = minf(float(c["to_go"]), to_goal)
	pass_play = op.kind != "run"
	carry_slot = op.carrier_slot()
	var i := 0
	for s in Play.OFFENSE_SLOTS:
		var p := _make(s, 0, off_team, op.assigns.get(s, {"kind": "block"}), i)
		off.append(p)
		players.append(p)
		by_slot["o:" + s] = p
		i += 1
	for s in Play.DEFENSE_SLOTS:
		var p := _make(s, 1, def_team, dp.assigns.get(s, {"kind": "zone", "zone": "hook middle"}), i)
		dfn.append(p)
		players.append(p)
		by_slot["d:" + s] = p
		i += 1
	_line_up()
	ball_pos = Vector2(ball_x, 0)
	ball_h = 0.3


func _make(s: String, side: int, team: Dictionary, a: Dictionary, i: int) -> P:
	var p := P.new()
	p.slot = s
	p.group = Play.SLOT_GROUP[s]
	p.side = side
	p.team = int(team["index"])
	p.idx = i
	p.body = BODY[p.group].duplicate()
	p.spd_scale = 1.0 + (rng.randf() - 0.5) * 0.06
	p.brain = (team["brains"] as Dictionary).get(s, null)
	if p.brain != null:
		p.dial = p.brain.dials
	p.assign = a
	p.next_think = 0.3 + (i % 5) * 0.02
	return p


func _line_up() -> void:
	var gun := off_play.formation != "under center"
	for p: P in off:
		var spot := Vector2.ZERO
		match p.slot:
			"QB":
				spot = Vector2(0, -5.0) if gun else Vector2(0, -1.3)
			"RB":
				if off_play.formation == "empty":
					spot = Vector2(8.5, -1.2)
				elif off_play.formation == "pistol":
					spot = Vector2(0, -7.5)
				elif gun:
					spot = Vector2(1.6, -5.2)
				else:
					spot = Vector2(0, -7.0)
			_:
				spot = OFFENSE_SPOTS[p.slot]
		if off_play.align.has(p.slot):
			spot = off_play.align[p.slot]
			spot.y = minf(spot.y, -0.6)
		p.pos = Vector2(ball_x + spot.x, spot.y)
		if p.group == "WR" or p.slot == "RB" and off_play.formation == "empty":
			p.pos.x = clampf(p.pos.x, -SIDELINE + 2.0, SIDELINE - 2.0)
		p.face = Vector2(0, 1)
	var press := def_play.front == "press"
	var goal_line := def_play.front == "goal line" or to_goal < 8.0
	for p: P in dfn:
		var spot: Vector2 = DEFENSE_SPOTS[p.slot]
		var at := Vector2(ball_x + spot.x, spot.y)
		if p.group == "CB":
			var wr: P = by_slot["o:WR1" if p.slot == "CB1" else "o:WR2"]
			at = Vector2(wr.pos.x + (1.0 if wr.pos.x < ball_x else -1.0), 1.5 if press else 6.5)
		if p.group == "S":
			at.y = minf(at.y, maxf(to_goal - 1.0, 4.0))
		if p.group == "LB" and goal_line:
			at.y = 2.5
		at.y = minf(at.y, maxf(to_goal + 0.5, 1.0)) if p.group != "DL" else at.y
		if def_play.align.has(p.slot):
			var al: Vector2 = def_play.align[p.slot]
			at = Vector2(ball_x + al.x, clampf(al.y, 0.9, maxf(to_goal + 0.5, 1.0)))
		p.pos = at
		p.face = Vector2(0, -1)
	for p: P in players:
		p.pos.x = clampf(p.pos.x, -SIDELINE + 0.8, SIDELINE - 0.8)
		p.hist = [p.pos]
	# coverage targets
	for p: P in dfn:
		match String(p.assign.get("kind", "")):
			"man":
				var on: String = p.assign.get("on", "")
				if on == "":
					on = {"CB1": "WR1", "CB2": "WR2", "SS": "TE", "FS": "WR3", "OLB1": "WR3", "MLB": "RB", "OLB2": "TE"}.get(p.slot, "RB")
				p.cover = by_slot["o:" + on]
			"zone":
				if p.assign.has("at"):
					var at2: Vector2 = p.assign["at"]
					p.zone_anchor = Vector2(clampf(ball_x + at2.x, -SIDELINE + 2, SIDELINE - 2), clampf(minf(at2.y, to_goal + 2.0), 1.0, 40.0))
					p.zone_r = float(p.assign.get("size", 7.0))
				else:
					var z: Array = ZONE_SPOT[p.assign["zone"]]
					var a: Vector2 = z[0]
					p.zone_anchor = Vector2(clampf(ball_x * 0.5 + a.x, -SIDELINE + 3, SIDELINE - 3), minf(a.y, maxf(to_goal + 2.0, 3.0)))
					p.zone_r = z[1]
	# line up over the man you have, or toward your zone
	for p: P in dfn:
		if p.group == "DL" or def_play.align.has(p.slot):
			continue
		if p.cover != null and p.group == "CB" and not (p.cover.slot == ("WR1" if p.slot == "CB1" else "WR2")):
			# a corner on someone other than his usual receiver lines up over that man
			var mc := p.cover
			p.pos = Vector2(mc.pos.x + signf(ball_x - mc.pos.x) * 0.8, minf(1.5 if press else 6.0, maxf(to_goal - 0.5, 1.0)))
		elif p.cover != null and p.group != "CB":
			var m := p.cover
			var inside := signf(ball_x - m.pos.x) if absf(m.pos.x - ball_x) > 1.0 else 0.0
			var depth := 4.5 if p.group == "LB" else 6.0
			if m.slot == "RB":
				p.pos = Vector2(m.pos.x * 0.3 + ball_x * 0.7, 4.5)
			else:
				p.pos = Vector2(m.pos.x + inside * 1.0, minf(2.0 if press else depth, maxf(to_goal - 0.5, 1.0)))
		elif String(p.assign.get("kind", "")) == "zone" and p.group in ["S", "CB"]:
			p.pos = p.pos.lerp(Vector2(p.zone_anchor.x, minf(p.zone_anchor.y - 3.0, maxf(to_goal, 2.0))), 0.6)
		p.pos.x = clampf(p.pos.x, -SIDELINE + 0.8, SIDELINE - 0.8)
		p.hist = [p.pos]
	for p: P in off:
		if String(p.assign.get("kind", "")) == "route":
			_build_route(p)
	var qb: P = by_slot["o:QB"]
	if String(qb.assign.get("kind", "")) == "pass":
		reads = qb.assign["reads"]


## Route waypoints, absolute. "Out" means toward the near sideline.
## Where a run is aimed (yards across from the ball), for a named gap or "run at X".
static func gap_x_of(a: Dictionary) -> float:
	if a.has("gap_x"):
		return float(a["gap_x"])
	return float(GAP_X.get(String(a.get("gap", "middle")), 0.0))


static func gap_wide(a: Dictionary) -> bool:
	if a.has("gap_x"):
		return absf(float(a["gap_x"])) > 4.0
	var g := String(a.get("gap", ""))
	return g.begins_with("sweep") or g.begins_with("outside")


func _build_route(p: P) -> void:
	var o := 1.0 if p.pos.x >= ball_x - 0.5 else -1.0      # outside direction
	if p.slot == "RB" and absf(p.pos.x - ball_x) < 2.0:
		o = 1.0 if p.pos.x >= ball_x else -1.0
	var name: String = p.assign["route"]
	var dep: float = p.assign.get("depth", -1.0)
	var s := p.pos
	var w: Array = []
	var stop := false
	var dp := func(def: float) -> float: return dep if dep > 0.0 else def
	match name:
		"path":
			for q in p.assign["path"]:
				w.append(s + (q as Vector2))
			stop = bool(p.assign.get("stop", false))
		"go", "fade":
			w = [s + Vector2(o * (1.5 if name == "fade" else 0.3), 12), s + Vector2(o * (3.0 if name == "fade" else 0.5), 45)]
		"seam":
			w = [s + Vector2(-o * 1.0, 10), s + Vector2(-o * 1.5, 45)]
		"slant":
			var dd: float = dp.call(3.0)
			w = [s + Vector2(0, dd), s + Vector2(-o * 7, dd + 6), s + Vector2(-o * 18, dd + 14)]
		"out":
			var dd: float = dp.call(8.0)
			w = [s + Vector2(0, dd), s + Vector2(o * 4, dd - 0.5), s + Vector2(o * 9, dd - 0.8)]
			stop = true
		"in", "dig":
			var dd: float = dp.call(10.0 if name == "dig" else 7.0)
			w = [s + Vector2(0, dd), s + Vector2(-o * 4, dd), s + Vector2(-o * 30, dd)]
		"post":
			var dd: float = dp.call(10.0)
			w = [s + Vector2(0, dd), s + Vector2(-o * 7, dd + 9), s + Vector2(-o * 14, dd + 30)]
		"corner":
			var dd: float = dp.call(10.0)
			w = [s + Vector2(0, dd), s + Vector2(o * 7, dd + 8), s + Vector2(o * 14, dd + 24)]
		"hitch", "stop":
			var dd: float = dp.call(5.0)
			w = [s + Vector2(0, dd + 0.6), s + Vector2(-o * 0.3, dd)]
			stop = true
		"curl":
			var dd: float = dp.call(10.0)
			w = [s + Vector2(0, dd + 1.0), s + Vector2(-o * 1.2, dd - 1.0)]
			stop = true
		"comeback":
			var dd: float = dp.call(13.0)
			w = [s + Vector2(0, dd + 1.0), s + Vector2(o * 2.0, dd - 2.0)]
			stop = true
		"flat":
			w = [s + Vector2(o * 3, 1.5), s + Vector2(o * 7, 2.5), s + Vector2(o * 10, 3.0)]
			stop = true
		"swing":
			w = [s + Vector2(o * 3, -1.0), s + Vector2(o * 7, 0.5), s + Vector2(o * 9, 2.5)]
			stop = true
		"wheel":
			w = [s + Vector2(o * 4, 0.5), s + Vector2(o * 8, 4.0), s + Vector2(o * 9, 40.0)]
		"drag", "cross":
			var dd: float = dp.call(2.5 if name == "drag" else 8.0)
			w = [s + Vector2(-o * 1.5, dd), s + Vector2(-o * 30, dd + 1.0)]
		"angle":
			w = [s + Vector2(o * 3, 2.0), s + Vector2(-o * 1, 5.0), s + Vector2(-o * 12, 7.0)]
		"screen":
			w = [s + Vector2(o * 3.0, -2.0)]
			stop = true
	for k in w.size():
		var q: Vector2 = w[k]
		w[k] = Vector2(clampf(q.x, -SIDELINE + 0.6, SIDELINE - 0.6), q.y)
	p.route = w
	p.wp = 0
	p.route_stop = stop
	p.released = not bool(p.assign.get("chip", false))


## ---- the loop --------------------------------------------------------------------------------

func step() -> void:
	if over:
		return
	t += DT
	if not snapped and t >= 0.3:
		_snap()
	if snapped:
		for p: P in players:
			if t >= p.next_think:
				p.next_think = t + BRAIN_EVERY
				_think(p)
		_assign_blocks()
		for p: P in players:
			_drive(p)
		_resolve_blocks()
		_move_all()
		_ball()
		_contacts()
		_check_end()
	if t > PLAY_CAP and not over:
		_end("whistle", carrier.pos if carrier != null else ball_pos)


func run_to_end() -> Dictionary:
	var guard := 0
	while not over and guard < 2000:
		step()
		guard += 1
	return result


func _snap() -> void:
	snapped = true
	var qb: P = by_slot["o:QB"]
	carrier = qb
	ball_state = "held"
	_say("snap")
	# play action / handoff bookkeeping
	if String(qb.assign.get("kind", "")) == "carry":
		carry_slot = "QB"
	# press: a corner on top of his man jams the release
	for d: P in dfn:
		if d.cover != null and d.pos.distance_to(d.cover.pos) < 3.0 and def_play.front == "press":
			var m := d.cover
			var win := float(d.body["power"]) * 0.6 + d.d("aggression") * 0.5 - float(m.body["agility"]) * 0.5 - float(m.body["power"]) * 0.3
			m.mem["_jam_until"] = t + clampf(0.15 + win, 0.1, 0.7)


## ---- the brain -------------------------------------------------------------------------------

func _think(p: P) -> void:
	if p.brain == null or p.down:
		p.intent = "assignment"
		return
	p.intent = "assignment"
	var key := "%d:%s" % [p.team, p.brain.name]
	if not tally.has(key):
		tally[key] = {}
	p.last_rule = Dsl.run(p.brain.rules, _sense.bind(p), _act.bind(p), p.mem, t, Brain.MODIFIERS, tally[key])


func _sense(id: String, a: Array, p: P) -> bool:
	match id:
		"always": return true
		"chance": return rng.randf() < 1.0 - pow(1.0 - clampf(float(a[0]), 0.0, 0.999), BRAIN_EVERY)
		"have_ball": return carrier == p and ball_state == "held"
		"mate_ball": return carrier != null and carrier.side == p.side and carrier != p and ball_state == "held" and not _qb_holding()
		"enemy_ball": return carrier != null and carrier.side != p.side and ball_state == "held" and not _qb_holding()
		"ball_air": return ball_state == "air"
		"thrown_to_me": return ball_state == "air" and air_target == p
		"thrown_to_my_man": return ball_state == "air" and p.cover != null and air_target == p.cover
		"ball_my_way": return ball_state == "air" and p.pos.distance_to(air["to"]) < 8.0
		"ball_loose": return ball_state == "loose"
		"before_throw": return ball_state == "held" and carrier != null and carrier.slot == "QB" and carrier.side == 0 and not thrown and not handed and not qb_runner and String(carrier.assign.get("kind", "")) == "pass"
		"after_handoff": return handed
		"run_play": return not pass_play
		"pass_play": return pass_play
		"they_run": return p.side == 1 and _run_read(p)
		"they_pass": return p.side == 1 and (thrown or (pass_play and t > 1.2 and not handed))
		"qb_scrambling": return scrambling or qb_runner
		"assignment_is": return String(p.assign.get("kind", "")) == String(a[0]) or (a[0] == "zone" and p.assign.get("kind", "") == "zone")
		"position_is": return p.slot.to_lower() == String(a[0]) or p.group.to_lower() == String(a[0])
		"time_over": return t - 0.3 > float(a[0])
		"time_under": return t - 0.3 < float(a[0])
		"drop_done": return bool(p.mem.get("_drop_done", false))
		"route_done": return p.route_done
		"enemy_within": return _nearest_enemy_d(p, false) < float(a[0])
		"rusher_within": return _rusher_d(p) < float(a[0])
		"pressure": return _rusher_d(p) < 2.2
		"pocket_collapsing": return _rushers_within(p, 3.0) >= 2
		"clean_pocket": return _rusher_d(p) > 4.0
		"blocker_ahead": return _blocker_ahead(p) != null
		"open_field": return _open_field(p)
		"crowd_ahead": return _crowd_ahead(p) >= 3
		"one_to_beat": return _crowd_ahead(p) == 1
		"sideline_within": return SIDELINE - absf(p.pos.x) < float(a[0])
		"engaged": return p.engaged != null
		"free": return p.engaged == null
		"carrier_within": return carrier != null and ball_state == "held" and carrier.side != p.side and p.pos.distance_to(carrier.pos) < float(a[0])
		"carrier_past": return carrier != null and carrier.side != p.side and _past(carrier, p)
		"carrier_outside": return carrier != null and absf(carrier.pos.x - ball_x) > absf(p.pos.x - ball_x) + 1.0
		"qb_within": return p.pos.distance_to((by_slot["o:QB"] as P).pos) < float(a[0])
		"my_man_open": return p.cover != null and _sep(p.cover) > 2.5
		"my_man_beyond": return p.cover != null and p.pos.distance_to(p.cover.pos) > float(a[0])
		"my_man_within": return p.cover != null and p.pos.distance_to(p.cover.pos) < float(a[0])
		"receiver_in_zone": return _zone_threat(p) != null
		"deep_threat": return _deepest_receiver_y() > p.pos.y - 3.0
		"target_open": return _best_read(p, 1.6 - 1.0 * p.d("risk"))["r"] != null
		"deep_open": return _best_read(p, 1.4 - 0.8 * p.d("risk"), 15.0)["r"] != null
		"first_open": return not reads.is_empty() and _open(p, by_slot["o:" + reads[0]]) > 1.6 - 1.0 * p.d("risk")
		"checkdown_open": return _checkdown(p) != null
		"slot_open":
			var k := "o:" + String(a[0]).to_upper()
			return by_slot.has(k) and _open(p, by_slot[k]) > 1.6 - 1.0 * p.d("risk")
		"open_by": return _best_read(p, float(a[0]))["r"] != null
		"none_open": return _best_read(p, 1.0)["r"] == null
		"i_am_open": return _sep(p) > 2.5
		"past_los": return _dirpos(p) > 0.0
		"behind_los": return _dirpos(p) <= 0.0
		"past_sticks": return p.pos.y >= sticks
		"short_sticks": return p.pos.y < sticks
		"sticks_within": return absf(sticks - p.pos.y) < float(a[0])
		"goal_within": return (to_goal - p.pos.y if p.side == 0 else p.pos.y + own_goal) < float(a[0])
		"red_zone": return to_goal < 20.0
		"down_is": return int(ctx["down"]) == int(a[0])
		"third_down": return int(ctx["down"]) == 3
		"fourth_down": return int(ctx["down"]) == 4
		"to_go_over": return float(ctx["to_go"]) > float(a[0])
		"to_go_under": return float(ctx["to_go"]) < float(a[0])
		"winning": return _diff(p) > 0
		"losing": return _diff(p) < 0
		"trailing_by": return -_diff(p) > int(a[0])
		"leading_by": return _diff(p) > int(a[0])
		"clock_under": return float(ctx.get("clock", 900)) < float(a[0])
		"quarter_is": return int(ctx.get("quarter", 1)) == int(a[0])
		"late_game": return int(ctx.get("quarter", 1)) == 4 and float(ctx.get("clock", 900)) < 240.0
		"phase_is": return p.phase == String(a[0])
	return false


func _act(id: String, a: Array, p: P) -> bool:
	var qb_live := ball_state == "held" and carrier == p and p.slot == "QB" and not thrown and not handed and _dirpos(p) <= 0.5 and String(p.assign.get("kind", "")) == "pass" and not qb_runner
	var ball_mine := ball_state == "held" and carrier == p
	match id:
		"assignment":
			p.intent = "assignment"
			return true
		"hold":
			p.intent = "hold"
			return true
		"set_phase":
			p.phase = String(a[0])
			return true
		# --- QB
		"throw_open":
			if not qb_live:
				return false
			var b := _best_read(p, 1.6 - 1.0 * p.d("risk"))
			return b["r"] != null and _throw(p, b["r"])
		"throw_first":
			if not qb_live or reads.is_empty():
				return false
			return _throw(p, by_slot["o:" + reads[0]])
		"throw_best":
			if not qb_live:
				return false
			var b := _best_read(p, -99.0)
			return b["r"] != null and _throw(p, b["r"])
		"throw_deep":
			if not qb_live:
				return false
			var b := _best_read(p, 0.6 - 0.9 * p.d("risk"), 15.0)
			return b["r"] != null and _throw(p, b["r"])
		"throw_short":
			if not qb_live:
				return false
			var b := _best_read(p, 1.2 - 0.8 * p.d("risk"), -99.0, 8.0)
			return b["r"] != null and _throw(p, b["r"])
		"throw_checkdown":
			if not qb_live:
				return false
			var r := _checkdown(p)
			return r != null and _throw(p, r)
		"throw_to":
			if not qb_live:
				return false
			var k := "o:" + String(a[0]).to_upper()
			return by_slot.has(k) and k != "o:QB" and _throw(p, by_slot[k])
		"throw_away":
			if not qb_live:
				return false
			_throw_away(p)
			return true
		"scramble":
			if not qb_live:
				return false
			scrambling = true
			p.intent = "scramble"
			return true
		"tuck_run":
			if not (ball_mine and p.slot == "QB" and not thrown and not handed):
				return false
			qb_runner = true
			p.intent = "daylight"
			_say("QB keeps it")
			return true
		"step_up":
			if not qb_live:
				return false
			p.intent = "step_up"
			return true
		"take_sack":
			if not qb_live:
				return false
			p.intent = "hold"
			return true
		"next_read":
			if not qb_live:
				return false
			read_idx = (read_idx + 1) % maxi(reads.size(), 1)
			read_t = t
			return true
		# --- ball carrier
		"daylight", "follow_blocker", "cut_upfield", "bounce", "reverse_field", "out_of_bounds", "go_down", "pylon":
			if not _is_runner(p):
				return false
			if id == "follow_blocker" and _blocker_ahead(p) == null:
				return false
			p.intent = id
			return true
		"juke":
			if not _is_runner(p) or t < p.juke_cd or _nearest_enemy_d(p, false) > 3.0:
				return false
			p.juke_until = t + 0.4
			p.juke_cd = t + 1.6
			_fx("juke", p, _nearest_enemy(p, false))
			p.slow_until = maxf(p.slow_until, t + 0.3)   # a juke costs a step
			var e := _nearest_enemy(p, false)
			if e != null:
				var side := signf(p.pos.x - e.pos.x)
				if side == 0.0:
					side = 1.0 if rng.randf() < 0.5 else -1.0
				p.vel += Vector2(side * 4.0 * float(p.body["agility"]), 0)
			return true
		"stiff_arm":
			if not _is_runner(p) or t < p.stiff_cd or _nearest_enemy_d(p, false) > 2.0:
				return false
			p.stiff_until = t + 0.5
			p.stiff_cd = t + 1.0
			_fx("stiff_arm", p, _nearest_enemy(p, false))
			return true
		"lower_shoulder":
			if not _is_runner(p):
				return false
			p.manner["lower_shoulder"] = true
			return true
		"protect":
			if not ball_mine:
				return false
			p.manner["protect"] = true
			return true
		# --- receivers
		"break_off":
			if p.side != 0 or ball_mine or String(p.assign.get("kind", "")) != "route":
				return false
			p.intent = "break_off"
			return true
		"settle":
			if p.side != 0 or ball_mine or String(p.assign.get("kind", "")) != "route" or thrown:
				return false
			p.intent = "settle"
			return true
		"go_deep":
			if p.side != 0 or ball_mine or thrown:
				return false
			p.intent = "go_deep"
			return true
		"high_point":
			p.manner["high_point"] = true
			return true
		"secure":
			p.manner["secure"] = true
			return true
		"block_downfield":
			if carrier == null or carrier.side != p.side or carrier == p or ball_state != "held" or _qb_holding():
				return false
			p.intent = "block_downfield"
			return true
		# --- blockers
		"block", "pass_block", "drive_block", "cut_block", "double_team", "pick_up_blitz":
			if p.side != 0 or ball_mine:
				return false
			if id == "pick_up_blitz" and _free_rusher(p) == null:
				return false
			p.intent = id
			return true
		"release":
			if p.side != 0 or p.route.is_empty():
				return false
			p.released = true
			if p.engaged != null:
				_unlock(p)
			p.intent = "assignment"
			return true
		# --- defense
		"rush", "bull_rush", "speed_rush", "contain", "spy", "cover_man", "drop_zone", "stay_deep", "pursue", "fill_gap", "blitz", "go_ball":
			if p.side != 1 and id != "pursue" and id != "go_ball":
				return false
			if id == "cover_man" and p.cover == null:
				return false
			if id == "go_ball" and ball_state != "loose":
				return false
			p.intent = id
			return true
		"spin_move":
			if p.engaged == null or t < p.juke_cd:
				return false
			p.juke_cd = t + 2.0
			if rng.randf() < 0.22 + 0.3 * float(p.body["agility"]) - 0.1 * float(p.engaged.body["agility"]):
				_shed(p)
			return true
		"shed":
			if p.engaged == null:
				return false
			p.intent = "shed"
			return true
		"play_ball":
			if ball_state != "air":
				return false
			p.intent = "play_ball"
			return true
		"jump_route":
			if p.side != 1 or thrown:
				return false
			p.intent = "jump_route"
			return true
		"tackle":
			if carrier == null or carrier.side == p.side:
				return false
			p.intent = "pursue"
			return true
		"wrap_up", "hit_hard", "strip":
			if p.side == (carrier.side if carrier != null else 0) and ball_state == "held":
				return false
			p.manner[id] = true
			return true
	return false


## ---- reading the field ----------------------------------------------------------------------

func _diff(p: P) -> int:
	var d := int(ctx.get("score_diff", 0))
	return d if p.side == 0 else -d


func _dirpos(p: P) -> float:
	return p.pos.y


## The quarterback still has it behind the line, not yet thrown, handed off or run.
func _qb_holding() -> bool:
	return carrier != null and carrier.slot == "QB" and carrier.side == 0 and not thrown and not handed and not qb_runner


func _is_runner(p: P) -> bool:
	if ball_state != "held" or carrier != p:
		return false
	if p.slot == "QB" and p.side == 0 and not thrown and not handed:
		return qb_runner or (scrambling and p.pos.y > 0.0)
	return true


func _run_read(p: P) -> bool:
	if handed and t - handoff_t > 0.35 - 0.2 * p.d("vision"):
		return true
	if qb_runner or (carrier != null and carrier.side == 0 and carrier.pos.y > 0.5):
		return true
	return false


func _enemies(p: P) -> Array:
	return dfn if p.side == 0 else off


func _mates(p: P) -> Array:
	return off if p.side == 0 else dfn


func _nearest_enemy(p: P, free_only: bool) -> P:
	var best: P = null
	var bd := 1e9
	for e: P in _enemies(p):
		if e.down or (free_only and e.engaged != null):
			continue
		var d := p.pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_enemy_d(p: P, free_only: bool) -> float:
	var e := _nearest_enemy(p, free_only)
	return p.pos.distance_to(e.pos) if e != null else 99.0


## A rusher is a free defender who has got into the backfield.
func _rusher_d(p: P) -> float:
	var bd := 99.0
	for e: P in dfn:
		if e.down or e.engaged != null or e.pos.y > -0.3:
			continue
		bd = minf(bd, p.pos.distance_to(e.pos))
	return bd


func _rushers_within(p: P, r: float) -> int:
	var n := 0
	for e: P in dfn:
		if not e.down and e.engaged == null and e.pos.y <= -0.3 and p.pos.distance_to(e.pos) < r:
			n += 1
	return n


func _enemies_within(p: P, r: float, free_only: bool) -> int:
	var n := 0
	for e: P in _enemies(p):
		if not e.down and (not free_only or e.engaged == null) and p.pos.distance_to(e.pos) < r:
			n += 1
	return n


func _attack_dir(p: P) -> float:
	return 1.0 if p.side == 0 else -1.0


func _crowd_ahead(p: P) -> int:
	var dir := _attack_dir(p)
	var n := 0
	for e: P in _enemies(p):
		if e.down or e.engaged != null:
			continue
		var rel := e.pos - p.pos
		if rel.y * dir > -1.0 and rel.length() < 10.0:
			n += 1
	return n


func _open_field(p: P) -> bool:
	var dir := _attack_dir(p)
	for e: P in _enemies(p):
		if e.down:
			continue
		var rel := e.pos - p.pos
		if rel.y * dir > -1.5 and rel.length() < 6.0:
			return false
	return true


func _blocker_ahead(p: P) -> P:
	var dir := _attack_dir(p)
	var best: P = null
	var bd := 1e9
	for m: P in _mates(p):
		if m == p or m.down:
			continue
		var rel := m.pos - p.pos
		if rel.y * dir > 0.3 and rel.y * dir < 7.0 and absf(rel.x) < 4.0:
			var d := rel.length()
			if d < bd:
				bd = d
				best = m
	return best


func _past(c: P, p: P) -> bool:
	var dir := _attack_dir(c)
	return (c.pos.y - p.pos.y) * dir > 1.0


## How far the nearest defender is from a receiver, standing still.
func _sep(r: P) -> float:
	var bd := 99.0
	for e: P in _enemies(r):
		if e.down:
			continue
		bd = minf(bd, r.pos.distance_to(e.pos))
	return bd


func _ball_speed(dist: float) -> float:
	return 17.5 + 6.0 * QB_ARM * clampf(dist / 30.0, 0.3, 1.0)


## Where the ball would meet the receiver and how long it would fly.
func _lead(qb: P, r: P) -> Array:
	var c := r.pos
	var T := 0.3
	for _i in 3:
		var dist := qb.pos.distance_to(c)
		T = 0.18 + dist / _ball_speed(dist) + (0.25 if dist > 28.0 else 0.0)
		c = _predict(r, T)
	return [c, T]


## Where a receiver will be in `dt` seconds, following his route.
func _predict(r: P, dt: float) -> Vector2:
	if r.route.is_empty() or r.route_done and r.route_stop or r.intent == "settle":
		if r.route_stop or r.intent == "settle":
			return r.pos + r.vel * minf(dt, 0.2)
		return r.pos + r.vel * dt
	var pos := r.pos
	var left := dt * r.spd() * 0.95
	var k := r.wp
	while left > 0.0 and k < r.route.size():
		var w: Vector2 = r.route[k]
		var d := pos.distance_to(w)
		if d <= left:
			pos = w
			left -= d
			k += 1
		else:
			pos += (w - pos).normalized() * left
			left = 0.0
	if left > 0.0 and not r.route_stop and r.route.size() >= 2:
		var dir := (r.route[r.route.size() - 1] - r.route[r.route.size() - 2] as Vector2).normalized()
		pos += dir * left
	pos.x = clampf(pos.x, -SIDELINE + 0.5, SIDELINE - 0.5)
	return pos


## How open a throw to r would be: the margin the nearest defender has to make up when the
## ball arrives (yards; positive = open), less a penalty for a defender in the lane.
func _open(qb: P, r: P) -> float:
	if r == null or r.down or r.engaged != null or (r.group == "OL"):
		return -99.0
	if r.assign.get("kind", "") != "route" and r.intent != "break_off" and not (scrambling and r.group in ["WR", "TE", "RB"]):
		if not (r.slot == "RB" and t > 1.5):
			return -99.0
	if not r.released:
		return -99.0
	var lc := _lead(qb, r)
	var c: Vector2 = lc[0]
	var T: float = lc[1]
	if absf(c.x) > SIDELINE - 0.4 or c.y > to_goal + 9.5:
		return -99.0
	var margin := 99.0
	for e: P in dfn:
		if e.down:
			continue
		var reach := e.spd() * maxf(T - 0.35 + 0.3 * float(e.body["agility"]) - 0.25, 0.0) * 0.75
		if e.engaged != null:
			reach *= 0.3
		var m := e.pos.distance_to(c) - reach - REACH * 0.8
		# in the lane: under the throw, close to the line from qb to c
		var seg := c - qb.pos
		var tt := clampf((e.pos - qb.pos).dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
		var lane := e.pos.distance_to(qb.pos + seg * tt)
		if tt > 0.25 and tt < 0.92 and lane < 1.6 and T > 0.6:
			m = minf(m, lane - 1.6)
		margin = minf(margin, m)
	return margin


func _best_read(qb: P, need: float, min_depth := -99.0, max_depth := 99.0) -> Dictionary:
	var best: P = null
	var bs := -1e9
	var order: Array = reads if not reads.is_empty() else ["WR1", "WR2", "WR3", "TE", "RB"]
	for i in order.size():
		var r: P = by_slot["o:" + order[i]]
		var depth := _predict(r, 0.8).y
		if depth < min_depth or depth > max_depth:
			continue
		var o := _open(qb, r)
		if o < need:
			continue
		# reads earlier in the order and further downfield are worth a little more
		var s := minf(o, 4.0) * (0.6 + 0.4 * qb.d("vision")) - i * 0.35 + clampf(depth, -3.0, 25.0) * (0.04 + 0.07 * qb.d("risk"))
		if s > bs:
			bs = s
			best = r
	return {"r": best, "s": bs}


func _checkdown(qb: P) -> P:
	var best: P = null
	var bo := 1.0 - qb.d("risk")
	for s in ["RB", "TE"]:
		var r: P = by_slot["o:" + s]
		var o := _open(qb, r)
		if o > bo and _predict(r, 0.6).y < 7.0:
			bo = o
			best = r
	return best


func _free_rusher(p: P) -> P:
	var qb: P = by_slot["o:QB"]
	var best: P = null
	var bd := 1e9
	for e: P in dfn:
		if e.engaged != null or e.down or not _rushing(e):
			continue
		var d := e.pos.distance_to(qb.pos)
		if d < bd and d < 9.0:
			bd = d
			best = e
	return best


func _rushing(e: P) -> bool:
	var k := String(e.assign.get("kind", ""))
	return k == "rush" or k == "blitz" or e.intent in ["rush", "bull_rush", "speed_rush", "blitz", "contain"]


func _zone_threat(p: P) -> P:
	if String(p.assign.get("kind", "")) != "zone":
		return null
	var best: P = null
	var bs := -1e9
	var deep := DEEP_ZONES.has(String(p.assign["zone"]))
	for r: P in off:
		if not (r.group in ["WR", "TE", "RB"]) or r.assign.get("kind", "") != "route":
			continue
		var fut := _predict(r, 0.5)
		var d := fut.distance_to(p.zone_anchor)
		if d > p.zone_r * (1.0 + 0.6 * (1.0 - p.d("discipline"))):
			continue
		var s := -d + (fut.y * 0.6 if deep else 0.0)
		if s > bs:
			bs = s
			best = r
	return best


func _deepest_receiver_y() -> float:
	var y := -99.0
	for r: P in off:
		if r.group in ["WR", "TE", "RB"]:
			y = maxf(y, r.pos.y)
	return y


## ---- doing it --------------------------------------------------------------------------------

func _throw(qb: P, r: P) -> bool:
	if r == null or r == qb:
		return false
	var lc := _lead(qb, r)
	var c: Vector2 = lc[0]
	var T: float = lc[1]
	var dist := qb.pos.distance_to(c)
	var sigma := (0.25 + 0.012 * dist + 0.0009 * dist * dist) * (1.3 - QB_ACC) * float(K["throw_err"])
	if _rusher_d(qb) < 2.0:
		sigma *= 1.6
	if scrambling or qb.vel.length() > 3.0:
		sigma *= 1.3
	var err := Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
	var to := c + err
	ball_state = "air"
	thrown = true
	air = {"from": qb.pos, "to": to, "t0": t, "T": T, "lob": dist > 28.0, "dist": dist}
	air_target = r
	stat["target"] = r.slot
	_fx("throw", qb, r, to)
	_bump("att", qb)
	_say("%s throws to %s" % [qb.slot, r.slot])
	carrier = null
	return true


func _throw_away(qb: P) -> void:
	var sx := SIDELINE + 4.0 if qb.pos.x >= 0 else -SIDELINE - 4.0
	var to := Vector2(sx, qb.pos.y + 6.0)
	ball_state = "air"
	thrown = true
	air = {"from": qb.pos, "to": to, "t0": t, "T": qb.pos.distance_to(to) / 18.0, "lob": false, "dist": 20.0, "away": true}
	air_target = null
	_bump("att", qb)
	_say("thrown away")
	carrier = null


func _bump(k: String, p: P, v := 1.0) -> void:
	var key := "%s:%s" % [k, p.slot if p != null else "-"]
	stat[key] = float(stat.get(key, 0.0)) + v


func _say(text: String) -> void:
	events.append({"t": t, "text": text})


## ---- what each player wants ----------------------------------------------------------------

func _drive(p: P) -> void:
	if p.down:
		if t >= p.down_until:
			p.down = false
		else:
			p.mem["_want"] = Vector2.ZERO
			return
	if p.engaged != null:
		return
	var want := Vector2.ZERO
	var frac := 1.0
	if ball_state == "dead":
		p.mem["_want"] = Vector2.ZERO
		return
	if ball_state == "loose":
		want = (ball_pos - p.pos)
		p.mem["_want"] = want.normalized() * p.spd()
		return
	if carrier == p:
		_drive_carrier(p)
		return
	if ball_state == "air":
		_drive_air(p)
		return
	var live_pass := carrier != null and carrier.slot == "QB" and carrier.side == 0 and not thrown and not handed and not qb_runner
	if p.side == 0:
		if carrier == null or carrier.side == 1:
			_pursue(p)           # turnover: chase
		elif p.slot == "QB" and handed:
			_drive_handoff_qb(p)
		elif live_pass:
			_drive_offense_pre(p)
		else:
			_drive_blocker_for_carrier(p)
	else:
		if carrier != null and carrier.side == 1:
			_drive_blocker_for_carrier(p)
		elif live_pass and not _run_read(p):
			_drive_defense_pre(p)
		else:
			_drive_defense_run(p)


func _set_want(p: P, v: Vector2) -> void:
	p.mem["_want"] = v


func _toward(p: P, target: Vector2, frac := 1.0, arrive := 0.6) -> void:
	var d := target - p.pos
	var L := d.length()
	if L < 0.05:
		_set_want(p, Vector2.ZERO)
		return
	var sp := p.spd() * frac
	if L < arrive:
		sp *= L / arrive
	var dir := d / L
	if L > 2.0:
		dir = _avoid(p, dir)
	_set_want(p, dir * sp)


## Step round the bodies in the way (a pile of linemen, a teammate) instead of walking into them.
func _avoid(p: P, dir: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for q: P in players:
		if q == p or q == carrier or q == p.block_target or q.down:
			continue
		var rel := q.pos - p.pos
		var ahead := rel.dot(dir)
		if ahead <= 0.0 or ahead > 2.2:
			continue
		var lat := rel - dir * ahead
		var off := lat.length()
		if off > 1.0:
			continue
		var side := -lat.normalized() if off > 0.01 else Vector2(-dir.y, dir.x)
		var w := (1.0 - off) * (1.0 - ahead / 2.2) * (1.6 if q.engaged != null else 0.9)
		push += side * w
	if push == Vector2.ZERO:
		return dir
	return (dir + push * 1.4).normalized()


## Offense before the ball is out (pass) or before the handoff (run).
func _drive_offense_pre(p: P) -> void:
	var k := String(p.assign.get("kind", ""))
	var qb: P = by_slot["o:QB"]
	match p.intent:
		"hold":
			_set_want(p, Vector2.ZERO)
			return
		"go_deep":
			_toward(p, Vector2(p.pos.x, p.pos.y + 20.0))
			return
		"settle":
			_settle(p)
			return
		"break_off":
			# come back toward the QB's side of the field, staying in front of him
			var aim := Vector2(lerpf(p.pos.x, qb.pos.x, 0.35), maxf(qb.pos.y + 6.0, p.pos.y - 3.0))
			_toward(p, aim, 0.9)
			return
		"block", "pass_block", "drive_block", "cut_block", "double_team", "pick_up_blitz":
			if p.slot != "QB":
				_drive_block(p)
				return
		"block_downfield":
			_drive_blocker_for_carrier(p)
			return
	if p.slot == "QB":
		_drive_qb(p)
		return
	if p == carrier:
		return
	match k:
		"route":
			if not p.released:
				if t > 1.1 or p.mem.get("_chipped", false):
					p.released = true
				else:
					_drive_block(p)
					return
			_run_route(p)
			if scrambling and p.route_done and p.d("discipline") < 0.8:
				var aim := Vector2(lerpf(p.pos.x, qb.pos.x, 0.25), maxf(qb.pos.y + 7.0, 3.0))
				_toward(p, aim, 0.8)
		"block", "lead", "pull":
			_drive_block(p)
		"carry":
			_drive_carry_path(p)
		"handoff":
			_set_want(p, Vector2.ZERO)
		_:
			_drive_block(p)


func _run_route(p: P) -> void:
	if t < float(p.mem.get("_jam_until", 0.0)):
		_set_want(p, Vector2(0, 1.5))
		return
	if p.wp >= p.route.size():
		p.route_done = true
		if p.route_stop:
			_settle(p)
		elif p.route.size() >= 2:
			var dir := (p.route[p.route.size() - 1] - p.route[p.route.size() - 2] as Vector2).normalized()
			_set_want(p, dir * p.spd())
			if absf(p.pos.x) > SIDELINE - 1.0:
				_set_want(p, Vector2(0, p.spd()))
		else:
			_settle(p)
		return
	var w: Vector2 = p.route[p.wp]
	if p.pos.distance_to(w) < 0.7:
		p.wp += 1
		if p.wp >= p.route.size():
			p.route_done = true
		return
	_toward(p, w, 1.0, 0.0 if p.wp < p.route.size() - 1 or not p.route_stop else 2.5)


## Find the soft spot: drift away from the nearest defender, across, not up.
func _settle(p: P) -> void:
	var e := _nearest_enemy(p, true)
	if e == null or p.pos.distance_to(e.pos) > 6.0:
		_set_want(p, Vector2.ZERO)
		return
	var away := (p.pos - e.pos)
	away.y *= 0.3
	_set_want(p, away.normalized() * p.spd() * 0.45)


func _drive_qb(p: P) -> void:
	var a := p.assign
	var k := String(a.get("kind", ""))
	if k == "handoff" or (k == "pass" and false):
		_drive_handoff_qb(p)
		return
	if k == "carry":
		# QB keeper / sneak: he is the runner from the snap
		qb_runner = true
		return
	# pass: the drop
	var gun := off_play.formation != "under center"
	var drop := float(a.get("drop", 5))
	var depth := -(1.3 + drop * 0.9) if not gun else -(5.0 + drop * 0.45)
	if not p.mem.has("_drop_target"):
		p.mem["_drop_target"] = Vector2(p.pos.x, depth)
	var fake := bool(a.get("fake", false))
	if fake and t < 1.05:
		var rb: P = by_slot["o:RB"]
		_toward(p, rb.pos + Vector2(0, 0.6), 0.8)
		p.mem["_faked"] = true
		return
	var dt: Vector2 = p.mem["_drop_target"]
	if p.intent == "scramble" or scrambling:
		_drive_scramble(p)
		return
	if p.intent == "step_up":
		_toward(p, Vector2(p.pos.x, dt.y + 1.5), 0.5)
		return
	if not p.mem.get("_drop_done", false):
		_toward(p, dt, 0.9, 0.2)
		if p.pos.distance_to(dt) < 0.35 or t > 0.3 + 0.5 + drop * 0.2:
			p.mem["_drop_done"] = true
			read_t = t
		return
	# in the pocket: slide away from the nearest free rusher
	var e := _nearest_enemy(p, true)
	if e != null and p.pos.distance_to(e.pos) < 3.5:
		var away := (p.pos - e.pos).normalized()
		away.y = clampf(away.y, -0.3, 0.6)
		_set_want(p, away * p.spd() * 0.5)
	else:
		_set_want(p, Vector2.ZERO)
	_qb_default(p)


## The QB's own read when no rule decided: go through the reads, throw when one is open enough,
## hold on as long as his patience lets him, then throw it away, check down or run.
func _qb_default(p: P) -> void:
	if p.last_rule >= 0 and p.intent != "assignment":
		return
	if not (ball_state == "held" and carrier == p and not thrown):
		return
	if t < float(p.mem.get("_next_qb", 0.0)):
		return
	p.mem["_next_qb"] = t + BRAIN_EVERY
	if reads.is_empty():
		reads = ["WR1", "WR2", "WR3", "TE", "RB"]
	var need := 1.2 - 1.2 * p.d("risk")
	var per_read := 0.45 + 0.35 * p.d("patience")
	if t - read_t > per_read:
		read_t = t
		read_idx = mini(read_idx + 1, reads.size() - 1)
	var cur: P = by_slot["o:" + reads[read_idx]]
	var since := t - 0.3
	var pressure := _rusher_d(p)
	# vision lets him see an open man who isn't his current read
	if _open(p, cur) > need:
		_throw(p, cur)
		return
	if p.d("vision") > 0.0 and rng.randf() < p.d("vision") * 0.35:
		# a quick look back across the reads he has already been through
		for k in read_idx:
			var r: P = by_slot["o:" + reads[k]]
			if _open(p, r) > need + 0.3:
				_throw(p, r)
				return
	var limit := 2.6 + 1.6 * p.d("patience")
	if pressure < 1.6 or since > limit:
		var b := _best_read(p, need - 1.2 - 0.8 * p.d("risk"))
		if b["r"] != null:
			_throw(p, b["r"])
			return
		var cd := _checkdown(p)
		if cd != null:
			_throw(p, cd)
			return
		if pressure < 1.6 and rng.randf() < 0.3 + 0.4 * (1.0 - p.d("discipline")):
			scrambling = true
			p.intent = "scramble"
			return
		if since > limit + 0.8 or pressure < 1.0:
			if p.d("discipline") > 0.35 and rng.randf() < 0.75:
				_throw_away(p)
			elif _open_field(p) or rng.randf() < 0.5:
				qb_runner = true
				p.intent = "daylight"


func _drive_scramble(p: P) -> void:
	# toward the emptier side, a little forward; once past the line he is a runner
	var left := 0
	var right := 0
	for e: P in dfn:
		if e.pos.y < p.pos.y + 8.0 and not e.down:
			if e.pos.x < p.pos.x:
				left += 1
			else:
				right += 1
	var sx := -1.0 if left < right else 1.0
	if p.mem.has("_scr_dir"):
		sx = float(p.mem["_scr_dir"])
	p.mem["_scr_dir"] = sx
	_set_want(p, Vector2(sx, 0.25).normalized() * p.spd() * 0.9)
	if absf(p.pos.x) > SIDELINE - 4.0:
		_set_want(p, Vector2(0, 1) * p.spd() * 0.8)
	_qb_default(p)
	if p.pos.y > 0.3:
		qb_runner = true


func _drive_handoff_qb(p: P) -> void:
	var rb: P = by_slot["o:" + (carry_slot if carry_slot != "" else "RB")]
	if handed:
		# carry out the fake: bootleg away from the run
		var away := -signf(rb.pos.x - p.pos.x)
		_toward(p, p.pos + Vector2(away * 3.0, -1.5), 0.5)
		return
	var draw := String(rb.assign.get("gap", "")) == "draw"
	if draw and t < 1.0:
		_toward(p, Vector2(p.pos.x, -6.5), 0.8)
		return
	# meet the back on his path; the exchange happens at the mesh, a beat after the snap
	_toward(p, rb.pos + rb.vel * 0.15, 0.85, 0.3)
	var mesh_t := 0.3 + (1.0 if draw else (0.55 if off_play.formation == "under center" else 0.45))
	if t >= mesh_t and p.pos.distance_to(rb.pos) < 3.5:
		_handoff(p, rb)


func _handoff(qb: P, rb: P) -> void:
	handed = true
	handoff_t = t
	carrier = rb
	ball_state = "held"
	_bump("rush_att", rb)
	_fx("handoff", qb, rb)
	_say("handoff to %s" % rb.slot)


## The carrier, before he has the ball, heads for the mesh and then the hole.
func _drive_carry_path(p: P) -> void:
	var gap := String(p.assign.get("gap", "middle"))
	var gx: float = ball_x + gap_x_of(p.assign)
	if gap == "draw" and t < 0.9:
		_set_want(p, Vector2.ZERO)
		return
	if gap_wide(p.assign):
		_toward(p, Vector2(gx, -2.5), 1.0, 0.0)
	else:
		_toward(p, Vector2(gx, -1.2), 0.9, 0.0)


func _drive_carrier(p: P) -> void:
	# a QB with the ball behind the line before he decides to run is driven by _drive_qb
	if p.slot == "QB" and p.side == 0 and not handed and not thrown and not qb_runner:
		_drive_qb(p)
		return
	if p.intent == "go_down":
		_set_want(p, Vector2.ZERO)
		_end("down", p.pos)
		return
	var dir := _attack_dir(p)
	var since_handoff := t - handoff_t
	# patience: follow the called hole for a beat before freelancing
	var keeper := carry_slot == "QB" and p.slot == "QB" and not handed
	if keeper:
		since_handoff = t - 0.3
	if (handed or keeper) and p == by_slot.get("o:" + carry_slot) and since_handoff < 0.25 + 0.6 * p.d("patience") and p.intent == "assignment" and p.side == 0:
		var gap := String(p.assign.get("gap", "middle"))
		var gx: float = ball_x + gap_x_of(p.assign)
		var aim := Vector2(gx, p.pos.y + 3.0)
		if gap_wide(p.assign):
			# get to the edge at the line, then turn it up
			aim = Vector2(gx, 1.0) if absf(p.pos.x - gx) > 1.5 else Vector2(gx, p.pos.y + 4.0)
		_toward(p, aim, 1.0, 0.0)
		return
	var sp := p.spd() * float(K["carry_speed"])
	if t >= p.steer_t:
		p.steer_t = t + 0.15
		var nh := _steer(p)
		# a hard cut costs speed: less for an agile runner
		var turn := acos(clampf(nh.dot(p.heading), -1.0, 1.0))
		if turn > 0.35 and p.vel.length() > 3.0:
			p.slow_until = maxf(p.slow_until, t + turn * 0.25 * (1.2 - float(p.body["agility"])))
		p.heading = nh
	if p.manner.get("protect", false):
		sp *= 0.93
	if t < p.slow_until:
		sp *= 0.7
	_set_want(p, p.heading * sp)


## The run: score headings by ground gained against how soon a defender gets there.
func _steer(p: P) -> Vector2:
	var dir := _attack_dir(p)
	var vision := p.d("vision")
	var best := Vector2(0, dir)
	var bs := -1e9
	var angs := [-90, -70, -52, -36, -22, -10, 0, 10, 22, 36, 52, 70, 90]
	if p.intent == "reverse_field":
		angs += [-130, 130]
	var wide_side := -1.0 if p.pos.x > 0 else 1.0
	var sight := (7.0 + 9.0 * vision) * float(K["sight"])
	var seen: Array = []
	for e: P in _enemies(p):
		if e.down:
			continue
		var rel := e.pos - p.pos
		var dd := rel.length()
		# he sees what is ahead of him and close by; a man coming from behind is a surprise
		if dd < 2.5 or (dd < sight and rel.normalized().dot(p.heading) > 0.25):
			seen.append(e)
	for ad in angs:
		var a := deg_to_rad(float(ad))
		var h := Vector2(sin(a), cos(a) * dir)
		var prog := h.y * dir
		var risk := 0.0
		for e: P in _enemies(p):
			if e.down:
				continue
			var w := 0.2 if e.engaged != null else 1.0
			for tau in [0.35, 0.7, 1.1, 1.6]:
				var cp: Vector2 = p.pos + h * p.spd() * tau
				var reach: float = e.spd() * tau * 0.9 + TACKLE_R
				var m: float = cp.distance_to(e.pos) - reach
				risk += w * exp(-maxf(m, -2.0) * 0.9) * (1.6 - tau * 0.6) * 0.25
		var end: Vector2 = p.pos + h * p.spd() * 1.2
		var oob := absf(end.x) > SIDELINE - 0.5
		var s := prog * (2.2 + 0.6 * (1.0 - vision)) - risk * (0.25 + 0.45 * vision) * float(K["evade"])
		match p.intent:
			"cut_upfield":
				s += prog * 2.0
			"bounce":
				s += h.x * wide_side * 1.5
			"follow_blocker":
				var b := _blocker_ahead(p)
				if b != null:
					s -= (p.pos + h * 2.0).distance_to(b.pos + Vector2(0, -dir * 0.8)) * 0.6
			"out_of_bounds":
				s += h.x * signf(p.pos.x if p.pos.x != 0 else 1.0) * 3.0
				oob = false
			"pylon":
				var py := Vector2(signf(p.pos.x) * SIDELINE, to_goal if dir > 0 else -own_goal)
				s -= (p.pos + h * 3.0).distance_to(py) * 0.5
			"daylight":
				s -= risk * 0.3
		if oob:
			s -= 6.0
		s -= maxf(absf(end.x) - 21.0, 0.0) * 0.35
		# behind the line on an inside run, going sideways is going nowhere
		if p.side == 0 and p.pos.y < 1.0 and not gap_wide(p.assign):
			s -= absf(h.x) * 1.2
		s += h.dot(p.heading) * (0.6 - 0.3 * float(p.body["agility"]))
		if s > bs:
			bs = s
			best = h
	return best


## Blocking: the target is picked by _assign_blocks; here we close on him.
func _drive_block(p: P) -> void:
	var tgt := p.block_target
	if tgt == null:
		var qb: P = by_slot["o:QB"]
		if pass_play and not handed:
			# no one to block: sit between the QB and the line
			_toward(p, Vector2(lerpf(p.pos.x, qb.pos.x, 0.2), clampf(p.pos.y, qb.pos.y + 1.5, -0.6)), 0.6)
		else:
			_toward(p, p.pos + Vector2(0, 2.0), 0.6)
		return
	if pass_play and not handed and not thrown and p.intent != "drive_block":
		# pass set: get between the rusher and the QB
		var qb: P = by_slot["o:QB"]
		var line := (qb.pos - tgt.pos).normalized()
		_toward(p, tgt.pos + line * 0.9, 1.0, 0.3)
	else:
		_toward(p, tgt.pos + Vector2(0, -0.5), 1.0, 0.0)


func _drive_blocker_for_carrier(p: P) -> void:
	if p.group == "OL" and p.block_target != null and p.engaged != null:
		return
	var tgt := p.block_target
	if tgt != null:
		_toward(p, tgt.pos - (tgt.pos - carrier.pos).normalized() * 0.6, 1.0, 0.0)
	else:
		# escort: stay ahead of the carrier
		var dir := _attack_dir(carrier)
		_toward(p, carrier.pos + Vector2(0, dir * 3.0), 0.85)


func _pursue(p: P) -> void:
	if carrier == null:
		_set_want(p, Vector2.ZERO)
		return
	var c := carrier
	var d := p.pos.distance_to(c.pos)
	var aim := _intercept_point(p, c)
	# stay on top: a deep defender keeps the carrier in front of him
	var dir := _attack_dir(c)
	if (p.pos.y - c.pos.y) * dir > 1.5 and d > 4.0 and (p.intent == "stay_deep" or (p.group == "S" and p.d("discipline") > 0.6 and d > 7.0)):
		# keep leverage: match him across the field, stay between him and the goal, close in
		var lead := d / p.spd()
		aim = Vector2(c.pos.x + c.vel.x * lead, c.pos.y + dir * clampf(d * 0.35, 1.0, 5.0))
	_toward(p, aim, 1.0, 0.0)


## Where to run to meet the carrier: the earliest point on his line (at his current velocity)
## that I can reach no later than he does; if none, cut him off further along.
func _intercept_point(p: P, c: P) -> Vector2:
	# assume he is heading for the end zone as much as where he is going now
	var dirg := _attack_dir(c)
	var v := c.vel.lerp(Vector2(0, dirg) * c.spd(), 0.45)
	var close := p.pos.distance_to(c.pos)
	if close < 3.5:
		# break down and go at him: aim at where he'll be in a blink
		return c.pos + v * (0.08 + 0.05 * close)
	var sp := p.spd() * (0.92 + 0.08 * p.d("vision")) * float(K["pursuit"])
	var tt := 0.0
	while tt <= 2.5:
		var q := c.pos + v * tt
		if p.pos.distance_to(q) <= sp * tt + TACKLE_R:
			return q
		tt += 0.1
	# can't catch him on that line: aim at where he's going, ahead of him by the goal line
	return c.pos + v * 1.2


## Defense before the throw.
func _drive_defense_pre(p: P) -> void:
	var qb: P = by_slot["o:QB"]
	var k := String(p.assign.get("kind", ""))
	var it := p.intent
	if it == "assignment":
		it = {"rush": "rush", "blitz": "blitz", "man": "cover_man", "zone": "drop_zone", "spy": "spy"}.get(k, "drop_zone")
		if k == "rush" and bool(p.assign.get("contain", false)):
			it = "contain"
		# play action: an aggressive linebacker bites
		if qb.mem.get("_faked", false) and t < 1.3 and p.group in ["LB", "S"] and p.mem.get("_bit", -1) == -1:
			p.mem["_bit"] = 1 if rng.randf() < p.d("aggression") * 0.8 else 0
			if p.mem["_bit"] == 1:
				p.bitten_until = t + 0.9
	if t < p.bitten_until:
		_toward(p, Vector2(p.pos.x, 0.5), 0.9)
		return
	match it:
		"rush", "bull_rush", "speed_rush", "blitz", "shed":
			var aim := qb.pos
			if it == "speed_rush" or (p.group == "DL" and p.slot.begins_with("DE")):
				# arc around the edge
				var o := signf(p.pos.x - ball_x) if absf(p.pos.x - ball_x) > 0.5 else 1.0
				if p.pos.y > qb.pos.y + 1.5 and it == "speed_rush":
					aim = qb.pos + Vector2(o * 2.0, 1.0)
			_toward(p, aim, 1.0, 0.0)
		"contain":
			var o := signf(p.pos.x - ball_x) if absf(p.pos.x - ball_x) > 0.5 else 1.0
			var aim := Vector2(qb.pos.x + o * 2.5, qb.pos.y + 0.8)
			if absf(qb.pos.x - ball_x) > 3.0 and signf(qb.pos.x - ball_x) == o:
				aim = qb.pos
			_toward(p, aim, 0.95, 0.0)
		"spy":
			_toward(p, Vector2(qb.pos.x, maxf(qb.pos.y + 6.0, 4.0)), 0.8)
			if qb_runner or (scrambling and qb.pos.y > -1.0):
				_pursue(p)
		"cover_man":
			_cover_man(p)
		"drop_zone":
			_cover_zone(p)
		"stay_deep":
			_toward(p, Vector2(p.pos.x, maxf(p.pos.y, _deepest_receiver_y() + 3.0)), 0.8)
		"jump_route":
			if p.cover != null:
				var fut := _predict(p.cover, 0.6)
				_toward(p, fut + (qb.pos - fut).normalized() * 0.8, 1.0, 0.0)
			else:
				var th := _zone_threat(p)
				if th != null:
					var fut2 := _predict(th, 0.6)
					_toward(p, fut2 + (qb.pos - fut2).normalized() * 0.8, 1.0, 0.0)
				else:
					_cover_zone(p)
		"pursue", "fill_gap":
			if carrier != null and carrier.slot != "QB":
				_pursue(p)
			else:
				_toward(p, qb.pos, 1.0, 0.0)
		_:
			if k == "zone":
				_cover_zone(p)
			elif k == "man":
				_cover_man(p)
			else:
				_toward(p, qb.pos, 1.0, 0.0)


func _cover_man(p: P) -> void:
	var m := p.cover
	if m == null:
		_cover_zone(p)
		return
	var lag := clampf(0.38 - 0.28 * float(p.body["agility"]), 0.05, 0.4)
	var n := clampi(int(round(lag / DT)), 0, m.hist.size() - 1)
	var seen: Vector2 = m.hist[m.hist.size() - 1 - n]
	var seen_v := m.vel
	var cushion := 1.0 + 1.6 * (1.0 - p.d("aggression"))
	var inside := signf(ball_x - seen.x) * 0.6
	if m.pos.y > 12.0:
		cushion = 0.6 + 0.8 * (1.0 - p.d("aggression"))
	var aim := seen + seen_v * 0.25 + Vector2(inside, cushion)
	# off coverage: give ground, never come up to meet a man who is still coming at you
	if m.pos.y < p.pos.y and m.vel.y > 1.0:
		aim.y = maxf(aim.y, p.pos.y + clampf(m.vel.y * 0.12, 0.0, 1.2) * (1.0 if p.pos.y - m.pos.y < cushion + 2.0 else 0.0))
	if m.pos.y > p.pos.y - 0.5 and m.pos.y > 4.0:
		# he's even or past me: run with him, in phase, on his inside hip
		aim = m.pos + m.vel * 0.45 + Vector2(inside * 0.6, 0.6)
	if m.slot == "RB" and m.route.is_empty() and not handed:
		# back stays in to block: sit on him / spy
		aim = Vector2(m.pos.x, maxf(m.pos.y + 4.0, 3.0))
	_toward(p, aim, 1.0, 0.3)


func _cover_zone(p: P) -> void:
	var anchor := p.zone_anchor
	var k := String(p.assign.get("kind", ""))
	if k != "zone":
		anchor = p.pos
	var th := _zone_threat(p)
	var deep := k == "zone" and DEEP_ZONES.has(String(p.assign["zone"]))
	var aim := anchor
	if th != null:
		var fut := _predict(th, 0.35)
		var w := 0.55 + 0.35 * (1.0 - p.d("discipline"))
		aim = anchor.lerp(fut, w)
		if deep:
			# a deep defender only shades across; he comes up only for a receiver already deep
			aim.x = lerpf(anchor.x, fut.x, w)
			aim.y = maxf(anchor.y - 2.0 * (1.0 - p.d("discipline")), fut.y + 3.0 + 2.0 * p.d("discipline"))
		else:
			aim = aim + Vector2(0, 0.8)
	var frac := 0.85 if p.pos.distance_to(aim) > 4.0 else 1.0
	_toward(p, aim, frac, 0.5)


## Defense once the run is read, or a scramble.
func _drive_defense_run(p: P) -> void:
	if p.intent == "spy" and carrier != null and carrier.slot == "QB":
		_pursue(p)
		return
	if p.intent == "cover_man" and p.cover != null and p.d("discipline") > 0.6 and t - handoff_t < 0.8 and handed:
		_cover_man(p)
		return
	if p.intent == "stay_deep":
		_pursue(p)
		return
	if (p.intent == "contain" or (p.intent == "assignment" and bool(p.assign.get("contain", false)))) and carrier != null:
		var o := signf(p.pos.x - ball_x) if absf(p.pos.x - ball_x) > 0.5 else 1.0
		if (carrier.pos.x - ball_x) * o < absf(p.pos.x - ball_x):
			_toward(p, Vector2(carrier.pos.x + o * 2.0, carrier.pos.y + 1.0), 1.0, 0.0)
			return
	# deep defenders hold their depth a moment (play action)
	if p.group in ["CB", "S"] and t - handoff_t < 0.5 * p.d("discipline") and handed:
		_set_want(p, Vector2.ZERO)
		return
	_pursue(p)


func _drive_air(p: P) -> void:
	var to: Vector2 = air["to"]
	var left := float(air["t0"]) + float(air["T"]) - t
	if p == air_target:
		# get there as the ball does, not before and past it
		var dv := to - p.pos
		var need := dv / maxf(left, 0.12)
		if need.length() > p.spd():
			need = need.normalized() * p.spd()
		_set_want(p, need)
		return
	if p.side == 1:
		var reachable := p.pos.distance_to(to) - REACH < p.spd() * (left + 0.25)
		if p.intent == "play_ball" or p.intent == "jump_route" or reachable:
			_toward(p, to, 1.0, 0.2)
		else:
			_toward(p, to + Vector2(0, 3.0), 0.9)
		return
	# offense: drift toward where it is coming down to block for the catch
	if p.group in ["WR", "TE", "RB"] and p.pos.distance_to(to) < 15.0:
		_toward(p, to, 0.6)
	elif p.group != "OL":
		_set_want(p, p.vel * 0.8)
	else:
		_set_want(p, Vector2.ZERO)


## ---- blocks ----------------------------------------------------------------------------------

## Who blocks whom, re-decided every tenth of a second.
func _assign_blocks() -> void:
	if int(t / DT) % 3 != 0:
		return
	var blocking: Array = []
	var carrier_side := carrier.side if carrier != null else 0
	var live_pass := pass_play and not handed and not thrown and not qb_runner
	var ball_out := ball_state == "held" and carrier != null and not (carrier.slot == "QB" and carrier.side == 0 and not handed and not qb_runner)
	for p: P in players:
		if p == carrier or p.down:
			continue
		if p.side != carrier_side:
			if p.engaged == null:
				p.block_target = null
			continue
		var k := String(p.assign.get("kind", ""))
		var blocks := false
		if p.side == 0 and not ball_out:
			blocks = k in ["block", "lead", "pull"] or (k == "route" and not p.released) or p.intent in ["block", "pass_block", "drive_block", "cut_block", "double_team", "pick_up_blitz"]
			if not pass_play and p.group == "WR" and k != "route":
				blocks = true
		elif ball_out:
			blocks = p.group in ["OL", "TE", "WR", "RB", "QB"] if p.side == 0 else true
			if p.side == 1 and p.group == "DL":
				blocks = false
		if blocks:
			blocking.append(p)
		elif p.engaged == null:
			p.block_target = null
	if blocking.is_empty():
		return
	var targets: Array = []
	for e: P in players:
		if e.side == carrier_side or e.down:
			continue
		if live_pass:
			if _rushing(e) or e.pos.y < 2.5:
				targets.append(e)
		elif not ball_out:
			if e.pos.y < 9.0 and absf(e.pos.x - ball_x) < 12.0:
				targets.append(e)
		else:
			targets.append(e)
	var qb: P = by_slot["o:QB"]
	if not ball_out and not live_pass and carrier != null and carrier.side == 0:
		_assign_run_blocks(blocking)
		return
	var taken := {}
	# engaged pairs keep each other
	for b: P in blocking:
		if b.engaged != null:
			b.block_target = b.engaged
			taken[b.engaged.idx] = int(taken.get(b.engaged.idx, 0)) + 1
	var free: Array = blocking.filter(func(b): return b.engaged == null)
	# greedy: cheapest pair first
	var pairs: Array = []
	for b: P in free:
		for e in targets:
			var d: float = b.pos.distance_to(e.pos)
			var cost := d
			if live_pass:
				cost = d + e.pos.distance_to(qb.pos) * 0.35
				if b.group == "OL" and absf(e.pos.x - b.pos.x) > 4.5:
					cost += 6.0
			elif not ball_out:
				cost = d + absf(e.pos.x - b.pos.x) * 0.8
				if String(b.assign.get("kind", "")) == "pull":
					var side := float(b.assign.get("dir", 1))
					cost = absf(e.pos.x - (ball_x + side * 6.0)) + e.pos.y * 0.3
			else:
				cost = d + e.pos.distance_to(carrier.pos) * 0.8
				if (e.pos.y - carrier.pos.y) * _attack_dir(carrier) < -2.0:
					cost += 8.0   # already beaten: leave him
			if b.intent == "pick_up_blitz" and e.group in ["LB", "S", "CB"]:
				cost -= 3.0
			if b.block_target == e:
				cost -= 3.5   # stick with your man
			if not ball_out and not live_pass and b.group == "OL" and e.group == "DL":
				cost -= 2.0   # linemen take the down linemen first
			pairs.append([cost, b, e])
	pairs.sort_custom(func(x, y): return x[0] < y[0])
	var done := {}
	for pr in pairs:
		var b: P = pr[1]
		var e: P = pr[2]
		if done.has(b.idx):
			continue
		var cap := 2 if (b.intent == "double_team" or (live_pass and free.size() > targets.size())) else 1
		if int(taken.get(e.idx, 0)) >= cap:
			continue
		if pr[0] > 18.0:
			continue
		b.block_target = e
		done[b.idx] = true
		taken[e.idx] = int(taken.get(e.idx, 0)) + 1
	for b: P in free:
		if not done.has(b.idx):
			b.block_target = null


## Run blocking by area: blockers left to right take the box defenders left to right; the men
## left over are the ones furthest from the hole (the backside). A puller takes the first man
## outside on the play side.
func _assign_run_blocks(blocking: Array) -> void:
	var cs := by_slot.get("o:" + carry_slot) as P
	var gap := String(cs.assign.get("gap", "middle")) if cs != null else "middle"
	var hole := ball_x + (gap_x_of(cs.assign) if cs != null else 0.0)
	var side := signf(hole - ball_x)
	var box: Array = []
	for e: P in dfn:
		if not e.down and e.pos.y < 7.5 and absf(e.pos.x - ball_x) < 9.0:
			box.append(e)
	var line: Array = []
	var pullers: Array = []
	for b: P in blocking:
		if b.engaged != null:
			continue
		if String(b.assign.get("kind", "")) == "pull":
			pullers.append(b)
		elif b.group in ["OL", "TE", "RB", "QB"] or absf(b.pos.x - ball_x) < 9.0:
			line.append(b)
		else:
			# a wide receiver blocks the man on him
			var best: P = null
			var bd := 1e9
			for e: P in dfn:
				var d := b.pos.distance_to(e.pos)
				if d < bd:
					bd = d
					best = e
			b.block_target = best if bd < 12.0 else null
	var engaged_on := {}
	for b: P in blocking:
		if b.engaged != null:
			engaged_on[b.engaged.idx] = true
	box = box.filter(func(e): return not engaged_on.has(e.idx))
	box.sort_custom(func(a, b): return a.pos.x < b.pos.x)
	line.sort_custom(func(a, b): return a.pos.x < b.pos.x)
	# leave the backside men unblocked first
	while box.size() > line.size():
		if side < 0.0:
			box.pop_back()
		elif side > 0.0:
			box.pop_front()
		else:
			# middle: the deepest goes
			var deepest := 0
			for i in box.size():
				if box[i].pos.y > box[deepest].pos.y:
					deepest = i
			box.remove_at(deepest)
	# pullers: the first man outside on the play side
	for pl: P in pullers:
		var best: P = null
		var bd := 1e9
		for e: P in dfn:
			if e.down:
				continue
			var d: float = absf(e.pos.x - (hole + side * 1.5)) + e.pos.y * 0.4
			if d < bd:
				bd = d
				best = e
		pl.block_target = best
	if box.is_empty():
		return
	# pair in order; extra blockers help on the man nearest the hole
	var off_i := 0
	if line.size() > box.size():
		var extra := line.size() - box.size()
		off_i = extra if side < 0.0 else 0
	for i in line.size():
		var b: P = line[i]
		var k := i - off_i
		if k >= 0 and k < box.size():
			b.block_target = box[k]
		else:
			var near: P = box[0]
			for e: P in box:
				if absf(e.pos.x - hole) < absf(near.pos.x - hole):
					near = e
			b.block_target = near


func _resolve_blocks() -> void:
	# new engagements
	for b: P in players:
		if b.engaged != null or b.block_target == null or b.down or b == carrier:
			continue
		var e := b.block_target
		if e.down or e == carrier or e.blockers.size() >= 2:
			continue
		if float(e.shed_from.get(b.idx, 0.0)) > t:
			continue
		if b.pos.distance_to(e.pos) < ENGAGE_R + (0.35 if b.group == "OL" else 0.0):
			b.engaged = e
			if e.engaged == null:
				e.engaged = b
			e.blockers.append(b)
			if b.intent == "cut_block":
				# all or nothing: he goes down, or the blocker does
				if rng.randf() < 0.45 + (float(b.body["power"]) - float(e.body["agility"])) * 0.5:
					_knock_down(e, 1.1)
					_fx("pancake", b, e)
				else:
					_knock_down(b, 1.2)
				_unlock(b)
	# locked pairs: push and shed
	for e: P in players:
		if e.blockers.is_empty():
			continue
		var bl: Array = e.blockers.filter(func(x): return x.engaged == e and not x.down)
		e.blockers = bl
		if bl.is_empty():
			e.engaged = null
			continue
		var b: P = bl[0]
		var qb: P = by_slot["o:QB"]
		var goal: Vector2
		var e_on_d := e.side != (carrier.side if carrier != null else 0)
		if carrier != null and carrier != qb or handed or qb_runner:
			goal = carrier.pos if carrier != null else ball_pos
		else:
			goal = qb.pos
		if ball_state == "air":
			goal = air["to"]
		var dirE := (goal - e.pos).normalized()
		var bpow := 0.0
		for x: P in bl:
			bpow += float(x.body["power"]) * (1.08 if x.intent == "drive_block" else 1.0)
		var epow := float(e.body["power"]) * (1.15 if e.intent == "bull_rush" else 1.0)
		var double := bl.size() >= 2
		var run_block := not pass_play or handed or ball_out_of_qb()
		var rate := 0.35 + (epow - bpow) * 3.0
		if run_block:
			rate -= 0.5
		if double:
			rate -= 0.6
		rate = clampf(rate, -1.6, 1.8)
		if rate < 0.0 and run_block and carrier != null and e.side == 1:
			# the blocker is winning: he turns his man away from the hole and opens it
			var hole := carrier.pos.x
			if carrier.side == 0 and carrier.pos.y < 0.5 and String(carrier.assign.get("gap", "")) != "":
				hole = ball_x + gap_x_of(carrier.assign)
			var away := signf(e.pos.x - hole) if absf(e.pos.x - hole) > 0.1 else signf(e.pos.x - b.pos.x + 0.001)
			var pd := Vector2(away, 0.6).normalized()
			e.mem["_push"] = pd * -rate
			e.mem["_bface"] = -pd
		else:
			e.mem["_push"] = dirE * rate
			e.mem["_bface"] = dirE
		# shed
		var sh := 0.12 + (epow - float(b.body["power"])) * 0.6 + float(e.body["agility"]) * 0.12
		if e.intent == "speed_rush":
			sh += float(e.body["agility"]) * 0.15
		if e.intent == "shed" or e.group in ["LB", "S", "CB"]:
			sh += 0.12
		if carrier != null and carrier.side != e.side and e.pos.distance_to(carrier.pos) < 2.5 and not _qb_holding():
			# the runner is right there: worth letting go of the block, unless the blocker has him sealed
			var seal := (carrier.pos - e.pos).normalized().dot((b.pos - e.pos).normalized())
			sh += (0.5 + 0.4 * e.d("aggression")) * (0.3 if seal > 0.3 else 1.0)
		if double:
			sh *= 0.35
		if not e_on_d:
			sh = 0.4
		if rng.randf() < maxf(sh, 0.01) * DT * float(K["shed"]):
			_shed(e)
	# a blocker whose man has left him lets go
	for b: P in players:
		if b.engaged != null and not b.engaged.blockers.has(b) and b.engaged.engaged != b:
			b.engaged = null


func ball_out_of_qb() -> bool:
	return carrier != null and carrier.slot != "QB"


func _shed(e: P) -> void:
	for b: P in e.blockers:
		e.shed_from[b.idx] = t + 1.0
		b.engaged = null
		b.block_target = null
		b.stumble_until = t + 0.4
	e.blockers.clear()
	e.engaged = null
	# a step past the blocker
	e.vel += Vector2(rng.randf_range(-1.5, 1.5), 0)


func _unlock(b: P) -> void:
	if b.engaged != null:
		b.engaged.blockers.erase(b)
		if b.engaged.engaged == b:
			b.engaged.engaged = null if b.engaged.blockers.is_empty() else b.engaged.blockers[0]
	b.engaged = null


func _knock_down(p: P, secs: float) -> void:
	p.down = true
	p.down_until = t + secs
	if p.engaged != null:
		_unlock(p)
	for b: P in p.blockers:
		b.engaged = null
	p.blockers.clear()
	p.engaged = null


## ---- movement --------------------------------------------------------------------------------

func _move_all() -> void:
	for p: P in players:
		var want: Vector2 = p.mem.get("_want", Vector2.ZERO)
		if p.down:
			p.vel = p.vel.move_toward(Vector2.ZERO, 20.0 * DT)
		elif p.engaged != null or not p.blockers.is_empty():
			# locked: the pair moves together with the defender's push
			var e := p if not p.blockers.is_empty() else p.engaged
			var push: Vector2 = e.mem.get("_push", Vector2.ZERO)
			p.vel = p.vel.move_toward(push, 8.0 * DT)
		else:
			var acc := float(p.body["accel"])
			if t < p.stumble_until:
				want *= 0.3
			if p == carrier and t < p.juke_until:
				acc *= 1.6
			p.vel = p.vel.move_toward(want, acc * DT * (2.5 if want.length() < p.vel.length() - 0.5 else 1.0))
		p.pos += p.vel * DT
		if p.vel.length() > 0.5:
			p.face = p.face.slerp(p.vel.normalized(), 0.2)
	# a blocker stays square in front of his man
	for e: P in players:
		if e.blockers.is_empty():
			continue
		var b: P = e.blockers[0]
		var face: Vector2 = e.mem.get("_bface", (b.pos - e.pos).normalized())
		var spot := e.pos + face * 0.85
		b.pos = b.pos.lerp(spot, 0.3)
		if e.blockers.size() > 1:
			var b2: P = e.blockers[1]
			b2.pos = b2.pos.lerp(e.pos + face.rotated(0.9) * 0.9, 0.3)
	# bodies don't overlap (a light push; the ball carrier is not slowed by his own men)
	for i in players.size():
		var a: P = players[i]
		for j in range(i + 1, players.size()):
			var b: P = players[j]
			if a.down or b.down:
				continue
			var d := b.pos - a.pos
			var L := d.length()
			if L < BODY_R * 2.0 and L > 0.0001:
				if (a.engaged == b or b.engaged == a):
					continue
				var push := d / L * (BODY_R * 2.0 - L) * 0.5
				a.pos -= push
				b.pos += push
	for p: P in players:
		p.hist.append(p.pos)
		if p.hist.size() > 16:
			p.hist.pop_front()


## ---- the ball --------------------------------------------------------------------------------

func _ball() -> void:
	match ball_state:
		"held":
			if carrier != null:
				ball_pos = carrier.pos
				ball_h = 1.0
				if carrier.side == 0 and not thrown and not stat.has("fumbler"):
					stat["rusher"] = carrier.slot
				if carrier.side == 0 and carrier.pos.y > 0.0 and not crossed_los:
					crossed_los = true
		"air":
			var from: Vector2 = air["from"]
			var to: Vector2 = air["to"]
			var u := clampf((t - float(air["t0"])) / float(air["T"]), 0.0, 1.0)
			ball_pos = from.lerp(to, u)
			var apex := 2.0 + float(air["dist"]) * (0.18 if air["lob"] else 0.08)
			ball_h = 1.9 + 4.0 * apex * u * (1.0 - u) - 0.6 * u
			if u >= 1.0:
				_arrive()
		"loose":
			ball_h = 0.2
			for p: P in players:
				if not p.down and p.pos.distance_to(ball_pos) < 0.8 and rng.randf() < 0.3:
					_recover(p)
					break
			if t > loose_until + 3.0:
				_end("fumble_dead", ball_pos)


func _arrive() -> void:
	var to: Vector2 = air["to"]
	if air.get("away", false) or absf(to.x) > SIDELINE or to.y > to_goal + 10.0:
		_incomplete("incomplete")
		return
	var best_d: P = null
	var dd := 1e9
	var best_o: P = null
	var od := 1e9
	for p: P in players:
		if p.down:
			continue
		var d := p.pos.distance_to(to)
		if d > REACH:
			continue
		if p.side == 1 and d < dd:
			dd = d
			best_d = p
		elif p.side == 0 and p.group != "OL" and p.slot != "QB" and d < od:
			od = d
			best_o = p
	if best_d != null:
		var q := 1.0 - dd / REACH
		var p_int := float(best_d.body["hands"]) * 0.42 * q
		if best_d.intent in ["play_ball", "jump_route"]:
			p_int *= 1.35
		if best_o == null:
			p_int *= 1.7
		if rng.randf() < p_int:
			_intercept(best_d)
			return
		var p_pbu := 0.45 * q * (0.5 + float(best_d.body["agility"]) * 0.6)
		if best_o == null or rng.randf() < p_pbu * (0.7 if best_o.manner.get("high_point", false) else 1.0):
			_say("broken up by %s" % best_d.slot)
			_fx("pbu", best_d, best_o, to)
			stat["pbu_by"] = best_d.slot
			_incomplete("broken up")
			return
	if best_o == null:
		var tr := air_target
		_say("nobody there (target %s %.1f yd away)" % [tr.slot if tr != null else "-", tr.pos.distance_to(to) if tr != null else -1.0])
	if best_o != null:
		var q := 1.0 - od / REACH
		var pc := (0.86 + 0.12 * float(best_o.body["hands"])) * (0.7 + 0.3 * q) * float(K["catch"])
		if best_d != null:
			pc *= 0.85
		if best_o.manner.get("secure", false):
			pc *= 1.06
		if best_o.manner.get("high_point", false) and best_d != null:
			pc *= 1.1
		if rng.randf() < minf(pc, 0.98):
			_catch(best_o)
			return
		_say("dropped by %s" % best_o.slot)
		_fx("drop", best_o, null, to)
	_incomplete("incomplete")


func _catch(r: P) -> void:
	carrier = r
	ball_state = "held"
	r.pos = r.pos.lerp(air["to"], 0.5)
	_bump("comp", by_slot["o:QB"])
	_bump("rec", r)
	stat["catch_y"] = r.pos.y
	stat["catch_slot"] = r.slot
	_say("caught by %s" % r.slot)
	_fx("catch", r, null, air["to"])
	if r.manner.get("secure", false):
		r.slow_until = t + 0.4
	if r.pos.y >= to_goal:
		_end("td", r.pos)


func _intercept(d: P) -> void:
	carrier = d
	ball_state = "held"
	_bump("int", by_slot["o:QB"])
	_bump("int_by", d)
	stat["turnover"] = "int"
	_say("INTERCEPTED by %s" % d.slot)
	_fx("int", d, air_target, air["to"])
	for p: P in players:
		if p.engaged != null:
			_unlock(p)
		p.block_target = null


func _incomplete(why: String) -> void:
	if not air.is_empty() and not air.get("away", false):
		_fx("incomplete", null, null, air["to"])
	ball_state = "dead"
	_end(why, Vector2(ball_x, 0))


func _recover(p: P) -> void:
	_fx("recover", p)
	if p.side == 1:
		stat["turnover"] = "fumble"
		stat["fr_by"] = p.slot
		_say("FUMBLE recovered by the defense (%s)" % p.slot)
	else:
		_say("fumble, recovered by %s" % p.slot)
	carrier = p
	ball_state = "held"
	_end("recovered", p.pos)


## ---- contact ---------------------------------------------------------------------------------

func _contacts() -> void:
	if ball_state != "held" or carrier == null:
		return
	var c := carrier
	var gang := 0
	for e: P in _enemies(c):
		if not e.down and e.pos.distance_to(c.pos) < 1.6:
			gang += 1
	for e: P in _enemies(c):
		if e.down or t < e.tackle_cd:
			continue
		var d := e.pos.distance_to(c.pos)
		var dive := false
		if e.engaged != null and d > 0.9:
			continue   # a blocked man can only reach out an arm
		if d > TACKLE_R:
			# a diving tackle: closing on him and nearly there
			if d < TACKLE_R + 0.75 and (c.pos - e.pos).dot(e.vel - c.vel) > 0.0 and rng.randf() < 0.12:
				dive = true
			else:
				continue
		e.tackle_cd = t + 0.55
		var p := float(K["tackle"]) + (float(e.body["tackle"]) - 0.6) * 0.7 + (float(e.body["power"]) - float(c.body["power"])) * 0.25 - float(c.body["agility"]) * 0.1
		if e.engaged != null:
			p *= 0.3
		if e.manner.get("wrap_up", false):
			p += 0.12
		if c.manner.get("lower_shoulder", false):
			p -= 0.15 * clampf(float(c.body["power"]) - float(e.body["power"]) + 0.3, 0.0, 1.0)
		if e.manner.get("hit_hard", false):
			p -= 0.05
		if e.manner.get("strip", false):
			p -= 0.15
		if t < c.juke_until:
			p -= 0.26 * float(c.body["agility"])
		if t < c.stiff_until:
			p -= 0.25 * clampf(float(c.body["power"]) - float(e.body["power"]) + 0.6, 0.0, 1.0)
		if c.slot == "QB" and not handed and c.pos.y < 0.5:
			p += 0.18   # in the pocket he can't get away
		p += (gang - 1) * 0.12
		if dive:
			p *= 0.5
		if rng.randf() < clampf(p, 0.05, 0.97):
			# tackled - did it come out?
			var pf := 0.008 + (0.03 if e.manner.get("hit_hard", false) else 0.0) + (0.07 if e.manner.get("strip", false) else 0.0)
			if c.manner.get("protect", false):
				pf *= 0.3
			var dir := _attack_dir(c)
			var fall := 0.4 + clampf(float(c.body["power"]) - float(e.body["power"]), -0.3, 0.5)
			# a pile at the line surges forward behind its blockers
			if c.side == 0 and absf(c.pos.y) < 2.0:
				var mates := 0
				for m: P in off:
					if m != c and m.engaged != null and m.pos.distance_to(c.pos) < 3.0 and m.pos.y > c.pos.y - 0.5:
						mates += 1
				fall += mates * rng.randf_range(0.15, 0.45)
			if c.manner.get("lower_shoulder", false):
				fall += 0.8
			if e.manner.get("hit_hard", false):
				fall -= 0.4
			var spot := c.pos + Vector2(0, dir * maxf(fall, 0.0))
			stat["tackler"] = e.slot
			var is_sack := c.slot == "QB" and c.side == 0 and not handed and not thrown and c.pos.y < 0.0 and String(c.assign.get("kind", "")) == "pass"
			_fx("sack" if is_sack else ("dive_tackle" if dive else ("big_hit" if e.manner.get("hit_hard", false) or (e.vel - c.vel).length() > 11.5 else "tackle")), e, c)
			if rng.randf() < pf:
				_fumble(c, e)
				return
			_knock_down(c, 99.0)
			if c.slot == "QB" and c.side == 0 and not handed and not thrown and c.pos.y < 0.0 and String(c.assign.get("kind", "")) == "pass":
				_bump("sack", e)
				_end("sack", spot)
			else:
				_end("tackle", spot)
			return
		else:
			if dive:
				_knock_down(e, 0.6)
			else:
				e.stumble_until = t + 0.35
			c.slow_until = t + 0.3
			_fx("dive_miss" if dive else "miss", e, c)
			_bump("missed", e)
			if c.manner.get("lower_shoulder", false) and float(c.body["power"]) > float(e.body["power"]):
				_say("%s runs through %s" % [c.slot, e.slot])


func _fumble(c: P, by: P) -> void:
	_say("FUMBLE! %s strips it" % by.slot)
	stat["ff_by"] = by.slot
	stat["fumbler"] = c.slot
	_fx("fumble", c, by)
	_bump("fumble", c)
	ball_state = "loose"
	ball_pos = c.pos + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
	ball_pos.x = clampf(ball_pos.x, -SIDELINE + 0.3, SIDELINE - 0.3)
	loose_until = t
	carrier = null
	_knock_down(c, 99.0)


## ---- the whistle ----------------------------------------------------------------------------

func _check_end() -> void:
	if over or ball_state != "held" or carrier == null:
		return
	var c := carrier
	if absf(c.pos.x) > SIDELINE:
		_end("out", Vector2(signf(c.pos.x) * SIDELINE, c.pos.y))
		return
	if c.side == 0 and c.pos.y >= to_goal:
		_end("td", c.pos)
	elif c.side == 1 and c.pos.y <= -own_goal:
		_end("td", c.pos)
	elif c.side == 1 and c.pos.y > to_goal + 10.0:
		_end("out", c.pos)


func _end(why: String, spot: Vector2) -> void:
	if over:
		return
	over = true
	if ball_state != "dead":
		ball_state = "dead"
	var c := carrier
	var turnover := String(stat.get("turnover", ""))
	var r := {"why": why, "y": spot.y, "x": spot.x, "t": t, "turnover": turnover, "td": why == "td",
		"carrier": c.slot if c != null else "", "carrier_side": c.side if c != null else 0, "events": events, "stat": stat,
		"incomplete": why in ["incomplete", "broken up"], "pass": thrown, "sack": why == "sack"}
	if why == "td" and c != null and c.side == 1:
		r["def_td"] = true
	# a safety: the offense's carrier brought down in his own end zone
	if c != null and c.side == 0 and spot.y <= -own_goal and why != "td":
		r["safety"] = true
	# yards for the box score
	if c != null and c.side == 0 and not r["incomplete"]:
		var gain := spot.y
		if thrown and stat.has("catch_slot"):
			r["pass_yds"] = gain
		elif why == "sack":
			r["sack_yds"] = gain
		else:
			r["rush_yds"] = gain
	r["clock_stops"] = r["incomplete"] or why in ["out", "td"] or turnover != "" or r.get("safety", false)
	result = r
	_say({"td": "TOUCHDOWN", "out": "out of bounds", "tackle": "tackled", "sack": "SACKED", "whistle": "whistle", "down": "down"}.get(why, why))
