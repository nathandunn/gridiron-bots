extends Node3D
## Entry point. In a browser: the stadium, the HUD and a game to watch. Headless:
##   godot --headless --path . -- --sim=20 --red=Balanced --blue="Air Raid" [--q=360] [--seed=1]
##   godot --headless --path . -- --lint=ai/01-qb-pocket-passer.ai
##   godot --headless --path . -- --plays=200 --red=... (per-call yards, no game clock)

var view: FieldView
var hud: Hud
var cam: BroadcastCam
var game: Game
var sim: PlaySim
var sfx: Sfx
var announcer: Announcer
var sound_mode := 0          # 0 sound and voice, 1 sound only, 2 muted
var red_coach := "Balanced"
var blue_coach := "Air Raid"
var coaches := ["Balanced", "Air Raid"]
var picks := [{}, {}]
var calling := ["pick", "coach"]   # Red: you pick from a hand of new plays; Blue: its coach
var _choice := {}                  # the person's picks for the coming snap
const HAND := 8   # how each side picks plays: coach / random / generated
var qlen := 300.0
var speed := 1.0
var paused := false
var _acc := 0.0
var _between := 0.0
var _phase := "idle"          # idle / presnap / live / after / kick / over
var _snap_info := {}
var _batch_left := 0
var _batch_games: Array = []
var _batch_seed := 0


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	Library.ensure()
	if args.has("k"):
		for kv in String(args["k"]).split(",", false):
			var pr := kv.split(":")
			PlaySim.K[pr[0]] = float(pr[1])
	if args.has("lint"):
		_lint(String(args["lint"]))
		return
	red_coach = String(args.get("red", red_coach))
	blue_coach = String(args.get("blue", blue_coach))
	coaches = [red_coach, blue_coach]
	qlen = float(args.get("q", qlen))
	for t in 2:
		var key: String = ["red", "blue"][t]
		if args.has(key + "call"):
			# --redcall=random | generated | coach
			calling[t] = String(args[key + "call"])
		if args.has(key + "picks"):
			# --redpicks=QB:Scrambler,WR:Burner
			for kv in String(args[key + "picks"]).split(",", false):
				var pr := kv.split(":")
				if pr.size() == 2:
					picks[t][pr[0].to_upper()] = pr[1].replace("_", " ")
	if args.has("sim") or args.has("plays") or DisplayServer.get_name() == "headless":
		_headless(args)
		return
	_build_ui()
	if args.has("speed"):
		set_speed(float(args["speed"]))
	for t in 2:
		var key: String = ["red", "blue"][t]
		if args.has(key + "call"):
			calling[t] = String(args[key + "call"])
	if args.has("redcall") or args.has("bluecall"):
		new_game()
	if args.has("swipetest"):
		await get_tree().create_timer(3.0).timeout
		_swipe_test()
		return
	if args.has("shot"):
		# --shot=out.png --at=6 [--panel=teams|editor|log] : a screenshot for checking the look
		# --on=tackle,big_hit : instead, the first of those moments after --at (shot --after later)
		var at := float(args.get("at", "6"))
		if args.has("view"):
			cam.set_view(String(args["view"]))
		await get_tree().create_timer(at).timeout
		if args.has("on"):
			var kinds := String(args["on"]).split(",")
			var hit := [false]
			view.moment.connect(func(a: Dictionary): if String(a["kind"]) in kinds: hit[0] = true)
			var waited := 0.0
			while not hit[0] and waited < 240.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
		match String(args.get("panel", "")):
			"teams": hud.open_teams()
			"editor": hud.open_editor("ai", String(args.get("name", "")))
			"coach": hud.open_editor("coach")
			"play": hud.open_editor("play")
			"log": hud.open_log()
			"batch": run_batch(int(args.get("n", "3")))
			"toast": hud.toast(String(args.get("text", "TURNOVER ON DOWNS\nBlue ball")).replace("|", "\n"), 5.0)
			"stats": hud._stats_tab = String(args.get("tab", "team")); hud.show_stats(game, "live")
		await get_tree().create_timer(float(args.get("after", "0.6"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(args["shot"]))
		get_tree().quit()


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	# the same keys on a web page's query string
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		for part in q.trim_prefix("?").split("&", false):
			var kv := part.split("=", true, 1)
			out[kv[0].uri_decode()] = kv[1].uri_decode().replace("+", " ") if kv.size() > 1 else "1"
	return out


func _lint(path: String) -> void:
	var kind := "ai"
	if path.ends_with(".coach"):
		kind = "coach"
	elif path.ends_with(".play"):
		kind = "play"
	var errs := Library.lint(kind, FileAccess.get_file_as_string(path))
	if errs.is_empty():
		print("OK ", path)
	for e in errs:
		print("ERROR ", e)
	get_tree().quit(0 if errs.is_empty() else 1)


func _headless(args: Dictionary) -> void:
	var seed_v := int(args.get("seed", "1"))
	var red := Team.build(0, red_coach, picks[0], calling[0])
	var blue := Team.build(1, blue_coach, picks[1], calling[1])
	if args.has("plays"):
		_play_lab(red, blue, int(args["plays"]), seed_v, args)
		get_tree().quit()
		return
	var n := int(args.get("sim", "1"))
	var games: Array = []
	var t0 := Time.get_ticks_msec()
	for i in n:
		# swap who is Red every other game so neither coach always gets the opening kick
		var g := Batch.play_game(red, blue, qlen, seed_v * 1000 + i)
		games.append(g)
		if args.has("verbose"):
			for e in g.log:
				print("Q%d %s  %d-%d  %s" % [e["q"], _clock(e["clock"]), e["score"][0], e["score"][1], e["text"]])
		print("game %d: %s %d - %d %s (%d plays)" % [i + 1, red_coach, g.score[0], g.score[1], blue_coach, g.plays_run])
	if args.has("box"):
		var lg: Game = games[games.size() - 1]
		for q in lg.quarter_ends:
			print("end of Q%d: %d-%d  line %s" % [q["q"], q["score"][0], q["score"][1], q["line"]])
		for t in 2:
			print("== ", Team.NAMES[t])
			for slot in lg.pstats[t]:
				var d: Dictionary = lg.pstats[t][slot]
				var parts := []
				for k in Game.PSTAT_KEYS:
					if float(d[k]) != 0.0:
						parts.append("%s %s" % [k, str(snappedf(float(d[k]), 0.1))])
				print("  %-5s %s" % [slot, " ".join(parts)])
		var gen := 0
		for e in lg.log:
			if e.has("off_text") and gen < 1:
				print(e["off_text"])
				gen += 1
	var agg := Batch.aggregate(games)
	print("--- %d games, %.1fs" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	print("%s wins %d, %s wins %d, ties %d" % [red_coach, agg["wins"][0], blue_coach, agg["wins"][1], agg["ties"]])
	for t in 2:
		print("%-16s %s" % [[red_coach, blue_coach][t], Batch.line(agg, t)])
	if args.has("calls"):
		for t in 2:
			print("== %s calls" % [red_coach, blue_coach][t])
			var c: Dictionary = agg["calls"][t]
			for nm in c:
				print("  %-16s %4d  %.1f" % [nm, c[nm][0], float(c[nm][1]) / maxf(float(c[nm][0]), 1.0)])
	if args.has("rules"):
		for t in 2:
			var bt: Dictionary = agg["brain_tally"][t]
			for bn in bt:
				var b: Brain = Library.brain(bn)
				for ln in bt[bn]:
					print("  %s | %s | %d" % [bn, b.rule_text(int(ln)) if b != null else str(ln), bt[bn][ln]])
	get_tree().quit()


## Every offensive play against every defensive play, from the 25 on 1st and 10: what it gains.
func _play_lab(red: Dictionary, blue: Dictionary, n: int, seed_v: int, args: Dictionary) -> void:
	var offs: Array = Library.plays_for("offense")
	var defs: Array = Library.plays_for("defense")
	if args.has("off"):
		offs = [String(args["off"])]
	if args.has("def"):
		defs = [String(args["def"])]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var yl := float(args.get("yl", "25"))
	for on in offs:
		var row := "%-15s" % on
		var tot := 0.0
		var cnt := 0
		var outs := {}
		var all_g: Array = []
		for dn in defs:
			var sum := 0.0
			for i in n:
				var s := PlaySim.new()
				var r := RandomNumberGenerator.new()
				r.seed = rng.randi()
				s.setup(red, blue, Library.play(on), Library.play(dn), {"yl": yl, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
				var res := {}
				if args.has("trace") and i == int(args.get("ti", "0")):
					var k := 0
					while not s.over and k < 600:
						s.step()
						k += 1
						if k % int(args.get("every", "9")) == 0:
							var parts := []
							for p in s.players:
								var near: bool = args["trace"] == "near" and s.carrier != null and p.pos.distance_to(s.carrier.pos) < 7.0
								if near or String(args["trace"]).split(",").has(p.slot) or args["trace"] == "all":
									parts.append("%s(%.1f,%.1f)%s%s%s" % [p.slot, p.pos.x, p.pos.y, "E" if p.engaged != null else "", "D" if p.down else "", ("[" + p.intent + "]") if p.intent != "assignment" else ""] + ("->" + p.block_target.slot if p.block_target != null else ""))
							print("t=%.1f ball=%s %s(%.1f,%.1f) | %s" % [s.t, s.ball_state, s.carrier.slot if s.carrier != null else "-", s.ball_pos.x, s.ball_pos.y, " ".join(parts)])
					res = s.result
				else:
					res = s.run_to_end()
				var gain := 0.0 if res["incomplete"] else float(res["y"])
				if res["turnover"] != "":
					gain = -25.0
				sum += gain
				all_g.append(gain)
				var w := String(res["why"]) + ("/" + String(res["turnover"]) if res["turnover"] != "" else "")
				if args.has("misses") and gain >= 20.0:
					var mi := 0
					for k in res["stat"]:
						if String(k).begins_with("missed:"):
							mi += int(res["stat"][k])
					w = "big, missed %d" % mi
				if args.has("tacklers") and gain < 0.0:
					w = "neg by " + String(res["stat"].get("tackler", "?")) + " t<%d" % int(ceil(res["t"]))
				outs[w] = int(outs.get(w, 0)) + 1
				if args.has("verbose") and i < int(args.get("vn", "2")):
					print(on, " v ", dn, ": ", res["why"], " ", snappedf(gain, 0.1), " ", " | ".join(res["events"].map(func(e): return "%.1f %s" % [e["t"], e["text"]])))
			row += " %6.1f" % (sum / n)
			tot += sum
			cnt += n
		all_g.sort()
		var big := all_g.filter(func(x): return x >= 20.0).size()
		var neg := all_g.filter(func(x): return x < 0.0).size()
		print(row, "   avg %.1f med %.1f  20+ %d%%  neg %d%%  " % [tot / cnt, all_g[all_g.size() / 2], 100 * big / cnt, 100 * neg / cnt], outs if args.has("outs") else "")
	print("columns: ", ", ".join(defs))


func _clock(c: float) -> String:
	var s := maxi(int(c), 0)
	return "%d:%02d" % [s / 60, s % 60]


## ---- watching a game -------------------------------------------------------------------------

const PRESNAP := 0.9
const AFTER := 1.4
var _wait := 0.0
var _skip_drive := false
var _batch_team := -1
var stop_at_quarters := true
var _seen_q := 0


func _build_ui() -> void:
	_scale_for_phone()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# night in a neon arena
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.5, 0.7)
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.1
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.07, 0.14)
	e.fog_density = 0.004
	env.environment = e
	add_child(env)
	# the light towers: a cool key light and a magenta rim
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.05, 0.45, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(0.85, 0.9, 1.0)
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.6, PI + 0.6, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(1.0, 0.35, 0.8)
	add_child(rim)
	view = FieldView.new()
	add_child(view)
	cam = BroadcastCam.new()
	cam.field = view
	add_child(cam)
	var vp := get_viewport().get_visible_rect().size
	cam.set_view("Arcade")
	sfx = Sfx.new()
	add_child(sfx)
	announcer = Announcer.new()
	add_child(announcer)
	view.moment.connect(_on_moment)
	view.trash_talk.connect(func(t: int, slot: String, line: String): announcer.trash(t, slot, line))
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.mark_view(cam.view)
	announcer.hud = hud
	new_game()


## A phone's canvas is in device pixels: scale the 2D up so the text is readable.
func _scale_for_phone() -> void:
	if not OS.has_feature("web"):
		return
	var dpr := DisplayServer.screen_get_scale()
	var w := get_viewport().get_visible_rect().size.x
	if dpr > 1.2 and w / dpr >= 300.0:
		get_tree().root.content_scale_factor = dpr


func new_game() -> void:
	game = Game.new()
	var seed_v := randi()
	game.setup(Team.build(0, coaches[0], picks[0], calling[0]), Team.build(1, coaches[1], picks[1], calling[1]), qlen, seed_v)
	sim = null
	_skip_drive = false
	_seen_q = 0
	_choice = {}
	hud.show_call("")
	hud.show_result("Kick-off: %s receive" % Team.NAMES[game.poss])
	_next()


func library_changed() -> void:
	# new edits take effect from the next snap: rebuild the teams' brains
	if game == null:
		return
	for t in 2:
		var nt := Team.build(t, coaches[t], picks[t], calling[t])
		game.teams[t]["coach"] = nt["coach"]
		game.teams[t]["brains"] = nt["brains"]
		game.teams[t]["calling"] = nt["calling"]


func overlay_changed(open: bool) -> void:
	cam.input_blocked = open


func _open_picker(side: String) -> void:
	_skip_drive = false
	_phase = "picking"
	var hand := PlayGen.hand(game.rng, side, HAND, game.to_go)
	var team: int = game.poss if side == "offense" else 1 - game.poss
	var coach := game.coach_suggest(side == "offense", hand)
	hud.open_picker(game, team, side, hand, coach)
	if OS.get_cmdline_user_args().has("--autopick"):
		# test hook: pick for the person (a random card)
		var kind := "off" if side == "offense" else "def"
		(func(): pick_made(kind, hand[randi() % hand.size()])).call_deferred()


## From the picker: kind is "off" / "def" (value: a generated {text, play}), "kick" ("punt" /
## "field_goal"), or "coach_off" / "coach_def" (let the coach call this one).
func pick_made(kind: String, value: Variant) -> void:
	_choice[kind] = value
	hud.close_overlay()
	_next()


func redeal(side: String) -> void:
	hud.close_overlay()
	_open_picker(side)


## Call out what just happened, big, in the middle of the screen.
func _announce(e: Dictionary, poss_before: int, score_before: Array) -> void:
	var r: Dictionary = sim.result
	var who: String = Team.NAMES[poss_before]
	var other: String = Team.NAMES[1 - poss_before]
	var st: Dictionary = r.get("stat", {})
	var scored: int = game.score[0] + game.score[1] - score_before[0] - score_before[1]
	if r.get("def_td", false):
		hud.toast("PICK SIX!\n%s score" % other if r.get("turnover", "") == "int" else "SCOOP AND SCORE!\n%s score" % other, 2.4)
	elif r.get("td", false) or scored >= 6:
		hud.toast("TOUCHDOWN!\n%s" % who, 2.4)
	elif r.get("safety", false):
		hud.toast("SAFETY!\n2 points %s" % other, 2.2)
	elif r.get("turnover", "") == "int":
		hud.toast("INTERCEPTED!\nby %s · %s ball" % [String(r.get("carrier", "")), other], 2.2)
	elif r.get("turnover", "") == "fumble":
		hud.toast("FUMBLE!\nRecovered by %s · %s ball" % [String(st.get("fr_by", "the defense")), other], 2.2)
	elif String(e.get("down_event", "")) == "downs":
		hud.toast("TURNOVER ON DOWNS\n%s ball" % other, 2.2)
	elif r.get("sack", false):
		hud.toast("SACK!", 1.2)
	elif String(e.get("down_event", "")) == "first_down":
		hud.toast("FIRST DOWN!\n%s" % who, 1.4)
	elif float(e.get("gain", 0.0)) >= 20.0:
		hud.toast("BIG GAIN! +%d" % int(round(float(e["gain"]))), 1.4)
	_call_result(e, r, who, other, scored)


## The announcer's last word on the play, and the crowd.
func _call_result(e: Dictionary, r: Dictionary, who: String, other: String, scored: int) -> void:
	if _skip_drive:
		return
	var gain := int(round(float(e.get("gain", 0.0))))
	var line := ""
	var big := true
	if r.get("def_td", false):
		line = "He's gone! %s take it back for six!" % other
	elif r.get("td", false) or scored >= 6:
		line = "TOUCHDOWN, %s!" % who
	elif r.get("safety", false):
		line = "Safety! Two points for %s." % other
	elif r.get("turnover", "") != "":
		line = "Turnover! %s ball." % other
	elif String(e.get("down_event", "")) == "downs":
		line = "Stopped short! %s take over on downs." % other
	elif r.get("incomplete", false):
		line = "Incomplete."
		big = false
	else:
		line = ("Gain of %d." % gain) if gain > 0 else (("Loss of %d." % -gain) if gain < 0 else "No gain.")
		big = false
		if String(e.get("down_event", "")) == "first_down":
			line += " First down, %s!" % who
			big = true
	announcer.result(line, big)
	if r.get("td", false) or r.get("def_td", false) or scored >= 6:
		sfx.play("roar", -2.0)
		var slot := String(r.get("carrier", ""))
		for p in sim.players:
			if p.slot == slot and (p == sim.carrier or sim.carrier == null):
				view.touchdown(p)
				break
	elif big or gain >= 12:
		sfx.play("roar", -9.0)


## A moment of the play, heard and called.
func _on_moment(a: Dictionary) -> void:
	if _skip_drive or sim == null:
		return
	sfx.on_action(String(a["kind"]))
	announcer.on_action(a, sim)


## Sound and voice, voice off, or quiet. Returns the button's new label.
func next_sound() -> String:
	sound_mode = (sound_mode + 1) % 3
	sfx.on = sound_mode < 2
	announcer.voice = sound_mode == 0
	if sound_mode != 0:
		announcer.stop()
	return ["Sound: voice", "Sound: on", "Sound: off"][sound_mode]


func resume_after_break() -> void:
	if _phase == "qbreak":
		_next()


func toggle_pause() -> void:
	paused = not paused
	hud.mark_paused(paused)


func set_speed(s: float) -> void:
	speed = s
	hud.mark_speed(s)


func next_view() -> String:
	return cam.next_view()


func skip_drive() -> void:
	_skip_drive = true


## Ask the coaches for the next snap; kicks resolve at once and are shown as a note.
func _next() -> void:
	hud.show_state(game)
	# a quarter just ended: show the box score and wait for Continue
	if game.quarter_ends.size() > _seen_q:
		_seen_q = game.quarter_ends.size()
		var snap: Dictionary = game.quarter_ends[_seen_q - 1]
		if not game.over and stop_at_quarters:
			_skip_drive = false
			_phase = "qbreak"
			hud.show_stats(game, "quarter", snap)
			return
	if game.over:
		sim = null
		view.set_play(null, game.poss, game.yl, game.to_go)
		_phase = "over"
		hud.show_result("Final")
		hud.show_game_over(game)
		return
	# a side the person calls: deal a hand of new plays and wait for the pick
	if game.calling_for(true) == "pick" and not (_choice.has("off") or _choice.has("coach_off")):
		_open_picker("offense")
		return
	if game.calling_for(false) == "pick" and not (_choice.has("def") or _choice.has("coach_def") or _choice.has("kick")):
		_open_picker("defense")
		return
	var poss_before := game.poss
	var snap := game.next_snap(_choice)
	_choice = {}
	if snap["kind"] != "play":
		hud.show_call("")
		hud.show_result(String(snap.get("text", "")))
		if snap["kind"] == "fg":
			hud.toast("FIELD GOAL IS GOOD!" if bool(snap.get("good", false)) else "NO GOOD!", 2.0)
		elif snap["kind"] == "punt":
			hud.toast("PUNT", 1.2)
		_phase = "kick"
		_wait = AFTER * 1.2
		if poss_before != game.poss:
			_skip_drive = false
		view.set_play(null, game.poss, game.yl, game.to_go)
		hud.show_state(game)
		return
	sim = game.make_sim()
	var team: String = Team.NAMES[game.poss]
	hud.show_call("%s: %s   vs   %s" % [team, snap["off_name"], snap["def_name"]])
	view.set_play(sim, game.poss, game.yl, game.to_go)
	announcer.presnap(game, String(snap["off_name"]), String(snap["def_name"]))
	_phase = "presnap"
	_wait = PRESNAP


func _process(delta: float) -> void:
	if hud == null or game == null:
		return
	if _batch_left > 0:
		_batch_step()
		return
	if _phase == "picking" and not hud.any_overlay():
		# the picker was closed: the coach calls this one
		var side := "coach_off" if game.calling_for(true) == "pick" and not (_choice.has("off") or _choice.has("kick") or _choice.has("coach_off")) else "coach_def"
		_choice[side] = true
		_next()
		return
	if _phase == "qbreak" and not hud.any_overlay():
		_next()   # the break panel was closed without Continue
		return
	if paused or hud.any_overlay() and _phase != "over":
		return
	var d := delta * speed
	if _skip_drive:
		d = 1e9
	match _phase:
		"presnap":
			_wait -= d
			if _wait <= 0.0:
				_phase = "live"
				_acc = 0.0
				hud.show_board(false)   # the scoreboard steps aside while the ball is live
		"live":
			_acc += minf(d, 10.0)
			var guard := 0
			while _acc >= PlaySim.DT and not sim.over and guard < 2000:
				sim.step()
				view.stepped()
				_acc -= PlaySim.DT
				guard += 1
			view.alpha = _acc / PlaySim.DT
			if sim.over:
				view.alpha = 1.0
				var poss_before := game.poss
				var score_before: Array = game.score.duplicate()
				Batch._fold_tally(game, sim)
				var e := game.finish(sim)
				hud.show_result(String(e["text"]))
				hud.show_state(game)
				sfx.play("whistle", -10.0)
				_announce(e, poss_before, score_before)
				hud.show_board(true)
				if randf() < 0.3:
					view.babble_now()
				if poss_before != game.poss:
					_skip_drive = false
				_phase = "after"
				_wait = AFTER
		"after", "kick":
			_wait -= d
			if _wait <= 0.0:
				_next()


## ---- a batch in the browser: one game a frame ------------------------------------------------

func run_batch(n: int) -> void:
	hud.close_overlay()
	_batch_left = n
	_batch_games = []
	_batch_seed = randi()
	paused = false
	hud.set_progress("Simulating %d games..." % n)


func _batch_step() -> void:
	var i := _batch_games.size()
	var g := Batch.play_game(Team.build(0, coaches[0], picks[0], calling[0]), Team.build(1, coaches[1], picks[1], calling[1]), qlen, _batch_seed + i)
	_batch_games.append(g)
	_batch_left -= 1
	hud.set_progress("Simulating... %d / %d" % [_batch_games.size(), _batch_games.size() + _batch_left])
	if _batch_left <= 0:
		hud.set_progress("")
		var agg := Batch.aggregate(_batch_games)
		hud.show_batch(agg, [coaches[0], coaches[1]])


## Test hook: a finger on a play card that slides must scroll and not pick; a tap must pick.
func _swipe_test() -> void:
	var sc: DragScroll = null
	var stack: Array = [hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is DragScroll:
			sc = n
		stack.append_array(n.get_children())
	if sc == null:
		print("SWIPE: no panel open")
		get_tree().quit(1)
		return
	var card: Control = null
	stack = [sc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).custom_minimum_size.y > 60 and sc.get_global_rect().has_point((n as Control).get_global_rect().get_center() + Vector2(0, 60)):
			card = n
		stack.append_array(n.get_children())
	var at := card.get_global_rect().get_center()
	var send := func(ev: InputEvent) -> void:
		Input.parse_input_event(ev)
		await get_tree().process_frame
	var down := func(p: Vector2, on: bool) -> InputEventMouseButton:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = on
		e.position = p
		e.global_position = p
		if on:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		return e
	print("SWIPE: start, card at ", at)
	var before := sc.scroll_vertical
	await send.call(down.call(at, true))
	for k in 12:
		var m := InputEventMouseMotion.new()
		m.position = at - Vector2(0, 25 * (k + 1))
		m.global_position = m.position
		m.relative = Vector2(0, -25)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		await send.call(m)
	await send.call(down.call(at - Vector2(0, 300), false))
	for k in 10:
		await get_tree().process_frame
	if not is_instance_valid(sc):
		print("SWIPE: FAILED - the slide picked a play")
		get_tree().quit(1)
		return
	var bar := sc.get_v_scroll_bar()
	print("SWIPE: scrolled %d -> %d (furthest it can go: %d), still picking: %s" % [before, sc.scroll_vertical, int(bar.max_value - bar.page), _phase == "picking"])
	# now a tap on a card that is on screen
	var target: Control = null
	stack = [sc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).custom_minimum_size.y > 60 and sc.get_global_rect().has_point((n as Control).get_global_rect().get_center()):
			target = n
			break
		stack.append_array(n.get_children())
	var c2 := target.get_global_rect().get_center()
	await send.call(down.call(c2, true))
	await send.call(down.call(c2, false))
	for k in 5:
		await get_tree().process_frame
	print("TAP: picked: %s (phase now %s)" % [_phase != "picking", _phase])
	get_tree().quit()
