[
  (keyword_computed)
  (keyword_reference)
  (keyword_on)
  (keyword_delete)
  (keyword_ignore)
  (keyword_unset)
  (keyword_cascade)
  (keyword_reject)
] @keyword

((variable_name) @variable.reserved
  (#match? @variable.reserved "^\\$(this|auth|action|file|target|value|parent|access|event|before|after|request|reference|token|session|input)$"))
