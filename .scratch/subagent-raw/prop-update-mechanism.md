# Official supported path: godot_ai plugin v3.1.5 → v4.0.0

Scope: how a project running the plugin at **v3.1.5** reaches **v4.0.0** (which
carries the #914 JSONC fix). Answers (1) auto vs manual, (2) what migration
touches, (3) preconditions. All citations are `path:line` against the dev repo
at `/Users/sambiggins/code/godot-ai`.

---

## TL;DR

- The supported v3→v4 path is a **one-click dock migration** ("click **Update**
  once in the Godot AI dock"), NOT a manual extract-over-the-tree re-install.
  Manually extracting a new add-on over the old tree is explicitly disallowed.
- BUT there is a **critical version caveat for v3.1.5 specifically**: the
  supported boundary is the *final signed v3 line* (v3.2.5), not any arbitrary
  v3. The documented behavior is that an older v3 updater **offers whatever
  release is latest** and self-heals — so the realistic path is
  **v3.1.5 → (v3 updater pulls latest v3) → final v3 → one-click v4 capsule
  crossing**, possibly two update clicks.
- **v4.0.0 is NOT PUBLICLY RELEASED YET.** Public v4 publication is fail-closed
  pending qualification + maintainer approval. The one-click path only works
  once publication opens. This is a hard blocker for the three real installs
  today.

---

## (1) Automatic one-click dock migration vs manual re-install

**Automatic one-click, via the dock — this is the ONLY supported end-user path.**

- README, "Existing installation": "click **Update** in the Godot AI dock when
  an update is offered. The final signed v3 release supports a one-click
  migration to v4; Godot restarts once ... Do not extract a new add-on over the
  old tree."
  (`README.md`, "1. Install or update" → Existing installation paragraph)
- v4-migration.md is explicit: "The normal migration is one click" and lists
  the three steps (backup, ensure `uvx`, open in Godot 4.7+ and click
  **Update** once). (`docs/v4-migration.md:3-9`)
- "For supported clients, you do not need to download release files, run a
  verifier, stop the server, edit client configuration, press a second
  confirmation button, or restart Godot yourself." (`docs/v4-migration.md`,
  paragraph after the 3 steps)
- The closed-editor `script/v4-release install` path exists but is explicitly
  **not** the end-user path: "It is not the normal user migration path and
  should not be copied into end-user instructions."
  (`docs/v4-migration.md`, "If the migration is interrupted" section) and
  "it is not an end-user path." (`docs/releasing.md`, "The update path")

Mechanism under the hood: v3's own signed-sidecar updater downloads the
**migration capsule** (`godot-ai-plugin.zip` + `.sha256` + `.sha256.sig`), which
is a small bridge plugin with the canonical v4 triple embedded. v3 authenticates
the capsule and extracts it; the bridge then runs the v4 installer inside the
editor and restarts. (`docs/self-update.md`, "The v3-to-v4 capsule";
`docs/v4-migration.md`, "What the Update click does" steps 1-4)

---

## (2) What happens to project files and client configs during migration

### Add-on tree (the plugin itself)
- **Two-rename atomic swap, never a file-by-file overlay.** The complete
  pre-update add-on (bridge included) is renamed to
  `addons/.godot_ai_update/backup/<old version>/`, and the staged, verified v4
  tree is renamed into place. (`docs/v4-migration.md`, "What the Update click
  does" step 3; `docs/self-update.md`, step 7 "Swap")
- v3's `game_helper` autoload is removed before the swap (fix #946).
  (`docs/self-update.md`, "The v3-to-v4 capsule"; `docs/v4-migration.md` step 3)
- The old tree is **retained** as a backup until the next successful update
  replaces it. Nothing is deleted automatically on any failure path.
  (`docs/self-update.md`, step 10 "Retain" and "What this does not defend
  against"; `docs/v4-migration.md`, "If the migration is interrupted")

### The user's own project files (scenes, scripts)
- Migration touches only `addons/godot_ai/` and the sibling
  `addons/.godot_ai_update/` working directory. There is no documented mutation
  of user scene/script files by the migration itself.
- **Indirect risk**: step 1 of the update "saves the project" before relaunching
  (`docs/self-update.md`, step 1 "Check"). Any in-memory unsaved/AI-driven scene
  mutations get autosaved to disk at that point (consistent with the AGENTS.md
  "project_run autosave" trap). Commit/back up first.

### Client configs (MCP client entries)
- Owned client entries are **repinned/migrated automatically** on the first v4
  start after the swap.
- The crossing marker carries `replace_owned_mismatches`, so **v3-shaped owned
  entries are replaced outright** (an ordinary v4→v4 update instead keeps a
  pin-only repin and reports other drift for **Configure all**).
  (`docs/v4-migration.md`, "What the Update click does", the paragraph on the
  first v4 start; `docs/self-update.md`, step 9)
- **Cherry Studio is NOT migrated** — remove its stale v3 entry in Cherry Studio
  itself; the plugin cannot safely edit that app's internal DB.
  (`docs/v4-migration.md:` opening caveat and "Supported boundary")
- **Foreign client entries are reported, not migrated** — an entry under our
  name that launches something other than Godot AI is left untouched and named
  in editor output. (`docs/self-update.md`, "Known limits (4.0.0)")
- A client that doesn't notice its config change may need to be reopened, but
  restarting every client is **not** a migration step or a server-start gate.
  (`docs/v4-migration.md`, end of "What the Update click does")

### Server
- The matching managed v4 server is restarted automatically; `uvx` runs it.
  No separate process/package download is part of the update.
  (`docs/v4-migration.md`, first-v4-start paragraph)

---

## (3) Preconditions — what must be true before triggering

1. **A signed public v4 release must exist.** THE BLOCKER TODAY:
   "The public v4 release is not available yet: publication remains fail-closed
   until the cross-platform qualification run is complete and the maintainer
   approves promotion. ... Do not install an unpublished candidate into a real
   project." (`docs/v4-migration.md`, paragraph after "What the Update click
   does" intro). The dev tree is v4.0.0 (`plugin/addons/godot_ai/plugin.cfg:5`)
   but that is source, not a published signed release.
2. **Godot 4.7+.** v4 requires Godot 4.7 or newer in the 4.x line.
   (`docs/v4-migration.md:1-2`; README "Requirements"). On Godot 4.5/4.6 the
   bridge loads only far enough to explain the requirement and does NOT activate
   v4; upgrade Godot, reopen, click **Retry migration**.
   (`docs/v4-migration.md`, "Supported boundary")
3. **`uvx` installed and on `PATH`.** (`docs/v4-migration.md:6`)
4. **Back up or commit the project first** — the documented step 1.
   (`docs/v4-migration.md:5`; README "Existing installation").
5. **Leave Godot open during migration** — it restarts itself once; don't
   manually restart Godot. (`docs/v4-migration.md`, after the 3 steps)
6. **Editor lock / single editor**: the update takes an editor lock; a second
   editor on the same project racing past the process check is an unguarded
   case. Practically: only one editor on the project during migration.
   (`docs/self-update.md`, step 6 "Lock" and "What this does not defend
   against")

### The v3.1.5-specific caveat (IMPORTANT — the installs are 3.1.5, not final v3)
- The documented **supported boundary** is "the final signed v3 line to v4 on
  Godot 4.7+." (`docs/v4-migration.md`, "Supported boundary"; `docs/self-update.md`
  "The v3-to-v4 capsule" refers to the final v3 re-packed from the **`v3.2.5`**
  tag).
- v3.1.5 is an *intermediate* signed v3, not the final v3.2.5. The docs say a
  pre-v4 updater "offer[s] whatever release is latest and cannot know that v4
  needs Godot 4.7" (`docs/self-update.md`, "The v3-to-v4 capsule"), and:
  "Very old, unsigned updater generations are outside the automatic migration
  security boundary; update them to the latest v3 release first or ask for
  recovery help." (`docs/v4-migration.md`, "Supported boundary")
- v3.1.5 is signed (it shows an update path), so it is inside the signed
  boundary — but the safest documented sequence is to let the v3 updater bring
  each install to the **latest v3 first**, then perform the one-click v4
  crossing. Expect potentially **two Update clicks**.

---

## Supported upgrade path (step by step)

Preconditions: signed public v4 release published; Godot 4.7+ installed; `uvx`
on PATH; project committed/backed up; only one editor open on the project.

1. Commit or back up the project (git commit the whole project dir).
2. Ensure `uvx` is installed and on `PATH`.
3. Ensure Godot is **4.7+**. If on 4.5/4.6, upgrade Godot first — v4 will not
   activate otherwise.
4. Open the project in Godot 4.7+.
5. In the Godot AI dock, click **Update**. If the v3.1.5 updater offers a newer
   v3 (not v4) first, accept it, let Godot restart, then click **Update** again
   for the v4 crossing.
6. Leave Godot open. It saves the project, verifies + stages the v4 tree, does
   the two-rename swap, and restarts itself once automatically.
7. On the v4 start, the plugin re-hashes the live tree against the signed
   inventory, records `success`, repins owned client entries (v3-shaped ones
   replaced outright), and starts the managed v4 server.
8. Reopen any MCP client that didn't notice its new config. Remove any stale
   Cherry Studio v3 entry manually.
9. Verify: check the dock shows v4.0.0 and connected; confirm the marker at
   `addons/.godot_ai_update/pending.json` is `status: success`.

---

## Risks

- **HARD BLOCKER: no published signed v4 release exists yet.** The one-click
  path cannot run against a real install today. Installing an unpublished
  candidate into a real project is explicitly warned against.
  (`docs/v4-migration.md`)
- **Running editor + live MCP server interference** (pnw-mystical had this):
  the update quiesces the dispatcher and takes an editor lock, but a second
  editor racing the lock is unguarded. Close extra editors first.
- **Autosave-on-update data pollution**: the update saves the project before
  restart; any unsaved in-memory scene mutations get persisted. Commit first so
  you can revert.
- **Godot below 4.7**: migration will not complete; the bridge (in the
  transitional fallback) can restore final v3 in place instead of leaving a dead
  tree, then you upgrade Godot and retry. (`docs/self-update.md`, "The v3-to-v4
  capsule" fallback)
- **Marker states after an interrupted swap**: `rolled_back` (previous version
  restored, dock shows reason) or `repair_required` (no backup — plugin inactive,
  restore `addons/godot_ai/` from VCS or run `script/v4-release install`). Never
  delete `addons/.godot_ai_update/` by hand while unresolved.
  (`docs/self-update.md`, step 9 and "Known limits"; `docs/v4-migration.md`,
  "If the migration is interrupted")
- **Client-mutation lock stranding**: post-update repin shares an account-wide
  lock; a stranded lock fails client mutation closed. Recovery is to stop the
  MCP client processes and remove the exact lock dir printed in the error.
  (`docs/releasing.md`, "Recovering a stranded client mutation lock")
- **Cherry Studio & foreign entries not migrated** — manual cleanup needed.
- **v3.1.5 is not final v3 (v3.2.5)** — may require an intermediate v3 update
  before the v4 crossing; treat as a two-step path.

---

## Fork note (from the input file's framing)
The #914 fix lives in the dev tree at v4.0.0. Because no signed public v4
release exists yet, the documented one-click path cannot deliver it to the three
v3.1.5 installs today. For a **fork-local** delivery, the honest options are (a)
wait for/produce a signed v4 release and use the dock path, or (b) closed-editor
`script/v4-release install` against a locally built+signed candidate (a
qualification/recovery tool, not the end-user path) — this bypasses the v3
capsule crossing entirely and requires building the signed release locally.
Either way, this is release-availability–gated, not a limitation of the update
machinery itself.
