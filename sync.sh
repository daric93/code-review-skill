#!/usr/bin/env bash
# Install / round-trip skills, agents, steering between this repo and a provider's config dir.
#
# Usage:
#   ./sync.sh kiro                 # push to ~/.kiro (user level)
#   ./sync.sh kiro --project DIR   # push to DIR/.kiro (project level)
#   ./sync.sh claude               # push to ~/.claude (user level)
#   ./sync.sh claude --project DIR # push to DIR/.claude (project level)
#   ./sync.sh status kiro          # show which installed files differ from the repo
#   ./sync.sh pull kiro            # copy installed files back into the repo (round-trip)
#
# Canonical source in this repo is always folder-per-skill with a SKILL.md:
#   skills/<name>/SKILL.md      and   projects/<proj>/skills/<name>/SKILL.md
# Shared includes live in skills/_shared/*.md (no SKILL.md — not standalone skills).
# Per-provider on-disk layout:
#   - Kiro   -> <root>/.kiro/skills/<name>.md          (flat .md)  + skills/_shared/*.md
#   - Claude -> <root>/.claude/skills/<name>/SKILL.md  (folder)    + skills/_shared/*.md
# Agents (Kiro format) and steering install only for the kiro target.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

verb="push"
case "${1:-}" in
  pull|status) verb="$1"; shift ;;
esac

provider="${1:-}"
shift || true
project_dir=""
if [ "${1:-}" = "--project" ]; then
  project_dir="${2:?--project requires a directory}"
fi

# Resolve the install root for a provider.
root_for() { # <provider>
  case "$1" in
    kiro)   echo "${project_dir:+$project_dir/.kiro}"  | grep . || echo "$HOME/.kiro" ;;
    claude) echo "${project_dir:+$project_dir/.claude}"| grep . || echo "$HOME/.claude" ;;
  esac
}

# Map a repo skill dir to its installed path for a provider.
installed_skill_path() { # <provider> <root> <name>
  case "$1" in
    kiro)   echo "$2/skills/$3.md" ;;
    claude) echo "$2/skills/$3/SKILL.md" ;;
  esac
}

iter_skill_dirs() { # prints every repo skill dir (general + project), excluding _shared
  for d in "$SCRIPT_DIR"/skills/*/ "$SCRIPT_DIR"/projects/*/skills/*/; do
    [ -f "$d/SKILL.md" ] && echo "${d%/}"
  done
}

case "$verb" in
  push)
    case "$provider" in
      kiro|claude) : ;;
      *) echo "Usage: $0 {kiro|claude} [--project DIR]"; exit 1;;
    esac
    root="$(root_for "$provider")"
    echo "Installing to $root"
    while IFS= read -r d; do
      name="$(basename "$d")"
      if [ "$provider" = kiro ]; then
        mkdir -p "$root/skills"; cp "$d/SKILL.md" "$root/skills/$name.md"
        echo "  skill  -> $root/skills/$name.md"
      else
        mkdir -p "$root/skills/$name"; cp "$d/SKILL.md" "$root/skills/$name/SKILL.md"
        echo "  skill  -> $root/skills/$name/SKILL.md"
      fi
    done < <(iter_skill_dirs)
    # Shared includes (both providers): top-level and project-level _shared
    if ls "$SCRIPT_DIR"/skills/_shared/*.md "$SCRIPT_DIR"/projects/*/skills/_shared/*.md >/dev/null 2>&1; then
      mkdir -p "$root/skills/_shared"
      for sh in "$SCRIPT_DIR"/skills/_shared/*.md "$SCRIPT_DIR"/projects/*/skills/_shared/*.md; do
        [ -f "$sh" ] && cp "$sh" "$root/skills/_shared/"
      done
      echo "  shared -> $root/skills/_shared/"
    fi
    if [ "$provider" = kiro ]; then
      mkdir -p "$root/agents"
      for a in "$SCRIPT_DIR"/agents/*.md "$SCRIPT_DIR"/projects/*/agents/*.md; do
        [ -f "$a" ] || continue
        [ "$(basename "$a")" = "README.md" ] && continue
        cp "$a" "$root/agents/" && echo "  agent  -> $root/agents/$(basename "$a")"
      done
      if ls "$SCRIPT_DIR"/steering/*.md >/dev/null 2>&1; then
        mkdir -p "$root/steering"
        for s in "$SCRIPT_DIR"/steering/*.md; do
          cp "$s" "$root/steering/" && echo "  steer  -> $root/steering/$(basename "$s")"
        done
      fi
    else
      echo "  (agents + steering are Kiro-format; not installed for claude)"
    fi
    echo "Done."
    ;;

  status|pull)
    case "$provider" in
      kiro|claude) : ;;
      *) echo "Usage: $0 {status|pull} {kiro|claude} [--project DIR]"; exit 1;;
    esac
    root="$(root_for "$provider")"
    echo "$verb vs $root"
    while IFS= read -r d; do
      name="$(basename "$d")"
      inst="$(installed_skill_path "$provider" "$root" "$name")"
      repo="$d/SKILL.md"
      if [ ! -f "$inst" ]; then
        echo "  MISSING (not installed): $name"
      elif diff -q "$inst" "$repo" >/dev/null; then
        echo "  ok      $name"
      else
        echo "  DIFFERS $name"
        [ "$verb" = pull ] && cp "$inst" "$repo" && echo "          pulled -> $repo"
      fi
    done < <(iter_skill_dirs)
    # Agents (kiro only)
    if [ "$provider" = kiro ]; then
      for a in "$SCRIPT_DIR"/agents/*.md "$SCRIPT_DIR"/projects/*/agents/*.md; do
        [ -f "$a" ] || continue
        [ "$(basename "$a")" = "README.md" ] && continue
        inst="$root/agents/$(basename "$a")"
        if [ ! -f "$inst" ]; then echo "  MISSING (agent): $(basename "$a")"
        elif diff -q "$inst" "$a" >/dev/null; then echo "  ok      agent/$(basename "$a")"
        else echo "  DIFFERS agent/$(basename "$a")"; [ "$verb" = pull ] && cp "$inst" "$a" && echo "          pulled -> $a"; fi
      done
    fi
    echo "Done."
    ;;
esac
