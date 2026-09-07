---
id: "01"
title: "configure() read skips JSONC comment-stripping for config_allows_comments clients (Zed)"
status: open
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

## Root cause (source-grounded)

The JSONC-stripping path exists and Zed qualifies for it, but the `configure()` pre-read
doesn't thread the flag through:

- `plugin/addons/godot_ai/clients/zed.gd:11-18` sets `config_type = "json"`,
  `automatic_config_edits = false`, `config_allows_comments = true`.
- `_json_strategy.gd:498-499` — `_status_allows_comments(client)` = `config_allows_comments
  and not automatic_config_edits` → **true** for Zed.
- `_json_strategy.gd:475-487` — `_read_file_text()` strips JSONC comments **only when its
  `allow_comments` arg is true**; otherwise it strict-parses and `push_warning("MCP | JSON
  parse error on line %d ...")` at :486-487.
- The **status** path threads the flag: `:141 _read_or_init(path, _status_allows_comments(client))`.
- The **configure** path does NOT: `:29 _read_or_init(read_path)` — `allow_comments`
  defaults to `false` (`_read_or_init` :583, `_read_file_text` :449). The auto-configure-on-load
  flow hits this and strict-parses Zed's JSONC → the "line 0" warning on the `//` header.

## Fix direction

Thread `_status_allows_comments(client)` into the `configure()` pre-read at
`_json_strategy.gd:29`, matching the status path at `:141`. A read that only
inspects/measures existing content must never strict-parse a client whose config is
declared JSONC. Audit other `_read_or_init` / `_read_file_text` callers that pass the
default `allow_comments = false` on a JSONC client while fixing.

## Repro

1. Place a Zed `settings.json` with the stock `// Zed settings` header at
   `~/.config/zed/settings.json` (Zed need not be installed).
2. Open a Godot project with the Godot AI plugin enabled.
3. Observe `MCP | JSON parse error on line 0` at load.

## Acceptance criteria

- [ ] `configure()`'s pre-read (`_json_strategy.gd:29`) strips JSONC comments for a
      `config_allows_comments` client (threads `_status_allows_comments(client)` or equivalent).
- [ ] No `MCP | JSON parse error on line 0` warning at editor load with a stock Zed
      `settings.json` present.
- [ ] Other read callers passing default `allow_comments = false` on a JSONC client are
      audited and fixed or confirmed safe.

## Validation criteria

- With a `// Zed settings`-headed `~/.config/zed/settings.json`, enabling the plugin +
  running the Zed Configure/status flow produces no strict-JSON parse warning; a
  regression test parses a JSONC fixture through the `configure()` read path without warning.

## Notes

Environment: Godot 4.7.2.stable, Godot AI plugin v3.1.5. Affects any
`config_allows_comments = true` client (Zed today; VS Code / other JSONC configs by the
same logic). Originally mis-filed as upstream hi-godot/godot-ai#992 (now closed); tracked
here in the fork.
