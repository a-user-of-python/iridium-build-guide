#!/bin/bash
# iridium-ipa-build.sh — Build the Iridium iOS app (with DX10 shims) to an
# unsigned .ipa from your Mac.
#
# Usage:
#   bash iridium-ipa-build.sh
#
# What it does:
#   1. Clones (or updates) a-user-of-python/iridium into ~/Desktop/iridium
#      and checks out the dx10-shim-frontends branch (your DX10 work).
#   2. Apple Silicon Mac: runs the repo's own local IPA build
#      (ci/build-local-ipa.sh). First run takes several hours.
#   3. Intel Mac: Iridium's build scripts require Apple Silicon for local
#      builds, so this dispatches the build to GitHub Actions on your fork,
#      waits for it to finish, and downloads the finished
#      Iridium-unsigned.ipa next to this script's output folder.
#
# The IPA is UNSIGNED. Sign it with your sideloading tool of choice
# (Sideloadly, AltStore, etc.) before installing on a device.
#
# Requirements:
#   - macOS with Xcode installed (free from the Mac App Store).
#   - Apple Silicon: nothing else — the build installs its own Homebrew tools.
#   - Intel: the GitHub CLI (gh), logged in:  brew install gh && gh auth login
#     Also enable Actions on your fork once:
#     https://github.com/a-user-of-python/iridium/settings/actions

set -euo pipefail

section() { printf '\n===== %s =====\n' "$1"; }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script needs macOS."

REPO="a-user-of-python/iridium"
BRANCH="${IRIDIUM_BRANCH:-dx10-shim-frontends}"
BUILD_DIR="$HOME/Desktop/iridium"

# ---------------------------------------------------------------- clone ---
section "Getting the source ($REPO @ $BRANCH)"
if [ -e "$BUILD_DIR" ] && [ ! -d "$BUILD_DIR/.git" ]; then
  die "$BUILD_DIR exists but is not a git checkout. Move or rename it, then run again."
fi
if [ -d "$BUILD_DIR/.git" ]; then
  echo "Using existing checkout at $BUILD_DIR"
  git -C "$BUILD_DIR" fetch origin
else
  echo "Cloning into $BUILD_DIR ..."
  git clone "https://github.com/$REPO.git" "$BUILD_DIR"
fi
git -C "$BUILD_DIR" checkout "$BRANCH"
git -C "$BUILD_DIR" pull --ff-only origin "$BRANCH"
echo "Updating submodules (this can take a while the first time)..."
git -C "$BUILD_DIR" submodule update --init --recursive
SHA=$(git -C "$BUILD_DIR" rev-parse HEAD)
REMOTE_SHA=$(git -C "$BUILD_DIR" rev-parse "origin/$BRANCH")
[ "$SHA" = "$REMOTE_SHA" ] || die "Local checkout ($SHA) does not match origin/$BRANCH ($REMOTE_SHA). Delete $BUILD_DIR and run again for a fresh clone."
echo "Building commit: $SHA"

ARCH="$(uname -m)"
echo "This Mac: $(uname -s) $ARCH"

# ------------------------------------------------------- Apple Silicon -----
if [ "$ARCH" = "arm64" ]; then
  section "Apple Silicon detected: local build"
  xcode-select -p >/dev/null 2>&1 || die "Xcode is not installed. Install it free from the Mac App Store, then run again."
  echo "Xcode: $(xcodebuild -version | head -1)"
  python3 --version || die "python3 is required."
  echo "Starting the local IPA build. First run takes several hours;"
  echo "later runs reuse everything that did not change."
  echo "Full log: $BUILD_DIR/.build/local-build-logs/"
  cd "$BUILD_DIR"
  bash ci/build-local-ipa.sh
  echo
  echo "Done. Your IPA is in $BUILD_DIR/.build/ (see the IPA: line above)."
  exit 0
fi

# -------------------------------------------------------------- Intel ------
section "Intel Mac detected"
cat <<'EOF'
Iridium's own build scripts require an Apple Silicon Mac for local
compilation (enforced in ci/local_build_tools.py and
ci/prepare-native-runtime.sh), so a local build is not supported here.
Instead, this script runs the repo's official "Build unsigned IPA"
workflow on GitHub's Apple Silicon runners, waits for it, and downloads
the finished IPA. Same source, same checks — just built in the cloud.
EOF

command -v gh >/dev/null 2>&1 || die "The GitHub CLI is required: brew install gh"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"

# Actions must be enabled on the fork (they are off by default on forks).
if ! gh api "repos/$REPO/actions/workflows" --jq '.workflows[] | select(.name=="Build unsigned IPA") | .name' 2>/dev/null | grep -q "Build unsigned IPA"; then
  die "The 'Build unsigned IPA' workflow was not found. Enable Actions on your fork once: https://github.com/$REPO/settings/actions"
fi

DISPATCH_ID="mac-$(date +%Y%m%d-%H%M%S)"
section "Dispatching the cloud build"
gh workflow run build-unsigned-ipa.yml --repo "$REPO" --ref "$BRANCH" \
  -f expected_sha="$SHA" -f dispatch_id="$DISPATCH_ID"
echo "Workflow dispatched (id: $DISPATCH_ID). Finding the run..."

RUN_ID=""
for _ in $(seq 1 30); do
  RUN_ID=$(gh api "repos/$REPO/actions/workflows/build-unsigned-ipa.yml/runs?event=workflow_dispatch&per_page=20" \
    --jq ".workflow_runs[] | select(.display_title | contains(\"$DISPATCH_ID\")) | .id" 2>/dev/null | head -1) || true
  [ -n "$RUN_ID" ] && break
  sleep 10
done
[ -n "$RUN_ID" ] || die "Could not find the dispatched run. Check https://github.com/$REPO/actions"
echo "Run: https://github.com/$REPO/actions/runs/$RUN_ID"

section "Waiting for the build (takes a few hours — you can close this and check the link above)"
gh run watch "$RUN_ID" --repo "$REPO" || true

CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq .conclusion)
echo "Build conclusion: $CONCLUSION"
[ "$CONCLUSION" = "success" ] || die "The cloud build did not succeed. See the run link above for logs."

section "Downloading the IPA"
OUT_DIR="$BUILD_DIR/ipa-output"
mkdir -p "$OUT_DIR"
gh run download "$RUN_ID" --repo "$REPO" -n "Iridium-unsigned-$SHA" -D "$OUT_DIR"
echo
echo "Done. Your IPA:"
ls -la "$OUT_DIR"/Iridium-unsigned.ipa
echo
echo "It is UNSIGNED — sign it with Sideloadly/AltStore/etc. before installing."
