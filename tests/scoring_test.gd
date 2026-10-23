extends SceneTree
## No kicking: every score is a 7, and the coach's starred card matches his own call's shape.
func _init() -> void:
	Library.ensure()
	var bad := 0
	for s in 20:
		var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, s)
		for t in 2:
			if g.score[t] % 7 != 0:
				bad += 1
	print("SCORES not a multiple of 7: ", bad)
	var g := Game.new()
	g.setup(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 1)
	var same := 0
	var n := 0
	for i in 200:
		var side := "offense" if i % 2 == 0 else "defense"
		var hand := PlayGen.hand(g.rng, side, 8, g.to_go)
		var c := g.coach_suggest(side == "offense", hand)
		if int(c["index"]) < 0:
			continue
		n += 1
		var want: Play = Library.play(String(c["call"]))
		var got: Play = hand[int(c["index"])]["play"]
		if side == "offense":
			if (want.kind == "run") == (got.kind == "run"):
				same += 1
		else:
			same += 1 if absf(float(Play.features(want)["rush"]) - float(Play.features(got)["rush"])) <= 2.0 else 0
	print("COACH PICK matches the call's shape: %d / %d" % [same, n])
	quit()
