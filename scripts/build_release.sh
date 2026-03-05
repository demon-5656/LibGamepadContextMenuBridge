#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON_DIR="$ROOT_DIR/LibGamepadContextMenuBridge"
DIST_DIR="$ROOT_DIR/dist"

if [[ ! -d "$ADDON_DIR" ]]; then
  echo "Addon directory not found: $ADDON_DIR" >&2
  exit 1
fi

VERSION="$(awk -F': ' '/^## Version:/ {print $2}' "$ADDON_DIR/LibGamepadContextMenuBridge.txt" | tr -d '[:space:]')"
if [[ -z "$VERSION" ]]; then
  VERSION="dev"
fi

mkdir -p "$DIST_DIR"
BASENAME="LibGamepadContextMenuBridge-v${VERSION}"

if command -v zip >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && zip -r "$DIST_DIR/${BASENAME}.zip" "LibGamepadContextMenuBridge" >/dev/null)
  echo "Built: $DIST_DIR/${BASENAME}.zip"
else
  (cd "$ROOT_DIR" && tar -czf "$DIST_DIR/${BASENAME}.tar.gz" "LibGamepadContextMenuBridge")
  echo "Built: $DIST_DIR/${BASENAME}.tar.gz"
fi
