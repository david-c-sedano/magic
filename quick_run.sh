#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || "$1" != *.ssa ]]; then
    echo "Usage: $0 <filename>.ssa [gcc linker flags...]" >&2
    exit 1
fi

input=$1
base=${input%.ssa}
shift

qbe -t amd64_win -o "${base}.s" "$input"
gcc "${base}.s" -o "${base}.exe" "$@"

exe="${base}.exe"
if [[ "$exe" != /* && "$exe" != ./* && "$exe" != ../* ]]; then
    exe="./$exe"
fi

"$exe"

# THANK YOU CLANKER FOR THIS!!!
# NOTE: TO COMPILE RAYLIB EXAMPLE DO
# odin run . --debug -- -file:tests/rl_window.magic -out:rl_window.ssa -include-paths:./raylib
# ./quick_run.sh rl_window.ssa -Lraylib -lraylib -lopengl32 -lgdi32 -lwinmm
# MAKE SURE TO PASS `--debug` SO YOU CAN SEE WHAT AN AST+IR LOOK LIKE!!
