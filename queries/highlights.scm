((variable_name) @variable.reserved
  (#match? @variable.reserved "^\\$(this|auth|action|file|target|value|parent|access|event|before|after|request|reference|token|session|input)$"))
