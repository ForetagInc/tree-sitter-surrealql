[
  (keyword_computed)
  (keyword_reference)
] @keyword

[
  (keyword_none)
] @constant.builtin

(reference_on_delete_clause
  (keyword_on) @constant.builtin
  (keyword_delete) @constant.builtin)

(reference_on_delete_clause
  [
    (keyword_ignore)
    (keyword_unset)
    (keyword_cascade)
    (keyword_reject)
  ] @keyword)

(reference_on_delete_clause
  (keyword_then) @keyword.control)

(function_call
  (custom_function_name) @function)

(function_call
  (function_name) @function)

(function_call
  (function_name) @function.builtin
  (#match? @function.builtin "^(array|crypto|duration|encoding|geo|http|math|meta|not|object|parse|rand|record|search|session|sleep|string|time|type|vector)::[a-zA-Z_][a-zA-Z0-9_]*$"))

(function_call
  (function_name) @function.special
  (#match? @function.special "^(array|crypto|duration|encoding|geo|http|math|meta|not|object|parse|rand|record|search|session|sleep|string|time|type|vector)::[a-zA-Z_][a-zA-Z0-9_]*::[a-zA-Z_][a-zA-Z0-9_]*$"))

(variable_name) @variable.parameter
