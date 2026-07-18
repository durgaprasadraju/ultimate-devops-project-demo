# Git Issues Encountered in This Project

> A practical record of the Git problems you hit while wiring CI/CD + Argo CD,
> why each one happened, and how to fix or avoid it next time.
>
> For **all** issues in this session (CI, Argo CD, Docker Hub, GitHub Actions,
> and Git), see the full log: [ISSUES_AND_FIXES.md](./ISSUES_AND_FIXES.md).

---

## Quick map of what went wrong

| # | Symptom you saw | Root cause | Fix |
|---|-----------------|------------|-----|
| 1 | `fatal: Need to specify how to reconcile divergent branches` | Local and remote both have unique commits; Git has no default pull strategy | `git pull --rebase origin main` |
| 2 | `! [rejected] main -> main (non-fast-forward)` | Remote moved ahead (CI commit) while you had local commits | Pull/rebase first, then push |
| 3 | Branches keep diverging after every CI run | CI commits image-tag updates back to `main` | Always `pull --rebase` before push |
| 4 | Push fails from Cursor agent: `could not read Username` | Agent environment has no GitHub credentials | Push from your own terminal |
| 5 | (Earlier CI design) Force-push to `main` | Old workflow used `git push -f` | Removed; CI now does normal push + rebase |

---

## 1. Divergent branches on `git pull`

### What you saw

```text
hint: You have divergent branches and need to specify how to reconcile them.
hint:   git config pull.rebase false  # merge
hint:   git config pull.rebase true   # rebase
hint:   git config pull.ff only       # fast-forward only
fatal: Need to specify how to reconcile divergent branches
```

### What it means

Your local `main` and `origin/main` both had commits the other did not:

```text
Local:   A -- B -- C (your commits)
Remote:  A -- D       (someone else's / CI commit)
```

Git refuses to guess whether you want a **merge commit** or a **rebase**.

### Why it happened here

1. You committed locally (workflow fixes).
2. At the same time, CI (or another push) added a commit on GitHub.
3. Histories forked → “divergent branches”.

### Fix (recommended for this repo)

Do **not** change global git config unless you want to. Use per-command:

```bash
git pull --rebase origin main
```

That replays your local commits **on top of** remote:

```text
Result:  A -- D -- B' -- C'
```

Then:

```bash
git push origin main
```

### Alternatives (know the difference)

| Command | Result | When to use |
|---------|--------|-------------|
| `git pull --rebase` | Linear history, no merge commit | Day-to-day on `main` with CI commits |
| `git pull --no-rebase` | Creates a merge commit | When you explicitly want a merge |
| `git pull --ff-only` | Succeeds only if no divergence | Strict “no rewrite / no merge” |

---

## 2. Push rejected: non-fast-forward

### What you saw

```text
! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to 'https://github.com/...'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
```

### What it means

GitHub’s `main` has commits you don’t have locally. A normal push would **overwrite** those remote commits, so Git blocks it.

```text
Remote tip:  ... -- CI-commit
Your tip:    ... -- your-commit   (missing CI-commit)
```

### Why it happens often in *this* project

Your reusable CI workflow does this after building an image:

1. Updates `kubernetes/<service>/deploy.yaml` with the new image tag.
2. Commits: `[CI]: Update <service> image tag to <run_id>`
3. Pushes that commit to `main`.

So **every successful service build moves `origin/main` forward**. If you still have unpushed local commits, your next `git push` will fail until you integrate.

### Fix

```bash
git pull --rebase origin main
git push origin main
```

Typical status after a successful rebase:

```text
## main...origin/main [ahead 1]
```

That means: “I have 1 local commit ready to push; remote is fully included.”

### What **not** to do

| Bad idea | Why |
|----------|-----|
| `git push --force` on `main` | Deletes remote CI / teammate commits |
| Ignore the rejection and keep committing | Divergence grows; harder to resolve later |

---

## 3. “CI keeps rewriting my main” (ongoing friction)

### What’s going on

This is **not a Git bug**. It’s GitOps by design in this repo:

```text
You push code
    → GitHub Actions builds image
    → Actions commits new image tag into kubernetes/.../deploy.yaml
    → Argo CD sees Git change → deploys to EKS
```

So `main` receives:

- Human commits (features, workflow fixes)
- Bot commits (`[CI]: Update ... image tag`)

### How to work with it cleanly

Before every push to `main`:

```bash
git fetch origin
git status
# if behind or diverged:
git pull --rebase origin main
git push origin main
```

Or as one habit:

```bash
git pull --rebase origin main && git push origin main
```

### Why CI serializes builds (`max-parallel: 1`)

If two services finished at once and both tried:

```bash
git commit && git push
```

they would race and often fail with rejected pushes / rebase conflicts. The workflow builds **one service at a time** when updating Git for that reason.

---

## 4. Agent / Cursor cannot push (credential gap)

### What you saw (from the agent environment)

```text
fatal: could not read Username for 'https://github.com': No such device or address
```

### What it means

The AI sandbox can often **fetch** and **rebase** using existing remotes, but it does **not** have your GitHub login/password/PAT for **push**.

### Fix

Always push from **your** terminal (where you already authenticated):

```bash
git push origin main
```

If HTTPS asks for a password, use a [GitHub Personal Access Token](https://github.com/settings/tokens), not your GitHub account password. Or use SSH:

```bash
git remote -v
# ideally: git@github.com:durgaprasadraju/ultimate-devops-project-demo.git
```

---

## 5. Old anti-pattern (already fixed in workflows)

### What the original product-catalog CI did

```bash
git push origin HEAD:main -f
```

### Why that was dangerous

Force-push rewrites remote history. It can:

- Wipe CI commits
- Wipe teammate commits
- Break Argo CD / other clones that already pulled the old tip

### Current safer pattern

1. CI updates the manifest.
2. `git pull --rebase` (inside the workflow).
3. Normal `git push` (no `-f`).
4. Callers grant `permissions: contents: write` so the bot can push.

---

## Mental model for *your* repo

```text
┌──────────────────┐     push / CI commit      ┌──────────────────┐
│  Your laptop     │ ─────────────────────────► │  GitHub main     │
│  (local commits) │ ◄─── pull --rebase ─────── │  + CI tag commits│
└──────────────────┘                            └────────┬─────────┘
                                                         │
                                                         │ Argo CD watches
                                                         ▼
                                                ┌──────────────────┐
                                                │  EKS (otel-demo) │
                                                └──────────────────┘
```

**Rule of thumb:** treat `main` as shared. Never assume you’re the only writer. CI is another writer.

---

## Cheat sheet (copy/paste)

### Before pushing

```bash
git status
git pull --rebase origin main
git push origin main
```

### After a rejected push

```bash
git pull --rebase origin main
# resolve conflicts if any, then:
git add .
git rebase --continue   # only if conflict during rebase
git push origin main
```

### See why you diverged

```bash
git fetch origin
git log --oneline --left-right HEAD...origin/main
```

- `<` = only on your machine  
- `>` = only on GitHub  

### Abort a bad rebase

```bash
git rebase --abort
```

---

## How these issues connected to CI/CD work

| DevOps change | Git side effect |
|---------------|-----------------|
| CI updates `deploy.yaml` and pushes to `main` | You get “behind / divergent” often |
| Manual `workflow_dispatch` builds all services | Many CI commits in a row → pull before every local push |
| Path filters + per-service builds | Fewer unexpected runs, but CI still owns image-tag commits |
| Argo CD syncs Git → cluster | Git history *is* the deployment record |

---

## Summary

You didn’t break Git. You hit the normal friction of a **shared `main` branch with automated commits**:

1. **Divergent pull** → need explicit `--rebase` (or merge).
2. **Non-fast-forward push** → remote moved first; rebase then push.
3. **CI commits** → expected; pull often.
4. **Agent can’t push** → push from your authenticated terminal.
5. **Force-push** → removed from workflows; don’t bring it back on `main`.

If you remember only one command for this project:

```bash
git pull --rebase origin main && git push origin main
```
