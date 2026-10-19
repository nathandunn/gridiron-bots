class_name PlayGen
extends RefCounted
## Plays designed from nothing, at random, every time.
##
## Offense: the five linemen stay on the ball (they must), but everyone else lines up wherever
## chance puts them - receivers anywhere across the field, a tight end attached or flexed out, a
## back deep, offset or split wide, the quarterback under centre or at any depth. A pass gives
## every receiver a freehand route (one to three legs in random directions and lengths, sometimes
## sitting down at the end), a random drop and a random order of reads. A run aims at any point
## along the line, with random pullers and lead blockers, and receivers sometimes run decoys.
##
## Defense: every one of the eleven gets a random job - rush, blitz, man on a random receiver,
## a zone of random size anywhere on the field, or spy - and a random place to line up.
##
## Each play is written as ordinary play text (`WR1 at -14 -1`, `route path 0 6 -5 12 -5 30`,
## `run at 6.5`, `zone at -8 14 size 9`) and read by Play.parse, so any of them can be saved,
## edited and called again like a hand-written play.

const ADJ := ["Neon", "Chrome", "Ion", "Plasma", "Turbo", "Quantum", "Volt", "Laser", "Titan", "Rogue",
	"Static", "Nova", "Hyper", "Arc", "Omega", "Vortex", "Zero", "Pulse", "Echo", "Cobalt", "Radium", "Flux"]
const NOUN := ["Viper", "Hammer", "Comet", "Lattice", "Spiral", "Vector", "Fork", "Trident", "Cascade",
	"Grid", "Wedge", "Swarm", "Lance", "Helix", "Circuit", "Prism", "Rail", "Storm", "Mirage", "Coil", "Drone", "Sabre"]

const FIELD := 24.0        # how far from the ball a player may line up (the field is 26.7 either side)


static func _name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [ADJ[rng.randi() % ADJ.size()], NOUN[rng.randi() % NOUN.size()]]


static func _r(x: float) -> float:
	return snappedf(x, 0.5)


## A number as play text: one decimal, no float noise.
static func _f(x: float) -> String:
	var t := "%.1f" % snappedf(x, 0.5)
	return t.trim_suffix(".0") if t.ends_with(".0") else t


static func _pick(rng: RandomNumberGenerator, a: Array) -> Variant:
	return a[rng.randi() % a.size()]


static func _shuffle(rng: RandomNumberGenerator, a: Array) -> Array:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = b[i]
		b[i] = b[j]
		b[j] = t
	return b


## A spot nobody else is standing on.
static func _free_spot(rng: RandomNumberGenerator, taken: Array, make: Callable) -> Vector2:
	var p: Vector2 = make.call()
	for _i in 30:
		var ok := true
		for q in taken:
			if (q as Vector2).distance_to(p) < 2.2:
				ok = false
				break
		if ok:
			break
		p = make.call()
	taken.append(p)
	return p


## A freehand route from a start: one to three legs, each a random direction and length.
## Waypoints are written relative to the start.
static func _route(rng: RandomNumberGenerator, start: Vector2, short_drop: bool) -> String:
	var legs := rng.randi_range(1, 3)
	var pos := Vector2.ZERO
	var heading := deg_to_rad(rng.randf_range(-35.0, 35.0))   # 0 = straight upfield
	var pts: Array[String] = []
	for k in legs:
		var L := rng.randf_range(3.0, 9.0 if short_drop else 15.0)
		if k > 0:
			heading += deg_to_rad(rng.randf_range(-150.0, 150.0))
		var step := Vector2(sin(heading), cos(heading)) * L
		var nxt := pos + step
		# keep inside the field and not running backwards much
		nxt.x = clampf(start.x + nxt.x, -FIELD - 1.5, FIELD + 1.5) - start.x
		nxt.y = clampf(nxt.y, 0.5 if k == 0 else -1.5, 40.0)
		pos = nxt
		pts.append("%s %s" % [_f(pos.x), _f(pos.y)])
	var stop := pos.y < 20.0 and rng.randf() < 0.3
	return "route path %s%s" % [" ".join(pts), " stop" if stop else ""]


## A random offensive play: {text, play}.
static func offense(rng: RandomNumberGenerator) -> Dictionary:
	var lines: Array[String] = []
	var taken: Array = []
	# the line is fixed: C, guards, tackles
	for x in [0.0, -1.35, 1.35, -2.7, 2.7]:
		taken.append(Vector2(x, -0.8))
	var qb_depth := -1.3 if rng.randf() < 0.35 else _r(rng.randf_range(-3.5, -7.5))
	var formation := "under center" if qb_depth > -2.0 else "shotgun"
	var qb := Vector2(0, qb_depth)
	taken.append(qb)
	var wide := func() -> Vector2:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		return Vector2(_r(side * rng.randf_range(5.0, FIELD)), -0.8 if rng.randf() < 0.6 else -1.5)
	var at := {}
	for s in ["WR1", "WR2", "WR3"]:
		at[s] = _free_spot(rng, taken, wide)
	if rng.randf() < 0.6:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		at["TE"] = _free_spot(rng, taken, func(): return Vector2(side * 4.1, -1.0))
	else:
		at["TE"] = _free_spot(rng, taken, wide)
	if rng.randf() < 0.72:
		at["RB"] = _free_spot(rng, taken, func(): return Vector2(_r(rng.randf_range(-4.0, 4.0)), _r(rng.randf_range(-3.0, -8.0))))
	else:
		at["RB"] = _free_spot(rng, taken, wide)
	var name := _name(rng)
	lines.append("formation " + formation)
	lines.append("QB at 0 %s" % _f(qb_depth))
	for s in ["WR1", "WR2", "WR3", "TE", "RB"]:
		lines.append("%s at %s %s" % [s, _f(at[s].x), _f(at[s].y)])
	var about := ""
	if rng.randf() < 0.42:
		# a run: aim anywhere along the line
		var keeper := rng.randf() < 0.15
		var hole := _r(rng.randf_range(-6.0, 6.0) if keeper else rng.randf_range(-12.0, 12.0))
		lines.append("kind run")
		lines.append("OL: block run")
		var pulls := 0
		for g in ["LG", "RG", "LT", "RT"]:
			if rng.randf() < 0.18 and pulls < 2:
				lines.append("%s: pull %s" % [g, "right" if hole > 0.0 else "left"])
				pulls += 1
		if keeper:
			lines.append("QB: run at %s" % _f(hole))
			lines.append("RB: block lead" if rng.randf() < 0.6 else "RB: " + _route(rng, at["RB"], true))
		else:
			lines.append("QB: handoff")
			lines.append("RB: run at %s" % _f(hole))
		var decoys := 0
		for s in ["WR1", "WR2", "WR3", "TE"]:
			if rng.randf() < 0.3:
				lines.append("%s: %s" % [s, _route(rng, at[s], false)])
				decoys += 1
			else:
				lines.append("%s: block" % s)
		about = "%sRun at %+.1f%s%s" % ["QB keeper. " if keeper else "", hole, (", %d pulling" % pulls) if pulls > 0 else "", (", %d decoy routes" % decoys) if decoys > 0 else ""]
	else:
		var drop := rng.randi_range(1, 9)
		var pa: bool = at["RB"].x > -4.5 and at["RB"].x < 4.5 and rng.randf() < 0.22
		var short := drop <= 3
		var routers: Array = []
		lines.append("kind pass")
		lines.append("OL: block pass")
		for s in ["WR1", "WR2", "WR3"]:
			lines.append("%s: %s" % [s, _route(rng, at[s], short)])
			routers.append(s)
		var te_roll := rng.randf()
		if te_roll < 0.3:
			lines.append("TE: block")
		else:
			lines.append("TE: %s%s" % ["block then " if te_roll < 0.5 else "", _route(rng, at["TE"], short)])
			routers.append("TE")
		var rb_roll := rng.randf()
		if rb_roll < 0.4 and at["RB"].y < -2.0:
			lines.append("RB: block")
		else:
			lines.append("RB: %s%s" % ["block then " if rb_roll < 0.55 and at["RB"].y < -2.0 else "", _route(rng, at["RB"], true)])
			routers.append("RB")
		lines.append("QB: %s drop %d read %s" % ["play action" if pa else "pass", drop, " ".join(_shuffle(rng, routers))])
		about = "%d routes, %d-step drop%s" % [routers.size(), drop, ", play action" if pa else ""]
	return _finish(name, "offense", about, lines)


## A random defensive play: {text, play}.
static func defense(rng: RandomNumberGenerator) -> Dictionary:
	var lines: Array[String] = []
	var jobs := {}
	var targets := _shuffle(rng, ["WR1", "WR2", "WR3", "TE", "RB"])
	var counts := {"rush": 0, "blitz": 0, "man": 0, "zone": 0, "spy": 0}
	for s in Play.DEFENSE_SLOTS:
		var g: String = Play.SLOT_GROUP[s]
		var r := rng.randf()
		var job := ""
		if g == "DL":
			job = "rush" if r < 0.8 else "zone"
		else:
			job = "blitz" if r < 0.18 else ("man" if r < 0.5 else ("zone" if r < 0.92 else "spy"))
		jobs[s] = job
	# at least three come after the quarterback
	var rushers := Play.DEFENSE_SLOTS.filter(func(s): return jobs[s] in ["rush", "blitz"]).size()
	for s in _shuffle(rng, Play.DEFENSE_SLOTS):
		if rushers >= 3:
			break
		if not (jobs[s] in ["rush", "blitz"]):
			jobs[s] = "rush" if Play.SLOT_GROUP[s] == "DL" else "blitz"
			rushers += 1
	var taken: Array = []
	for s in Play.DEFENSE_SLOTS:
		var job: String = jobs[s]
		counts[job] = int(counts[job]) + 1
		var line := ""
		var spot := Vector2.INF
		match job:
			"rush", "blitz":
				line = "rush contain" if job == "rush" and rng.randf() < 0.3 else job
				var deep := 1.0 if Play.SLOT_GROUP[s] == "DL" else rng.randf_range(1.0, 5.0)
				spot = _free_spot(rng, taken, func(): return Vector2(_r(rng.randf_range(-7.0, 7.0)), _r(deep)))
			"man":
				var tgt: String = targets[0] if not targets.is_empty() else String(_pick(rng, ["WR1", "WR2", "WR3", "TE", "RB"]))
				if not targets.is_empty():
					targets.pop_front()
				line = "man " + tgt
			"zone":
				var zx := _r(rng.randf_range(-20.0, 20.0))
				var zy := _r(rng.randf_range(2.0, 22.0))
				var size := _r(rng.randf_range(4.0, 11.0))
				line = "zone at %s %s size %s" % [_f(zx), _f(zy), _f(size)]
				spot = _free_spot(rng, taken, func(): return Vector2(_r(zx * rng.randf_range(0.4, 1.0)), _r(clampf(zy - rng.randf_range(1.0, 6.0), 1.5, 15.0))))
			"spy":
				line = "spy"
				spot = _free_spot(rng, taken, func(): return Vector2(_r(rng.randf_range(-3.0, 3.0)), _r(rng.randf_range(4.0, 8.0))))
		lines.append("%s: %s" % [s, line])
		if spot != Vector2.INF:
			lines.append("%s at %s %s" % [s, _f(spot.x), _f(spot.y)])
	var kind := "blitz" if int(counts["blitz"]) >= 2 else ("man" if int(counts["man"]) > int(counts["zone"]) else "zone")
	var parts := []
	for k in ["rush", "blitz", "man", "zone", "spy"]:
		if int(counts[k]) > 0:
			parts.append("%d %s" % [counts[k], k])
	lines.insert(0, "kind " + kind)
	lines.insert(1, "front " + ("press" if rng.randf() < 0.4 else "off"))
	return _finish(_name(rng), "defense", ", ".join(parts), lines)


static func _finish(name: String, side: String, about: String, lines: Array[String]) -> Dictionary:
	var text := "play \"%s\"\nabout \"%s\"\nside %s\n%s\n" % [name, about, side, "\n".join(lines)]
	var p := Play.parse(text)
	if not p.errors.is_empty():
		push_warning("generated play didn't read: %s\n%s" % ["; ".join(p.errors), text])
	return {"text": text, "play": p}


## A hand of n different plays to choose from. Offense: runs and passes both in the mix, more
## runs on short yardage and more passes on long.
static func hand(rng: RandomNumberGenerator, side: String, n: int, to_go := 10.0) -> Array:
	var out: Array = []
	var seen := {}
	var want_runs := 3
	if to_go <= 2.0:
		want_runs = 4
	elif to_go >= 8.0:
		want_runs = 2
	var runs := 0
	var guard := 0
	while out.size() < n and guard < 300:
		guard += 1
		var g: Dictionary = offense(rng) if side == "offense" else defense(rng)
		var p: Play = g["play"]
		if not p.errors.is_empty() or seen.has(p.name):
			continue
		if side == "offense":
			var is_run := p.kind == "run"
			var left := n - out.size()
			if is_run and runs >= want_runs:
				continue
			if not is_run and left <= want_runs - runs:
				continue
			if is_run:
				runs += 1
		seen[p.name] = true
		out.append(g)
	if side == "offense":
		out.sort_custom(func(a, b): return int(a["play"].kind == "run") > int(b["play"].kind == "run"))
	return out
