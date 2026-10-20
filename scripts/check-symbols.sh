#!/usr/bin/env bash
# Check that every CONFIG_X in a fragment has a Kconfig entry in the tree.
# Catches the silent-drop class: a symbol with no Kconfig entry is accepted by
# merge_config.sh and then vanishes in olddefconfig with no error.
#
# Usage: ./scripts/check-symbols.sh configs/wireless.fragment [more.fragment ...]
#        SRC=/path/to/kernel (default <repo>/src/kernel)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$ROOT/src/kernel}
[ -d "$SRC" ] || { echo "no kernel tree at $SRC" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <fragment> [...]" >&2; exit 2; }

bad=0
for frag in "$@"; do
  echo "== $frag"
  while read -r line; do
    case $line in
      CONFIG_*=*) sym=${line%%=*}; sym=${sym#CONFIG_} ;;
      *) continue ;;
    esac
    if grep -rqE "^[[:space:]]*(menu)?config ${sym}$" --include='Kconfig*' "$SRC" 2>/dev/null; then
      printf '  OK       %s\n' "$sym"
    else
      printf '  NO ENTRY %s\n' "$sym"; bad=1
    fi
  done < "$frag"
done

[ "$bad" = 0 ] || { echo "some symbols have no Kconfig entry" >&2; exit 1; }
echo "OK: all symbols have Kconfig entries"
