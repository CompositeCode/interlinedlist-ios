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
- **Never commit on the default branch** (`main`): if HEAD is `main`, create and switch to a descriptive feature branch first.

## Steps

1. **Survey what's waiting** — never commit blind:
   ```bash
   git status
   git diff --stat HEAD
   git diff HEAD            # full diff: staged + unstaged
   ```

2. **Safety-check the branch**:
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
   If it prints `main`, branch first: `git switch -c <type>/<short-topic>`.

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
