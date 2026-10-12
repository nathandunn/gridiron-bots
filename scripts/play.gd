class_name Play
extends RefCounted
## A play: a formation and every position's assignment.
##
##   play "Slants"
##   about "Three-step drop, slants inside, back in the flat."
##   side offense
##   kind pass
##   formation shotgun
##   QB: pass drop 3 read WR3 WR1 WR2 RB
##   RB: route flat
##   WR: route slant 5
##   TE: block then route flat
##   OL: block pass
##
## Group names (OL, WR, DL, LB, CB, S) set every slot of the group; a later line for one slot
## (WR3: route out 6) overrides it. The position's brain decides how the assignment is played.

const OFFENSE_SLOTS := ["QB", "RB", "WR1", "WR2", "WR3", "TE", "LT", "LG", "C", "RG", "RT"]
const DEFENSE_SLOTS := ["DE1", "DT1", "DT2", "DE2", "OLB1", "MLB", "OLB2", "CB1", "CB2", "FS", "SS"]
const SLOT_GROUP := {
	"QB": "QB", "RB": "RB", "WR1": "WR", "WR2": "WR", "WR3": "WR", "TE": "TE",
	"LT": "OL", "LG": "OL", "C": "OL", "RG": "OL", "RT": "OL",
	"DE1": "DL", "DT1": "DL", "DT2": "DL", "DE2": "DL", "OLB1": "LB", "MLB": "LB", "OLB2": "LB",
	"CB1": "CB", "CB2": "CB", "FS": "S", "SS": "S",
}
const GROUP_SLOTS := {
	"OL": ["LT", "LG", "C", "RG", "RT"], "WR": ["WR1", "WR2", "WR3"],
	"DL": ["DE1", "DT1", "DT2", "DE2"], "LB": ["OLB1", "MLB", "OLB2"], "CB": ["CB1", "CB2"], "S": ["FS", "SS"],
	"DE": ["DE1", "DE2"], "DT": ["DT1", "DT2"], "OLB": ["OLB1", "OLB2"],
}
const FORMATIONS := ["shotgun", "under center", "pistol", "empty"]
const FRONTS := ["even", "press", "off", "goal line"]
const ROUTES := ["go", "fade", "slant", "out", "in", "dig", "post", "corner", "hitch", "curl", "comeback", "flat", "seam", "drag", "cross", "wheel", "screen", "swing", "angle", "stop"]
const GAPS := ["inside left", "inside right", "middle", "outside left", "outside right", "sweep left", "sweep right", "draw", "sneak"]
const ZONES := ["deep third left", "deep third middle", "deep third right", "deep half left", "deep half right",
	"deep middle", "flat left", "flat right", "hook left", "hook middle", "hook right", "curl left", "curl right", "robber"]

var name := ""
var about := ""
var side := "offense"
var kind := "pass"            # offense: pass / run; defense: man / zone / blitz (for the coaches' reads)
var formation := "shotgun"
var front := "even"
var assigns := {}             # slot -> {kind, ...}
var errors: Array[String] = []
var source := ""


static func parse(text: String) -> Play:
	var p := Play.new()
	p.source = text
	var lines := text.split("\n")
	for i in lines.size():
		var line := Dsl.strip_comment(lines[i]).strip_edges()
		if line == "":
			continue
		var ln := i + 1
		var low := Dsl.lower_outside_quotes(line)
		if low.begins_with("play "):
			p.name = Dsl.quoted(line.substr(5))
		elif low.begins_with("about "):
			p.about = Dsl.quoted(line.substr(6))
		elif low.begins_with("side "):
			p.side = low.substr(5).strip_edges()
			if not ["offense", "defense"].has(p.side):
				p.errors.append("line %d: side is offense or defense" % ln)
		elif low.begins_with("kind "):
			p.kind = low.substr(5).strip_edges()
		elif low.begins_with("formation "):
			p.formation = low.substr(10).strip_edges()
			if not FORMATIONS.has(p.formation):
				p.errors.append("line %d: formations are %s" % [ln, ", ".join(FORMATIONS)])
		elif low.begins_with("front "):
			p.front = low.substr(6).strip_edges()
			if not FRONTS.has(p.front):
				p.errors.append("line %d: fronts are %s" % [ln, ", ".join(FRONTS)])
		elif low.find(":") > 0:
			var c := low.find(":")
			var who := low.substr(0, c).strip_edges().to_upper()
			var what := low.substr(c + 1).strip_edges()
			var slots: Array = []
			if GROUP_SLOTS.has(who):
				slots = GROUP_SLOTS[who]
			elif SLOT_GROUP.has(who):
				slots = [who]
			else:
				p.errors.append("line %d: no position '%s'" % [ln, who])
				continue
			var a := p._assignment(what, ln)
			if a.is_empty():
				continue
			for s in slots:
				p.assigns[s] = a
		else:
			p.errors.append("line %d: can't read '%s'" % [ln, line])
	if p.name == "":
		p.errors.append("the play has no name (play \"...\")")
	var want: Array = OFFENSE_SLOTS if p.side == "offense" else DEFENSE_SLOTS
	var missing := []
	for s in want:
		if not p.assigns.has(s):
			missing.append(s)
	if not missing.is_empty():
		p.errors.append("no assignment for %s" % ", ".join(missing))
	for s in p.assigns:
		if not want.has(s):
			p.errors.append("%s is on the other side of the ball" % s)
			break
	return p


func _assignment(what: String, ln: int) -> Dictionary:
	var w := what.split(" ", false)
	if w.is_empty():
		errors.append("line %d: no assignment" % ln)
		return {}
	var a := {"text": what}
	match w[0]:
		"pass", "play":
			# pass drop 5 read WR1 WR2 / play action drop 7 read ...
			a["kind"] = "pass"
			a["fake"] = w[0] == "play"
			a["drop"] = 5
			a["reads"] = []
			var i := 1
			while i < w.size():
				if w[i] == "drop" and i + 1 < w.size() and w[i + 1].is_valid_int():
					a["drop"] = int(w[i + 1])
					i += 2
				elif w[i] == "read":
					for k in range(i + 1, w.size()):
						var s: String = w[k].to_upper()
						if not ["RB", "WR1", "WR2", "WR3", "TE"].has(s):
							errors.append("line %d: '%s' can't be read (RB, WR1, WR2, WR3, TE)" % [ln, w[k]])
						else:
							a["reads"].append(s)
					break
				else:
					i += 1
			if (a["reads"] as Array).is_empty():
				a["reads"] = ["WR1", "WR2", "WR3", "TE", "RB"]
		"handoff":
			a["kind"] = "handoff"
		"run", "carry":
			var gap := " ".join(w.slice(1))
			if not GAPS.has(gap):
				errors.append("line %d: gaps are %s" % [ln, ", ".join(GAPS)])
				return {}
			a["kind"] = "carry"
			a["gap"] = gap
		"route", "block":
			var rest := w
			a["chip"] = false
			if w[0] == "block":
				if w.size() == 1 or w[1] == "pass" or w[1] == "run":
					a["kind"] = "block"
					return a
				if w.size() >= 3 and w[1] == "then" and w[2] == "route":
					a["chip"] = true
					rest = w.slice(2)
				elif w[1] == "lead":
					a["kind"] = "lead"
					return a
				else:
					errors.append("line %d: 'block', 'block then route ...' or 'block lead'" % ln)
					return {}
			if rest.size() < 2 or not ROUTES.has(rest[1]):
				errors.append("line %d: routes are %s" % [ln, ", ".join(ROUTES)])
				return {}
			a["kind"] = "route"
			a["route"] = rest[1]
			a["depth"] = float(rest[2]) if rest.size() > 2 and rest[2].is_valid_float() else -1.0
		"lead":
			a["kind"] = "lead"
		"pull":
			a["kind"] = "pull"
			a["dir"] = -1 if w.size() > 1 and w[1] == "left" else 1
		"rush":
			a["kind"] = "rush"
			a["contain"] = w.size() > 1 and w[1] == "contain"
		"blitz":
			a["kind"] = "blitz"
		"man":
			a["kind"] = "man"
			a["on"] = w[1].to_upper() if w.size() > 1 else ""
			if a["on"] != "" and not ["RB", "WR1", "WR2", "WR3", "TE"].has(a["on"]):
				errors.append("line %d: man on RB, WR1, WR2, WR3 or TE" % ln)
				return {}
		"zone":
			var z := " ".join(w.slice(1))
			if not ZONES.has(z):
				errors.append("line %d: zones are %s" % [ln, ", ".join(ZONES)])
				return {}
			a["kind"] = "zone"
			a["zone"] = z
		"spy":
			a["kind"] = "spy"
		_:
			errors.append("line %d: don't know the assignment '%s'" % [ln, what])
			return {}
	return a


func carrier_slot() -> String:
	for s in assigns:
		if String(assigns[s].get("kind", "")) == "carry":
			return s
	return ""
