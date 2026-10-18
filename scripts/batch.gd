class_name Batch
extends RefCounted
## Whole games with nothing drawn, and what they add up to.


static func play_game(red: Dictionary, blue: Dictionary, qlen: float, seed_v: int) -> Game:
	var g := Game.new()
	g.setup(red, blue, qlen, seed_v)
	var guard := 0
	while not g.over and guard < 400:
		guard += 1
		var snap := g.next_snap()
		if snap["kind"] != "play":
			continue
		var sim := g.make_sim()
		sim.run_to_end()
		g.finish(sim)
		_fold_tally(g, sim)
	return g


## Brain rule counts from a play, kept on the game: team -> brain -> line -> n
static func _fold_tally(g: Game, sim: PlaySim) -> void:
	if not g.has_meta("brain_tally"):
		g.set_meta("brain_tally", [{}, {}])
	var bt: Array = g.get_meta("brain_tally")
	for key in sim.tally:
		var parts := String(key).split(":", true, 1)
		var team := int(parts[0])
		var bn := parts[1]
		var d: Dictionary = bt[team].get(bn, {})
		for ln in sim.tally[key]:
			d[ln] = int(d.get(ln, 0)) + int(sim.tally[key][ln])
		bt[team][bn] = d


## Add up a list of finished games.
static func aggregate(games: Array) -> Dictionary:
	var out := {"pstats": [{}, {}], "line": [[0, 0, 0, 0], [0, 0, 0, 0]], "n": games.size(), "wins": [0, 0], "ties": 0, "points": [0, 0], "stats": [{}, {}],
		"calls": [{}, {}], "brain_tally": [{}, {}], "coach_tally": [{}, {}], "scores": []}
	for g in games:
		var gm: Game = g
		var w := gm.winner()
		if w < 0:
			out["ties"] += 1
		else:
			out["wins"][w] += 1
		out["scores"].append(gm.score.duplicate())
		for t in 2:
			out["points"][t] += gm.score[t]
			for q in 4:
				out["line"][t][q] += gm.line[t][q]
			for slot in gm.pstats[t]:
				if not out["pstats"][t].has(slot):
					var z := {}
					for k in Game.PSTAT_KEYS:
						z[k] = 0.0
					out["pstats"][t][slot] = z
				var acc: Dictionary = out["pstats"][t][slot]
				for k in Game.PSTAT_KEYS:
					if String(k).ends_with("long"):
						acc[k] = maxf(float(acc[k]), float(gm.pstats[t][slot][k]))
					else:
						acc[k] = float(acc[k]) + float(gm.pstats[t][slot][k])
			for k in gm.stats[t]:
				out["stats"][t][k] = float(out["stats"][t].get(k, 0.0)) + float(gm.stats[t][k])
			for n in gm.calls[t]:
				var c: Array = out["calls"][t].get(n, [0, 0.0])
				out["calls"][t][n] = [int(c[0]) + int(gm.calls[t][n][0]), float(c[1]) + float(gm.calls[t][n][1])]
			for ln in gm.coach_tally[t]:
				out["coach_tally"][t][ln] = int(out["coach_tally"][t].get(ln, 0)) + int(gm.coach_tally[t][ln])
			if gm.has_meta("brain_tally"):
				var bt: Array = gm.get_meta("brain_tally")
				for bn in bt[t]:
					var d: Dictionary = out["brain_tally"][t].get(bn, {})
					for ln in bt[t][bn]:
						d[ln] = int(d.get(ln, 0)) + int(bt[t][bn][ln])
					out["brain_tally"][t][bn] = d
	return out


static func line(agg: Dictionary, t: int) -> String:
	var n := maxi(int(agg["n"]), 1)
	var s: Dictionary = agg["stats"][t]
	var att := maxf(float(s.get("pass_att", 0)), 1.0)
	var ra := maxf(float(s.get("rush_att", 0)), 1.0)
	return "pts %.1f | comp %.0f%% %.1f ypa | rush %.1f ypc | sacks %.1f | INT %.2f fum %.2f | 3rd %.0f%% | plays %.0f | punts %.1f fg %.1f/%.1f" % [
		float(agg["points"][t]) / n, 100.0 * float(s.get("comp", 0)) / att, float(s.get("pass_yds", 0)) / att,
		float(s.get("rush_yds", 0)) / ra, float(s.get("sacks", 0)) / n, float(s.get("ints", 0)) / n,
		float(s.get("fumbles", 0)) / n, 100.0 * float(s.get("third_conv", 0)) / maxf(float(s.get("third_att", 0)), 1.0),
		float(s.get("plays", 0)) / n, float(s.get("punts", 0)) / n, float(s.get("fg", 0)) / n, float(s.get("fg_att", 0)) / n]
