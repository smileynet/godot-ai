# Research: JSONC spec and how VS Code / Zed handle comments vs strict JSON

## Summary

JSONC ("JSON with Comments") is a superset of JSON that adds JavaScript-style `//` line comments and `/* */` block comments; it was informally introduced by Microsoft for VS Code config files (`settings.json`, `launch.json`, `tasks.json`) and is formalized at jsonc.org against the behavior of Microsoft's reference `jsonc-parser` in its default configuration. Comments are trivia — stripping them MUST yield the same data representation — and trailing-comma support is OFF by default in the reference parser (`allowTrailingComma: false`), so it is opt-in per tool. VS Code tolerates trailing commas only in its own official config files (via a JSON schema flag) and warns elsewhere; Zed accepts both `//` and block comments plus trailing commas (with a discouraging warning).

## Details

### Comment delimiters (jsonc.org spec)
- **Single-line**: start with `//`, continue until a line ending (LF `U+000A`, CRLF, or lone CR `U+000D`).
- **Multi-line / block**: start with `/*`, end with `*/`; may span multiple lines or sit inline (e.g. `"age": /* inline */ 25`).
- Comments may appear **anywhere insignificant whitespace is allowed** in regular JSON.
- Semantics: comments are ignored during parsing. "Removing all comments MUST yield the same data representation of the JSON values."

### Edge cases
- **Comments inside strings**: a `//` or `/*` occurring *inside a JSON string literal* is NOT a comment — it is string content. The spec defines "insignificant whitespace" as explicitly "not part of a string," and the reference scanner tokenizes strings before recognizing comment tokens, so string contents are never treated as comments. (Naive regex strippers get this wrong; robust strippers like `jsonc-parser.stripComments` are string-aware. Some simple tools sidestep it by only stripping comments that have preceding whitespace.)
- **Block comments do not nest**: the first `*/` closes the comment. A `/* outer /* inner */ ... */` leaves trailing `... */` as invalid syntax. This matches JavaScript semantics.
- **`#` comments are NOT supported**: JSONC stays a subset of JavaScript syntax, and JS has no `#` line comments. (This distinguishes JSONC from JSON5/HJSON/other variants.)
- **Trailing commas**: a comma after the last array element or object member. Per spec Appendix A, JSONC parsers *MAY* support them, but the reference `jsonc-parser` sets `allowTrailingComma: false` by default → a trailing comma is a parse error unless the consumer opts in.
- **File extension / mode line**: recommended extension is `.jsonc`. If a `.json` extension is used for JSONC content, the spec recommends a leading Emacs-style mode line, e.g. `// -*- mode: jsonc -*-`.
- **Media type**: `application/jsonc` (senders SHOULD NOT label JSONC as `application/json`).

### Microsoft `jsonc-parser` (the reference implementation)
- ESM-only node module; provides a fault-tolerant scanner + parser usable for plain JSON too.
- `ParseOptions`: `{ disallowComments?, allowTrailingComma?, allowEmptyContent? }` — comments allowed by default, trailing commas disallowed by default.
- `createScanner(text, ignoreTrivia)` — when `ignoreTrivia` is set, whitespace and comments are skipped as tokens.
- **`stripComments(text, replaceCh?)`** utility: removes JS-style comments, optionally replacing every non-newline comment character with `replaceCh` (preserves offsets/line numbers — useful before handing text to a strict `JSON.parse`).
- The `onComment` visitor callback fires (when comments are allowed) at each line/block comment's offset+length, confirming comments are lexed as first-class trivia, not string content.

### VS Code behavior
- Uses `jsonc-parser` for `settings.json` / `launch.json` / `tasks.json` (language mode "JSON with Comments" / `jsonc`).
- **Trailing commas**: historically allowed silently in JSONC mode; VS Code later changed to *warn* on trailing commas (`jsonc(519)`) — EXCEPT for its own official config files, whose JSON schema declares `"allowTrailingComma": true`, suppressing the warning. So the tolerance is schema-driven, not global. (microsoft/vscode #102061, #205168, #80419.)
- Strict `.json` files (no JSONC schema) reject comments and trailing commas as errors.

### Zed behavior
- Zed's `settings.json` (and keymap) use JSONC: "Zed also supports a super-set of JSON called JSONC, which allows single line comments (`//`)." Official docs phrase it as "JSON with support for `//` comments."
- In "JSON with Comments" mode Zed accepts **both** `//` single-line and `/* */` block comments (per issue #12316), and `cmd-/` / `ctrl-/` toggles line comments.
- Zed **accepts trailing commas but displays a warning** discouraging them (issue #12316).

### Contrast with strict JSON
- RFC 8259 / ECMA-404 JSON forbids all comments and trailing commas; `JSON.parse` (JS) and Python `json.loads` fail on both. Strict pipelines (jq, APIs) must strip comments first (via `jsonc-parser`, `strip-json-comments`, JSON5, etc.) before parsing.

## Sources

- [L2:verified] JSONC Specification — https://jsonc.org/ (comment delimiters, no-nesting, no `#`, trailing-comma appendix, mode line, media type)
- [L1:verified] Microsoft `node-jsonc-parser` README — https://github.com/microsoft/node-jsonc-parser (ParseOptions defaults, `stripComments`, `onComment`, scanner trivia)
- [L4:verified] Zed JSON language docs — https://github.com/zed-industries/zed/blob/main/docs/src/languages/json.md
- [L4:verified] Zed configuring-zed docs — https://github.com/zed-industries/zed/blob/main/docs/src/configuring-zed.md
- [L1:reported] Zed issue #12316 (block comments + trailing-comma warning) — https://github.com/zed-industries/zed/issues/12316
- [L1:verified] VS Code issue #102061 (trailing commas tolerated via schema) — https://github.com/microsoft/vscode/issues/102061
- [L1:verified] VS Code issue #205168 (`jsonc(519)` on trailing commas in non-internal files) — https://github.com/microsoft/vscode/issues/205168
- [L4:established] jsonc.org draft references RFC 2119 and the VS Code JSON docs — https://code.visualstudio.com/docs/languages/json#_json-with-comments
- [L1:reported] JSONC-Spec (community) — https://github.com/JSONC-Spec/JSONC-Spec (JSONC is a superset of JSON)

## Open Questions

- **Does Godot's/target tooling need trailing-comma tolerance?** The reference parser defaults it off; if a config writer emits trailing commas, the consuming parser must explicitly enable `allowTrailingComma` or the file must not emit them.
- **Which stripping approach is safe for the consumer here?** A string-aware stripper (jsonc-parser `stripComments`, or the Python `json5`/`commentjson` equivalents) is required; naive regex-based stripping breaks on `//` or `/*` inside string values.
- **Offset preservation**: if downstream error messages need accurate line/column, use `stripComments(text, ' ')` (replace-with-space) rather than deletion so offsets stay stable — worth confirming against the actual consumer.
- **`#`-comment sources**: some "JSONC" tools in the wild (and JSON5) allow `#` or unquoted keys; the jsonc.org spec explicitly does NOT. Confirm the specific dialect any given file targets before assuming.
