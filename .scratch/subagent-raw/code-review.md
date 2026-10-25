# Code review — Ticket 01: JSONC comment-strip on the `configure()` read path

Scope: verify the ticket's root-cause claim, trace the actual load-time warning
path, audit every `_read_or_init` / `_read_file_text` caller, and recommend a
fix that respects the read-only-strip invariant.

**Headline: the ticket's proposed fix is WRONG and would introduce a data-loss
regression. The ticket's root-cause diagnosis is REFUTED against current code:
`configure()`'s unthreaded read at `_json_strategy.gd:29` is UNREACHABLE for
Zed (and for every other `automatic_config_edits = false` client), so it cannot
be the source of a load-time warning.** All read-only paths that a Zed row
actually exercises already thread the JSONC flag and are already test-covered.

---

## 1. Confirmed / refuted ticket claims (with current line numbers)

All line numbers verified against the working tree
(`plugin/addons/godot_ai/clients/_json_strategy.gd`,
`plugin/addons/godot_ai/clients/_base.gd`,
`plugin/addons/godot_ai/clients/zed.gd`,
`plugin/addons/godot_ai/client_configurator.gd`).

| Ticket claim | Cited line | Actual line | Verdict |
|---|---|---|---|
| Zed sets `config_type="json"`, `automatic_config_edits=false`, `config_allows_comments=true` | zed.gd:11-18 | zed.gd:13, 16, 18 | **CONFIRMED** |
| `_status_allows_comments = config_allows_comments and not automatic_config_edits` → true for Zed | :498-499 | **:495-496** (`_status_allows_comments`), body at :496 | **CONFIRMED** (function moved; logic identical) |
| `_read_file_text` strips JSONC only when `allow_comments`, else strict-parse + `push_warning` | :475-487 | def **:449**; strip branch **:477-484**; strict-parse `push_warning` **:486-487** | **CONFIRMED** |
| status path threads the flag: `_read_or_init(path, _status_allows_comments(client))` | :141 | **:141** (inside `check_status_details`) | **CONFIRMED** |
| configure path does NOT thread: `_read_or_init(read_path)` defaults `allow_comments=false` | :29 | **:29** (inside `configure`); `_read_or_init` def :583, `_read_file_text` def :449 | **CONFIRMED** (the call is unthreaded) |
| "The auto-configure-on-load flow hits this and strict-parses Zed's JSONC → the line-0 warning" | :486-487 | — | **REFUTED** — see §2. `configure()` is never reached for Zed. |

The one factual code claim (line 29 is unthreaded) is true. The **causal**
claim — that this line produces the load-time warning for Zed — is false,
because control never reaches it for a `automatic_config_edits = false` client.

---

## 2. The `configure()` read at `_json_strategy.gd:29` is unreachable for Zed

`McpJsonStrategy.configure()` is only invoked from
`McpClientConfigurator._dispatch_configure()` (`client_configurator.gd:809`),
which is only invoked from the public `McpClientConfigurator.configure()`
(`client_configurator.gd:489`). That public entry point gates first:

```gdscript
# client_configurator.gd:495-496
if not client.automatic_config_edits:
    return _manual_edit_result(client, "configure")
```

Zed has `automatic_config_edits = false`, so `configure()` returns the
"manual edit" result **before** `_dispatch_configure` → `JsonStrategy.configure`
→ `_read_or_init(read_path)` (:29) is ever called. The unthreaded read at :29
is dead code for Zed.

The two callers of the public `configure()`:
- **Dock button** (`mcp_dock.gd` → `client_job_owner.gd:491`): user-initiated,
  not a load-time event, and still passes through the :495 gate.
- **Post-update migration** (`client_job_owner.gd`): its probe list is
  pre-filtered to automatic clients only —
  `if not probe.is_empty() and bool(probe.get("automatic_config_edits", true))`
  (`client_job_owner.gd:250`, with the load-bearing comment at :245-249 naming
  Zed's JSONC explicitly). Zed is excluded from the probe set, so migration
  never calls `configure("zed", …)` either.

Test `test_zed_configure_and_remove_never_mutate_jsonc`
(`test_project/tests/test_clients.gd:4233`) already pins this: `configure("zed")`
returns `status=error` / "manual edit" and the file is byte-for-byte unchanged.

**Conclusion:** threading `_status_allows_comments(client)` into `:29` (the
ticket's fix) changes nothing observable for Zed, because that read never runs
for Zed.

---

## 3. The actual load-time code path for a Zed row (traced)

At editor load the dock builds/refreshes each client row. For Zed
(`config_type = "json"`), the reads that actually touch the file are:

1. **Status refresh** → `ClientConfigurator.check_status(...)` /
   `check_status_details_for_url_with_cli_path(...)` →
   `_dispatch_check_status_with_cli_path_details` (`client_configurator.gd:855`,
   `"json"` branch :857) → `JsonStrategy.check_status_details`
   (`_json_strategy.gd:125`) → `_read_or_init(path, _status_allows_comments(client))`
   (**:141**). Flag threaded → JSONC stripped → **no warning**.
2. **Open/Reveal button visibility** → `effective_authoritative_path`
   (`client_configurator.gd`, used at `mcp_dock.gd:706`) →
   `authoritative_tier_path` (`_json_strategy.gd:779`). For a non-merge client
   like Zed this returns `""` immediately (`_uses_merge_tiers` false) and falls
   back to `resolved_config_path_details().path` — **no file parse at all**.
3. **Manual "Run this manually" block** (built lazily on toggle, not at load) →
   `effective_config_path` (`client_configurator.gd:1142`) →
   `manual_target_details` (`_json_strategy.gd:815`) →
   `_read_or_init(fallback_path, allow_comments)` (**:855**) with
   `allow_comments = _status_allows_comments(client)` (:848). Flag threaded →
   **no warning**.
4. **Installed badge** → `is_installed()` (`_base.gd`) →
   `resolved_config_path()` + `FileAccess.file_exists` — existence check only,
   **no parse**.

Every load-time read for Zed threads the JSONC flag (or does not parse at all).
The status path is already covered by `test_zed_status_reads_stock_jsonc_settings`
(`test_clients.gd`, asserts `error_msg == ""` on a `// Zed settings` +
`/* multi line */` header) and the manual path by
`test_zed_manual_instructions_do_not_report_a_parse_failure`.

**I could not find a load-time path in the current tree that strict-parses
Zed's JSONC and emits `MCP | JSON parse error on line 0`.** The read-side
tolerance for JSONC (#914) is already present and wired into exactly the paths
a Zed row hits. The ticket appears to describe a pre-#914 state, or a warning
whose real source is a *different, non-Zed* client (see §5) or a stale/misfiled
observation (the ticket notes it was originally mis-filed as the now-closed
upstream #992).

> Note: this review is static tracing, not a live repro. I did not launch a
> Godot editor with a stock Zed `settings.json` to observe the console. The
> code paths above are exhaustive for a Zed row; if a warning still appears
> live, the next step is to capture the actual file path in the warning text
> (`push_warning` at :486-487 always appends `in <path>`) — that identifies
> which client/file is really being strict-parsed.

---

## 4. Caller inventory — every `_read_or_init` / `_read_file_text` call site

| # | Line | Enclosing func | reads-only or read-then-write | threads `allow_comments`? | Correct? |
|---|------|----------------|-------------------------------|---------------------------|----------|
| 1 | :29 | `configure()` | **read-then-write** | no (default false) | **CORRECT** — must NOT strip. Stripping then re-serializing would drop the user's comments on write. Also unreachable for JSONC clients (gated at configurator :495). |
| 2 | :141 | `check_status_details()` | read-only | yes — `_status_allows_comments(client)` | CORRECT |
| 3 | :233 | `remove()` | **read-then-write** (token-preserving) | no (default false) | **CORRECT** — must NOT strip; also unreachable for Zed (gated at configurator :734). See §4a. |
| 4 | :584 | `_read_or_init()` (wrapper) | n/a — passes its param through to `_read_file_text` | passes through | CORRECT |
| 5 | :687 | `_load_project_definitions()` | read-only (inspection) | yes — `allow_comments` param, forwarded by callers | CORRECT |
| 6 | :727 | `_load_merge_tiers()` | **shared** — used by both read-only (status/manual) and read-then-write (`_configure_merged`, `_remove_merged`) | yes — `allow_comments` param; **callers decide** | CORRECT — read-only callers pass `_status_allows_comments`, mutating callers pass default false. See §4b. |
| 7 | :855 | `manual_target_details()` | read-only | yes — `_status_allows_comments(client)` (:848) | CORRECT |

### 4a. `remove()` (:233) is also gated and also must not strip
`remove()` uses `_read_file_text(path)` (no flag) then does token-preserving
textual surgery on `original_text`. It is reached only via public
`ClientConfigurator.remove()`, which has the same `automatic_config_edits`
gate (`client_configurator.gd:734`). Zed can't reach it. Even if it could,
`remove` writes the file, so it correctly must NOT strip comments — though note
its removal edits `original_text` (byte-preserving), so comments would actually
survive; but the *parse* of a commented file would still fail at :486-487 and
return `ok=false`, causing remove to error. That's acceptable and consistent:
a mutating op refuses a file it can't safely round-trip. Not in scope for this
ticket; flagged only for completeness.

### 4b. `_load_merge_tiers` / `_load_project_definitions` are correctly parameterized
Both take `allow_comments` and forward it. Their read-only callers
(`_check_status_merged` :159, `manual_target_details` :848,
`authoritative_tier_path` :788) pass `_status_allows_comments(client)`; their
mutating callers (`_configure_merged` via `_load_merge_tiers()` default,
`_remove_merged`) pass the default `false`. This is the correct split. Zed is
not a merge-tier client, so these don't apply to it, but the pattern is sound
for any future JSONC merge-tier client.

---

## 5. Blast radius of the ticket's proposed fix (why NOT to do it)

The ticket says: "Thread `_status_allows_comments(client)` into the
`configure()` pre-read at :29." This is actively harmful:

- **The invariant** (documented at `_json_strategy.gd:493-495` and `_base.gd:59-64`):
  `config_allows_comments` is honored **only** on read-only paths, and requires
  `automatic_config_edits = false`, *specifically so that no Configure/Remove
  can parse a file it would then re-serialize without the discarded comments*.
- `configure()` (:29) reads, mutates the parsed dict (:32-38), then **writes**
  the re-serialized dict (`JSON.stringify`, :43). `JSON.stringify` cannot emit
  comments. If :29 stripped comments, a Configure on a JSONC file would silently
  **delete every comment in the user's config**.
- Today this is impossible because JSONC clients are `automatic_config_edits=false`
  and can't reach `configure()`. Threading the flag at :29 would only matter if
  that gate were later removed — at which point it would be a latent data-loss
  bug. Adding it now bakes in the wrong contract and directly contradicts the
  `test_json_comment_tolerance_is_gated_on_manual_edit_descriptors` test
  (`test_clients.gd`), which pins that comment tolerance is gated on manual-edit
  descriptors precisely because "configure re-serializes the parsed dict".

**The correct answer to the ticket's critical question #2:** the "real bug"
described is not present in current code. The read-only inspection paths are
NOT misrouted through `configure()`; they go through `check_status_details`,
`manual_target_details`, and `authoritative_tier_path`, all of which already
strip comments. There is no code change that both (a) fixes a real load-time
Zed warning and (b) respects the invariant — because (a) does not exist in the
current tree.

---

## 6. Recommended action

**Do not implement the ticket as written.** Recommended path:

1. **Reproduce first, statically-refuted.** Ask the reporter for the *exact*
   warning text including the file path (`push_warning` at :486-487 always
   appends `in <path>`). That path names the offending client. If it is
   `~/.config/zed/settings.json`, the warning must be coming from a build that
   predates #914 (the read-side JSONC tolerance) — confirm the plugin version;
   the ticket cites v3.1.5, and the current tree is v4 with #914 landed.
2. **If the path is a *different* client's file** (a non-JSONC client whose
   file happens to contain comments, or a client the user hand-edited into
   JSONC), the fix is to decide whether that client should also declare
   `config_allows_comments = true` + `automatic_config_edits = false`, per the
   existing invariant — NOT to strip comments in `configure()`.
3. **If the warning genuinely reproduces on the current tree for Zed at load**,
   the fix belongs at whichever read is firing — which, from the exhaustive
   trace in §3, would have to be a path I could not find. In that case the real
   deliverable is identifying that path via the live warning's file argument,
   not the ticket's :29 change.
4. **Close/rewrite the ticket** with the corrected root cause. The acceptance
   criterion "configure()'s pre-read strips JSONC comments" should be rejected;
   it violates the write-safety invariant and the existing gate test.

### If a regression test is still wanted for the load path
The honest test is a **status-path** regression (the path that actually runs at
load), and it already exists: `test_zed_status_reads_stock_jsonc_settings`. If
extra coverage is desired, add an assertion that building a dock row for Zed
against a `// Zed settings`-headed file produces no `push_warning` — but note
GDScript can't easily assert on `push_warning`; the existing `error_msg == ""`
assertion on `check_status_details` is the load-representative check.

---

## 7. Test files touching this area

- `test_project/tests/test_clients.gd`:
  - `:4207` `test_zed_attach_entry_scrubs_every_http_only_key`
  - `:4233` `test_zed_configure_and_remove_never_mutate_jsonc` (pins configure/remove refuse Zed, file unchanged)
  - `:4269` `test_zed_descriptor_opts_into_read_only_jsonc` (pins both flags)
  - `~:4277` `test_zed_status_reads_stock_jsonc_settings` (status reads `//` + `/* */` header, `error_msg == ""`, entry verifies) — **the load-representative test; already green for the ticket's scenario**
  - `~:4311` `test_zed_manual_instructions_do_not_report_a_parse_failure` (manual_target_details survives JSONC header)
  - `~:4335` `test_json_comment_tolerance_is_gated_on_manual_edit_descriptors` (pins that comment tolerance is gated on manual-edit descriptors — **the test the ticket's fix would break**)
- `test_project/tests/test_dock.gd:577` — "manual-only JSONC clients must not enter the hard automatic M6 barrier" (pins Zed's exclusion from the post-update automatic path).
- Reference context (not tests): `.scratch/subagent-raw/docs-config-review.md`
  (documented contract inventory), `.scratch/subagent-raw/research-jsonc.md`,
  `.scratch/subagent-raw/research-priorart.md`.

No Python-side tests are involved; this is entirely GDScript strategy code.
