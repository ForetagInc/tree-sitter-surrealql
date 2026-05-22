; tree-sitter-surrealql highlight queries
; Node names mirror @surrealdb/lezer (PascalCase) — see grammar.js for the
; complete set of nodes.

; Keywords and literals
(Keyword) @keyword
(Bool) @constant.builtin.boolean
(None) @constant.builtin
(Literal) @constant.builtin

; Identifiers
(Ident) @variable
(VariableName) @variable
(RecordTbIdent) @type
(RecordIdIdent) @constant
(KeyName) @property
(TypeName) @type
(FunctionName) @function

; Strings, numbers, regex
(String) @string
(FormatString) @string.special
(Regex) @string.regex
(Int) @number
(Float) @number.float
(Decimal) @number
(VersionNumber) @number
(Duration) @number
(DurationPart) @number

; Comments
(Comment) @comment
(BlockComment) @comment.block

; Operators / punctuation
(Operator) @operator
(RangeOp) @operator
(LookupRight) @operator
(LookupLeft) @operator
(LookupBoth) @operator
(Pipe) @punctuation.special
(Colon) @punctuation.delimiter
(BraceOpen) @punctuation.bracket
(BraceClose) @punctuation.bracket
(Any) @operator
(At) @operator
(Optional) @operator

; Token / clause keywords aliased through Distance / Filter / Tokenizer / etc.
(Distance) @constant.builtin
(Filter) @constant.builtin
(AnalyzerTokenizer) @constant.builtin
(TokenType) @constant.builtin
(HttpMethod) @constant.builtin
(IndexTypeClause) @type
