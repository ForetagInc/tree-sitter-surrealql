# tree-sitter-surrealql

Tree-sitter grammar for [SurrealQL](https://surrealdb.com/docs/surrealql), built as a parallel implementation of the [`@surrealdb/lezer`](https://github.com/surrealdb/codemirror/tree/main/packages/lezer-surrealql) parser. The grammar mirrors lezer's node names, hierarchy, and token aliasing 1:1 so that the parsed trees can be compared structurally.

> Targetting SurrealDB v3 and above. Branch `tree-sitter-parity` rebuilds the grammar from scratch against the lezer reference; the previous `main` retains the original `tree-sitter-surrealql` grammar (Cellan Hall) for compatibility.

## Layout

- [`grammar.js`](grammar.js) — tree-sitter grammar (PascalCase rule names matching lezer)
- [`src/scanner.c`](src/scanner.c) — external scanner (object/block disambiguation + JS function bodies)
- [`test/corpus/`](test/corpus/) — auto-generated test fixtures matching lezer's tree output
- [`queries/highlights.scm`](queries/highlights.scm) — highlight queries (regenerate when grammar nodes change)
- [`compare.ts`](compare.ts) — diff a SurrealQL file against the lezer parser
- [`run-corpus.ts`](run-corpus.ts) — run the lezer test corpus through both parsers and report mismatches
- [`gen-corpus.ts`](gen-corpus.ts) — regenerate `test/corpus/*.txt` from lezer's expected trees

## Status

- `353 / 355` lezer corpus tests produce identical canonical trees (`bun run run-corpus.ts`).
- `tree-sitter test` succeeds on `353 / 355` fixtures (the two failing tests are JavaScript function bodies whose internal `BraceOpen` / `JavaScriptContent` / `BraceClose` cannot be exposed without breaking the external scanner for invalid input — see [`LEZER_ISSUES.md`](LEZER_ISSUES.md)).
- `reference.surql` contains several constructs that neither parser fully supports (`|table:N..M|`, `FOR x IN SELECT … {…}`, `IF x { … } ELSE { … }` as a value, `FULLTEXT ANALYZER …`, `1f`/`2f` literals, …). Lezer recovers with embedded `⚠` markers; tree-sitter's recovery wraps broader regions in `(ERROR …)`. The comparison harness flattens error nodes to align the surrounding well-formed structure.

## Scripts

```bash
bun run gen        # tree-sitter generate
bun run test       # tree-sitter test (corpus fixtures)
bun run compare    # bun run compare.ts reference.surql
bun run gen-corpus # bun run gen-corpus.ts (regenerate test/corpus/*.txt)
```

## Design

- **PascalCase rule names** mirror lezer node types exactly. Hidden rules use a leading underscore (analogous to lezer's lowercase "passthrough" rules).
- **Token-as-node visibility** (`Keyword`, `Operator`, `RangeOp`, `BraceOpen`, `Colon`, `Pipe`, `LookupRight`, `LookupLeft`, `LookupBoth`, `Any`, `Bool`, `None`, `Literal`, etc.) is achieved with `alias($._kw_x, $.Keyword)` at every call site. The visible rules' bodies double as the underlying keyword regexes.
- **Inline named nodes** from lezer (e.g. `Subscript`, `Filter`, `Legacy`, `Modern`, `Point`, `BulkInsert`, `EnforcedClause`, `DefaultAlways`, …) are promoted to top-level rules with the same name.
- The **external scanner** (`src/scanner.c`) handles two cases:
  - `OBJECT_OPEN` — mirrors lezer's `objectToken` to distinguish `{key:value}` (Object) from `{stmt;}` (Block) from `{1,2}` (Set).
  - `JS_FUNCTION_BODY` — consumes the entire `function() { … }` body as a single token, replicating lezer's `@skip {}` behaviour without splitting the JS content into separate sub-tokens (which would cascade on invalid input during error recovery).

## Credits

Building on the foundation of Cellan Hall's [`tree-sitter-surrealql`](https://github.com/ce11an/tree-sitter-surrealql). The current `tree-sitter-parity` branch reworks the grammar to match the lezer reference exactly; the original implementation is preserved on `main`.
