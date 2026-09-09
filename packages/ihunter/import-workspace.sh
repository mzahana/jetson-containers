#!/usr/bin/env bash
#
# import-workspace.sh -- clone the ROS 2 workspace from ihunter.repos, pinned.
#
#   ./import-workspace.sh [manifest] [dest-root] [--force]
#
# Why not vcstool: `python3-vcstool` is NOT in Ubuntu's archive. It comes from
# the ROS apt repo, which this board deliberately does not have -- ROS lives in
# the container, not on the host. Requiring it meant a fresh board failed
# bootstrap with "E: Unable to locate package python3-vcstool". git and
# python3-yaml (both in Ubuntu main) are enough to do the same job.
#
# An existing checkout is never modified without --force. On a vehicle, silently
# moving a package to a different commit is how a board ends up flying something
# nobody chose; the mismatch is reported instead, and moving it is a decision.
#
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
MANIFEST="${1:-$HERE/ihunter.repos}"
DEST="${2:-$HOME/ihunter_shared_volume}"
FORCE=0
for a in "$@"; do [ "$a" = "--force" ] && FORCE=1; done

G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; X=$'\033[0m'
ok()   { echo "  ${G}ok${X}   $*"; }
warn() { echo "  ${Y}warn${X} $*"; }
bad()  { echo "  ${R}fail${X} $*"; }

[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || {
    echo "python3-yaml is required: sudo apt install -y python3-yaml" >&2; exit 1; }

# path<TAB>url<TAB>version, one per line
entries="$(python3 - "$MANIFEST" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
for path, spec in (doc.get('repositories') or {}).items():
    print('%s\t%s\t%s' % (path, spec['url'], spec.get('version', '')))
PY
)"

fail=0; skipped=0; cloned=0; drift=0
while IFS=$'\t' read -r path url version; do
    [ -n "$path" ] || continue
    target="$DEST/$path"
    name="$(basename "$path")"

    if [ -d "$target/.git" ]; then
        have="$(git -C "$target" rev-parse HEAD 2>/dev/null || echo unknown)"
        dirty="$(git -C "$target" status --porcelain 2>/dev/null | head -1)"
        if [ "$have" = "$version" ]; then
            ok "$name at the pinned commit"
        elif [ "$FORCE" = 1 ]; then
            [ -n "$dirty" ] && { bad "$name has local changes -- refusing to move it"; fail=$((fail+1)); continue; }
            git -C "$target" fetch -q origin && git -C "$target" checkout -q "$version" \
                && ok "$name moved to the pinned commit" || { bad "$name could not move to $version"; fail=$((fail+1)); }
        else
            drift=$((drift+1))
            warn "$name is at ${have:0:9}, manifest pins ${version:0:9} (use --force to move it)"
        fi
        [ -n "$dirty" ] && warn "$name has uncommitted local changes"
        skipped=$((skipped+1))
        continue
    fi

    mkdir -p "$(dirname "$target")"
    if ! git clone -q "$url" "$target" 2>/dev/null; then
        case "$url" in
            git@*) bad "$name: clone failed. Private repo -- is this board's deploy key added?" ;;
            *)     bad "$name: clone failed from $url" ;;
        esac
        fail=$((fail+1)); continue
    fi
    if [ -n "$version" ] && ! git -C "$target" checkout -q "$version" 2>/dev/null; then
        warn "$name: cloned, but '$version' could not be checked out (left on the default branch)"
    else
        ok "$name cloned at ${version:0:9}"
    fi
    cloned=$((cloned+1))
done <<< "$entries"

echo
echo "  $cloned cloned, $skipped already present, $drift not at the pinned commit, $fail failed"
[ "$fail" -eq 0 ]
