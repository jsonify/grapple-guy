#!/usr/bin/env bash
# One command to (re)generate the Xcode project cleanly. Run from anywhere:
#   ./tools/setup.sh            # auto-detects your signing team the first time
#   ./tools/setup.sh ABCDE12345 # or pass your 10-character team ID explicitly
#
# What it does:
#   1. Makes sure Config/Local.xcconfig has your DEVELOPMENT_TEAM (git-ignored, so it's never committed)
#   2. Quits Xcode if it's open (regenerating under an open Xcode causes "Missing package product")
#   3. Runs xcodegen, resolves the GrappleCore package, and reopens the project
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL=Config/Local.xcconfig

# 1. Signing team
team="${1:-}"
if [[ -z "$team" && -f "$LOCAL" ]] && grep -qE '^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}' "$LOCAL"; then
  echo "✓ Signing team already set in $LOCAL"
else
  if [[ -z "$team" ]]; then
    # The team ID is the OU field of your Apple Development certificate (Xcode creates it when you sign in).
    team=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null \
      | grep -oE 'OU ?= ?[A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}$' || true)
  fi
  if [[ -z "$team" ]]; then
    echo "✗ Couldn't find your team ID automatically."
    echo "  In Xcode: Settings → Accounts → select your Apple ID → your team shows its Team ID,"
    echo "  or pick the team once in Signing & Capabilities, then run:"
    echo "    grep -m1 DEVELOPMENT_TEAM GrappleGuy.xcodeproj/project.pbxproj"
    echo "  and re-run:  ./tools/setup.sh YOURTEAMID"
    exit 1
  fi
  printf 'DEVELOPMENT_TEAM = %s\n' "$team" > "$LOCAL"
  echo "✓ Wrote $LOCAL with DEVELOPMENT_TEAM = $team"
fi

# 2. Close Xcode so it doesn't hold on to the old project
if pgrep -x Xcode >/dev/null; then
  echo "• Quitting Xcode (it will ask to save anything unsaved)…"
  osascript -e 'tell application "Xcode" to quit' || true
  for _ in {1..20}; do pgrep -x Xcode >/dev/null || break; sleep 0.5; done
fi

# 3. Regenerate, resolve the local package, reopen
command -v xcodegen >/dev/null || { echo "✗ xcodegen not found: brew install xcodegen"; exit 1; }
xcodegen
echo "• Resolving packages…"
xcodebuild -project GrappleGuy.xcodeproj -scheme GrappleGuy -resolvePackageDependencies >/dev/null
echo "✓ Project ready"
open GrappleGuy.xcodeproj
