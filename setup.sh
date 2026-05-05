#!/usr/bin/env bash
# setup.sh — install tmux-supervisor by symlinking scripts into ~/.local/bin
# and the slash command into ~/.claude/commands.
#
# Idempotent. Re-runnable. Removes pre-existing files at the install paths
# only after backing them up to <path>.bak-<timestamp>.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
CLAUDE_CMD_DIR="${CLAUDE_CMD_DIR:-$HOME/.claude/commands}"
QUEUE_DIR="${CLAUDE_MSG_QUEUE_DIR:-$HOME/.claude/msg-queue}"

ts="$(date +%Y%m%d-%H%M%S)"

link_into() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    if [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
      echo "  ok    $dst -> $src (already linked)"
      return 0
    fi
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    mv "$dst" "$dst.bak-$ts"
    echo "  saved $dst -> $dst.bak-$ts"
  fi
  ln -s "$src" "$dst"
  echo "  link  $dst -> $src"
}

echo "tmux-supervisor: installing from $REPO_DIR"
echo
echo "binaries -> $LOCAL_BIN"
for name in claude-msg claude-msg-daemon claude-coord tmux-send; do
  link_into "$REPO_DIR/bin/$name" "$LOCAL_BIN/$name"
  chmod +x "$REPO_DIR/bin/$name"
done

echo
echo "claude commands -> $CLAUDE_CMD_DIR"
link_into "$REPO_DIR/commands/tmux-supervisor.md" "$CLAUDE_CMD_DIR/tmux-supervisor.md"

echo
echo "queue dir -> $QUEUE_DIR"
mkdir -p "$QUEUE_DIR/pending" "$QUEUE_DIR/sent" "$QUEUE_DIR/failed"
echo "  ok    $QUEUE_DIR/{pending,sent,failed}"

echo
case ":$PATH:" in
  *":$LOCAL_BIN:"*) echo "PATH includes $LOCAL_BIN" ;;
  *) echo "WARN: $LOCAL_BIN is not in PATH. Add this to your shell rc:"
     echo '  export PATH="$HOME/.local/bin:$PATH"' ;;
esac

echo
echo "Done. Try: claude-msg --daemon-status"
