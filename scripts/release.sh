#!/bin/bash
# Release gate (#47, option 2): a release can only be cut through this
# script, and this script will not cut one until the full test suite AND
# the regression gate pass. That turns "someone remembers to run the gate"
# into "the process refuses to proceed without it".
#
# Usage: scripts/release.sh <new-version>        (e.g. 0.11.0)
#
# What it does, in order:
#   1. refuses on a dirty tree or off-main checkout
#   2. swift test (full suite)
#   3. scripts/regression-gate.sh (accuracy goldens + model pin, #34/#48)
#   4. bumps the version in DataModels.swift + plugin.json
#   5. commits `chore: release v<version>`
# It does NOT push — review the commit, then push. If the plugin is
# distributed through a marketplace, sync it afterwards (common-release-flow).
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <new-version> (e.g. 0.11.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "x version must be semver X.Y.Z, got: $VERSION" >&2
  exit 1
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

[ -z "$(git status --porcelain)" ] || {
  echo "x working tree is dirty — commit or stash first" >&2
  exit 1
}
BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || {
  echo "x releases are cut from main, current branch: $BRANCH" >&2
  exit 1
}

echo "== release $VERSION: full test suite =="
swift test

echo "== release $VERSION: regression gate (accuracy goldens + model pin) =="
BESTASR_BIN="${BESTASR_BIN:-swift run -c release bestasr}" ./scripts/regression-gate.sh

echo "== release $VERSION: version bump =="
/usr/bin/python3 - "$VERSION" <<'PY'
import json, re, sys

version = sys.argv[1]

path = "Sources/BestASRKit/Models/DataModels.swift"
src = open(path).read()
new, n = re.subn(
    r'(public static let current = ")[0-9]+\.[0-9]+\.[0-9]+(")',
    rf"\g<1>{version}\g<2>", src)
assert n == 1, f"expected exactly one version constant in {path}, patched {n}"
open(path, "w").write(new)

path = "plugins/bestasr/.claude-plugin/plugin.json"
meta = json.load(open(path))
meta["version"] = version
with open(path, "w") as fh:
    json.dump(meta, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(f"bumped to {version} in DataModels.swift + plugin.json")
PY

git add Sources/BestASRKit/Models/DataModels.swift plugins/bestasr/.claude-plugin/plugin.json
git commit -m "chore: release v$VERSION"
echo "== release $VERSION ready — review the commit, then push =="
echo "   (marketplace-distributed plugin: run the plugin-update sync afterwards)"
