class_name Brain
extends RefCounted
## A position brain: how one player plays his assignment, written as rules.
##
##   ai "Gunslinger"
##   about "Lets it fly. Trusts the arm over the read."
##   position QB
##   dials risk 0.8 patience 0.3 aggression 0.7 discipline 0.3
##
##   rules:
##     when before the throw and deep target open -> throw deep
##     when before the throw and rusher within 2 -> throw to open; throw to best
##     otherwise -> follow assignment
##
## Rules are read top to bottom ten times a second; the first that holds and can be done decides.
## Anything no rule decides falls to the engine's default for the player's assignment, which
## reads the dials - so a brain of one line is still a whole player.

const GROUPS := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S"]
const DIALS := ["aggression", "risk", "patience", "discipline", "vision"]
const DIAL_HELP := {
	"aggression": "attack first: hit hard, bite on the run, jump routes",
	"risk": "throw into tight windows, go for the big play",
	"patience": "wait for blocks and routes to develop",
	"discipline": "stay in your lane / zone / contain",
	"vision": "see the open lane and the open man",
}

const CONDITIONS := [
	[["always"], "always"],
	[["chance", "#P"], "chance"],
	# the ball
	[["i", "have", "the", "ball"], "have_ball"],
	[["with", "the", "ball"], "have_ball"],
	[["mate", "has", "the", "ball"], "mate_ball"],
	[["we", "have", "the", "ball"], "mate_ball"],
	[["enemy", "has", "the", "ball"], "enemy_ball"],
	[["they", "have", "the", "ball"], "enemy_ball"],
	[["ball", "in", "air"], "ball_air"],
	[["ball", "in", "the", "air"], "ball_air"],
	[["ball", "thrown", "to", "me"], "thrown_to_me"],
	[["ball", "thrown", "to", "my", "man"], "thrown_to_my_man"],
	[["ball", "coming", "my", "way"], "ball_my_way"],
	[["ball", "loose"], "ball_loose"],
	[["before", "the", "throw"], "before_throw"],
	[["before", "the", "snap", "read"], "before_throw"],
	[["after", "the", "handoff"], "after_handoff"],
	[["run", "play"], "run_play"],
	[["pass", "play"], "pass_play"],
	[["they", "run"], "they_run"],
	[["they", "pass"], "they_pass"],
	[["qb", "scrambling"], "qb_scrambling"],
	[["assignment", "is", "$W"], "assignment_is"],
	[["position", "is", "$W"], "position_is"],
	[["time", "over", "#S"], "time_over"],
	[["time", "under", "#S"], "time_under"],
	[["drop", "done"], "drop_done"],
	[["route", "done"], "route_done"],
	# people near me
	[["enemy", "within", "#D"], "enemy_within"],
	[["defender", "within", "#D"], "enemy_within"],
	[["tackler", "within", "#D"], "enemy_within"],
	[["rusher", "within", "#D"], "rusher_within"],
	[["pressure"], "pressure"],
	[["pocket", "collapsing"], "pocket_collapsing"],
	[["clean", "pocket"], "clean_pocket"],
	[["blocker", "ahead"], "blocker_ahead"],
	[["open", "field"], "open_field"],
	[["open", "field", "ahead"], "open_field"],
	[["crowd", "ahead"], "crowd_ahead"],
	[["one", "man", "to", "beat"], "one_to_beat"],
	[["sideline", "within", "#D"], "sideline_within"],
	[["engaged"], "engaged"],
	[["blocked"], "engaged"],
	[["free"], "free"],
	[["unblocked"], "free"],
	[["carrier", "within", "#D"], "carrier_within"],
	[["ball", "carrier", "within", "#D"], "carrier_within"],
	[["carrier", "past", "me"], "carrier_past"],
	[["carrier", "outside", "me"], "carrier_outside"],
	[["qb", "within", "#D"], "qb_within"],
	[["quarterback", "within", "#D"], "qb_within"],
	[["my", "man", "open"], "my_man_open"],
	[["my", "man", "beyond", "#D"], "my_man_beyond"],
	[["my", "man", "within", "#D"], "my_man_within"],
	[["receiver", "in", "my", "zone"], "receiver_in_zone"],
	[["threat", "in", "my", "zone"], "receiver_in_zone"],
	[["deep", "threat"], "deep_threat"],
	# the read (QB)
	[["target", "open"], "target_open"],
	[["anyone", "open"], "target_open"],
	[["deep", "target", "open"], "deep_open"],
	[["first", "read", "open"], "first_open"],
	[["checkdown", "open"], "checkdown_open"],
	[["receiver", "open", "by", "#D"], "open_by"],
	[["no", "one", "open"], "none_open"],
	[["nobody", "open"], "none_open"],
	[["i", "am", "open"], "i_am_open"],
	[["past", "the", "line"], "past_los"],
	[["behind", "the", "line"], "behind_los"],
	# the game
	[["past", "the", "sticks"], "past_sticks"],
	[["short", "of", "the", "sticks"], "short_sticks"],
	[["sticks", "within", "#D"], "sticks_within"],
	[["goal", "line", "within", "#D"], "goal_within"],
	[["end", "zone", "within", "#D"], "goal_within"],
	[["in", "the", "red", "zone"], "red_zone"],
	[["down", "is", "#X"], "down_is"],
	[["third", "down"], "third_down"],
	[["fourth", "down"], "fourth_down"],
	[["to", "go", "over", "#X"], "to_go_over"],
	[["to", "go", "under", "#X"], "to_go_under"],
	[["winning"], "winning"],
	[["losing"], "losing"],
	[["trailing", "by", "over", "#X"], "trailing_by"],
	[["leading", "by", "over", "#X"], "leading_by"],
	[["clock", "under", "#S"], "clock_under"],
	[["quarter", "#X"], "quarter_is"],
	[["late", "in", "the", "game"], "late_game"],
	[["phase", "is", "$W"], "phase_is"],
	[["$W", "open"], "slot_open"],
]

const ACTIONS := [
	[["follow", "assignment"], "assignment"],
	[["do", "my", "job"], "assignment"],
	[["hold"], "hold"],
	[["set", "phase", "$W"], "set_phase"],
	# QB
	[["throw", "to", "open"], "throw_open"],
	[["throw", "to", "the", "open", "man"], "throw_open"],
	[["throw", "to", "first", "read"], "throw_first"],
	[["throw", "to", "best"], "throw_best"],
	[["force", "it"], "throw_best"],
	[["throw", "deep"], "throw_deep"],
	[["throw", "short"], "throw_short"],
	[["check", "down"], "throw_checkdown"],
	[["throw", "to", "$W"], "throw_to"],
	[["throw", "it", "away"], "throw_away"],
	[["throw", "away"], "throw_away"],
	[["scramble"], "scramble"],
	[["roll", "out"], "scramble"],
	[["tuck", "and", "run"], "tuck_run"],
	[["step", "up"], "step_up"],
	[["take", "the", "sack"], "take_sack"],
	[["next", "read"], "next_read"],
	# ball carrier
	[["run", "to", "daylight"], "daylight"],
	[["find", "the", "hole"], "daylight"],
	[["follow", "my", "blocker"], "follow_blocker"],
	[["follow", "blocker"], "follow_blocker"],
	[["cut", "upfield"], "cut_upfield"],
	[["north", "south"], "cut_upfield"],
	[["bounce", "outside"], "bounce"],
	[["reverse", "field"], "reverse_field"],
	[["get", "out", "of", "bounds"], "out_of_bounds"],
	[["head", "for", "the", "sideline"], "out_of_bounds"],
	[["juke"], "juke"],
	[["spin"], "juke"],
	[["stiff", "arm"], "stiff_arm"],
	[["lower", "shoulder"], "lower_shoulder"],
	[["truck", "him"], "lower_shoulder"],
	[["go", "down"], "go_down"],
	[["slide"], "go_down"],
	[["protect", "the", "ball"], "protect"],
	[["race", "for", "the", "pylon"], "pylon"],
	# receivers
	[["run", "my", "route"], "assignment"],
	[["break", "off", "the", "route"], "break_off"],
	[["come", "back", "to", "the", "ball"], "break_off"],
	[["settle", "in", "the", "gap"], "settle"],
	[["sit", "down"], "settle"],
	[["go", "deep"], "go_deep"],
	[["take", "the", "top", "off"], "go_deep"],
	[["high", "point", "it"], "high_point"],
	[["fight", "for", "the", "ball"], "high_point"],
	[["secure", "the", "catch"], "secure"],
	[["block", "downfield"], "block_downfield"],
	[["block", "for", "the", "carrier"], "block_downfield"],
	# blockers
	[["block"], "block"],
	[["pass", "block"], "pass_block"],
	[["drive", "block"], "drive_block"],
	[["cut", "block"], "cut_block"],
	[["double", "team"], "double_team"],
	[["help", "inside"], "double_team"],
	[["pick", "up", "the", "blitz"], "pick_up_blitz"],
	[["release"], "release"],
	[["chip", "and", "release"], "release"],
	# defense
	[["rush"], "rush"],
	[["rush", "the", "passer"], "rush"],
	[["bull", "rush"], "bull_rush"],
	[["speed", "rush"], "speed_rush"],
	[["spin", "move"], "spin_move"],
	[["shed", "the", "block"], "shed"],
	[["shed"], "shed"],
	[["contain"], "contain"],
	[["keep", "contain"], "contain"],
	[["spy", "the", "quarterback"], "spy"],
	[["spy", "the", "qb"], "spy"],
	[["cover", "my", "man"], "cover_man"],
	[["drop", "to", "my", "zone"], "drop_zone"],
	[["drop", "into", "coverage"], "drop_zone"],
	[["play", "the", "ball"], "play_ball"],
	[["jump", "the", "route"], "jump_route"],
	[["undercut"], "jump_route"],
	[["stay", "deep"], "stay_deep"],
	[["stay", "on", "top"], "stay_deep"],
	[["pursue"], "pursue"],
	[["chase"], "pursue"],
	[["take", "an", "angle"], "pursue"],
	[["fill", "the", "gap"], "fill_gap"],
	[["fill", "the", "hole"], "fill_gap"],
	[["blitz"], "blitz"],
	[["go", "for", "the", "ball"], "go_ball"],
	[["fall", "on", "it"], "go_ball"],
	[["tackle"], "tackle"],
	[["wrap", "up"], "wrap_up"],
	[["hit", "hard"], "hit_hard"],
	[["go", "for", "the", "strip"], "strip"],
	[["punch", "it", "out"], "strip"],
]

## Actions that set a manner and let the next rule be read.
const MODIFIERS := ["set_phase", "protect", "wrap_up", "hit_hard", "strip", "secure", "high_point", "lower_shoulder", "stiff_arm"]

var name := ""
var about := ""
var group := "QB"
var dials := {}
var rules: Array = []
var errors: Array[String] = []
var source := ""


static func parse(text: String) -> Brain:
	var b := Brain.new()
	b.source = text
	var in_rules := false
	var lines := text.split("\n")
	for i in lines.size():
		var line := Dsl.strip_comment(lines[i]).strip_edges()
		if line == "":
			continue
		var ln := i + 1
		var low := Dsl.lower_outside_quotes(line)
		if low.begins_with("ai ") or low.begins_with("brain "):
			b.name = Dsl.quoted(line.substr(line.find(" ") + 1))
		elif low.begins_with("about "):
			b.about = Dsl.quoted(line.substr(6))
		elif low.begins_with("position "):
			b.group = line.substr(9).strip_edges().to_upper()
			if not GROUPS.has(b.group):
				b.errors.append("line %d: no such position '%s' (%s)" % [ln, b.group, ", ".join(GROUPS)])
		elif low.begins_with("dials "):
			var parts := low.substr(6).split(" ", false)
			var k := 0
			while k + 1 < parts.size():
				var tr: String = parts[k]
				if not DIALS.has(tr):
					b.errors.append("line %d: '%s' is not a dial (%s)" % [ln, tr, ", ".join(DIALS)])
				elif not parts[k + 1].is_valid_float():
					b.errors.append("line %d: dial %s needs a number 0-1" % [ln, tr])
				else:
					b.dials[tr] = clampf(float(parts[k + 1]), 0.0, 1.0)
				k += 2
		elif low == "rules:" or low == "plays:" or low == "do:":
			in_rules = true
		elif low.begins_with("when ") or low.begins_with("otherwise"):
			if not in_rules:
				b.errors.append("line %d: a rule before 'rules:'" % ln)
				continue
			var r := Dsl.parse_rule(low, ln, CONDITIONS, ACTIONS, b.errors, "player")
			if not r.is_empty():
				r["text"] = line
				b._check_words(r, ln)
				b.rules.append(r)
		else:
			b.errors.append("line %d: can't read '%s'" % [ln, line])
	if b.name == "":
		b.errors.append("the brain has no name (ai \"...\")")
	return b


## Words that take a free word must take one of the right ones.
const TARGETS := ["rb", "wr1", "wr2", "wr3", "te"]
const ASSIGNMENTS := ["pass", "handoff", "carry", "route", "block", "lead", "pull", "rush", "blitz", "man", "zone", "spy"]


func _check_words(r: Dictionary, ln: int) -> void:
	for a in r["actions"]:
		if a["id"] == "throw_to" and not TARGETS.has(String(a["args"][0]).to_lower()):
			errors.append("line %d: throw to whom? (%s)" % [ln, ", ".join(TARGETS)])
	_check_cond(r["cond"], ln)


func _check_cond(c: Variant, ln: int) -> void:
	if c is Dictionary:
		var w := str(c["args"][0]).to_lower() if not (c["args"] as Array).is_empty() else ""
		match String(c["id"]):
			"slot_open":
				if not TARGETS.has(w):
					errors.append("line %d: '%s open' - open needs a receiver (%s)" % [ln, w, ", ".join(TARGETS)])
			"assignment_is":
				if not ASSIGNMENTS.has(w):
					errors.append("line %d: assignments are %s" % [ln, ", ".join(ASSIGNMENTS)])
	elif c is Array:
		for k in range(1, (c as Array).size()):
			if c[k] is Dictionary or c[k] is Array:
				_check_cond(c[k], ln)


func dial(k: String) -> float:
	return float(dials.get(k, 0.5))


func rule_text(line: int) -> String:
	for r in rules:
		if int(r["line"]) == line:
			return String(r["text"])
	return "line %d" % line
