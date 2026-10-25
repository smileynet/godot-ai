# Code review task: JSONC comment-strip on the configure() read path

## Ticket

`.tickets/01-jsonc-config-read-comment-strip.md` — read it fully first.

Summary: A `config_allows_comments = true` client (Zed) emits a spurious
`MCP | JSON parse error on line 0` warning at editor load because the
`configure()` pre-read strict-parses JSONC, while the `check_status` read
threads the JSONC flag.

## Files to read and analyze

- `plugin/addons/godot_ai/clients/_json_strategy.gd` — the strategy. Key funcs:
  - `configure()` — calls `_read_or_init(read_path)` (NO allow_comments arg).
  - `check_status_details()` — calls `_read_or_init(path, _status_allows_comments(client))`.
  - `_status_allows_comments(client)` = `config_allows_comments and not automatic_config_edits`.
  - `_read_or_init(path, allow_comments=false)` -> `_read_file_text(path, allow_comments)`.
  - `_read_file_text` strips JSONC only when allow_comments; else strict-parse + push_warning.
  - Also: `manual_target_details`, `authoritative_tier_path`, `_load_project_definitions`,
    `_load_merge_tiers` — some thread allow_comments, some don't. Audit ALL callers.
- `plugin/addons/godot_ai/clients/zed.gd` — Zed descriptor. Note `automatic_config_edits = false`.
- `plugin/addons/godot_ai/clients/_base.gd` — McpClient base; find where config_allows_comments,
  automatic_config_edits are declared and any related invariants.
- Search for other clients with `config_allows_comments = true` (grep the clients/ dir).
- Find where configure() is triggered on editor load (auto-configure flow) — grep for
  `configure(` and the dock/registration code. Confirm whether Zed's `automatic_config_edits=false`
  means configure() actually runs at load, or whether the warning comes from a DIFFERENT read path
  (status/manual). The ticket claims "auto-configure-on-load flow" — VERIFY this precisely.

## Critical question to resolve

`_status_allows_comments` has a documented invariant: it is READ-ONLY by construction, so
"no Configure/Remove can parse a file it would then re-serialize without the discarded comments."
`configure()` WRITES the file after reading. If we thread comment-stripping into configure()'s
read, and configure() then writes, comments would be DROPPED from the user's file.

Determine:
1. For Zed (`automatic_config_edits=false`), does configure() ever actually reach the write?
   Trace the code path. Does the dock gate configure() on automatic_config_edits?
2. Is the correct fix to thread the flag into configure()'s read (ticket's proposal), OR is the
   real bug that a read-only inspection path is misrouted through configure()? Which read is
   ACTUALLY producing the load-time warning?
3. Enumerate every `_read_or_init` / `_read_file_text` caller and classify each as read-only
   (safe to strip comments) vs read-then-write (stripping would drop comments on write).

## Output

Write findings to `.scratch/subagent-raw/code-review.md`:
- Confirmed/refuted ticket claims with exact current line numbers.
- The actual load-time code path that emits the warning (traced).
- Caller inventory table: func | reads-only or read-then-write | threads allow_comments? | correct?
- Recommended fix, with reasoning about the read-only invariant.
- Any test files covering this (grep tests/ and test_project/tests/).
