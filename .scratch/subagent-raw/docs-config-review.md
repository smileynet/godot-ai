# docs-config-review — Ticket 01 context (JSONC / Zed comment handling)

Scope: docs + config review only. No code changes made. This is a reference inventory of the *documented contract*, *doc gaps*, and *existing test coverage* around JSONC / `config_allows_comments` / `automatic_config_edits` / Zed configuration — so ticket 01's fix knows what already exists and where a regression test belongs.

## 1. Documented contracts (quoted, with file:line)

### `docs/client-configuration.md`

The single authoritative prose contract lives here.

- `docs/client-configuration.md:198-207` — the read-side JSONC contract:
  > `automatic_config_edits = false` marks a client whose settings file the dock never rewrites: Configure and Remove return the manual entry instead. `config_allows_comments = true` is its read-side companion for JSONC clients — Zed's `settings.json` opens with a `//` header that `JSON.parse` rejects, so without it a stock install shows a permanent parse error. Status, the manual instructions, and Open/Reveal strip `//` and `/* */` from a throwaway parse copy; markers inside JSON strings survive, and an unterminated block comment fails closed. No write path takes that branch, and the flag is honored only while `automatic_config_edits` is false, so a JSONC descriptor cannot pick up a comment-destroying rewrite by flipping one field.

- `docs/client-configuration.md:186-190` — Zed's untagged-enum sharp edge (why HTTP-only keys must be scrubbed, why it stays manual):
  > Zed's untagged entry enum makes removing `url`/`headers`/`oauth` load-bearing

- `docs/client-configuration.md:152` — the byte-for-byte preservation promise that comment tolerance must not violate (dsh context, same principle):
  > preserves every other row byte-for-byte (other insert rows, overrides, comments, `!!js` expressions).

### `plugin/addons/godot_ai/clients/_base.gd` (descriptor field contract)

- `_base.gd:53-57` — `automatic_config_edits`:
  ```gdscript
  ## False when the client's settings format cannot be round-tripped safely by
  ## the matching strategy. Status checks remain read-only; Configure and Remove
  ## return the existing manual instructions without touching the file.
  var automatic_config_edits: bool = true
  ```

- `_base.gd:59-64` — `config_allows_comments`:
  ```gdscript
  ## True when the config file is JSONC (Zed ships a `//` header). Honored by the
  ## JSON strategy's reads only — comments are stripped from a throwaway parse
  ## copy, so the row shows a real status instead of a permanent parse error
  ## (#914). Requires `automatic_config_edits = false`; the strategy ignores it
  ## otherwise rather than let a re-serializing Configure drop the comments.
  var config_allows_comments: bool = false
  ```

### `plugin/addons/godot_ai/clients/zed.gd` (the one descriptor that opts in)

- `zed.gd:18` — `config_allows_comments = true` (Zed is currently the only client that sets it). `automatic_config_edits = false` is also set on the Zed descriptor (asserted by tests).

### `plugin/addons/godot_ai/clients/_json_strategy.gd` (implementation contract)

- `_json_strategy.gd:498-500` — the gate is the AND of both flags, documented as read-only-by-construction:
  ```gdscript
  ## Read-only by construction: requiring both flags means no Configure/Remove
  ## can parse a file it would then re-serialize without the discarded comments.
  ## Re-enabling automatic edits restores the parse error instead of a lossy write.
  static func _status_allows_comments(client: McpClient) -> bool:
      return client.config_allows_comments and not client.automatic_config_edits
  ```

- `_json_strategy.gd:447-489` — `_read_file_text(path, allow_comments=false)`: strips JSONC from a **parse copy only**; `original_text` stays byte-for-byte (BOM preserved too). Unterminated block comment → fail closed (`ok:false`), never parse the leftover source.

- `_json_strategy.gd:503-560` — `_strip_jsonc(text)` / `_skip_jsonc_comment_at(text, i)`: hand-written scanner. Contract points baked into the code + comments:
  - markers inside JSON strings survive (string state machine with escape handling)
  - a comment must not glue neighboring tokens (`tru/* x */e` ≠ `true`) — emits a space or newline
  - block-comment newlines are re-emitted so `JSON.parse` error line numbers still match the source
  - line comments terminate on `\r` as well as `\n` (CR-only files) — `get_string_from_utf8()` keeps CR
  - returns `{"ok": true, "text": String}` or `{"ok": false, "error": String}`

### Python side: NOT involved

`src/` grep hits (`batch.py`, `tools/__init__.py`) are false positives — `JsonCoerced` matched `jsonc` case-insensitively; `commands` matched `comment`. **The comment-tolerant read path is entirely GDScript-side.** Any ticket-01 fix and its regression test belong in the plugin + `test_project/tests/`, not `tests/`.

## 2. Doc gaps the fix should address

The prose is unusually thorough for this feature (`#914`). Candidate gaps to check against the actual ticket-01 bug:

1. **No enumeration of *which callers* pass `allow_comments`.** `docs/client-configuration.md:200` lists "Status, the manual instructions, and Open/Reveal" as the read paths that strip comments. If ticket 01 is about a *fourth* read path that was missed (e.g., a merge-tier read, a verify/diff read, or a newly added inspection call that forgot to thread `_status_allows_comments`), the doc's enumerated list is the thing that's stale and should be updated to match. Confirm the doc's "Status / manual instructions / Open/Reveal" list is exhaustive against every read call site in `_json_strategy.gd`.
2. **`_base.gd:59-64` doc-comment says "the JSON strategy's reads only"** but does not name the merge-tier read (`_load_merge_tiers`) that a test already covers (`test_merged_json_status_reads_jsonc_tiers`). If the bug is a read path that bypassed the gate, the `_base.gd` contract comment should be tightened to say "all read paths, including merge tiers."
3. **CR/CRLF handling is documented only in code comments**, not in `client-configuration.md`. If ticket 01 involves a line-ending edge, prose should mention it.
4. **No doc note that `config_allows_comments` is currently Zed-only.** If the fix generalizes to another JSONC client, add it to the descriptor list at `client-configuration.md:186-207`.

If ticket 01's actual defect is none of the above, the doc is likely already correct and only the code + a regression test need to change — the prose contract at `:198-207` is the acceptance oracle.

## 3. Existing test coverage inventory

All coverage is in `test_project/tests/test_clients.gd` (GDScript, runs in-editor via `test_run`). Section header at ~line 4262: `# ----- #914: comment-tolerant READ for JSONC clients -----`.

Descriptor-level:
- `test_zed_descriptor_opts_into_read_only_jsonc` (~4292) — asserts Zed has `config_allows_comments == true` AND `automatic_config_edits == false`.
- `test_zed_attach_entry_scrubs_every_http_only_key` (~4208) — untagged-enum scrub (url/headers/oauth/type stripped; enabled/timeout preserved).

Status-read through a JSONC file:
- `test_zed_status_reads_stock_jsonc_settings` (~4300) — stock `//` + `/* */` header, absent entry → `NOT_CONFIGURED` with empty error_msg; present entry → `CONFIGURED`.
- `test_zed_manual_instructions_do_not_report_a_parse_failure` (~4334) — `manual_target_details` survives a JSONC header (`ok:true`, correct `key_path`).
- `test_merged_json_status_reads_jsonc_tiers` (~4380) — merge-tier read folds through the same gate → `CONFIGURED`.

The gate (both-flags AND):
- `test_json_comment_tolerance_is_gated_on_manual_edit_descriptors` (~4354) — plain client → ERROR "parse error"; `config_allows_comments=true` alone (still writable) → ERROR; both flags → `NOT_CONFIGURED`.

Fail-closed / byte preservation:
- `test_zed_configure_and_remove_never_mutate_jsonc` (~4231) — Configure/Remove both error with "manual edit"; file byte-for-byte unchanged.
- `test_json_strategy_refuses_to_overwrite_unparseable_file` (~2691) — pre-#914 refuse-to-clobber (trailing comma / stray comment) — file preserved.
- `test_json_jsonc_read_fails_closed_on_unterminated_block_comment` (~4368) — unterminated `/*` → ERROR "unterminated block comment".

`_strip_jsonc` unit-level (direct static calls):
- `test_strip_jsonc_preserves_comment_markers_inside_strings` (~4399) — `// not a comment` inside a string survives.
- `test_strip_jsonc_does_not_glue_tokens_across_a_comment` (~4410) — `tru/* x */e` must not parse as `true`.
- `test_strip_jsonc_terminates_line_comments_on_cr` (~4421) — CR-terminated line comment doesn't eat the object.
- `test_json_jsonc_read_handles_cr_only_line_endings` (~4433) — full read path with CR-only endings → `NOT_CONFIGURED`.
- `test_strip_jsonc_keeps_block_comment_newlines` (~4451) — newline re-emitted so parse error lines match.
- `test_strip_jsonc_rejects_unterminated_comment_and_string` (~4460) — both unterminated block comment and unterminated string → `ok:false` with matching error.

Coverage assessment: The `_strip_jsonc` scanner and the single-file + merge-tier read paths are well covered. Gaps that a ticket-01 regression might target: (a) any read path NOT in {status, manual_target_details, merge tiers} — e.g. Open/Reveal, or a verify/diff read — that doesn't thread `allow_comments`; (b) nested block comments (JSONC does not support nesting — `/* a /* b */ c */` — no test asserts the documented single-level behavior); (c) a `/*`/`//` sequence split across the string/non-string boundary right at a quote.

## 4. Suggested regression-test location + shape

Location: **`test_project/tests/test_clients.gd`**, appended to the existing `# ----- #914: comment-tolerant READ for JSONC clients -----` section (after `test_strip_jsonc_rejects_unterminated_comment_and_string`, ~line 4467). Keep it beside the sibling `_strip_jsonc` / status-read tests so the section stays the one home for JSONC behavior. Do **not** add anything Python-side — the fix is GDScript-only.

Shape — match the ticket's actual defect to one of these:

- If the bug is a **missed read call site** (a read that errored on a JSONC header because it didn't pass `_status_allows_comments`): drive it end-to-end through the public strategy entry point that the buggy caller uses, against a Zed descriptor + a stock `// header\n{…}` file written with the existing `_write_text` helper, and assert the returned status is `NOT_CONFIGURED`/`CONFIGURED` (not `ERROR`) with an empty `error_msg` — mirroring `test_zed_status_reads_stock_jsonc_settings`. Also assert byte-for-byte preservation of the file after the call (read back and `assert_eq(after, body, …)`), mirroring `test_zed_configure_and_remove_never_mutate_jsonc`.

- If the bug is a **scanner edge** (nesting, boundary): call `McpJsonStrategy._strip_jsonc(...)` directly (unit shape, like the other `test_strip_jsonc_*`), assert `ok`, then `JSON.parse_string` the result and assert the decoded Variant's field values (not just presence) — per the test-hygiene rule against count/presence-only assertions.

- If the bug touches **the gate** (comment tolerance leaking to a writable client): extend `test_json_comment_tolerance_is_gated_on_manual_edit_descriptors`'s three-state table with the specific flag combination the bug allowed, asserting the strict `ERROR "parse error"` for anything short of both-flags.

Naming: `test_<area>_<behavior>` following the section's convention (e.g. `test_zed_<readpath>_tolerates_jsonc_header`, or `test_strip_jsonc_<edge>`).

Run gate (per AGENTS.md): after adding, `test_run suite=clients` against a live Godot editor, plus `ruff check` (no-op here) and full `pytest -v`. GDScript client behavior is not caught by Python mocks.
