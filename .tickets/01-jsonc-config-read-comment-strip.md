---
id: "01"
title: "configure() read skips JSONC comment-stripping for config_allows_comments clients (Zed)"
status: done
blocked_by: []
---

# configure() read skips JSONC comment-stripping for config_allows_comments clients (Zed)

## Problem

The plugin emits a spurious warning at editor load when a JSONC client config is present,
even though the client already declares `config_allows_comments = true`:

```
WARNING: core/variant/variant_utility.cpp:1033 - MCP | JSON parse error on line 0: Unexpected character in ~/.config/zed/settings.json
```

Zed ships `settings.json` as JSONC with a leading `// Zed settings` comment by default, so
this fires on a stock Zed install (or a stale leftover config dir). Cosmetic — the MCP
connection still succeeds — but it reads like a real error.

## Root cause — REVISED after review (2026-09-07)

The original diagnosis (below, struck) was **refuted** against the current v4 tree by a
code review + research pass (subagent findings in `.scratch/subagent-raw/`, verified
directly in source). The proposed fix would have caused **data loss**.

### What's actually true

- `configure()`'s pre-read at `_json_strategy.gd:29` IS unthreaded (`_read_or_init(read_path)`,
  `allow_comments` defaults false) — confirmed.
- But that read is **unreachable for Zed**. The public entry point gates first:
  `client_configurator.gd:495` — `if not client.automatic_config_edits: return _manual_edit_result(...)`.
  Zed sets `automatic_config_edits = false` (`zed.gd:16`), so control returns before the JSON
  strategy's `configure()` read ever runs. The post-update migration also pre-filters Zed out
  (`client_job_owner.gd:249`). `remove()` has the same gate (`client_configurator.gd:734`).
- **Every load-time read a Zed row actually exercises already threads the JSONC flag:**
  status → `check_status_details` (`_json_strategy.gd:141`, threads `_status_allows_comments`);
  manual block → `manual_target_details` (`:848/:855`, threads it); Open/Reveal →
  `authoritative_tier_path` returns `""` for non-merge Zed (no parse); installed badge →
  existence check only. All are covered by green tests (`test_zed_status_reads_stock_jsonc_settings`,
  `test_zed_manual_instructions_do_not_report_a_parse_failure`).
- No current load-time path strict-parses Zed's JSONC. The read-side JSONC tolerance (#914)
  is already present and wired into exactly the paths a Zed row hits. The ticket cites plugin
  **v3.1.5**; the current tree is **v4 with #914 landed** — the observation predates the fix.

### Why the proposed fix was harmful

`configure()` reads → mutates the parsed dict → **writes** via `JSON.stringify`, which cannot
emit comments. Threading comment-stripping into its read would silently **delete every comment
in the user's config on write**. This directly violates the documented invariant
(`_json_strategy.gd:493-495`, `_base.gd:59-64`: `config_allows_comments` is honored on
read-only paths only, gated on `automatic_config_edits = false`) and would break
`test_json_comment_tolerance_is_gated_on_manual_edit_descriptors`.

Caller audit (all 7 `_read_or_init`/`_read_file_text` sites): every one is correct as-is —
read-only paths thread the flag, read-then-write paths (configure/remove) correctly do NOT
strip, and the merge-tier readers are parameterized so callers decide.

### Struck original diagnosis (kept for provenance)

> ~~The `configure()` pre-read doesn't thread the flag, so the auto-configure-on-load flow
> strict-parses Zed's JSONC → the line-0 warning.~~ — REFUTED: `configure()` is gated out for
> `automatic_config_edits = false` clients and never runs for Zed.

## Fix direction — REVISED

**Do not thread `_status_allows_comments` into `configure()`:29** — it is a no-op for Zed
(unreachable) and a latent data-loss bug if the gate is ever removed.

The correct next step is **reproduction, not a code change**:

1. Capture the *exact* warning text including the file path — `push_warning` at
   `_json_strategy.gd:486-487` always appends `in <path>`. That path names the offending
   client/file.
2. If the path is `~/.config/zed/settings.json` on a **current v4** build, that contradicts
   the exhaustive trace — investigate the specific firing read (none found statically). If it
   only reproduces on **v3.1.5**, this is already fixed by #914 → close as fixed.
3. If the path is a **different client's** file (a non-JSONC client the user hand-edited to
   contain comments), the fix is to decide whether that client should declare
   `config_allows_comments = true` + `automatic_config_edits = false` per the existing
   invariant — NOT to strip comments in `configure()`.

Zed is currently the **only** client with `config_allows_comments = true` (verified).

## Live reproduction — 2026-09-07 (Godot 4.7.2.stable, current v4 tree)

Ran a headless GDScript repro (`.scratch/repro_zed_jsonc.gd`) that builds the Zed descriptor
(`config_allows_comments=true`, `automatic_config_edits=false`) and drives each load-time read
against a stock `// Zed settings\n{...}` JSONC file:

```
REPRO_RESULT descriptor config_allows_comments=true automatic_config_edits=false
REPRO_RESULT check_status_details status=0 error_msg=""          # load-time status refresh — CLEAN
REPRO_RESULT manual_target_details ok=true error=""              # "Run this manually" inspect — CLEAN
REPRO_RESULT strict_read(no_flag) ok=false error="JSON parse error on line 0: Unexpected character"
REPRO_RESULT tolerant_read(flag) ok=true error=""                # flagged read strips comments — CLEAN
```

The `MCP | JSON parse error on line 0: Unexpected character in <path>` warning (stderr,
`push_warning`) fires **only** on the strict no-flag read — backtrace `_read_file_text:488
← _read_or_init:584`. That is exactly `configure()`'s `:29` read. Both paths a Zed row
actually hits at load (`check_status_details`, `manual_target_details`) are clean.

**Conclusion:** the warning reproduces only via the strict `configure()`-style read, which is
gated out for Zed (`automatic_config_edits=false`, `client_configurator.gd:495`). It does NOT
reproduce through any Zed load path in v4. The reported v3.1.5 warning predates #914, which
wired the JSONC flag into the load-time reads. **Resolvable as already-fixed by #914** unless a
current-v4 build reproduces it with a captured `in <path>` naming a live-firing read (none found
by static trace or this repro).

## Repro

1. Place a Zed `settings.json` with the stock `// Zed settings` header at
   `~/.config/zed/settings.json` (Zed need not be installed).
2. Open a Godot project with the Godot AI plugin enabled.
3. Observe `MCP | JSON parse error on line 0` at load.

## Acceptance criteria — REVISED

- [x] Exact warning text (with the `in <path>` file argument) captured from a **current v4**
      build, OR confirmed that the warning only reproduces on the cited v3.1.5.
- [x] Root cause identified from that path: (a) v3.1.5-only → close as fixed by #914; or
      (b) a different client's file → route to that client's descriptor decision; or
      (c) a genuine current-tree Zed load-path regression → fix at the firing read (none
      found by static trace, so this requires the live path).
- [x] No code change threads comment-stripping into `configure()`/`remove()` reads
      (write paths must never strip — would delete user comments on re-serialize).

### Struck original criteria (kept for provenance)

> ~~`configure()`'s pre-read (`_json_strategy.gd:29`) strips JSONC comments for a
> `config_allows_comments` client.~~ — REJECTED: violates the write-safety invariant and
> breaks `test_json_comment_tolerance_is_gated_on_manual_edit_descriptors`.

## Validation criteria — REVISED

- If a code fix is warranted, a regression test on the **status path** (the read that
  actually runs at load) covers it. `test_zed_status_reads_stock_jsonc_settings` already
  asserts `error_msg == ""` against a `// Zed settings` + `/* */` header and is green — the
  load-representative scenario is already covered. Any new test appends to the `#914` section
  in `test_project/tests/test_clients.gd`.
- If no current-tree defect is found, the resolution documents the refutation (v3.1.5 vs v4
  #914) and the ticket closes as already-fixed / not-reproducible.

## Notes

Environment: Godot 4.7.2.stable, Godot AI plugin v3.1.5. Affects any
`config_allows_comments = true` client (Zed today; VS Code / other JSONC configs by the
same logic). Originally mis-filed as upstream hi-godot/godot-ai#992 (now closed); tracked
here in the fork.

### 2026-09-07 research + review pass

Hardened via 2 research subagents (JSONC spec, comment-preservation prior art) + code
review + docs/config review. Raw findings: `.scratch/subagent-raw/{code-review,
research-jsonc,research-priorart,docs-config-review}.md`. Directly verified in source:
the `automatic_config_edits` gate (`client_configurator.gd:495`) and that Zed is the only
`config_allows_comments = true` client. Net: the original fix was refuted as harmful
(data loss on re-serialize) and the diagnosed path is unreachable in v4; retargeted to
reproduction-first. Prior-art takeaway if a JSONC client ever DOES need automatic edits:
never `parse → JSON.stringify → overwrite`; use minimal text-edit splicing over the
original bytes (the jsonc-parser `modify()` + `applyEdits()` model VS Code uses), which the
plugin's `remove()` already approximates with its token-preserving surgery.

## Resolution (2026-09-07)

Refuted the original diagnosis and reproduced live. On the current v4 tree (Godot 4.7.2, #914 landed), a headless repro (.scratch/repro_zed_jsonc.gd) drove every Zed load-time read against a stock '// Zed settings' JSONC file: check_status_details -> status=NOT_CONFIGURED error_msg='' (clean); manual_target_details -> ok=true (clean); tolerant flagged read -> ok=true (clean). The 'JSON parse error on line 0' warning fires ONLY on the strict no-flag read (configure()'s :29 path, backtrace _read_file_text:488 <- _read_or_init:584), which is gated out for Zed at client_configurator.gd:495 (automatic_config_edits=false). The v3.1.5 report predates #914. No code change made: the ticket's proposed fix (thread the flag into configure()'s read) would delete user comments on re-serialize and was rejected. Closed as already-fixed-by-#914.
