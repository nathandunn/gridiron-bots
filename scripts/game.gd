class_name Game
extends RefCounted
## A game: four quarters, downs and distance, the coaches' calls, the score and the box
## score. Plays themselves are PlaySims; the game asks for the next one with next_snap() and is
## told how it went with finish(result).
##
## No kicking: a touchdown is 7 points, a safety is 7 to the defense, and after any score or
## change of possession the other side starts at its own 25. Fourth down is always a go.

const HASH := 3.08

var teams: Array = []          # {index, name, coach: Coach, brains: {slot: Brain}}
var rng := RandomNumberGenerator.new()
var score := [0, 0]
var quarter := 1
var qlen := 360.0
var clock := 360.0
var poss := 0
var yl := 25.0                 # the offense's yard line, 0 = own goal
var down := 1
var to_go := 10.0
var ball_x := 0.0
var over := false
var opened := 0                # who received the opening kick
var log: Array = []            # one entry a snap or kick
var stats := [{}, {}]
var calls := [{}, {}]          # per team: play name -> [times, yards]
var kinds := [{"run": 0, "pass": 0}, {"run": 0, "pass": 0}]   # what each team has called on offense
var last_call := ["", ""]
var last_gain := [0.0, 0.0]
var last_kind := ["", ""]
var coach_tally := [{}, {}]    # rule line -> count
var drive := {}                # the current drive: team, start, plays, yards
var drives: Array = []
var pending := {}              # the call for the snap in play
var plays_run := 0
var down_event := ""           # what the last snap did to the downs: "first_down", "downs" (turned over), ""
var line := [[0, 0, 0, 0], [0, 0, 0, 0]]   # points a quarter
var pstats := [{}, {}]         # per team: slot -> player box score
var quarter_ends: Array = []   # a snapshot at the end of each quarter: {q, score, line, stats, pstats}

## How each side picks its plays: "coach" (the coach's rules), "random" (any play in the book),
## "generated" (a new play made up every down). Kicks on fourth down stay the coach's call.
const CALLING := ["pick", "coach", "random", "generated"]
const CALLING_LABEL := {"pick": "You pick (from new plays)", "coach": "Coach calls", "random": "Random from playbook", "generated": "Random new plays"}


func setup(red: Dictionary, blue: Dictionary, quarter_secs: float, seed_v: int) -> void:
	teams = [red, blue]
	red["index"] = 0
	blue["index"] = 1
	qlen = quarter_secs
	clock = qlen
	rng.seed = seed_v
	for t in 2:
		stats[t] = {"plays": 0, "pass_att": 0, "comp": 0, "pass_yds": 0.0, "rush_att": 0, "rush_yds": 0.0,
			"sacks": 0, "sack_yds": 0.0, "ints": 0, "fumbles": 0, "td": 0, "fg": 0, "fg_att": 0, "punts": 0,
			"first_downs": 0, "third_att": 0, "third_conv": 0, "fourth_att": 0, "fourth_conv": 0, "yards": 0.0,
			"top": 0.0, "explosive": 0, "turnovers": 0}
	opened = rng.randi() % 2
	_kickoff(1 - opened)
	_say("Kick-off: %s receive. Touchback." % teams[poss]["name"])


func _say(s: String) -> void:
	log.append({"text": s, "q": quarter, "clock": clock, "score": score.duplicate(), "kind": "note"})


func offense() -> Dictionary:
	return teams[poss]


func defense() -> Dictionary:
	return teams[1 - poss]


func _kickoff(receiver: int) -> void:
	poss = receiver
	yl = 25.0
	down = 1
	to_go = 10.0
	ball_x = 0.0
	_new_drive()


func _new_drive() -> void:
	if not drive.is_empty():
		drives.append(drive)
	drive = {"team": poss, "start": yl, "plays": 0, "yards": 0.0, "result": ""}


## What the side on offense / defense picks with, right now.
func calling_for(on_offense: bool) -> String:
	return String((offense() if on_offense else defense()).get("calling", "coach"))


## `choice` carries a person's picks: {off: {text, play}} / {def: {text, play}}.
## A side set to "pick" with no choice given plays a made-up play (as in a batch).
func next_snap(choice: Dictionary = {}) -> Dictionary:
	if over:
		return {"kind": "over"}
	var oc: Coach = offense()["coach"]
	var dc: Coach = defense()["coach"]
	var od := _coach_call(oc, true, poss)
	var dd := _coach_call(dc, false, 1 - poss)
	if calling_for(true) == "pick" and choice.has("off"):
		od = {"kind": "play", "play": od.get("play", "")}
		if od["play"] == "":
			od["play"] = Library.plays_for("offense")[0]
	if String(od["kind"]) == "kneel":
		return _kneel()
	var op: Play = Library.play(od["play"])
	var dp: Play = Library.play(dd.get("play", ""))
	if dp == null:
		dp = Library.play(Library.plays_for("defense")[0])
	pending = {"kind": "play", "off_text": "", "def_text": ""}
	var off_mode := calling_for(true)
	var def_mode := calling_for(false)
	if off_mode == "pick":
		off_mode = ""      # nobody to ask (a batch) or "let the coach call it": the coach's play
		if choice.has("off"):
			op = choice["off"]["play"]
			pending["off_text"] = choice["off"]["text"]
	if def_mode == "pick":
		def_mode = ""
		if choice.has("def"):
			dp = choice["def"]["play"]
			pending["def_text"] = choice["def"]["text"]
	match off_mode:
		"random":
			var o: Array = Library.plays_for("offense")
			op = Library.play(o[rng.randi() % o.size()])
		"generated":
			var g := PlayGen.offense(rng)
			op = g["play"]
			pending["off_text"] = g["text"]
	match def_mode:
		"random":
			var d: Array = Library.plays_for("defense")
			dp = Library.play(d[rng.randi() % d.size()])
		"generated":
			var g := PlayGen.defense(rng)
			dp = g["play"]
			pending["def_text"] = g["text"]
	pending["off"] = op
	pending["def"] = dp
	pending["off_name"] = op.name
	pending["def_name"] = dp.name
	return pending


## A PlaySim for the pending call.
func make_sim() -> PlaySim:
	var sim := PlaySim.new()
	var ctx := {"yl": yl, "down": down, "to_go": to_go, "ball_x": ball_x, "quarter": quarter, "clock": clock,
		"score_diff": score[poss] - score[1 - poss]}
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	sim.setup(offense(), defense(), pending["off"], pending["def"], ctx, r)
	return sim


func _coach_call(c: Coach, on_offense: bool, team: int, count := true) -> Dictionary:
	var out := {"kind": "", "play": ""}
	var rules: Array = c.offense_rules if on_offense else c.defense_rules
	var act := func(id: String, a: Array) -> bool:
		match id:
			"call":
				var opts: Array = []
				for n in a[0]:
					var p: Play = Library.play(n)
					if p != null and p.side == ("offense" if on_offense else "defense"):
						opts.append(n)
				if opts.is_empty():
					return false
				out["kind"] = "play"
				out["play"] = opts[rng.randi() % opts.size()]
				return true
			"punt", "field_goal":
				return false   # no kicking in this game: the next rule decides
			"kneel":
				if not on_offense:
					return false
				out["kind"] = id
				return true
			"go_for_it":
				return true
		return false
	var sense := func(id: String, a: Array) -> bool:
		return _coach_sense(id, a, team, on_offense)
	Dsl.run(rules, sense, act, {}, 0.0, Coach.MODIFIERS, coach_tally[team] if count else {})
	if out["kind"] == "":
		var opts := Library.plays_for("offense" if on_offense else "defense")
		out["kind"] = "play"
		out["play"] = opts[rng.randi() % opts.size()]
	return out


## Which card in a dealt hand the coach would call: his own call from the playbook, matched to
## the closest play in the hand. {index, call} - call is the playbook play he had in mind.
func coach_suggest(on_offense: bool, hand: Array) -> Dictionary:
	var team := poss if on_offense else 1 - poss
	var c: Coach = (offense() if on_offense else defense())["coach"]
	var d := _coach_call(c, on_offense, team, false)
	var want: Play = Library.play(String(d.get("play", "")))
	if want == null:
		return {"index": -1, "call": String(d.get("kind", ""))}
	var fw := Play.features(want)
	var best := -1
	var best_d := INF
	for i in hand.size():
		var dist := Play.feature_distance(fw, Play.features(hand[i]["play"]))
		if dist < best_d:
			best_d = dist
			best = i
	return {"index": best, "call": want.name}


func _coach_sense(id: String, a: Array, team: int, on_offense: bool) -> bool:
	var diff: int = score[team] - score[1 - team]
	var to_goal := 100.0 - yl
	match id:
		"always": return true
		"chance": return rng.randf() < float(a[0])
		"down_is": return down == int(a[0])
		"first_down": return down == 1
		"second_down": return down == 2
		"third_down": return down == 3
		"fourth_down": return down == 4
		"to_go_over": return to_go > float(a[0])
		"to_go_under": return to_go < float(a[0])
		"goal_to_go": return yl + to_go >= 100.0
		"goal_within": return to_goal < float(a[0])
		"fg_range": return to_goal + 17.0 <= 52.0
		"own_goal_within": return yl < float(a[0])
		"backed_up": return yl < 10.0
		"red_zone": return to_goal <= 20.0
		"past_midfield": return yl > 50.0
		"leading_by": return diff > int(a[0])
		"trailing_by": return -diff > int(a[0])
		"winning": return diff > 0
		"losing": return diff < 0
		"tied": return diff == 0
		"quarter_is": return quarter == int(a[0])
		"clock_under": return clock < float(a[0])
		"half_ending": return (quarter == 2 or quarter == 4) and clock < 120.0
		"game_ending": return quarter == 4 and clock < 150.0
		"last_call_was": return last_call[team] == String(a[0])
		"last_gained_over": return last_gain[team] > float(a[0])
		"last_failed": return last_gain[team] < 3.0
		"avg_over", "avg_under":
			var c: Array = calls[team].get(String(a[0]), [0, 0.0])
			if int(c[0]) < 2:
				return false
			var avg := float(c[1]) / float(c[0])
			return avg > float(a[1]) if id == "avg_over" else avg < float(a[1])
		"called_over": return int(calls[team].get(String(a[0]), [0, 0.0])[0]) > int(a[1])
		"pass_avg_over", "pass_avg_under", "run_avg_over", "run_avg_under":
			var st: Dictionary = stats[team]
			var n := int(st["pass_att"]) if id.begins_with("pass") else int(st["rush_att"])
			if n < 3:
				return false
			var avg2 := (float(st["pass_yds"]) if id.begins_with("pass") else float(st["rush_yds"])) / n
			return avg2 > float(a[0]) if id.ends_with("over") else avg2 < float(a[0])
		"they_ran_last": return last_kind[1 - team] == "run"
		"they_passed_last": return last_kind[1 - team] == "pass"
		"they_run_over", "they_pass_over":
			var k: Dictionary = kinds[1 - team]
			var tot := int(k["run"]) + int(k["pass"])
			if tot < 4:
				return false
			var share := float(k["run"] if id == "they_run_over" else k["pass"]) / tot
			return share > float(a[0])
	return false


func _kneel() -> Dictionary:
	yl = maxf(yl - 1.0, 1.0)
	var e := {"kind": "kneel", "text": "%s take a knee." % offense()["name"]}
	_advance_down(-1.0)
	_tick(40.0, false)
	_log_play(e)
	return e


func _log_play(e: Dictionary) -> void:
	e["q"] = quarter
	e["clock"] = clock
	e["score"] = score.duplicate()
	log.append(e)


## The play is over: move the ball, the downs, the clock and the score.
func finish(sim: PlaySim) -> Dictionary:
	var r: Dictionary = sim.result
	var op: Play = pending["off"]
	var dp: Play = pending["def"]
	var team := poss
	var st: Dictionary = stats[team]
	var dst: Dictionary = stats[1 - team]
	plays_run += 1
	st["plays"] = int(st["plays"]) + 1
	drive["plays"] = int(drive["plays"]) + 1
	var gain := 0.0 if r["incomplete"] else float(r["y"])
	var was_down := down
	var was_to_go := to_go
	# the box score
	if r["pass"]:
		st["pass_att"] = int(st["pass_att"]) + 1
		if r.has("pass_yds"):
			st["comp"] = int(st["comp"]) + 1
			st["pass_yds"] = float(st["pass_yds"]) + gain
	elif r["sack"]:
		st["sacks"] = int(st["sacks"]) + 1
		st["sack_yds"] = float(st["sack_yds"]) + gain
	elif r.has("rush_yds"):
		st["rush_att"] = int(st["rush_att"]) + 1
		st["rush_yds"] = float(st["rush_yds"]) + gain
	var kind := "pass" if op.kind != "run" else "run"
	kinds[team][kind] = int(kinds[team][kind]) + 1
	last_kind[team] = kind
	last_call[team] = op.name
	last_call[1 - team] = dp.name
	var c: Array = calls[team].get(op.name, [0, 0.0])
	calls[team][op.name] = [int(c[0]) + 1, float(c[1]) + (gain if r["turnover"] == "" else -20.0)]
	var dc: Array = calls[1 - team].get(dp.name, [0, 0.0])
	calls[1 - team][dp.name] = [int(dc[0]) + 1, float(dc[1]) + (gain if r["turnover"] == "" else -20.0)]
	if was_down == 3:
		st["third_att"] = int(st["third_att"]) + 1
	if was_down == 4:
		st["fourth_att"] = int(st["fourth_att"]) + 1
	if gain >= 20.0:
		st["explosive"] = int(st["explosive"]) + 1
	var desc := _describe(sim, op, dp, gain)
	var e := {"kind": "play", "team": team, "off": op.name, "def": dp.name, "gain": gain, "why": r["why"], "text": desc,
		"down": was_down, "to_go": was_to_go, "yl": yl}
	down_event = ""
	_player_stats(sim, team, gain)
	if pending.get("off_text", "") != "":
		e["off_text"] = pending["off_text"]
	if pending.get("def_text", "") != "":
		e["def_text"] = pending["def_text"]
	var elapsed := float(r["t"])
	# the outcome
	if r.get("def_td", false):
		st["turnovers"] = int(st["turnovers"]) + 1
		st["ints"] = int(st["ints"]) + (1 if r["turnover"] == "int" else 0)
		dst["td"] = int(dst["td"]) + 1
		_pts(1 - team, 7)
		e["text"] += " Returned for a TOUCHDOWN!"
		drive["result"] = "pick six"
		_tick(elapsed, true)
		_kickoff(team)
	elif r["turnover"] != "":
		st["turnovers"] = int(st["turnovers"]) + 1
		if r["turnover"] == "int":
			st["ints"] = int(st["ints"]) + 1
		else:
			st["fumbles"] = int(st["fumbles"]) + 1
		drive["result"] = "INT" if r["turnover"] == "int" else "fumble"
		# no returns to the spot: every drive starts at the 25
		_tick(elapsed, true)
		_kickoff(1 - team)
	elif r.get("safety", false):
		_pts(1 - team, 7)
		e["text"] += " SAFETY - 7 points!"
		drive["result"] = "safety"
		_tick(elapsed, true)
		_kickoff(1 - team)
	elif r["td"]:
		st["td"] = int(st["td"]) + 1
		st["yards"] = float(st["yards"]) + gain
		drive["yards"] = float(drive["yards"]) + gain
		_pts(team, 7)
		drive["result"] = "TD"
		_tick(elapsed, true)
		_kickoff(1 - team)
	else:
		st["yards"] = float(st["yards"]) + gain
		drive["yards"] = float(drive["yards"]) + gain
		if not r["incomplete"]:
			ball_x = clampf(float(r["x"]), -HASH, HASH)
		yl = clampf(yl + gain, 0.5, 99.5)
		_advance_down(gain)
		var stops: bool = r["clock_stops"]
		_tick(elapsed + (0.0 if stops else _runoff(team)), stops)
	last_gain[team] = gain
	e["down_event"] = down_event
	_log_play(e)
	return e


func _runoff(team: int) -> float:
	# hurry up when behind late; milk it when ahead
	var diff: int = score[team] - score[1 - team]
	if (quarter == 4 or quarter == 2) and clock < 150.0 and diff <= 0:
		return 12.0
	if quarter == 4 and diff > 0:
		return 36.0
	return 27.0


func _advance_down(gain: float) -> void:
	var st: Dictionary = stats[poss]
	if gain >= to_go:
		if down == 3:
			st["third_conv"] = int(st["third_conv"]) + 1
		if down == 4:
			st["fourth_conv"] = int(st["fourth_conv"]) + 1
		st["first_downs"] = int(st["first_downs"]) + 1
		down_event = "first_down"
		down = 1
		to_go = minf(10.0, 100.0 - yl)
		return
	to_go -= gain
	down += 1
	if down > 4:
		down_event = "downs"
		drive["result"] = "downs"
		_kickoff(1 - poss)


## The player box score.
const PSTAT_KEYS := ["cmp", "att", "pyd", "ptd", "int", "sk", "skyd", "car", "ryd", "rtd", "rlong",
	"tgt", "rec", "recyd", "rectd", "reclong", "tkl", "sack", "dint", "pbu", "ff", "fr", "mt", "dtd", "fum"]


func _ps(t: int, slot: String) -> Dictionary:
	if slot == "":
		return {}
	if not pstats[t].has(slot):
		var d := {}
		for k in PSTAT_KEYS:
			d[k] = 0.0
		pstats[t][slot] = d
	return pstats[t][slot]


func _add(t: int, slot: String, k: String, v := 1.0) -> void:
	if slot == "":
		return
	var d := _ps(t, slot)
	d[k] = float(d[k]) + v


func _long(t: int, slot: String, k: String, v: float) -> void:
	if slot == "":
		return
	var d := _ps(t, slot)
	d[k] = maxf(float(d[k]), v)


func _player_stats(sim: PlaySim, off_t: int, gain: float) -> void:
	var r: Dictionary = sim.result
	var st: Dictionary = r["stat"]
	var def_t := 1 - off_t
	var offense_carrier := int(r.get("carrier_side", 0)) == 0
	if r["pass"]:
		var tgt := String(st.get("target", ""))
		if tgt != "":
			_add(off_t, "QB", "att")
			_add(off_t, tgt, "tgt")
		if r.has("pass_yds"):
			var rcv := String(st.get("catch_slot", ""))
			_add(off_t, "QB", "cmp")
			_add(off_t, "QB", "pyd", gain)
			_add(off_t, rcv, "rec")
			_add(off_t, rcv, "recyd", gain)
			_long(off_t, rcv, "reclong", gain)
			if r["td"] and offense_carrier:
				_add(off_t, "QB", "ptd")
				_add(off_t, rcv, "rectd")
		if r["turnover"] == "int":
			_add(off_t, "QB", "int")
	elif r["sack"]:
		_add(off_t, "QB", "sk")
		_add(off_t, "QB", "skyd", gain)
	elif r.has("rush_yds") or st.has("fumbler"):
		var ru := String(st.get("rusher", r["carrier"]))
		_add(off_t, ru, "car")
		if r.has("rush_yds"):
			_add(off_t, ru, "ryd", gain)
			_long(off_t, ru, "rlong", gain)
			if r["td"] and offense_carrier:
				_add(off_t, ru, "rtd")
	# defense (and offense, when they tackle after a turnover)
	for k in st:
		var ks := String(k)
		if ks.begins_with("sack:"):
			_add(def_t, ks.substr(5), "sack")
		elif ks.begins_with("int_by:"):
			_add(def_t, ks.substr(7), "dint")
		elif ks.begins_with("missed:"):
			_add(def_t if offense_carrier else off_t, ks.substr(7), "mt", float(st[k]))
		elif ks.begins_with("fumble:"):
			_add(off_t, ks.substr(7), "fum")
	if st.has("tackler") and r["why"] in ["tackle", "sack"] or (st.has("tackler") and st.has("ff_by")):
		_add(def_t if offense_carrier else off_t, String(st["tackler"]), "tkl")
	if st.has("pbu_by"):
		_add(def_t, String(st["pbu_by"]), "pbu")
	if st.has("ff_by"):
		_add(def_t, String(st["ff_by"]), "ff")
	if st.has("fr_by"):
		_add(def_t, String(st["fr_by"]), "fr")
	if r.get("def_td", false):
		_add(def_t, String(r["carrier"]), "dtd")


func _pts(t: int, n: int) -> void:
	score[t] += n
	line[t][clampi(quarter, 1, 4) - 1] += n


func _tick(secs: float, _stops: bool) -> void:
	var st: Dictionary = stats[poss]
	st["top"] = float(st["top"]) + minf(secs, clock)
	clock -= secs
	if clock <= 0.0:
		quarter_ends.append({"q": quarter, "score": score.duplicate(), "line": line.duplicate(true),
			"stats": stats.duplicate(true), "pstats": pstats.duplicate(true)})
		quarter += 1
		clock = qlen
		if quarter == 3:
			# second half: the other side receives
			_kickoff(1 - opened)
			_say("Second half. %s receive." % teams[poss]["name"])
		elif quarter > 4:
			over = true
			drive["result"] = drive.get("result", "") if drive.get("result", "") != "" else "end of game"
			drives.append(drive)
			_say("Final: %s %d, %s %d" % [teams[0]["name"], score[0], teams[1]["name"], score[1]])
		else:
			_say("End of quarter %d." % (quarter - 1))


func winner() -> int:
	if score[0] == score[1]:
		return -1
	return 0 if score[0] > score[1] else 1


func situation() -> String:
	var side := "own" if yl <= 50.0 else "opp"
	var line := int(round(yl if yl <= 50.0 else 100.0 - yl))
	var dn: String = ["", "1st", "2nd", "3rd", "4th"][clampi(down, 1, 4)]
	var tg := "Goal" if yl + to_go >= 100.0 else str(maxi(int(round(to_go)), 1))
	if line == 50:
		return "%s & %s at midfield" % [dn, tg]
	return "%s & %s, %s %d" % [dn, tg, side, line]


func _describe(sim: PlaySim, op: Play, dp: Play, gain: float) -> String:
	var r: Dictionary = sim.result
	var yd := int(round(gain))
	var s := ""
	var who := String(r["carrier"])
	match String(r["why"]):
		"incomplete", "broken up":
			s = "Pass incomplete" + (" (broken up)" if r["why"] == "broken up" else "")
		"sack":
			s = "SACKED for %d" % yd
		"td":
			s = "TOUCHDOWN %s, %d yards" % [who, yd]
		"out":
			s = "%s out of bounds, %+d" % [who, yd]
		_:
			if r["turnover"] == "int":
				s = "INTERCEPTED"
			elif r["turnover"] == "fumble":
				s = "FUMBLE, lost"
			elif r["pass"]:
				s = "Complete to %s, %+d" % [who, yd]
			else:
				s = "%s runs, %+d" % [who, yd]
	return "%s vs %s: %s" % [op.name, dp.name, s]


## Everything in one dictionary, for the result panel and the batch.
func summary() -> Dictionary:
	return {"line": line.duplicate(true), "pstats": pstats.duplicate(true), "score": score.duplicate(), "winner": winner(), "stats": stats.duplicate(true), "calls": calls.duplicate(true),
		"drives": drives.duplicate(true), "plays": plays_run, "coach_tally": coach_tally.duplicate(true)}
