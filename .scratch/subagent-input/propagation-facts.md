# Facts: cross-project propagation of the #914 JSONC fix

## The fix
- Commit `d0c91bd` "fix: read Zed's JSONC settings for status without a write path" (#914).
- Lives in `plugin/addons/godot_ai/clients/_json_strategy.gd` (the read paths thread
  `_status_allows_comments`), `_base.gd` (config_allows_comments field), `zed.gd` (opt-in).
- Shipped in the dev tree at plugin version **4.0.0** (`plugin/addons/godot_ai/plugin.cfg`).
- Ticket 01 (this fork's `.tickets/01-...md`) is CLOSED as already-fixed-by-#914. Live repro
  in `.scratch/repro_zed_jsonc.gd` confirms v4 load paths are clean; the warning only fires on
  the strict no-flag read that is gated out for Zed.

## The affected installs (this machine, under ~/code)
Three local projects have the plugin at the OLD version that shows the warning:
- `/Users/sambiggins/code/gdhelper-log/addons/godot_ai/plugin.cfg` -> version="3.1.5"
- `/Users/sambiggins/code/teach-me/test-scene/addons/godot_ai/plugin.cfg` -> version="3.1.5"
- `/Users/sambiggins/code/pnw-mystical/addons/godot_ai/plugin.cfg` -> version="3.1.5"
(pnw-mystical had a live editor + MCP server running during investigation.)

The dev repo itself: `/Users/sambiggins/code/godot-ai` (canonical plugin source, v4.0.0).

## The relevant machinery (verify against repo docs before recommending)
- Self-update / migration: `docs/self-update.md`, `docs/v4-migration.md`,
  plugin `update_manager.gd` / `update_installer.gd` / `release_verifier.gd`.
  v3.1.5 was "the final signed v3 release supports a one-click migration to v4" (README).
- Releases: `docs/releasing.md`. v4 is a clean break from v3 wire/updater compat.
- Upstream relationship: ticket was originally mis-filed as upstream `hi-godot/godot-ai#992`
  (now closed). This is a FORK. Determine whether anything needs to flow upstream vs is
  purely fork-local + local-install hygiene.

## The question each subagent answers (see your specific prompt)
How should the fix reach the three v3.1.5 installs, given v3->v4 is a major migration (not a
silent in-place update)? What is the safest, least-surprising path per project, and what are
the risks (data loss, running-editor interference, worktree safety)?
