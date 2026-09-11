#!/usr/bin/env bash
# Recomputes profile stats via the GitHub GraphQL API and renders
# assets/stats.svg from assets/stats.svg.in. Requires `gh` and `jq`.
#
# Stars, forks and watchers are summed over every public repository the
# user owns, collaborates on, or belongs to through an organisation,
# forks included — the same set the profile's repository list shows.
# Organisations are also queried by name (STATS_ORGS) because a private
# org membership is invisible to the default Actions token.
set -euo pipefail

LOGIN="${1:-${GITHUB_REPOSITORY_OWNER:-matasarei}}"
TEMPLATE="${2:-assets/stats.svg.in}"
OUT="${TEMPLATE%.in}"
ORGS="${STATS_ORGS:-grinchenkoedu profirealt}"

for key in STARS FORKS WATCHERS FOLLOWERS CONTRIBUTED; do
  if ! grep -q "__${key}__" "$TEMPLATE"; then
    echo "::error::placeholder __${key}__ not found in ${TEMPLATE}; refusing to continue" >&2
    exit 1
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh api graphql --paginate --slurp -f login="$LOGIN" -f query='
query($login: String!, $cursor: String) {
  user(login: $login) {
    followers { totalCount }
    repositoriesContributedTo(
      contributionTypes: [COMMIT, PULL_REQUEST, ISSUE, REPOSITORY]
      includeUserRepositories: false
    ) { totalCount }
    repositories(
      first: 100
      after: $cursor
      ownerAffiliations: [OWNER, ORGANIZATION_MEMBER, COLLABORATOR]
      privacy: PUBLIC
    ) {
      pageInfo { hasNextPage endCursor }
      nodes { nameWithOwner stargazerCount forkCount watchers { totalCount } }
    }
  }
}' > "$tmp/user.json"

for org in $ORGS; do
  gh api graphql --paginate --slurp -f org="$org" -f query='
query($org: String!, $cursor: String) {
  organization(login: $org) {
    repositories(first: 100, after: $cursor, privacy: PUBLIC) {
      pageInfo { hasNextPage endCursor }
      nodes { nameWithOwner stargazerCount forkCount watchers { totalCount } }
    }
  }
}' > "$tmp/org-$org.json"
done

stats=$(jq -r -s '
  (.[0] | map(.data.user)) as $pages
  | ( [ $pages[].repositories.nodes[] ]
    + [ .[1:][][] | .data.organization.repositories.nodes[] ]
    | unique_by(.nameWithOwner) ) as $repos
  | [
      ($repos | map(.stargazerCount) | add // 0),
      ($repos | map(.forkCount) | add // 0),
      ($repos | map(.watchers.totalCount) | add // 0),
      $pages[0].followers.totalCount,
      $pages[0].repositoriesContributedTo.totalCount
    ] | @tsv' "$tmp/user.json" "$tmp"/org-*.json)

IFS=$'\t' read -r stars forks watchers followers contributed <<<"$stats"

echo "stars=$stars forks=$forks watchers=$watchers followers=$followers contributed=$contributed"

sed \
  -e "s/__STARS__/${stars}/g" \
  -e "s/__FORKS__/${forks}/g" \
  -e "s/__WATCHERS__/${watchers}/g" \
  -e "s/__FOLLOWERS__/${followers}/g" \
  -e "s/__CONTRIBUTED__/${contributed}/g" \
  "$TEMPLATE" > "$OUT"
