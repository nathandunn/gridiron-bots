#!/usr/bin/env bash
# Round robin of every coach pair: tools/robin.sh [games] [extra args]
cd "$(dirname "$0")/.."
N=${1:-16}; shift || true
C=("Balanced" "Air Raid" "Ground and Pound" "Adaptive" "Option Run")
run() { godot --headless --path . -- --sim=$N --red="$1" --blue="$2" "${@:3}" 2>&1 | grep -E "wins" | sed "s/^/[$1 v $2] /"; }
jobs_=0
for ((i=0;i<${#C[@]};i++)); do for ((j=i+1;j<${#C[@]};j++)); do
  run "${C[i]}" "${C[j]}" "$@" &
  jobs_=$((jobs_+1)); if (( jobs_ % 2 == 0 )); then wait; fi
done; done; wait
