#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != *.ssa ]]; then
    echo "Usage: $0 <filename>.ssa" >&2
    exit 1
fi

input=$1
base=${input%.ssa}

qbe -t amd64_win -o "${base}.s" "$input"
gcc "${base}.s" -o "${base}.exe"
"./${base}.exe"

## THANK YOU CLANKER FOR THIS!!!
