class_name Announcer
extends Node
## The play-by-play man. Each call is shown as a caption across the top of the screen while the
## ball is live, and spoken aloud (the browser's own speech voice) when the voice is on. Big moments
## cut in; small ones wait their turn. Robots' trash talk gets their own tinny voices.

var hud: Hud
var voice := true
var _voice_id := ""
var _last_minor := -10.0
var _t := 0.0

const ORD := ["", "1st", "2nd", "3rd", "4th"]
const SAY_ORD := ["", "First", "Second", "Third", "Fourth"]


var _trash_q: Array = []   # [due, text, pitch]


func _process(delta: float) -> void:
	_t += delta
	# robots talk once the announcer takes a breath
	if not _trash_q.is_empty():
		var q: Array = _trash_q[0]
		if _t > float(q[0]) + 3.0:
			_trash_q.pop_front()
		elif _t > float(q[0]) and voice and _voice() != "" and not DisplayServer.tts_is_speaking():
			_trash_q.pop_front()
			DisplayServer.tts_speak(String(q[1]), _voice(), 75, float(q[2]), 1.3)


func _voice() -> String:
	if _voice_id == "":
		var v := DisplayServer.tts_get_voices_for_language("en")
		if not v.is_empty():
			_voice_id = v[0]
	return _voice_id


func _speak(text: String, interrupt: bool, pitch := 1.0, rate := 1.15, vol := 80) -> void:
	if not voice:
		return
	var id := _voice()
	if id == "":
		return
	if not interrupt and DisplayServer.tts_is_speaking():
		return
	DisplayServer.tts_speak(text, id, vol, pitch, rate, 0, interrupt)


func say(caption: String, spoken := "", big := false) -> void:
	if hud != null:
		hud.caption(caption, big)
	_speak(spoken if spoken != "" else caption, big)


func stop() -> void:
	if voice and _voice() != "":
		DisplayServer.tts_stop()


## Before the snap: down, distance, where, and the calls.
func presnap(g: Game, off_name: String, def_name: String) -> void:
	var team: String = Team.NAMES[g.poss]
	var other: String = Team.NAMES[1 - g.poss]
	var where := "midfield"
	if g.yl < 49.5:
		where = "their own %d" % int(round(g.yl))
	elif g.yl > 50.5:
		where = "the %s %d" % [other, int(round(100.0 - g.yl))]
	var dist := "goal" if g.yl + g.to_go >= 99.5 else str(int(ceil(g.to_go - 0.01)))
	var d := clampi(g.down, 1, 4)
	say("%s and %s at %s. %s calls %s, %s answers with %s." % [ORD[d], dist, where, team, off_name, other, def_name],
		"%s and %s at %s. %s, %s." % [SAY_ORD[d], dist, where, team, off_name], true)


## A moment in the play.
func on_action(a: Dictionary, sim: PlaySim) -> void:
	var pa: PlaySim.P = sim.players[int(a["a"])] if int(a["a"]) >= 0 else null
	var pb: PlaySim.P = sim.players[int(a["b"])] if int(a["b"]) >= 0 else null
	var na := _name(pa)
	var nb := _name(pb)
	var line := ""
	var big := false
	match String(a["kind"]):
		"throw":
			line = "%s fires for %s..." % [na, nb]
		"handoff":
			line = "Handoff to %s." % nb
		"catch":
			line = "Caught by %s!" % na
		"drop":
			line = "Dropped! Right through the hands of %s." % na
			big = true
		"pbu":
			line = "Broken up by %s!" % na
		"int":
			line = "INTERCEPTED! %s picks it off!" % na
			big = true
		"big_hit":
			line = "OHHH! What a hit by %s!" % na
			big = true
		"sack":
			line = "%s gets home! Sack!" % na
			big = true
		"tackle":
			line = "%s brings him down." % na
		"dive_tackle":
			line = "Diving stop by %s!" % na
		"miss":
			line = "%s breaks the tackle of %s!" % [nb, na]
			big = true
		"dive_miss":
			line = "%s dives... and comes up empty!" % na
		"juke":
			line = "%s with a juke!" % na
		"stiff_arm":
			line = "Stiff arm by %s!" % na
		"fumble":
			line = "FUMBLE! It's loose!"
			big = true
		"recover":
			line = "%s falls on it!" % na
			big = true
		"pancake":
			line = "%s pancakes %s!" % [na, nb]
	if line == "":
		return
	if hud != null:
		hud.caption(line, big)
	# small calls only when the voice is free, and not too many of them
	if big:
		_speak(line, true)
	elif _t - _last_minor > 0.9:
		_last_minor = _t
		_speak(line, false)


## The end of the play.
func result(text: String, big: bool) -> void:
	say(text, "", big)


## A robot mouths off, in a voice of its own.
func trash(team: int, slot: String, line: String) -> void:
	if hud != null:
		hud.caption("%s %s: “%s”" % [Team.NAMES[team], slot, line], false, Color(1, 0.55, 0.85))
	_trash_q = [[_t + 0.5, line, 0.45 if team == 0 else 1.75]]


func _name(p: PlaySim.P) -> String:
	if p == null:
		return "the defense"
	return "%s %s" % [Team.NAMES[p.team], p.slot]
