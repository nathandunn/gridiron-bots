#!/usr/bin/env bash
# Each alternative brain swapped into Blue's Balanced lineup vs a plain Balanced Red.
cd "$(dirname "$0")/.."
N=${1:-20}
ALTS=("QB:Gunslinger" "QB:Scrambler" "QB:Game_Manager" "RB:Power_Back" "RB:Scatback" "WR:Burner" "WR:Possession_Receiver" "TE:Blocking_TE" "OL:Road_Grader" "DL:Speed_Rusher" "LB:Thumper" "CB:Ball_Hawk" "S:Enforcer")
one() { godot --headless --path . -- --sim=$N --red=Balanced --blue=Balanced --bluepicks="$1" 2>&1 | awk -v k="$1" '/wins/{w=$0} /^Balanced /{n++; if(n==1) r=$0; else b=$0} END{split(r,ra,"pts "); split(b,ba,"pts "); printf "%-26s %s || base pts %s\n", k, substr(ba[2],1,60), substr(ra[2],1,5)}'; }
i=0; for a in "${ALTS[@]}"; do one "$a" & i=$((i+1)); (( i % 2 == 0 )) && wait; done; wait
