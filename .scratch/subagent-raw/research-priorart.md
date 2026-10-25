# Prior Art: Reading JSONC to inspect without destroying user comments

## Summary

For a tool that must **read** a user's JSONC config to inspect it but **preserve
comments when the file must not be rewritten**, the field splits cleanly into two
modes, and the correct choice depends on whether you ever write back:

1. **Read-only inspection** — parse JSONC into a plain value (comments dropped
   *in the returned data*, but the file on disk is never touched). This is the
   right default when you only need to look. Comments are preserved trivially
   because you never write. The library returns a comment-free object; the file
   keeps its comments because you never re-serialize it.
2. **Round-trip / format-preserving edit** — when you *do* need to change one
   value in place, never `parse → mutate → JSON.stringify`. That flow discards
   comments, key order, and formatting. Instead compute a **minimal text edit**
   against the original source bytes (jsonc-parser's `modify()` + `applyEdits()`)
   or use a CST/model that stores comments as nodes (comment-json, json-five).

The single most important rule: **the destructive step is re-serialization, not
parsing.** A parser that strips comments is fine for inspection; the danger only
appears when you round-trip through a comment-blind serializer and write the
result back over the user's file.

## Details

### The read-only-inspection vs round-trip-rewrite distinction

- **Inspection (read, don't write):** Any JSONC-aware reader works. `jsonc-parser`'s
  `parse(text)` returns the JS value with comments and trailing commas tolerated;
  `stripComments(text)` yields clean JSON you can hand to `JSON.parse`. Python's
  `commentjson.loads` / `json-with-comments` (`jsonc.loads`) do the same. Because
  the file is never rewritten, comments survive by construction. For a tool whose
  contract is "look at the config, report what's there," this is the whole answer —
  and it is the safest path: read-only can never corrupt the file.
- **Rewrite (read, then write back):** This is where comments die. The naive
  `data = parse(f); data[k]=v; f.write(json.dumps(data))` collapses the file to
  bare JSON — no comments, reformatted, keys reordered. Two established ways to
  avoid this:
  1. **Surgical text edits over the original string** (jsonc-parser model). You
     never reconstruct the document; you compute the byte-range edits needed for
     one change and splice them into the untouched original.
  2. **Comment-carrying object model** (comment-json / json-five). The parser
     attaches comments to the nodes they annotate, so `dump()`/`dumps()` can
     re-emit them. Round-trip fidelity depends on the library and can be lossy
     for oddly-placed comments.

### How jsonc-parser (Microsoft/VS Code) handles it

`jsonc-parser` is the canonical reference — it is what VS Code uses for its own
settings.json. Its design *is* the read-only/round-trip split:

- `parse(text, errors?, options?)` → fault-tolerant JS value for **inspection**.
  Options include `allowTrailingComma` and `disallowComments`. Comments are
  dropped from the *returned value*, never from the source you hold.
- `parseTree(text)` → a **CST-style `Node` tree** with `offset`/`length` for every
  node, so you can locate a value in the original bytes without losing anything.
- `visit(text, visitor)` and `createScanner(text, ignoreTrivia?)` expose comments
  explicitly: the visitor has an `onComment` callback and the scanner emits
  `LineCommentTrivia` / `BlockCommentTrivia` tokens. `ignoreTrivia` toggles whether
  whitespace/comments are surfaced — the library treats comments as first-class
  "trivia," not garbage.
- **The format-preserving edit path** is `modify(text, path, value, options)` →
  returns an `EditResult` (an array of `{offset, length, content}` edits), then
  `applyEdits(text, edits)` splices those edits into the **original text**. Because
  edits are minimal byte-range operations against the source, everything outside
  the touched range — comments, key order, indentation — is preserved untouched.
  `ModificationOptions.formattingOptions` (with `keepLines: true`) controls only
  the newly inserted text's formatting; `getInsertionIndex` controls where a new
  key lands. Setting `value: undefined` removes a property. This is explicitly
  "compute edits, then apply to original," never "reparse and re-stringify."
- `format()` similarly returns edits (not a rewritten string), so even reformatting
  is expressed as edits against the original.

Takeaway: jsonc-parser deliberately makes *inspection* (`parse`) and
*format-preserving mutation* (`modify` + `applyEdits`) different APIs, so you can't
accidentally round-trip through a comment-stripping serializer.

### How comment-json / json-five (Python) handle it

- **comment-json** (`commentjson`): loads JSON-with-comments into Python objects
  and can preserve comments across load→dump by storing them on the object model.
  Known sharp edges reported by users: it can choke on certain block-comment (`/* */`)
  placements and its round-trip fidelity is weaker than jsonc-parser's edit model.
- **json-five** (`json5`, spyoungtech): a JSON5 parser with **explicit round-trip
  preservation of comments** via a *model-based* load/dump — you load to a model
  that carries non-data elements (comments), edit the model, and dump it back with
  comments intact. This is the Python analog of the CST approach.
- **json-with-comments** (`jsonc` on PyPI): `loads` strips `//` and `/* */` for
  reading; `dumps` can *add* comments. It is a strip-for-read + emit tool, not a
  fidelity-preserving round-tripper — good for inspection, not in-place edits.
- Other Python options in the space: `json-tricks`, `ro-json` (comment + order
  preservation). None matches jsonc-parser's minimal-edit guarantee.

### Design recommendation for "must not rewrite the file"

- If the tool only inspects: use a JSONC-aware **read** (`parse` / `stripComments` /
  `commentjson.loads`) and **never write**. Comments are safe because the file is
  never re-serialized. State loudly in the tool that it is read-only.
- If the tool ever writes back: use the **edit-the-original-bytes** model
  (jsonc-parser `modify` + `applyEdits`, or a comment-carrying model like json-five)
  — never `parse → JSON.stringify → overwrite`. Prefer minimal text edits over CST
  re-emit when comment/whitespace fidelity is a hard requirement, because
  edit-in-place touches only the changed range and cannot disturb anything else.

## Sources with URLs

- [L4:verified] jsonc-parser API reference (Microsoft/node-jsonc-parser),
  jsdocs.io — full surface: `parse`, `parseTree`, `visit`, `createScanner`
  (`ignoreTrivia`), `modify`, `applyEdits`, `format`, `stripComments`, `onComment`,
  `LineCommentTrivia`/`BlockCommentTrivia`, `EditResult`/`Edit {offset,length,content}`.
  https://www.jsdocs.io/package/jsonc-parser
- [L4:established] jsonc-parser repo (VS Code's parser). https://github.com/microsoft/node-jsonc-parser
- [L4:reported] commentjson docs — comments in JSON via `#`/`//`. https://commentjson.readthedocs.io/en/latest/
- [L4:established] json-five — "round-trip loading, editing, and dumping,
  preserving non-data elements such as comments (model-based load/dump)."
  https://github.com/spyoungtech/json-five
- [L4:reported] json-with-comments (PyPI `jsonc`) — strip `//` and `/* */` on read,
  add comments on dump. https://pypi.org/project/json-with-comments/
- [L6:reported] SO: "Preserve formatting when processing JSON" — recommends
  tracking source positions and substituting only changed components (the
  minimal-edit idea). https://stackoverflow.com/questions/61405219/
- [L6:reported] SO: "modify a JSON file using Python without losing comments" —
  confirms naive parse→dump loses comments; suggests JSON5/model-based tools.
  https://stackoverflow.com/questions/70546324/
- [L6:reported] SO: "Json.NET change value and keep comments" — same problem in
  .NET; keep comments + formatting when changing one value.
  https://stackoverflow.com/questions/35791920
- [L6:reported] Format-preserving multi-format editors that "touch only the bytes
  you point at" (edikt) and JSONC-preserving modifiers (aywson, jsonc-morph,
  jsonc-weaver) — corroborate the minimal-edit pattern.
  https://github.com/jhheider/edikt , https://github.com/threepointone/aywson ,
  https://github.com/dsherret/jsonc-morph

## Open Questions

- **This tool's actual contract:** does it *ever* write the config, or is it
  strictly inspect-only? If inspect-only, no comment-preservation machinery is
  needed at all — just a JSONC-tolerant reader and a "never write" guarantee.
  The whole preservation problem only exists on the write path.
- **Implementation language:** jsonc-parser (JS/TS) is the gold standard for
  edit-in-place; if the tool is Python, json-five's model-based round-trip is the
  closest equivalent but with weaker guarantees. Is there a language constraint?
- **Fidelity bar for the write path (if any):** must key order and exact
  indentation be byte-identical outside the edited value (→ minimal text edits),
  or is "comments retained, layout roughly preserved" acceptable (→ CST re-emit)?
- **Trailing commas / JSON5 features:** does the user's file use JSON5-only syntax
  (unquoted keys, single quotes)? That rules out strict-JSONC readers and pushes
  toward JSON5 parsers.
- **Concurrent external edits:** if the file may change on disk between read and
  write, edits computed against a stale `text` can corrupt it — need a re-read +
  recompute or a lock. (General round-trip hazard, not library-specific.)
