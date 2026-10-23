extends SceneTree
## Every play reports its moments (tackles, catches, drops, misses...) for the field to act out.
func _init() -> void:
	Library.ensure()
	var n := {}
	var g := Game.new()
	g.setup(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 7)
	var plays := 0
	while not g.over and plays < 400:
		var snap := g.next_snap()
		if snap["kind"] != "play":
			continue
		var sim := g.make_sim()
		sim.run_to_end()
		for a in sim.actions:
			n[a["kind"]] = int(n.get(a["kind"], 0)) + 1
		g.finish(sim)
		plays += 1
	print("ACTIONS over ", plays, " plays: ", n)
	quit()
