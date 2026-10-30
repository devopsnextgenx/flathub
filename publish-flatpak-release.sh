#!/usr/bin/env bash
#
# publish-flatpak-release.sh
#
# 1. Query https://github.com/devopsnextgenx/open-bc for the newest tag
#    and its commit SHA.
# 2. Create a new branch from "new-pr" named after the tag.
# 3. Take io.github.devopsnextgenx.open-bc.yml from the *master* branch
#    of the current repository and replace <TAG> and <COMMIT_SHA>.
# 4. Download scripts/packaging/cargo-sources.json from the tagged
#    commit of devopsnextgenx/open-bc and place it in the repo root,
#    next to the manifest.
# 5. Commit and push the new branch.
#
# Usage: ./publish-flatpak-release.sh
#

set -euo pipefail

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
UPSTREAM_REPO="devopsnextgenx/open-bc"
MANIFEST_FILE="io.github.devopsnextgenx.open-bc.yml"
CARGO_SOURCES_PATH="scripts/packaging/cargo-sources.json"
BASE_BRANCH="new-pr"
MASTER_BRANCH="master"

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' is required but not installed." >&2
    exit 1
  fi
}

require_cmd git
require_cmd curl
require_cmd jq

# ------------------------------------------------------------------
# 1. Fetch latest tag and commit SHA from the upstream repository
# ------------------------------------------------------------------
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/tags"

echo "Fetching latest tag from ${UPSTREAM_REPO}..."
TAG_JSON=$(curl -fsSL "$API_URL")

TAG=$(echo "$TAG_JSON" | jq -r '.[0].name')
COMMIT_SHA=$(echo "$TAG_JSON" | jq -r '.[0].commit.sha')

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "Error: Could not determine the latest tag." >&2
  exit 1
fi

if [[ -z "$COMMIT_SHA" || "$COMMIT_SHA" == "null" ]]; then
  echo "Error: Could not determine the commit SHA for tag '${TAG}'." >&2
  exit 1
fi

echo "Latest tag       : ${TAG}"
echo "Associated commit: ${COMMIT_SHA}"

# ------------------------------------------------------------------
# 2. Create a new branch from new-pr named after the tag
# ------------------------------------------------------------------
echo "Fetching origin/${BASE_BRANCH}..."
git fetch origin "${BASE_BRANCH}"

echo "Creating branch '${TAG}' from origin/${BASE_BRANCH}..."
git checkout -B "${TAG}" "origin/${BASE_BRANCH}"

# ------------------------------------------------------------------
# 3. Populate the manifest from master
# ------------------------------------------------------------------
echo "Extracting ${MANIFEST_FILE} from ${MASTER_BRANCH}..."
git show "${MASTER_BRANCH}:${MANIFEST_FILE}" > "${MANIFEST_FILE}"

echo "Replacing <TAG> with '${TAG}' and <COMMIT_SHA> with '${COMMIT_SHA}'..."
# Use a temporary file so we don't clobber the source while sed reads it.
sed -e "s/<TAG>/${TAG}/g" \
    -e "s/<COMMIT_SHA>/${COMMIT_SHA}/g" \
    "${MANIFEST_FILE}" > "${MANIFEST_FILE}.tmp"
mv "${MANIFEST_FILE}.tmp" "${MANIFEST_FILE}"

# ------------------------------------------------------------------
# 4. Download cargo-sources.json from the tagged commit
# ------------------------------------------------------------------
CARGO_SOURCES_URL="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${TAG}/${CARGO_SOURCES_PATH}"
CARGO_SOURCES_FILE="$(basename "${CARGO_SOURCES_PATH}")"

echo "Downloading ${CARGO_SOURCES_PATH} from tag '${TAG}'..."
curl -fsSL "${CARGO_SOURCES_URL}" -o "${CARGO_SOURCES_FILE}"

echo "Saved as ./${CARGO_SOURCES_FILE}"

# ------------------------------------------------------------------
# 5. Commit and push
# ------------------------------------------------------------------
echo "Staging changes..."
git add "${MANIFEST_FILE}" "${CARGO_SOURCES_FILE}"

# Only commit if there are actual changes.
if git diff --cached --quiet; then
  echo "No changes to commit. The manifest may already be up-to-date."
  exit 0
fi

COMMIT_MSG="Update ${MANIFEST_FILE} to ${TAG} (${COMMIT_SHA})"
echo "Committing: ${COMMIT_MSG}"
git commit -m "${COMMIT_MSG}"

echo "Pushing branch '${TAG}' to origin..."
git push -u origin "${TAG}"

echo "Done. Branch '${TAG}' has been created and pushed."