# Per-project update plan: three local v3.1.5 godot_ai installs

Scope: how the #914 JSONC fix (shipped in dev-tree plugin **4.0.0**) should reach the three
local installs still on **3.1.5**. Verified against `docs/v4-migration.md`, `docs/self-update.md`
references, `AGENTS.md` editor-safety rules, and direct inspection of each project.

## The blocking fact (applies to all three)

`docs/v4-migration.md` (L1 — governing project doc): **"The public v4 release is not available
yet: publication remains fail-closed until the cross-platform qualification run is complete and
the maintainer approves promotion... Do not install an unpublished candidate into a real
project."**

So the supported one-click **Update** → v4 migration path **cannot deliver the fix today** — there
is no published v4 release for the in-dock updater to fetch. Any attempt to force the fix in now
means hand-copying an unpublished candidate tree over a live install, which the migration doc
explicitly warns against and which bypasses the signed-capsule trust boundary. **The correct
action for all three is: do nothing until v4 publishes, then use the in-dock Update button per
project, in the safe order below.** None of these are urgent — the #914 symptom is a cosmetic
Zed JSONC parser *warning* on a strict no-flag read; v3.1.5 is otherwise functional.

## Classification + plan

| Project | Live / throwaway / real | Recommended action | Ordering | Risks | Who triggers |
|---|---|---|---|---|---|
| **teach-me/test-scene** | **Throwaway sub-project.** `test-scene/` is a shader/asset scratch scene (kaykit-dungeon assets, `shader_test.tscn`) nested in the real `teach-me` project; its `addons/` holds only `godot_ai`. Disposable. | **First candidate — or skip entirely.** Ideal low-stakes proving ground: migrate here first to confirm v4 flow on this machine before touching real projects. If the scene has no ongoing value, the cheaper action is to **remove the stale addon** (`addons/godot_ai/`) rather than migrate. Confirm which with the human. | **1st** (proving ground) | Editor must NOT be another session's live worktree — `test-scene` is inside the active `teach-me` project (very recent mtimes), so ensure no teach-me editor session is running against it first. Autosave persistence risk is low (throwaway scene) but non-zero. | Human runs it manually in-editor (open `test-scene/` in Godot 4.7+, click **Update**). Not agent-triggerable — needs a running editor + click. |
| **gdhelper-log** | **Real project, currently idle.** The gdhelper_log addon's own dev repo (100+ tickets, own `addons/gdhelper_log`, active through late Aug). `addons/godot_ai` is a dev tool it consumes. Last `.godot` activity Aug 29 — **no live editor now.** | **Migrate after test-scene proves the flow.** Standard supported path: commit/backup the repo, open in Godot 4.7+, click **Update** once. Because it's version-controlled, the `addons/godot_ai/` swap is fully recoverable via git. | **2nd** | Real work at stake, but git-backed → recoverable. Confirm no editor is open before starting (avoid the two-editors-racing-the-lock hazard from the migration security-boundary note). Requires `uvx` on PATH and Godot ≥ 4.7. | Human, in-editor. Agent may prepare (verify clean git tree, `uvx` present, Godot version) but the click is human. **Needs explicit human confirmation** (real project). |
| **pnw-mystical** | **Real, actively-developed game** (dialog_test, animation_test, click_test, main_menu — real features; `.godot/editor` touched Sep 07 15:21). **Had a live editor + MCP server during investigation.** | **Migrate LAST, and only from a cleanly-closed editor.** `godot_ai` here is NOT gd-plug-managed (`plug.gd` tracks only gdhelper-log, gdUnit4, inkgd, GDScript-formatter), so it uses the in-dock self-update path. Steps: (1) stop any MCP-driven work, (2) `git status` and commit/stash pending scene work — autosave during `project_run`/migration persists in-memory MCP mutations to `.tscn` on disk, (3) confirm only ONE editor instance, (4) open in 4.7+, click **Update** once, let Godot self-restart. | **3rd (last)** | **Highest.** Live editor + running MCP server ⇒ (a) autosave-on-migration can commit uncommitted in-memory scene mutations to disk (AGENTS.md live-smoke hygiene); (b) the migration security boundary explicitly does NOT defend against "two editors on the same project racing past the lock's process check" — a second live instance during the swap is a real corruption risk; (c) a running managed server should be quiesced first. | Human only, from a clean single-editor session. **Needs explicit human confirmation.** Do NOT let an automated/agent flow trigger this while an editor or MCP server is live. |

## Updates that need explicit human confirmation

- **pnw-mystical** — REQUIRED. Live real game, was running editor+server. Confirm editor fully
  closed, single instance, pending scene work committed, before the human clicks Update.
- **gdhelper-log** — REQUIRED. Real (if idle) project; confirm clean git tree and no open editor.
- **teach-me/test-scene** — confirm the decision (migrate as proving ground **vs** remove the stale
  addon). Lower stakes because it's throwaway, but still confirm no teach-me editor is live against it.

## Cross-cutting risks and preconditions (all three)

- **No published v4 yet** → the in-dock Update can't fetch the fix today. Gate all three on v4
  publication. Do not hand-install the unpublished candidate over any real project.
- **Godot ≥ 4.7 + `uvx` on PATH** are hard preconditions for the v4 migration (4.5/4.6 only show
  the refusal/"Retry migration").
- **One editor per project during the swap.** The two-renames swap + marker is recoverable, but a
  second live instance racing the lock is outside the security boundary.
- **Autosave persists MCP mutations.** Any live-editor project (esp. pnw-mystical) must have
  pending in-memory scene changes committed/stashed before migration, or use the throwaway-scene
  discipline from AGENTS.md.
- **Editor-launch safety.** Only launch Godot at a project's own real directory — never point an
  editor at another session's worktree (irrelevant to these three, which are standalone repos, but
  the rule stands if any is opened via a worktree).

## Recommended sequence (once v4 is published)

1. **teach-me/test-scene** — migrate as low-stakes proving ground (or remove the addon). Confirms
   the machine's v4 flow (`uvx`, signing, restart) before any real project.
2. **gdhelper-log** — git-backed real project, idle. Recoverable if the swap misbehaves.
3. **pnw-mystical** — real live game, last. Only from a cleanly-closed, single-instance editor with
   all pending scene work committed and the managed server quiesced.

## Upstream vs fork-local (from the facts)

The #914 fix already lives in this fork's dev tree at 4.0.0; the mis-filed upstream issue
(`hi-godot/godot-ai#992`) is closed. Nothing needs to flow upstream — this is purely fork-local
release publication + local-install hygiene. The three installs get the fix through a normal
published-v4 migration, not a special propagation step.
