# Lezer grammar issues catalog

Issues observed in [`lezer-surrealql/src/surrealql.grammar`](https://github.com/surrealdb/codemirror/blob/main/packages/lezer-surrealql/src/surrealql.grammar) while building the parallel tree-sitter grammar. The lezer grammar is treated as the leading reference and is **not** modified; this file simply records inconsistencies that surfaced during the parity work.

## Typos / spelling

- `DocLenghtsOrderClause` and `DocLenghtsCacheClause` — should be `DocLengthsOrderClause` / `DocLengthsCacheClause`. The corresponding keyword tokens are spelled correctly (`doc_lengths_order`, `doc_lengths_cache`), but the node names that surface in the tree use the misspelt `Lenghts`. The tree-sitter grammar replicates the exact misspelling to preserve parity.

## Empty named nodes

Lezer emits these nodes in the tree even when their content is empty (because the rule body matches an empty sequence). Tree-sitter cannot natively represent rules that match the empty string; the comparison harness in `compare.ts` strips them from lezer's tree when empty so the parsers can be compared structurally.

- `EnforcedClause { enforced? }` — emitted as empty `EnforcedClause` when `ENFORCED` is omitted in `TableTypeClause`.
- `DefaultAlways { always? }` — emitted as empty `DefaultAlways` inside `DefaultClause` when `ALWAYS` is omitted.
- `ApiOptions { (PermissionsBasicClause | MiddlewareClause)* }` — emitted as empty when no clauses follow in `defineApiOptions`.
- `RecurseOptions { ("+" name ("=" value)?)* }` — emitted as empty when no recurse options are present.

These are not "bugs" per se but they require special handling for any consumer that can't represent empty named nodes (tree-sitter, etc.).

## Inconsistent operator-keyword visibility

Inside the `Operator` rule, lezer mixes two flavours of keyword references:

| Keyword | Source token | Visible in tree? |
| --- | --- | --- |
| `IN` | regular `in [@name=Keyword]` | yes — `Operator(Keyword)` |
| `IS` | `is` from `@external extend` (no `@name`) | no — `Operator` alone |
| `AND`, `OR`, `CONTAINS`, `CONTAINSNOT`, …, `INTERSECTS` | `binaryOperatorKeyword` (no `@name`) | no — `Operator` alone |
| `NOT` (in `IS NOT`, `NOT IN`) | `opNot` (no `@name`) | sometimes — see below |
| `*=`, `?=`, `+`, `-`, etc. | `binaryOperator` literal punctuation | yes — `Operator("…")` quoted literal |

So `x IN y` parses as `BinaryExpression(Ident, Operator(Keyword), Ident)` but `x AND y` parses as `BinaryExpression(Ident, Operator, Ident)`. Likewise `x IS NOT y` shows `Operator` only, while `x NOT IN y` shows `Operator(Keyword, Keyword)`. The asymmetry is purely a side-effect of which tokens received `@name=Keyword` in the `@external extend` block versus the regular keyword list.

The tree-sitter grammar mirrors this exact asymmetry so the trees compare cleanly.

## Inconsistent literal-token visibility

Lezer's `@tokens` block declares some structural characters as token types (with or without `@name`), while inline literal strings inside rules remain anonymous. The result is that tokens declared in `@tokens` appear in the tree even without an `@name`, but the same character used inline does not:

| Token | Declared in `@tokens` | In tree? |
| --- | --- | --- |
| `{`, `}` | yes (`BraceOpen`/`BraceClose`) | yes, named |
| `:` | yes (`Colon`) | yes, named |
| `\|` | yes (`Pipe`) | yes, named |
| `[`, `]`, `<`, `>` | yes (no `@name`) | yes, as `"["`, `"]"`, `"<"`, `">"` literal-named |
| `(`, `)` | no — inline literal | no |
| `,` | no — inline literal | no |
| `;` | no — inline literal | no |

This means an array literal renders as `Array("[",Number(Int),"]")` (brackets are visible nodes named `[` and `]`) while a function call renders as `FunctionCall(FunctionName,ArgumentList(…))` with no `(` / `)` children even though both are part of the parse. The tree-sitter comparison strips these single-character "punctuation as named node" pieces to align trees.

## Unsupported SurrealQL syntax (lezer errors out)

The lezer grammar does not implement all SurrealQL constructs, even though the SurrealDB engine accepts them. The lezer parser produces `⚠` error markers in the tree for these constructs. Examples found in `reference.surql`:

- **Multi-record syntax** `|table:N..M|` — lezer emits `ERROR(Pipe), RecordId(…), ERROR(Pipe)`. The opening and closing pipes become standalone `Pipe` tokens wrapped in error nodes.
- **`FOR $x IN <bare-statement>`** — `FOR $x IN SELECT * FROM t { … }` is not valid in lezer (`SELECT * FROM t` is not in the iterable alternatives `Array | VariableName | SubQuery | Block`). Lezer recovers by emitting `Block(⚠, SelectStatement, ⚠, Block)`.
- **`IF expr { … } ELSE { … }` as a value** — used inside `SET name = IF $x = 'N/A' { NONE } ELSE { … }`. Lezer's `IfElseStatement` is only reachable from `_subqueryStatement` which is in `_statement`, not `_value`. Lezer recovers with a mix of `Range`, `BinaryExpression` and `⚠` errors.
- **`FULLTEXT ANALYZER name BM25(...)` in `DEFINE INDEX`** — `FULLTEXT` is not a keyword in the lezer grammar; lezer leaves it embedded inside `FieldsColumnsClause` with assorted `⚠` markers. Tree-sitter's recovery diverges here.
- **`Nf` float literals** (e.g. `1f`, `2f`) — only `N.Mf` and `Nef` are accepted by the `Float` token. `1f` is parsed as `Int` followed by an `⚠`. Tree-sitter is similar.
- **`TYPE F32` inside an `HnswClause`** — `IndexTypeClause` only matches the bare `F32`/`F64`/`I16`/`I32`/`I64` tokens; `TYPE F32` causes `HnswClause(..., ⚠, IndexTypeClause)`.
- **`..+name+name` recurse-with-options** — `RecurseRange { ... | Number rangeOp | rangeOp Number | rangeOp }` does not have a "RangeOp alone followed immediately by `+option`" case, so lezer parses the trailing `+option` into the `Number` slot of `RecurseRange`, producing `RecurseRange(RangeOp, Number(⚠))`.

These cases are recoverable in lezer (the parser keeps going with error markers) but tree-sitter's error recovery is local rather than structured around `⚠` placeholders, so the tree-sitter side ends up with broader `(ERROR …)` wrappers. They cannot be made bit-for-bit identical without either extending the lezer grammar (out of scope) or rewriting tree-sitter's error recovery.

## Other observations

- `since` / `until` annotations like `[since=2_0_0]` are runtime version gates used by `lezer-surrealql/src/version.js`. They do not affect the parse tree shape for the supported version, but consumers reading version metadata must do so via lezer's `NodeProp` API — there's no native equivalent in tree-sitter. The tree-sitter grammar omits version gating; all features are unconditionally available.
- `@detectDelim` in the lezer grammar causes certain matched delimiter pairs (e.g. `{`…`}`) to be tagged for indentation services. Tree-sitter has no equivalent and the produced trees are otherwise identical.
- The `JavaScriptBlock` rule in lezer is defined inside `@skip {}` so that the JavaScript content is not subjected to whitespace skipping. Tree-sitter uses an external scanner instead, which cannot easily expose the inner `JavaScriptContent` between `BraceOpen`/`BraceClose` without risking spurious matches during error recovery (see `JavaScriptBlock` comment in `grammar.js`). The tree-sitter grammar therefore emits `(JavaScriptBlock)` as a single leaf for `function(...) { ... }`, where lezer emits `JavaScriptBlock(BraceOpen, JavaScriptContent, BraceClose)`. This is the only known divergence on the lezer test corpus (2 of 355 tests).
