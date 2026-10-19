extends SceneTree
func _init() -> void:
	Library.ensure()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bad := 0
	var red := Team.build(0, "Balanced")
	var blue := Team.build(1, "Balanced")
	var gains := {"run": [], "pass": []}
	var whys := {}
	for i in 400:
		var o: Dictionary = PlayGen.offense(rng)
		var d: Dictionary = PlayGen.defense(rng)
		if not o["play"].errors.is_empty() or not d["play"].errors.is_empty():
			bad += 1
			print(o["play"].errors, d["play"].errors)
			continue
		var s := PlaySim.new()
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		s.setup(red, blue, o["play"], d["play"], {"yl": 30.0, "down": 1, "to_go": 10.0, "ball_x": 0.0, "quarter": 1, "clock": 600, "score_diff": 0}, r)
		var res := s.run_to_end()
		var g := 0.0 if res["incomplete"] else float(res["y"])
		gains[o["play"].kind].append(g)
		whys[res["why"]] = int(whys.get(res["why"], 0)) + 1
		if i == 0:
			print(o["text"])
			print(d["text"])
	print("bad: ", bad)
	for k in gains:
		var a: Array = gains[k]
		a.sort()
		var sum := 0.0
		for x in a:
			sum += x
		print("%s n=%d avg %.1f med %.1f" % [k, a.size(), sum / maxf(a.size(), 1), a[a.size() / 2] if a.size() > 0 else 0.0])
	print(whys)
	quit()
