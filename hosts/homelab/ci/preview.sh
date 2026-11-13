# homelab-preview <new system> [title]: markdown report of what deploying
# <new system> would change compared with the running one: package versions
# per container and for the whole system, and CVEs (vulnix) fixed / new.
new=$(readlink -f "${1:?new system}")
title=${2:-}
cur=$(readlink -f /run/current-system)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "## Deploy preview${title:+: $title}"
echo
echo "Running \`$(basename "$cur")\` → \`$(basename "$new")\`"
echo

conf() { sed -n 's/^SYSTEM_PATH=//p' "$1" 2>/dev/null || true; }

echo "### Containers"
echo
changed=0
for f in "$new"/etc/nixos-containers/*.conf; do
  c=$(basename "$f" .conf)
  n=$(conf "$f")
  o=$(conf "/etc/nixos-containers/$c.conf")
  [ "$n" = "$o" ] && continue
  changed=$((changed + 1))
  if [ -z "$o" ]; then
    echo "- **$c**: new container"
    continue
  fi
  echo "<details><summary><b>$c</b></summary>"
  echo
  echo '```'
  { nvd diff "$o" "$n" || true; } | tail -n +3
  echo '```'
  echo "</details>"
done
[ "$changed" = 0 ] && echo "No container changes."
echo

echo "### Whole system (host + all containers)"
echo
echo "<details><summary>package versions</summary>"
echo
echo '```'
{ nvd diff "$cur" "$new" || true; } | tail -n +3
echo '```'
echo "</details>"
echo

# vulnix matches package names/versions against the NVD: a hint, not a
# verdict (false positives, patches nixpkgs backported without a version bump).
cves() {
  { vulnix --json --cache-dir "${VULNIX_CACHE:-$HOME/.cache/vulnix}" "$1" 2>/dev/null || true; } \
    | jq -r '.[]? | .name as $p | .affected_by[]? | "\(.)\t\($p)"' | sort -u
}
cves "$cur" > "$tmp/old"
cves "$new" > "$tmp/new"
cut -f1 "$tmp/old" | sort -u > "$tmp/old-ids"
cut -f1 "$tmp/new" | sort -u > "$tmp/new-ids"
comm -23 "$tmp/old-ids" "$tmp/new-ids" > "$tmp/fixed"
comm -13 "$tmp/old-ids" "$tmp/new-ids" > "$tmp/added"

cvelist() {
  while read -r id; do
    pkgs=$(awk -F'\t' -v id="$id" '$1 == id {print $2}' "$tmp/old" "$tmp/new" | sort -u | paste -sd, -)
    echo "- [$id](https://nvd.nist.gov/vuln/detail/$id) ($pkgs)"
  done < "$1"
}

echo "### CVEs (vulnix)"
echo
echo "fixed: **$(grep -c . "$tmp/fixed")** · new: **$(grep -c . "$tmp/added")** · still open: $(grep -c . "$tmp/new-ids")"
echo
if [ -s "$tmp/fixed" ]; then
  echo "<details><summary>fixed</summary>"; echo; cvelist "$tmp/fixed"; echo; echo "</details>"
fi
if [ -s "$tmp/added" ]; then
  echo "<details><summary>new</summary>"; echo; cvelist "$tmp/added"; echo; echo "</details>"
fi
