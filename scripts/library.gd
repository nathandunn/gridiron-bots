class_name Library
extends RefCounted
## Gridiron's rule files on top of the Rulebook addon: coaches, plays and position brains, and
## the cross-checks between them (a coach may only call plays and pick brains that exist).

const KINDS := ["coach", "play", "ai"]
static var _registered := false


static func ensure() -> void:
	if not _registered:
		_registered = true
		RuleLibrary.EDITS = "user://gridiron_edits.json"
		RuleLibrary.register("coach", "res://coaches", ".coach", Coach.parse, _check_coach)
		RuleLibrary.register("play", "res://plays", ".play", Play.parse)
		RuleLibrary.register("ai", "res://ai", ".ai", Brain.parse)
	RuleLibrary.ensure()


static func _check_coach(c: Coach) -> Array[String]:
	var errs: Array[String] = []
	for p in c.plays_called():
		if RuleLibrary.get_obj("play", p) == null:
			errs.append("no play called \"%s\"" % p)
	for k in c.lineup:
		var b: Brain = RuleLibrary.get_obj("ai", c.lineup[k])
		if b == null:
			errs.append("no brain called \"%s\"" % c.lineup[k])
		elif b.group != Play.SLOT_GROUP.get(k, k):
			errs.append("\"%s\" is a %s brain, not %s" % [b.name, b.group, Play.SLOT_GROUP.get(k, k)])
	return errs


static func names(kind: String) -> Array:
	ensure()
	return RuleLibrary.names(kind)


static func get_obj(kind: String, n: String) -> Variant:
	ensure()
	return RuleLibrary.get_obj(kind, n)


static func coach(n: String) -> Coach:
	return get_obj("coach", n)


static func play(n: String) -> Play:
	return get_obj("play", n)


static func brain(n: String) -> Brain:
	return get_obj("ai", n)


static func brains_for(group: String) -> Array:
	return names("ai").filter(func(n): return (brain(n) as Brain).group == group)


static func plays_for(side: String) -> Array:
	return names("play").filter(func(n): return (play(n) as Play).side == side)


static func source(kind: String, n: String) -> String:
	ensure()
	return RuleLibrary.source(kind, n)


static func lint(kind: String, text: String) -> Array[String]:
	ensure()
	return RuleLibrary.lint(kind, text)


static func save(kind: String, text: String) -> Array:
	ensure()
	return RuleLibrary.save(kind, text)


static func reset(kind: String, n: String) -> void:
	ensure()
	RuleLibrary.reset(kind, n)


static func is_edited(kind: String, n: String) -> bool:
	ensure()
	return RuleLibrary.is_edited(kind, n)


## The pattern tables behind a kind of file, for the editor's word list.
static func tables(kind: String) -> Dictionary:
	match kind:
		"coach": return {"conditions": Coach.CONDITIONS, "actions": Coach.ACTIONS}
		"ai": return {"conditions": Brain.CONDITIONS, "actions": Brain.ACTIONS}
	return {}
