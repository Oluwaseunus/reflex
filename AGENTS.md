# Reflex Codex Worktree Setup

When starting work in a new Codex worktree for this project, first copy the local development helper files from the canonical Reflex checkout. Derive paths from Git instead of hard-coding a user-specific home directory:

```sh
worktree_root="$(git rev-parse --show-toplevel)"
canonical_root="$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)"

cp "$canonical_root/save" "$worktree_root/save"
chmod +x "$worktree_root/save"
cp "$canonical_root/.env" "$worktree_root/.env"
```

Notes:
- Do this whenever a new Codex worktree is created or a new conversation starts in a newly created Reflex worktree.
- Do not print, summarize, commit, or otherwise expose `.env`; it contains local secrets and is intentionally git-ignored.
- The `save` script should remain executable.
- After making code or project-file changes, run `./save` before sending the final response.
- If `./save` fails, or if the user explicitly asks not to run it, report that clearly in the final response.
