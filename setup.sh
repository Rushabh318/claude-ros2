#!/usr/bin/env bash
# Install claude-robotics context files into a ROS2 workspace.
#
# Usage:
#   ./setup.sh                    # install into current directory
#   ./setup.sh /path/to/ros2/ws   # install into a specific workspace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$(pwd)}"

if [[ ! -d "$TARGET" ]]; then
  echo "Error: target directory does not exist: $TARGET" >&2
  exit 1
fi

echo "Installing claude-robotics into: $TARGET"

cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"

mkdir -p "$TARGET/.claude/skills"
cp -r "$SCRIPT_DIR/.claude/skills/." "$TARGET/.claude/skills/"

SKILL_COUNT=$(ls "$SCRIPT_DIR/.claude/skills" | grep -v '^\.' | wc -l | tr -d ' ')

echo "Done."
echo "  $TARGET/CLAUDE.md"
echo "  $TARGET/.claude/skills/  ($SKILL_COUNT skill(s) installed)"
