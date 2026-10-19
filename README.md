# Gridiron Bots — robot football where the AI is the game

**Play:** https://gridiron-bots.apps.precogsoftwareservices.com

Eleven a side, four quarters, downs and distance — but you don't play the players, you write
them. Every decision in the game comes from a short, readable rule file, and every file can be
edited in the browser while you watch:

| Layer | Files | Decides |
|---|---|---|
| **Coach** | `coaches/*.coach` | Which play to call (down, distance, field position, score, clock, what has been working), punt or kick, and who plays where |
| **Play** | `plays/*.play` | The formation and every position's assignment (routes, blocks, gaps, rush, man, zone) |
| **Position brain** | `ai/*.ai` | How one player plays his assignment, ten times a second |

The rule language is [Rulebook](https://github.com/nathandunn/rulebook) (`addons/rulebook/`), the
same one behind [Drillbook Bots](https://github.com/nathandunn/drillbook-bots).

```
ai "Scrambler"
about "If the first look isn't there he's gone - and dangerous once he is."
position QB
dials risk 0.5 patience 0.3 discipline 0.4 vision 0.75 aggression 0.6

rules:
  when before the throw and drop done and first read open -> throw to first read
  when before the throw and pressure and not anyone open -> tuck and run
  when with the ball and past the line and one man to beat -> juke
  when with the ball and past the line -> run to daylight
  otherwise -> follow assignment
```

Rules are read top to bottom; the first that holds and can be done decides. Anything no rule
decides falls to the engine's default for the assignment, which reads the brain's **dials**
(aggression, risk, patience, discipline, vision) — so a one-line brain is still a whole player.

```
coach "Adaptive"
offense:
  when fourth down and in field goal range -> field goal
  when fourth down -> punt
  when "Power" averaging over 5 and chance 50% -> call "Power"
  when third down and to go over 6 -> call "Smash" or "Mesh" or "Four Verticals"
  otherwise -> call "Inside Zone" or "Slants" or "Curl Flat"
defense:
  when they run over 60% -> call "Run Blitz" or "Cover 1"
  otherwise -> call "Cover 3" or "Cover 2"
lineup:
  QB "Pocket Passer"
  CB "Ball Hawk"
```

## The look
A neon robot-football arena: dark steel field with glowing lines and lit rails, arena walls with
light panels, light towers, and armoured robots with visor lights in team colours (hot red vs
electric blue) that stride as they run. The default **Arcade** camera looks down steeply from
behind the offense and scrolls with the ball; Behind / Sideline / Overhead are still a tap away.
Real football rules, 11 a side.

## In the app
- **Teams** — a coach per side and a brain per position (or the coach's pick), game length.
- **Edit AI** — every coach, play and brain in an editor: live lint with line numbers and
  *did you mean …* suggestions, a word list per file kind (tap to insert, with an example),
  completion after a space, Save / Reset to shipped / Copy as new. Edits are kept in the browser
  and used from the next snap.
- **Call your own plays** (Red's default): each down you're dealt a hand of 8 brand-new plays —
  offense or defense — each card with a chalkboard diagram drawn from the engine's own alignment
  (routes, run path, blocks; zones, man lines, blitz arrows). Tap one, deal a new hand, or let the
  coach call it; on 4th down you can punt or kick. Set both sides to *You pick* for two players.
- **Play calling** (Teams panel, per side, offense and defense): *You pick*, *Coach calls*, *Random from
  playbook* (any play, every down), or *Random new plays* — a fresh play made up every down
  (`scripts/play_gen.gd`: formation, routes and depths, run gaps and pulls, shells, man matchups
  and blitzes), written as ordinary play text. The coach still decides punts and field goals.
  Generated plays can be saved to the playbook from the Log.
- **Box scores** — line score by quarter, team box and a player box per side (passing, rushing,
  receiving, defense: tackles, sacks, INTs, PBUs, forced fumbles). The game stops at each quarter
  break and at the end; **Stats** shows it any time; Sim ×N gives per-game averages.
- **Sim ×10 / ×50** — whole games with nothing drawn: wins, box score, yards a call for every
  play, and which coach and brain rules did the work.
- **Log** — play by play. **Views** — behind the offense (phones), sideline, overhead.

## Headless
```
godot --headless --path . -- --sim=20 --red=Balanced --blue="Air Raid" [--q=300] [--calls] [--rules]
godot --headless --path . -- --plays=20 [--off=Smash] [--def="Cover 2"]    # play-vs-play lab
godot --headless --path . -- --lint=ai/02-qb-gunslinger.ai
godot --headless --path . -- --sim=20 --redpicks=QB:Scrambler,CB:Ball_Hawk
godot --headless --path . -- --sim=1 --redcall=generated --bluecall=random --box  # box score by quarter
godot --headless --path . -- --sim=20 --k=tackle:0.9,throw_err:1.5         # engine knobs
```

## Engine (`scripts/`)
- `play_sim.gd` — one play in yards and seconds: routes with press jams and reaction lag, pass
  sets and area run blocking that turns men away from the hole, shedding, a QB's drop and read
  progression, lead passes with distance error, catch / break-up / interception at the catch
  point, a runner who steers by ground gained against who can reach him, pursuit angles,
  tackles (wrap up, hit hard, strip, dive), fumbles, the pile surging at the line.
- `game.gd` — quarters, clock and run-off, downs, punts and field goals rolled, PATs, the box score.
- `brain.gd`, `coach.gd`, `play.gd` — the three file kinds and their vocabularies.
- `field_view.gd`, `broadcast_cam.gd`, `hud.gd`, `main.gd` — the stadium, camera and UI.

Bodies are the same for every team at a position: the contest is between the brains.

## Build
`./build.sh` (Godot 4.7.2 + web templates) exports to `dist/`; the Dockerfile serves it with nginx.
