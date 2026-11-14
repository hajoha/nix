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
# verdict (false positives, patches nixpkgs backported without a version
# bump). What an update changes is "fixed" / "new"; "still open" is grouped
# by package so the big ones (kernel, JDK, ...) are visible at a glance.
whitelist=()
if [ -n "${VULNIX_WHITELIST:-}" ]; then whitelist=(--whitelist "$VULNIX_WHITELIST"); fi

# cves <system> <out>: <out> = "cve \t pname \t version \t cvss" per open
# CVE, <out>.wl = whitelisted CVE ids; fails if vulnix gave no report
cves() {
  vulnix --json --show-whitelisted --cache-dir "${VULNIX_CACHE:-$HOME/.cache/vulnix}" \
    "${whitelist[@]}" "$1" > "$2.json" 2> "$2.err" || true
  jq -e 'type == "array"' "$2.json" > /dev/null 2>&1 || return 1
  jq -r '.[] | . as $d | .affected_by[]
    | [., $d.pname, $d.version, ($d.cvssv3_basescore[.] // 0 | tostring)] | @tsv' \
    "$2.json" | sort -u > "$2"
  jq -r '.[] | .whitelisted[]' "$2.json" | sort -u > "$2.wl"
}

# severity <cvss>
sev() {
  awk -v s="$1" 'BEGIN {
    if (s >= 9) print "critical"; else if (s >= 7) print "high";
    else if (s >= 4) print "medium"; else if (s > 0) print "low"; else print "no score" }'
}

# cvelist <ids> <table> [max]: one line per CVE, highest score first
cvelist() {
  local max=${3:-100} n
  awk -F'\t' 'NR == FNR { want[$1] = 1; next }
    $1 in want {
      p[$1] = (p[$1] ? p[$1] ", " : "") $2 " " $3
      if ($4 + 0 > s[$1]) s[$1] = $4 + 0
    }
    END { for (id in p) printf "%s\t%.1f\t%s\n", id, s[id], p[id] }' "$1" "$2" \
    | sort -t$'\t' -k2,2nr -k1,1 > "$tmp/list"
  n=$(grep -c . "$tmp/list" || true)
  head -n "$max" "$tmp/list" | while IFS=$'\t' read -r id score pkgs; do
    label=$(sev "$score")
    if [ "$score" = 0.0 ]; then score="–"; fi
    echo "- [$id](https://nvd.nist.gov/vuln/detail/$id) **$score** $label · $pkgs"
  done
  if [ "$n" -gt "$max" ]; then echo "- … and $((n - max)) more"; fi
}

count() { grep -c . "$1" || true; }

echo "### CVEs (vulnix)"
echo
if ! cves "$cur" "$tmp/old" || ! cves "$new" "$tmp/new"; then
  echo "vulnix failed, no CVE report:"
  echo
  echo '```'
  { cat "$tmp/old.err" "$tmp/new.err" 2> /dev/null || true; } | tail -n 20
  echo '```'
  exit 0
fi

cut -f1 "$tmp/old" | sort -u > "$tmp/old-ids"
cut -f1 "$tmp/new" | sort -u > "$tmp/new-ids"
comm -23 "$tmp/old-ids" "$tmp/new-ids" > "$tmp/fixed"
comm -13 "$tmp/old-ids" "$tmp/new-ids" > "$tmp/added"
awk -F'\t' '$4 + 0 >= 7 { print $1 }' "$tmp/new" | sort -u > "$tmp/severe"
crit=$(awk -F'\t' '$4 + 0 >= 9 { print $1 }' "$tmp/new" | sort -u | grep -c . || true)

echo "fixed: **$(count "$tmp/fixed")** · new: **$(count "$tmp/added")** ·" \
  "still open: $(count "$tmp/new-ids") ($crit critical, $(($(count "$tmp/severe") - crit)) high)" \
  "· whitelisted: $(count "$tmp/new.wl")"
echo
echo "_Matched by package name and version against the NVD. Many \"open\" ones"
echo "are already patched in nixpkgs or don't apply; what this update changes"
echo "is fixed / new. Checked ones go into \`hosts/homelab/ci/vulnix-whitelist.toml\`._"
echo
if [ -s "$tmp/fixed" ]; then
  echo "<details><summary>fixed ($(count "$tmp/fixed"))</summary>"
  echo
  cvelist "$tmp/fixed" "$tmp/old"
  echo
  echo "</details>"
fi
if [ -s "$tmp/added" ]; then
  echo "<details open><summary>new ($(count "$tmp/added"))</summary>"
  echo
  cvelist "$tmp/added" "$tmp/new"
  echo
  echo "</details>"
fi

if [ -s "$tmp/new-ids" ]; then
  echo "<details><summary>still open by package</summary>"
  echo
  echo "| package | version | CVEs | critical | high | max CVSS |"
  echo "|---|---|--:|--:|--:|--:|"
  awk -F'\t' '{
      k = $2 "\t" $3; n[k]++; s = $4 + 0
      if (s >= 9) c[k]++; else if (s >= 7) h[k]++
      if (s > m[k]) m[k] = s
    }
    END { for (k in n) printf "%d\t%d\t%d\t%s\t%.1f\n", c[k], h[k], n[k], k, m[k] }' "$tmp/new" \
    | sort -t$'\t' -k1,1nr -k2,2nr -k3,3nr > "$tmp/pkgs"
  head -n 40 "$tmp/pkgs" | while IFS=$'\t' read -r c h n p v m; do
    if [ "$m" = 0.0 ]; then m="–"; fi
    echo "| $p | $v | $n | $c | $h | $m |"
  done
  if [ "$(count "$tmp/pkgs")" -gt 40 ]; then
    echo
    echo "… and $(($(count "$tmp/pkgs") - 40)) more packages"
  fi
  echo
  echo "</details>"
fi
if [ -s "$tmp/severe" ]; then
  echo "<details><summary>still open, critical / high ($(count "$tmp/severe"))</summary>"
  echo
  cvelist "$tmp/severe" "$tmp/new" 100
  echo
  echo "</details>"
fi
