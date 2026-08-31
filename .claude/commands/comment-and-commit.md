# /comment-and-commit

Stage the work that's waiting in the working tree, compose a high-quality commit message that accurately describes it, and commit. **Does not push.**

Optional argument (`$ARGUMENTS`): extra context to fold into the message — a ticket id, a scope hint, or an instruction like "split into two commits".

## Conventions (must follow)

- **Conventional Commits**: `type(scope): summary` — imperative mood, summary ≤ 72 chars. Types used in this repo: `feat`, `fix`, `docs`, `test`, `refactor`, `chore` (and combined forms like `test+docs`). Scope matches the area touched (`auth`, `documents`, `settings`, `orgs`, `lists`, …).
- The summary says **what changed and why**, never "update files" / "changes".
- Every commit message **ends with this trailer, exactly**:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```
- **Never push** from this command.
- **Never commit on the default branch** (`main`): if HEAD is `main`, isolate the work first (see Worktrees).
- Every commit also ends with any session trailer the harness specifies (e.g. `Claude-Session: <url>`) in addition to the `Co-Authored-By` line above.

## Worktrees (default for feature work)

Isolated/feature work happens in a dedicated **git worktree**, not by switching branches in the primary checkout — this keeps the main checkout clean and lets parallel efforts coexist. Agent worktrees live under `.claude/worktrees/`.

- **Know where you are:** `git worktree list` (all trees + their branches) and `git rev-parse --show-toplevel` (current root). The first `worktree list` entry is the primary checkout.
- **Already in a worktree** (a `.claude/worktrees/…` or `../interlinedlist-ios-<topic>` dir): just commit here — the steps below are identical. Still never commit on the base branch.
- **Starting fresh isolated work** from the primary checkout: create a worktree with its own branch instead of editing in place, then work and commit inside it:
  ```bash
  git worktree add ../interlinedlist-ios-<topic> -b <type>/<short-topic>
  ```
  (If the harness exposes an `EnterWorktree` tool, prefer it — it does the same thing.)
- **Changes already dirty in the primary checkout** (you edited in place before branching): don't fight it — branch in place (`git switch -c <type>/<topic>`) and commit; use a worktree from the outset next time. `git worktree add` creates a *clean* tree and will not carry your uncommitted edits.

## Steps

1. **Survey what's waiting** — never commit blind:
   ```bash
   git status
   git diff --stat HEAD
   git diff HEAD            # full diff: staged + unstaged
   ```

2. **Safety-check the branch / worktree** (see Worktrees above):
   ```bash
   git rev-parse --abbrev-ref HEAD
   git worktree list          # confirm whether you're in the primary checkout or a worktree
   ```
   If HEAD is `main`: create a worktree for the work (`git worktree add ../interlinedlist-ios-<topic> -b <type>/<topic>`) and continue there, or — if changes are already dirty here — `git switch -c <type>/<short-topic>` in place.

3. **Review, then stage.** Read the diff and decide what belongs in this commit. By default stage everything that's part of the work:
   ```bash
   git add -A
   ```
   Unstage anything machine-local or unrelated (`git restore --staged <file>`). Treat `.claude/settings.local.json` with suspicion — it accumulates session permission grants; include it only if those changes are intentional.

4. **Compose the message from the actual diff.** If the changes span clearly independent concerns, either (a) pick the strongest `type(scope)` for the summary and enumerate the other areas as body bullets, or (b) if the user asked for it, split into multiple commits via per-path / `git add -p` staging and repeat steps 3–5 per commit.

5. **Commit** with a HEREDOC so the body and trailer survive intact:
   ```bash
   git commit -F - <<'EOF'
   type(scope): concise imperative summary

   - concrete change and the reason it was needed
   - another concrete change

   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   EOF
   ```

6. **Confirm and report:**
   ```bash
   git show --stat HEAD
   ```
   Report the commit hash + subject. Do not push; mention that `/commit-and-pr` will push and open a PR if that's the next step.
