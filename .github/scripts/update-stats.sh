#!/usr/bin/env bash
# Recomputes profile stats via the GitHub GraphQL API and rewrites the
# static shields.io badge URLs in README.md. Requires `gh` and `jq`.
#
# Stars, forks and watchers are summed over every public repository the
# user owns, collaborates on, or belongs to through an organisation,
# forks included — the same set the profile's repository list shows.
set -euo pipefail

LOGIN="${1:-${GITHUB_REPOSITORY_OWNER:-matasarei}}"
README="${2:-README.md}"

badges=(Stargazers Forks Watchers Followers Contributed_to)
for badge in "${badges[@]}"; do
  if ! grep -q "badge/${badge}-" "$README"; then
    echo "::error::badge '${badge}' not found in ${README}; refusing to continue" >&2
    exit 1
  fi
done

stats=$(gh api graphql --paginate --slurp -f login="$LOGIN" -f query='
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
      nodes { stargazerCount forkCount watchers { totalCount } }
    }
  }
}' | jq -r '
  [.[] | .data.user] as $pages
  | ($pages | map(.repositories.nodes[])) as $repos
  | [
      ($repos | map(.stargazerCount) | add // 0),
      ($repos | map(.forkCount) | add // 0),
      ($repos | map(.watchers.totalCount) | add // 0),
      $pages[0].followers.totalCount,
      $pages[0].repositoriesContributedTo.totalCount
    ] | @tsv')

IFS=$'\t' read -r stars forks watchers followers contributed <<<"$stats"

echo "stars=$stars forks=$forks watchers=$watchers followers=$followers contributed=$contributed"

sed -i.bak -E \
  -e "s#(badge/Stargazers-)[0-9]+(-)#\1${stars}\2#" \
  -e "s#(badge/Forks-)[0-9]+(-)#\1${forks}\2#" \
  -e "s#(badge/Watchers-)[0-9]+(-)#\1${watchers}\2#" \
  -e "s#(badge/Followers-)[0-9]+(-)#\1${followers}\2#" \
  -e "s#(badge/Contributed_to-)[0-9]+(_Repos-)#\1${contributed}\2#" \
  "$README"
rm -f "$README.bak"
