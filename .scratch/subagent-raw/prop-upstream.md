# Propagation check: does the #914 JSONC fix need to flow upstream?

**Answer: No. The fix is already upstream. Nothing needs to propagate to `hi-godot/godot-ai`.**
This is purely fork-local ticket bookkeeping + local-install hygiene.

## Evidence

### 1. Upstream IS a configured remote
```
git remote -v
origin    https://github.com/smileynet/godot-ai.git   (fetch/push)
upstream  https://github.com/hi-godot/godot-ai.git     (fetch/push)
```
So propagation is checkable directly (fetched read-only during this inspection).

### 2. The fix commit d0c91bd (#914) is already on upstream
```
git cat-file -t d0c91bd            -> commit (exists)
git merge-base --is-ancestor d0c91bd upstream/main -> YES (ancestor of upstream/main)
git branch -a --contains d0c91bd   -> includes remotes/upstream/main, remotes/upstream/HEAD
git tag --contains d0c91bd         -> v4.0.0, v4.0.1
git log --all --grep 914           -> d0c91bd "fix: read Zed's JSONC settings for status without a write path"
```
The fix is shipped in upstream tags **v4.0.0 and v4.0.1** and lives on `upstream/main`.
It is not fork-only — the fork inherited it FROM upstream.

### 3. Fork divergence from upstream is bookkeeping-only
```
ahead  (local main has, upstream/main lacks): 3
behind (upstream/main has, local main lacks): 10
```
The 3 fork-only commits touch ONLY `.tickets/01-jsonc-config-read-comment-strip.md`:
- 2f6c181 chore(tickets): new 01 jsonc-config-read-comment-strip
- 426a663 docs(tickets): populate 01
- beb3f37 chore(tickets): close 01

`git show --stat` on each confirms every change is inside `.tickets/`. No source, no plugin,
no docs, no CI. These are local ticket files (this fork's `.tickets/` workflow) and have no
business going upstream.

(The larger file list from a raw `diff --stat upstream/main..main` — CI, README,
client_job_owner.gd, tests, plugin.cfg, pyproject.toml — is the fork being 10 commits BEHIND,
not fork changes. Those are upstream's own later commits, e.g. #991 job-owner polling fix and
the v4.0.1 release prep, that the fork simply hasn't pulled.)

### 4. Version state
- Fork `main` plugin.cfg: **4.0.0**
- Upstream `main` plugin.cfg: **4.0.1** (upstream has moved on to a patch release)
- v4.0.0 tag plugin.cfg: 4.0.0
- Merge base: 1042a38

The fork is a slightly-behind copy of upstream v4.0.0 plus local ticket files. It does NOT
carry any unique source fix that upstream lacks.

## The mis-filed upstream #992
Ticket was originally mis-filed as upstream `hi-godot/godot-ai#992` (now closed). Correctly so:
the fix (#914 / d0c91bd) already shipped upstream in v4.0.0, so there was nothing for #992 to
add. Closing it was the right call.

## Does anything need to flow either direction?
- **Fork -> upstream: NO.** The only fork-unique commits are `.tickets/` files. Upstream already
  has the actual code fix (#914) in v4.0.0/v4.0.1. There is no source delta to send up.
- **Upstream -> fork: optional, not required for this task.** The fork is 10 commits behind
  (incl. v4.0.1 prep and the #991 job-owner polling fix). Pulling `upstream/main` would bring
  the fork current, but it is unrelated to the JSONC/#914 question and is not needed to resolve it.

## Recommendation
1. **No upstream propagation needed.** The #914 JSONC fix is already in `hi-godot/godot-ai`
   (v4.0.0 and v4.0.1). Confirm the mis-filed #992 stays closed — no action.
2. **Treat the remaining work as purely local-install hygiene**: the three v3.1.5 installs
   under `~/code` (gdhelper-log, teach-me, pnw-mystical) need to reach a v4 build that contains
   d0c91bd. That is a v3->v4 migration/update problem on those machines, not an upstream PR.
3. **Optional, out of scope for #914**: sync the fork forward to `upstream/main` (currently
   v4.0.1) at a convenient point so it isn't 10 commits stale. Read-only inspection only for
   this session — no pull/push performed.
