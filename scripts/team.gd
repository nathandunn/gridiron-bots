class_name Team
extends RefCounted
## A side: a coach and a brain in every slot. Who plays where comes, first to last, from the
## viewer's picks for the slot, their picks for the position group, the coach's lineup for the
## slot, the coach's lineup for the group, and the first brain of that position.

const NAMES := ["Red", "Blue"]
const COLORS := [Color(0.82, 0.16, 0.14), Color(0.16, 0.36, 0.86)]


static func build(index: int, coach_name: String, picks: Dictionary = {}, calling := "coach") -> Dictionary:
	var c: Coach = Library.coach(coach_name)
	if c == null:
		c = Library.coach(Library.names("coach")[0])
	var brains := {}
	for s in Play.OFFENSE_SLOTS + Play.DEFENSE_SLOTS:
		brains[s] = brain_for(c, s, picks)
	return {"index": index, "name": NAMES[index], "coach": c, "brains": brains, "picks": picks.duplicate(), "calling": calling}


static func brain_for(c: Coach, slot: String, picks: Dictionary) -> Brain:
	var g: String = Play.SLOT_GROUP[slot]
	for n in [picks.get(slot, ""), picks.get(g, ""), c.lineup.get(slot, ""), c.lineup.get(g, "")]:
		if n != "":
			var b: Brain = Library.brain(n)
			if b != null and b.group == g:
				return b
	var opts := Library.brains_for(g)
	return Library.brain(opts[0]) if not opts.is_empty() else null
