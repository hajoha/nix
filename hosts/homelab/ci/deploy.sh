# homelab-deploy (homelab-deploy.service, started by the webhook on every
# push to main): deploys the current head of main with homelab-deploy-rev
# and reports the result as a commit status + a comment on the merged PR.
# Loops until main stops moving, so a push during a deploy is not lost.
last=
rc=0
while :; do
  rev=$(git ls-remote "$REPO_URL" refs/heads/main | cut -f1)
  [[ $rev =~ ^[0-9a-f]{40}$ ]] || { echo "cannot resolve main: '$rev'" >&2; exit 1; }
  [ "$rev" = "$last" ] && break
  last=$rev

  status "$rev" pending homelab/deploy "deploying"
  log=$(mktemp)
  r=0
  homelab-deploy-rev "$rev" 2>&1 | tee "$log" || r=$?
  case $r in
    0) state=success desc="deployed, no new problems" ;;
    3) state=error desc="build failed, nothing changed" ;;
    *) state=failure desc="broke something, rolled back" ;;
  esac
  rc=$r
  status "$rev" "$state" homelab/deploy "$desc"

  pr=$({ gh_api GET "/commits/$rev/pulls" || echo '[]'; } | jq -r '.[0].number // empty')
  if [ -n "$pr" ]; then
    {
      echo "### Deploy ${rev:0:7}: $desc"
      echo
      if [ "$r" = 0 ]; then
        grep '^== ' "$log" | tail -n 3 | sed 's/^== /- /' || true
      else
        echo '```'
        tail -n 80 "$log"
        echo '```'
      fi
    } | fit "journalctl -u homelab-deploy" | comment "$pr"
  fi
  rm -f "$log"
done
exit "$rc"
