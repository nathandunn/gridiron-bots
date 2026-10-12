#!/usr/bin/env bash
# usage: tools/grid.sh "tackle:0.7,evade:1.0" [games]
cd "$(dirname "$0")/.."
godot --headless --path . -- --sim=${2:-20} --red=Balanced --blue=Balanced --k="$1" 2>&1 | grep -E "^Balanced " | head -2 | sed "s/^/[$1] /"
