# Shared by the deploy / preview scripts: GitHub API with the PAT from
# $CREDENTIALS_DIRECTORY/token (no token: reporting is skipped).
token_file=${CREDENTIALS_DIRECTORY:-/nonexistent}/token

gh_api() {
  local method=$1 path=$2
  shift 2
  [ -r "$token_file" ] || return 1
  curl -fsS -X "$method" \
    -H "Authorization: Bearer $(cat "$token_file")" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO$path" "$@"
}

# status <sha> <pending|success|failure|error> <context> <description>
status() {
  jq -n --arg s "$2" --arg c "$3" --arg d "${4:0:140}" \
    '{state: $s, context: $c, description: $d}' \
    | gh_api POST "/statuses/$1" --data @- > /dev/null || true
}

# limit to what a comment can hold (65536 characters)
fit() {
  local body
  body=$(cat)
  if [ "${#body}" -gt 60000 ]; then
    printf "%s\n\n(truncated, full output: \`%s\`)\n" "${body:0:60000}" "$1"
  else
    printf '%s\n' "$body"
  fi
}

# comment <pr> [marker]: post stdin as a comment; with a marker, edit the
# previous comment that carries it instead of adding a new one
comment() {
  local pr=$1 marker=${2:-} body id=
  body=$(cat)
  [ -n "$marker" ] && body="<!-- $marker -->"$'\n'"$body"
  if [ -n "$marker" ]; then
    id=$({ gh_api GET "/issues/$pr/comments?per_page=100" || echo '[]'; } \
      | jq -r --arg m "<!-- $marker -->" '[.[] | select(.body | startswith($m))] | last | .id // empty')
  fi
  if [ -n "$id" ]; then
    jq -n --arg b "$body" '{body: $b}' | gh_api PATCH "/issues/comments/$id" --data @- > /dev/null || true
  else
    jq -n --arg b "$body" '{body: $b}' | gh_api POST "/issues/$pr/comments" --data @- > /dev/null || true
  fi
}
