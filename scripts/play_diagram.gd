class_name PlayDiagram
extends Control
## A chalkboard drawing of one play: the offense as O's with routes, blocks and the run path,
## or the defense as X's with zones, man lines and rush arrows. Players are lined up by the real
## engine (a PlaySim set up against a stock opponent), so what you see is where they start.

const VIEW_X := 24.0       # yards either side of the ball
const VIEW_UP := 18.0      # yards downfield shown
const VIEW_BACK := 8.0     # yards behind the line shown
const CHALK := Color(0.45, 0.95, 1.0)
const FAINT := Color(0.45, 0.95, 1.0, 0.3)
const RUN := Color(1.0, 0.88, 0.3)
const ZONE := Color(0.45, 0.75, 1.0, 0.28)
const RUSH := Color(1.0, 0.38, 0.8)

var play: Play
var _off: Array = []       # [{slot, pos, kind, route, gap}]
var _def: Array = []       # [{slot, pos, kind, zone_anchor, zone_r, cover_pos}]
var _qb := Vector2.ZERO


static var _stock_team := {}


func setup(p: Play) -> void:
	play = p
	if _stock_team.is_empty():
		_stock_team = Team.build(0, Library.names("coach")[0])
	var other: Play
	if p.side == "offense":
		other = Library.play("Cover 3") if Library.play("Cover 3") != null else Library.play(Library.plays_for("defense")[0])
	else:
		other = Library.play("Mesh") if Library.play("Mesh") != null else Library.play(Library.plays_for("offense")[0])
	var sim := PlaySim.new()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var op := p if p.side == "offense" else other
	var dp := other if p.side == "offense" else p
	var t1 := _stock_team.duplicate()
	t1["index"] = 1
	sim.setup(_stock_team, t1, op, dp, {"yl": 40.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
	_off.clear()
	_def.clear()
	for q in sim.off:
		var pl: PlaySim.P = q
		_off.append({"slot": pl.slot, "pos": pl.pos, "kind": String(pl.assign.get("kind", "")), "route": pl.route.duplicate(),
			"gap": String(pl.assign.get("gap", "")), "gx": PlaySim.gap_x_of(pl.assign), "dir": int(pl.assign.get("dir", 1)), "chip": bool(pl.assign.get("chip", false))})
		if pl.slot == "QB":
			_qb = pl.pos
	for q in sim.dfn:
		var pl: PlaySim.P = q
		_def.append({"slot": pl.slot, "pos": pl.pos, "kind": String(pl.assign.get("kind", "")), "zone_anchor": pl.zone_anchor,
			"zone_r": pl.zone_r, "cover_pos": pl.cover.pos if pl.cover != null else Vector2.INF, "contain": bool(pl.assign.get("contain", false))})
	queue_redraw()


func _to(p: Vector2) -> Vector2:
	var w := size.x
	var h := size.y
	var x := (p.x + VIEW_X) / (VIEW_X * 2.0) * w
	var y := (VIEW_UP - p.y) / (VIEW_UP + VIEW_BACK) * h
	return Vector2(x, y)


func _clip(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -VIEW_X + 0.5, VIEW_X - 0.5), clampf(p.y, -VIEW_BACK + 0.5, VIEW_UP - 0.5))


func _arrow(a: Vector2, b: Vector2, c: Color, w := 1.6) -> void:
	draw_line(a, b, c, w, true)
	var d := (b - a)
	if d.length() < 2.0:
		return
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b, b - d * 6.0 + n * 3.5, b - d * 6.0 - n * 3.5]), c)


func _path(pts: Array, c: Color, w := 1.6) -> void:
	if pts.size() < 2:
		return
	for i in pts.size() - 2:
		draw_line(pts[i], pts[i + 1], c, w, true)
	_arrow(pts[pts.size() - 2], pts[pts.size() - 1], c, w)


func _draw() -> void:
	if play == null:
		return
	# grass and the line of scrimmage
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.1))
	for yd in [-5.0, 5.0, 10.0, 15.0]:
		draw_line(_to(Vector2(-VIEW_X, yd)), _to(Vector2(VIEW_X, yd)), Color(0.4, 0.9, 1.0, 0.1), 1.0)
	for xd in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		draw_line(_to(Vector2(xd, -VIEW_BACK)), _to(Vector2(xd, VIEW_UP)), Color(0.4, 0.9, 1.0, 0.05), 1.0)
	draw_line(_to(Vector2(-VIEW_X, 0)), _to(Vector2(VIEW_X, 0)), Color(0.4, 0.65, 1.0, 0.7), 1.5)
	var r := maxf(size.x / 70.0, 3.2)
	if play.side == "offense":
		_draw_offense(r)
	else:
		_draw_defense(r)


func _draw_offense(r: float) -> void:
	for o in _off:
		var at := _to(o["pos"])
		match String(o["kind"]):
			"route":
				var pts := [at]
				for w in o["route"]:
					pts.append(_to(_clip(w)))
				_path(pts, CHALK)
			"carry":
				# the run: to the mesh, then through the hole
				var gx: float = o["gx"]
				var mesh := Vector2(gx * 0.35, minf(o["pos"].y + 2.0, -1.0))
				_path([at, _to(mesh), _to(Vector2(gx, 4.0))], RUN, 2.2)
			"pull":
				var d := float(o["dir"])
				_path([at, _to(o["pos"] + Vector2(0, -1.0)), _to(o["pos"] + Vector2(d * 5.0, 0.6))], RUN, 1.6)
			"lead":
				_arrow(at, _to(o["pos"] + Vector2(0, 4.0)), CHALK, 1.4)
			"block", "handoff":
				if o["slot"] != "QB":
					var up := _to(o["pos"] + Vector2(0, 1.0))
					draw_line(at, up, FAINT, 1.4, true)
					draw_line(up + Vector2(-4, 0), up + Vector2(4, 0), FAINT, 1.4, true)
		if bool(o["chip"]):
			draw_line(at + Vector2(-4, -6), at + Vector2(4, -6), FAINT, 1.4)
	for o in _off:
		var at := _to(o["pos"])
		draw_arc(at, r, 0, TAU, 14, CHALK, 1.6, true)
		if o["slot"] == "QB":
			draw_circle(at, r * 0.55, CHALK)
		if String(o["kind"]) == "carry":
			draw_circle(at, r * 0.55, RUN)


func _draw_defense(r: float) -> void:
	for d in _def:
		var at := _to(d["pos"])
		match String(d["kind"]):
			"zone":
				var c := _to(d["zone_anchor"])
				var rad: float = d["zone_r"] / (VIEW_X * 2.0) * size.x * 0.7
				draw_set_transform(c, 0, Vector2(1.0, 0.6))
				draw_circle(Vector2.ZERO, rad, ZONE)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				draw_line(at, c, Color(0.45, 0.75, 1.0, 0.7), 1.2, true)
			"man":
				if d["cover_pos"] != Vector2.INF:
					var m := _to(d["cover_pos"])
					_dashed(at, m, Color(1, 1, 1, 0.55))
					draw_arc(m, r * 0.8, 0, TAU, 10, FAINT, 1.2)
			"rush", "blitz":
				var tgt := _qb
				if bool(d["contain"]):
					tgt = _qb + Vector2(signf(d["pos"].x) * 4.0, 1.0)
				_arrow(at, _to(tgt), RUSH if d["kind"] == "blitz" else Color(1, 0.75, 0.7, 0.75), 2.0 if d["kind"] == "blitz" else 1.4)
			"spy":
				draw_arc(at, r * 1.8, 0, TAU, 16, RUN, 1.2)
	for d in _def:
		var at := _to(d["pos"])
		var c := RUSH if d["kind"] == "blitz" else CHALK
		draw_line(at + Vector2(-r, -r), at + Vector2(r, r), c, 2.0, true)
		draw_line(at + Vector2(-r, r), at + Vector2(r, -r), c, 2.0, true)


func _dashed(a: Vector2, b: Vector2, c: Color) -> void:
	var L := a.distance_to(b)
	var n := int(L / 6.0)
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), c, 1.2, true)
