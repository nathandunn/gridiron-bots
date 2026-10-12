class_name Coach
extends RefCounted
## A coach: calls the plays and picks who plays where.
##
##   coach "Air Raid"
##   about "Spread them out and throw."
##   offense:
##     when fourth down and goal line within 33 -> field goal
##     when fourth down -> punt
##     when third down and to go over 6 -> call "Four Verticals" or "Smash"
##     otherwise -> call "Slants" or "Mesh"
##   defense:
##     otherwise -> call "Cover 3" or "Cover 2"
##   lineup:
##     QB "Gunslinger"
##     WR "Burner"
##
## `call "A" or "B"` picks one at random. A coach who never says punt or field goal goes for it.

const CONDITIONS := [
	[["always"], "always"],
	[["chance", "#P"], "chance"],
	[["down", "is", "#X"], "down_is"],
	[["first", "down"], "first_down"],
	[["second", "down"], "second_down"],
	[["third", "down"], "third_down"],
	[["fourth", "down"], "fourth_down"],
	[["to", "go", "over", "#X"], "to_go_over"],
	[["to", "go", "under", "#X"], "to_go_under"],
	[["goal", "to", "go"], "goal_to_go"],
	[["goal", "line", "within", "#D"], "goal_within"],
	[["end", "zone", "within", "#D"], "goal_within"],
	[["in", "field", "goal", "range"], "fg_range"],
	[["own", "goal", "within", "#D"], "own_goal_within"],
	[["backed", "up"], "backed_up"],
	[["in", "the", "red", "zone"], "red_zone"],
	[["midfield", "crossed"], "past_midfield"],
	[["past", "midfield"], "past_midfield"],
	[["leading", "by", "over", "#X"], "leading_by"],
	[["trailing", "by", "over", "#X"], "trailing_by"],
	[["leading"], "winning"],
	[["winning"], "winning"],
	[["trailing"], "losing"],
	[["losing"], "losing"],
	[["tied"], "tied"],
	[["quarter", "#X"], "quarter_is"],
	[["clock", "under", "#S"], "clock_under"],
	[["half", "ending"], "half_ending"],
	[["game", "ending"], "game_ending"],
	[["last", "call", "was", "$W"], "last_call_was"],
	[["last", "play", "gained", "over", "#X"], "last_gained_over"],
	[["last", "play", "failed"], "last_failed"],
	[["passing", "averaging", "over", "#X"], "pass_avg_over"],
	[["running", "averaging", "over", "#X"], "run_avg_over"],
	[["passing", "averaging", "under", "#X"], "pass_avg_under"],
	[["running", "averaging", "under", "#X"], "run_avg_under"],
	[["$W", "averaging", "over", "#X"], "avg_over"],
	[["$W", "averaging", "under", "#X"], "avg_under"],
	[["$W", "called", "over", "#X", "times"], "called_over"],
	[["they", "ran", "last"], "they_ran_last"],
	[["they", "passed", "last"], "they_passed_last"],
	[["they", "run", "over", "#P"], "they_run_over"],
	[["they", "pass", "over", "#P"], "they_pass_over"],
]

const ACTIONS := [
	[["call", "$R"], "call"],
	[["punt"], "punt"],
	[["field", "goal"], "field_goal"],
	[["kick", "it"], "field_goal"],
	[["go", "for", "it"], "go_for_it"],
	[["kneel"], "kneel"],
]

const MODIFIERS := ["go_for_it"]

var name := ""
var about := ""
var offense_rules: Array = []
var defense_rules: Array = []
var lineup := {}        # group or slot -> brain name
var errors: Array[String] = []
var source := ""


static func parse(text: String) -> Coach:
	var c := Coach.new()
	c.source = text
	var block := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line := Dsl.strip_comment(lines[i]).strip_edges()
		if line == "":
			continue
		var ln := i + 1
		var low := Dsl.lower_outside_quotes(line)
		if low.begins_with("coach "):
			c.name = Dsl.quoted(line.substr(6))
		elif low.begins_with("about "):
			c.about = Dsl.quoted(line.substr(6))
		elif low == "offense:" or low == "defense:" or low == "lineup:":
			block = low.trim_suffix(":")
		elif low.begins_with("when ") or low.begins_with("otherwise"):
			if block != "offense" and block != "defense":
				c.errors.append("line %d: a rule outside 'offense:' or 'defense:'" % ln)
				continue
			var r := Dsl.parse_rule(low, ln, CONDITIONS, ACTIONS, c.errors, "coach")
			if r.is_empty():
				continue
			r["text"] = line
			for a in r["actions"]:
				if a["id"] == "call":
					var ns := Dsl.names_in(String(a["args"][0]))
					if ns.is_empty():
						c.errors.append("line %d: call needs a play name in quotes" % ln)
					a["args"] = [ns]
			(c.offense_rules if block == "offense" else c.defense_rules).append(r)
		elif block == "lineup":
			var sp := line.find(" ")
			if sp < 0:
				c.errors.append("line %d: lineup lines are POSITION \"Brain\"" % ln)
				continue
			var who := line.substr(0, sp).strip_edges().to_upper()
			if not Brain.GROUPS.has(who) and not Play.SLOT_GROUP.has(who):
				c.errors.append("line %d: no position '%s'" % [ln, who])
				continue
			c.lineup[who] = Dsl.quoted(line.substr(sp + 1))
		else:
			c.errors.append("line %d: can't read '%s'" % [ln, line])
	if c.name == "":
		c.errors.append("the coach has no name (coach \"...\")")
	return c


## Every play this coach can call, for the library check.
func plays_called() -> Array[String]:
	var out: Array[String] = []
	for rs in [offense_rules, defense_rules]:
		for r in rs:
			for a in r["actions"]:
				if a["id"] == "call":
					for n in a["args"][0]:
						if not out.has(n):
							out.append(n)
	return out
