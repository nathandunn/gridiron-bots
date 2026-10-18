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
var red_coach := "Balanced"
var blue_coach := "Air Raid"
var coaches := ["Balanced", "Air Raid"]
var picks := [{}, {}]
var calling := ["coach", "coach"]   # how each side picks plays: coach / random / generated
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
	if args.has("shot"):
		# --shot=out.png --at=6 [--panel=teams|editor|log] : a screenshot for checking the look
		var at := float(args.get("at", "6"))
		await get_tree().create_timer(at).timeout
		match String(args.get("panel", "")):
			"teams": hud.open_teams()
			"editor": hud.open_editor("ai", String(args.get("name", "")))
			"coach": hud.open_editor("coach")
			"play": hud.open_editor("play")
			"log": hud.open_log()
			"batch": run_batch(int(args.get("n", "3")))
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
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.62, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.5, 0)
	sun.light_energy = 1.1
	add_child(sun)
	view = FieldView.new()
	add_child(view)
	cam = BroadcastCam.new()
	cam.field = view
	add_child(cam)
	var vp := get_viewport().get_visible_rect().size
	cam.set_view("Behind" if vp.y > vp.x else "Sideline")
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.mark_view(cam.view)
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
	var poss_before := game.poss
	var snap := game.next_snap()
	if snap["kind"] != "play":
		hud.show_call("")
		hud.show_result(String(snap.get("text", "")))
		if snap["kind"] == "fg" and bool(snap.get("good", false)):
			hud.toast("FIELD GOAL")
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
	_phase = "presnap"
	_wait = PRESNAP


func _process(delta: float) -> void:
	if hud == null or game == null:
		return
	if _batch_left > 0:
		_batch_step()
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
				if game.score[0] + game.score[1] - score_before[0] - score_before[1] >= 6:
					hud.toast("TOUCHDOWN")
				elif e.get("why", "") == "sack":
					hud.toast("SACK", 1.0)
				elif sim.result.get("turnover", "") != "":
					hud.toast("TURNOVER")
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
