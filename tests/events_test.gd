extends SceneTree
func _init() -> void:
	Library.ensure()
	var g := Batch.play_game(Team.build(0, "Balanced"), Team.build(1, "Air Raid"), 300.0, 3)
	var n := {}
	for e in g.log:
		var k := String(e.get("down_event", ""))
		if k != "":
			n[k] = int(n.get(k, 0)) + 1
		if String(e.get("text", "")).find("INTERCEPTED") >= 0 or String(e.get("text", "")).find("FUMBLE") >= 0:
			n["turnover"] = int(n.get("turnover", 0)) + 1
	print("EVENTS ", n, " first downs in box: ", g.stats[0]["first_downs"] + g.stats[1]["first_downs"])
	quit()
