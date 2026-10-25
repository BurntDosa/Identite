#!/bin/zsh
# Builds the public source mirror from a private commit and pushes it as one sync commit.
# Usage: scripts/publish-public-mirror.sh <path-to-public-clone> [commit]
# The clone's origin must be github.com/BurntDosa/Identite; MIRROR_TEST_ORIGIN=<path> allows a local test remote.
set -euo pipefail

fail() { print -u2 "publish-public-mirror: $1"; exit 1; }

# grep with an explicit verdict: 0 = match, 1 = none, anything else aborts.
matches() {
  local code=0
  grep "$@" >/dev/null || code=$?
  (( code <= 1 )) || fail "grep failed ($code): $*"
  return $code
}

private=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
private=${private:A}
commit=$(git -C "$private" rev-parse --verify "${2:-HEAD}^{commit}")
sha=${commit[1,12]}
public=${${1:?path to a clone of BurntDosa/Identite}:A}

# The destination must be a separate, clean clone of the public mirror. Checked before anything is written.
[[ -d $public/.git ]] || fail "$public is not a Git checkout root"
[[ $(git -C "$public" rev-parse --show-toplevel) == $public ]] || fail "$public is not its repository root"
[[ $public != $private && $public != $private/* && $private != $public/* ]] || fail "destination overlaps the private repository"
[[ -z $(git -C "$public" status --porcelain --untracked-files=all) ]] || fail "destination has uncommitted or untracked changes"
origin=$(git -C "$public" remote get-url origin) || fail "destination has no origin"
if [[ -n ${MIRROR_TEST_ORIGIN:-} ]]; then
  [[ ${origin:A} == ${MIRROR_TEST_ORIGIN:A} ]] || fail "origin $origin is not the test remote"
else
  [[ $origin =~ '^(https://github\.com/|git@github\.com:)BurntDosa/Identite(\.git)?$' ]] || fail "origin $origin is not BurntDosa/Identite"
fi
if git -C "$public" rev-parse -q --verify HEAD >/dev/null; then
  ! git -C "$public" cat-file -e "$commit^{commit}" 2>/dev/null || fail "destination contains private history"
  git -C "$public" log --format=%s | while read -r subject; do
    [[ $subject == "Sync source from private main ("*")" ]] || fail "destination history has a non-sync commit: $subject"
  done
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
git -C "$private" archive "$commit" | tar -x -C "$stage"

# Private material: replica bank art and the scripts that drew it, bank reference images, review evidence,
# internal plans and prototypes.
excluded=(Prototypes docs/superpowers docs/release docs/design/references docs/design/build-review
  docs/design/prototype docs/design/mockups docs/design/assets docs/design/cardy/review DESIGN.md
  App/Shared/PersonalArt.xcassets docs/design/scripts/make-card-assets.swift docs/design/scripts/render-v4.swift
  docs/design/scripts/compare-hsbc.swift docs/design/scripts/make-gif.swift docs/design/scripts/render-menu-glyph.swift)
for entry in $excluded; do rm -rf "$stage/$entry"; done
mkdir -p "$stage/App/Shared/PersonalArt.xcassets"
print '{ "info" : { "author" : "xcode", "version" : 1 } }' > "$stage/App/Shared/PersonalArt.xcassets/Contents.json"

flagged=$(grep -rl 'PERSONAL_ART' --include='*.swift' "$stage") || (( $? == 1 )) || fail "scan for PERSONAL_ART failed"
for file in ${(f)flagged}; do
  unifdef -UPERSONAL_ART -o "$file" "$file" || (( $? == 1 )) || fail "unifdef failed on $file"  # 1 means changed
done

cat > "$stage/PUBLIC_MIRROR.md" <<'EOF'
# Public Source Mirror

This repository is generated from the private Identité project. It contains source code, card artwork, tests and documentation only. Replica bank artwork, reference images, review evidence and internal plans are intentionally excluded.

iPhone builds are distributed through TestFlight. The notarized Mac app is attached to Releases.
EOF

# Fail closed if anything private survived, by content as well as by name.
! matches -rl --include='*.swift' 'PERSONAL_ART' "$stage" || fail "PERSONAL_ART code remains"
private_blobs=$(git -C "$private" ls-tree -r "$commit" -- $excluded | awk '$2 == "blob" { print $3 }' | sort -u)
[[ -n $private_blobs ]] || fail "could not list excluded content"
# Asset-catalog Contents.json files are shared boilerplate metadata, not artwork.
exported_blobs=$(cd "$stage" && find . -type f ! -name Contents.json -print0 \
  | xargs -0 git hash-object | sort -u)
leaked=$(comm -12 <(print -r -- $private_blobs) <(print -r -- $exported_blobs))
[[ -z $leaked ]] || fail "excluded content survived under another name (blobs): ${leaked//$'\n'/ }"
for name in hsbc-white-wordmark hsbc-horizontal hdfc-bank PixelPlayWordmark PixelPlayTrophy MillenniaDoodleTile; do
  [[ -z $(find "$stage" -iname "*$name*") ]] || fail "replica asset remains: $name"
done

rsync -a --delete --exclude .git "$stage/" "$public/"
git -C "$public" add -A
git -C "$public" diff --cached --quiet || git -C "$public" commit -q -m "Sync source from private main ($sha)"
branch=$(git -C "$public" symbolic-ref --short HEAD)
git -C "$public" push -q origin "$branch"
[[ $(git -C "$public" ls-remote origin "refs/heads/$branch" | cut -f1) == $(git -C "$public" rev-parse HEAD) ]] \
  || fail "remote does not match the local mirror"
print "Published $sha to $origin ($branch)"
