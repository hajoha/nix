# homelab-preview-pr <pr> (homelab-preview@<pr>.service, started by the
# webhook when a PR is opened / pushed to): builds the PR's system and
# comments homelab-preview's report. Only PRs from branches of this repo
# into main, never forks (checked here against the API, not the webhook).
# Loops until the PR head stops moving.
pr=${1:?pr number}
[[ $pr =~ ^[0-9]+$ ]] || { echo "not a PR number: $pr" >&2; exit 2; }
work=${CACHE_DIRECTORY:?}
out=$work/pr-$pr
log=$work/pr-$pr.log
trap 'rm -f "$out"' EXIT

last=
while :; do
  info=$(gh_api GET "/pulls/$pr")
  read -r state head base sha < <(jq -r '[.state, .head.repo.full_name, .base.ref, .head.sha] | @tsv' <<< "$info")
  if [ "$state" != open ] || [ "$head" != "$REPO" ] || [ "$base" != main ]; then
    echo "PR #$pr: $state, $head → $base; not previewing"
    exit 0
  fi
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "bad head sha: $sha" >&2; exit 1; }
  [ "$sha" = "$last" ] && break
  last=$sha

  echo "== PR #$pr at $sha"
  status "$sha" pending homelab/preview "building"
  if nix build --accept-flake-config --out-link "$out" \
    "$REPO_URL?ref=refs/pull/$pr/head&rev=$sha#nixosConfigurations.homelab.config.system.build.toplevel" \
    2>&1 | tee "$log"; then
    homelab-preview "$out" "${sha:0:7}" | fit "journalctl -u homelab-preview@$pr" | comment "$pr" homelab-preview
    status "$sha" success homelab/preview "preview posted"
  else
    {
      echo "## Deploy preview: ${sha:0:7} does not build"
      echo
      echo '```'
      tail -n 80 "$log"
      echo '```'
    } | fit "journalctl -u homelab-preview@$pr" | comment "$pr" homelab-preview
    status "$sha" failure homelab/preview "build failed"
  fi
done
