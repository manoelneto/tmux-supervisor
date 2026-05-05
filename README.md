# tmux-supervisor

Reliable, non-blocking message delivery to [Claude Code](https://claude.com/claude-code)
panes running inside tmux — plus a `/tmux-supervisor` slash command for
orchestrating multi-worker Claude sessions.

The headline tool is **`claude-msg`**: a queue + daemon pair that

- enqueues messages to a target tmux pane and returns immediately,
- waits until the target Claude pane is ready (UI loaded **and** input box
  empty — accounting for ANSI-dim placeholder text and live user typing),
- delivers FIFO per target, using bracketed-paste for multiline messages,
- verifies the input buffer cleared before archiving the message.

It exists because `tmux send-keys "<text>" Enter` against a Claude TUI is
unreliable: Enter occasionally drops, multiline pastes get split into many
submits, and there's no protection against interleaving with a human typing
into the same pane.

## Components

| Path                          | What it is                                                                 |
| ----------------------------- | -------------------------------------------------------------------------- |
| `bin/claude-msg`              | CLI submitter. Non-blocking. Auto-spawns the daemon.                       |
| `bin/claude-msg-daemon`       | Single-instance worker (flock). Drains the queue.                          |
| `bin/tmux-send`               | Older one-shot send wrapper. Kept for ad-hoc use; **prefer `claude-msg`**. |
| `commands/tmux-supervisor.md` | Slash-command skill that orchestrates a Claude supervisor + workers.       |
| `setup.sh`                    | Symlinks all of the above into `~/.local/bin` and `~/.claude/commands`.    |

The runtime queue lives at `~/.claude/msg-queue/`:

```
pending/   unsent JSON files (named <ts>-<target>-<uuid>.json)
sent/      delivered archive
failed/    gave up
daemon.log daemon output (truncated on each daemon start)
daemon.pid current daemon pid
```

## Install

```bash
git clone https://github.com/<your-user>/tmux-supervisor.git ~/dev/tmux-supervisor
cd ~/dev/tmux-supervisor
./setup.sh
```

This symlinks:

- `~/.local/bin/{claude-msg,claude-msg-daemon,tmux-send}` → `bin/*`
- `~/.claude/commands/tmux-supervisor.md` → `commands/tmux-supervisor.md`

and ensures `~/.claude/msg-queue/{pending,sent,failed}` exists.

Make sure `~/.local/bin` is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### `claude-msg`

```bash
# Short message:
claude-msg session:window "your message"

# Long / multiline:
claude-msg session:window --read-file /tmp/brief.txt

# Inspect / control:
claude-msg --list                 # show pending queue
claude-msg --flush session:window # drop pending messages for one target
claude-msg --daemon-status
claude-msg --daemon-start
claude-msg --daemon-stop
```

The submitter writes a JSON file to `pending/` and exits non-blockingly.
The daemon picks it up, checks the target is ready, sends the message,
verifies delivery, then moves the file to `sent/`. Hard failures
(target gone, send failed, unverified) move to `failed/` after
`CLAUDE_MSG_MAX_ATTEMPTS` retries (default 10).

### Readiness checks

A pane is **ready** when:

1. The Claude TUI is rendered. The daemon recognises both old (`╭─...─╮`
   boxed) and new (`❯ ` cursor + `bypass permissions on` footer) layouts.
2. The input box is empty. The daemon distinguishes:
   - actual emptiness,
   - the dimmed placeholder suggestion Claude shows when nothing is typed
     (detected via the `\e[2m` SGR escape — real typed text uses normal
     attributes),
   - in-progress user typing (waits up to `CLAUDE_MSG_MAX_READINESS_WAIT`
     seconds, default 3600).

This makes it safe to `claude-msg` a pane while a human is using it: the
message will land the moment the human submits or clears their draft.

### Tunables

| Env var                          | Default | Purpose                                                            |
| -------------------------------- | ------- | ------------------------------------------------------------------ |
| `CLAUDE_MSG_QUEUE_DIR`           | `~/.claude/msg-queue` | Queue location.                                       |
| `CLAUDE_MSG_IDLE_TICK`           | `2`     | Seconds between scans when queue empty.                            |
| `CLAUDE_MSG_WORK_TICK`           | `1`     | Seconds between checks when work is pending.                       |
| `CLAUDE_MSG_MAX_ATTEMPTS`        | `10`    | Retries for hard failures before moving to `failed/`.              |
| `CLAUDE_MSG_MAX_READINESS_WAIT`  | `3600`  | Max seconds to wait for an in-use pane (user typing / busy).       |
| `CLAUDE_MSG_PASTE_LINES`         | `2`     | Line count threshold for switching to bracketed-paste delivery.    |

### `/tmux-supervisor`

The slash command in `commands/tmux-supervisor.md` is intended for use
inside Claude Code. It walks Claude through:

- spawning a tmux session of worker panes (`tmux new-window …`),
- delivering briefs and reports through `claude-msg` (no manual `sleep` /
  `tmux send-keys` / dropped Enters),
- collecting results, summarising, and tearing down.

Once `setup.sh` has linked the file into `~/.claude/commands/`, the command
is available as `/tmux-supervisor` in any Claude Code session.

### `tmux-send` (legacy)

`tmux-send` is kept because it remains useful for one-off shell sends to
non-Claude panes (or when you genuinely want synchronous fire-and-forget).
For anything talking to a Claude TUI, prefer `claude-msg`.

## Suggested shell helper

Drop this into your `~/.zshrc` / `~/.bashrc` to spin up a coord session
with Claude pre-configured for orchestration:

```bash
claude-coord() {
  if [ -z "$1" ]; then
    echo "Usage: claude-coord <slug>"
    return 1
  fi
  local slug="$1"
  local target="${slug}:coord"
  tmux new-session -d -s "$slug" -n coord
  tmux select-pane -t "$target" -T "claude-coord-${slug}"
  tmux send-keys -t "$target" "claude --dangerously-skip-permissions --worktree $slug" Enter

  # Non-blocking: claude-msg's daemon waits for the TUI to be ready before
  # delivering. No manual sleeps required.
  claude-msg "$target" "/tmux-supervisor"
  claude-msg "$target" "/caveman"
  tmux attach -t "$slug"
}
```

## Development

The scripts are pure Bash + `tmux` + `python3` (used only for JSON
read/write in the daemon). No build step.

To smoke-test after a change:

```bash
# Restart daemon with new code:
pkill -f claude-msg-daemon || true
~/.local/bin/claude-msg --daemon-start

# Send to any live Claude pane:
~/.local/bin/claude-msg my-session:my-window "ping"
tail -f ~/.claude/msg-queue/daemon.log
```

## License

MIT.
