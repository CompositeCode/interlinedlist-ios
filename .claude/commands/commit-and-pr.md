# /commit-and-pr

Commit all waiting work using the `/comment-and-commit` flow, push the branch, and open a pull request whose description summarizes everything the PR includes.

Optional argument (`$ARGUMENTS`): a PR title hint, a base-branch override, or extra context for the PR body.

## Conventions (must follow)

- **Runs `/comment-and-commit` first**, honoring all of its rules (Conventional Commits, the `Co-Authored-By` trailer, never committing on `main`).
- **Base branch** defaults to `main` unless `$ARGUMENTS` overrides it.
- The **PR body ends with this line, exactly**:
  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```
- Opening a PR is outward-facing: verify the branch, base, and commit list look right before creating it.

## Steps

1. **Commit waiting work.** Perform every step of `/comment-and-commit` so the tree is clean and all work is committed. If there's nothing to commit but the branch is already ahead of the base, continue.

2. **Determine branch + base, and preview the PR contents:**
   ```bash
   git rev-parse --abbrev-ref HEAD          # feature branch — must not be the base
   git log --oneline main..HEAD             # every commit this PR will include
   ```
   If HEAD equals the base branch, stop — step 1 should have branched.

3. **Push and set upstream:**
   ```bash
   git push -u origin HEAD
   ```

4. **Compose the PR** to describe the whole branch, not just the last commit:
   - **Title** — one Conventional-Commits-style line summarizing the branch.
   - **Body** — a `## Summary` paragraph; a `## What's included` list grouped from `git log main..HEAD`; a `## Testing` note (what was built/run and the result); and any caveats or follow-ups.

5. **Create the PR** (HEREDOC body keeps formatting and the trailer):
   ```bash
   gh pr create --base main --head "$(git rev-parse --abbrev-ref HEAD)" \
     --title "type(scope): summary of the whole branch" \
     --body "$(cat <<'EOF'
   ## Summary
   One or two sentences on the goal of this PR.

   ## What's included
   - area: concrete change (commits abc123, def456)
   - area: concrete change

   ## Testing
   - `xcodebuild ... test` — N passed

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

6. **Report the PR URL** that `gh` prints. If `gh` isn't authenticated, surface the error and tell the user to run `! gh auth login` in the prompt (so the interactive login lands in this session), then re-run.
