class_name PlayGen
extends RefCounted
## Random plays, made up fresh each down. Each one is written as ordinary play text and read by
## Play.parse, so a generated play is exactly what you could have typed in the editor (the log
## keeps the text, and the editor can save one).

const DEPTH := {"slant": [2, 4], "out": [5, 10], "in": [5, 9], "dig": [10, 14], "post": [9, 13], "corner": [9, 13],
	"hitch": [4, 7], "curl": [8, 12], "comeback": [11, 15], "cross": [5, 10], "drag": [2, 4]}
const DEEP := ["go", "fade", "post", "corner", "seam", "wheel"]
const SHORT := ["slant", "hitch", "out", "drag", "flat", "angle", "in"]
const MID := ["curl", "dig", "comeback", "cross", "in", "out"]


static func _pick(rng: RandomNumberGenerator, a: Array) -> Variant:
	return a[rng.randi() % a.size()]


static func _route(rng: RandomNumberGenerator, pool: Array) -> String:
	var r: String = _pick(rng, pool)
	if DEPTH.has(r):
		var d: Array = DEPTH[r]
		return "route %s %d" % [r, rng.randi_range(d[0], d[1])]
	return "route " + r


## A random offensive play: {text, play}.
static func offense(rng: RandomNumberGenerator) -> Dictionary:
	var lines: Array[String] = []
	var name := ""
	if rng.randf() < 0.42:
		var form: String = _pick(rng, ["under center", "shotgun", "pistol"])
		var gap: String = _pick(rng, ["inside left", "inside right", "middle", "outside left", "outside right", "sweep left", "sweep right", "draw"])
		if gap == "draw":
			form = "shotgun"
		var keeper := rng.randf() < 0.1 and gap in ["inside left", "inside right", "middle"]
		name = "Gen run: %s%s" % ["QB " if keeper else "", gap]
		lines.append("kind run")
		lines.append("formation " + form)
		lines.append("OL: block run")
		if (gap.begins_with("outside") or gap.begins_with("sweep")) and rng.randf() < 0.5:
			var side := "right" if gap.ends_with("right") else "left"
			lines.append("%s: pull %s" % ["LG" if side == "right" else "RG", side])
		if keeper:
			lines.append("QB: run " + gap)
			lines.append("RB: block lead")
		else:
			lines.append("QB: handoff")
			lines.append("RB: run " + gap)
		lines.append("TE: block")
		lines.append("WR: block")
	else:
		var form: String = _pick(rng, ["shotgun", "shotgun", "under center", "pistol", "empty"])
		var drop: int = _pick(rng, [3, 5, 5, 7])
		var pa := form == "under center" and rng.randf() < 0.35
		var pool: Array = SHORT if drop == 3 else (SHORT + MID if drop == 5 else MID + DEEP + DEEP)
		var routes := {}
		var used := {}
		for s in ["WR1", "WR2", "WR3"]:
			var r := _route(rng, pool)
			# no two receivers on the same route
			var guard := 0
			while used.has(r.split(" ")[1]) and guard < 6:
				r = _route(rng, pool)
				guard += 1
			used[r.split(" ")[1]] = true
			routes[s] = r
		var te_roll := rng.randf()
		var te := "block" if te_roll < 0.35 else (("block then " if te_roll < 0.6 else "") + _route(rng, ["flat", "seam", "drag", "out", "curl", "cross"]))
		var rb := "block" if form != "empty" and rng.randf() < 0.4 else _route(rng, ["flat", "swing", "wheel", "angle"])
		if form == "empty":
			rb = _route(rng, ["flat", "swing", "wheel", "angle", "hitch", "slant"])
		var readers := ["WR1", "WR2", "WR3"]
		if te != "block":
			readers.append("TE")
		if rb != "block":
			readers.append("RB")
		# a short drop reads the quick routes first; otherwise any order
		readers.shuffle()
		var tags := []
		for s in ["WR1", "WR2", "WR3"]:
			tags.append(String(routes[s]).split(" ")[1])
		name = "Gen %s: %s" % ["PA" if pa else ("quick" if drop == 3 else ("deep" if drop == 7 else "pass")), "/".join(tags)]
		lines.append("kind pass")
		lines.append("formation " + form)
		lines.append("QB: %s drop %d read %s" % ["play action" if pa else "pass", drop, " ".join(_shuffle(rng, readers))])
		for s in ["WR1", "WR2", "WR3"]:
			lines.append("%s: %s" % [s, routes[s]])
		lines.append("TE: " + te)
		lines.append("RB: " + rb)
		lines.append("OL: block pass")
	return _finish(name, "offense", "Made up for this down.", lines)


static func _shuffle(rng: RandomNumberGenerator, a: Array) -> Array:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = b[i]
		b[i] = b[j]
		b[j] = t
	return b


## A random defensive play: {text, play}.
static func defense(rng: RandomNumberGenerator) -> Dictionary:
	var lines: Array[String] = []
	var a := {}
	a["DT1"] = "rush"
	a["DT2"] = "rush"
	var contain := rng.randf() < 0.5
	a["DE1"] = "rush contain" if contain else "rush"
	a["DE2"] = "rush contain" if contain else "rush"
	var roll := rng.randf()
	var name := ""
	var kind := ""
	var front := ""
	var others := ["OLB1", "MLB", "OLB2", "FS", "SS"]
	if roll < 0.45:
		kind = "zone"
		front = "off"
		var shell := 2 if rng.randf() < 0.5 else 3
		var under: Array = []
		if shell == 2:
			a["FS"] = "zone deep half left"
			a["SS"] = "zone deep half right"
			a["CB1"] = "zone flat left"
			a["CB2"] = "zone flat right"
			under = ["hook left", "hook middle", "hook right", "curl left", "curl right", "robber"]
		else:
			a["CB1"] = "zone deep third left"
			a["CB2"] = "zone deep third right"
			a["FS"] = "zone deep third middle"
			a["SS"] = "zone " + String(_pick(rng, ["flat right", "flat left", "robber", "curl right"]))
			under = ["hook middle", "curl left", "curl right", "flat left", "flat right", "hook left", "hook right"]
		under = _shuffle(rng, under)
		var blitzer := ""
		if rng.randf() < 0.3:
			blitzer = String(_pick(rng, ["OLB1", "MLB", "OLB2"]))
		var k := 0
		for s in ["OLB1", "MLB", "OLB2"]:
			if s == blitzer:
				a[s] = "blitz"
			else:
				a[s] = "zone " + String(under[k])
				k += 1
		name = "Gen cover %d%s" % [shell, " + blitz" if blitzer != "" else ""]
	else:
		kind = "man" if roll < 0.82 else "blitz"
		front = "press" if rng.randf() < 0.5 else "off"
		a["CB1"] = "man WR1"
		a["CB2"] = "man WR2"
		var pool: Array = _shuffle(rng, ["SS", "FS", "OLB1", "MLB", "OLB2"])
		var deep := 0
		if kind == "man" and rng.randf() < 0.75:
			a["FS"] = "zone deep middle"
			pool.erase("FS")
			deep = 1
		for target in ["WR3", "TE", "RB"]:
			var s: String = pool.pop_front()
			a[s] = "man " + target
		var blitzes := 0
		for s in pool:
			var r := rng.randf()
			if kind == "blitz" or r < 0.4:
				a[s] = "blitz"
				blitzes += 1
			elif r < 0.6:
				a[s] = "spy"
			else:
				a[s] = "zone hook middle"
		name = "Gen %s, %d deep%s" % ["man" if kind == "man" else "cover 0", deep, (", %d blitz" % blitzes) if blitzes > 0 else ""]
	lines.append("kind " + kind)
	lines.append("front " + front)
	for s in Play.DEFENSE_SLOTS:
		lines.append("%s: %s" % [s, a[s]])
	return _finish(name, "defense", "Made up for this down.", lines)


static func _finish(name: String, side: String, about: String, lines: Array[String]) -> Dictionary:
	var text := "play \"%s\"\nabout \"%s\"\nside %s\n%s\n" % [name, about, side, "\n".join(lines)]
	var p := Play.parse(text)
	if not p.errors.is_empty():
		push_warning("generated play didn't read: %s\n%s" % ["; ".join(p.errors), text])
	return {"text": text, "play": p}
