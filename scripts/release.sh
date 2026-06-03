#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?VERSION is required (e.g. 0.1.0)}"
NPM_TAG="${NPM_TAG:-latest}"
DRY_RUN="${DRY_RUN:-false}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; then
  echo "Invalid semver: $VERSION" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "Installing dependencies..."
bun install --frozen-lockfile

echo "Running tests..."
bun test

echo "Setting version to $VERSION..."
npm version "$VERSION" --no-git-tag-version --allow-same-version

dry_run() {
  [ "$DRY_RUN" = "true" ]
}

revert_package_json() {
  if git ls-files --error-unmatch package.json &>/dev/null; then
    git checkout -- package.json
  fi
}

if ! dry_run; then
  if [ -z "${NPM_TOKEN:-}" ] && ! npm whoami &>/dev/null; then
    echo "NPM_TOKEN is required (or run npm login locally)" >&2
    revert_package_json
    exit 1
  fi
fi

publish_args=(--access public --tag "$NPM_TAG")
if dry_run; then
  publish_args+=(--dry-run)
fi

echo "Publishing @khoralabs/sourcemaps@${VERSION} (dist-tag: ${NPM_TAG})..."
npm publish "${publish_args[@]}"

if dry_run; then
  echo "Dry run complete; reverting package.json and skipping git tag/push"
  revert_package_json
  exit 0
fi

git config user.name "${GIT_USER_NAME:-github-actions[bot]}"
git config user.email "${GIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

git add package.json
git commit -m "release v${VERSION}"
git tag "v${VERSION}"
git push origin HEAD
git push origin "v${VERSION}"

echo "Released @khoralabs/sourcemaps@${VERSION}"
