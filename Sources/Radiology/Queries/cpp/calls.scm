(call_expression function: (qualified_identifier name: (identifier) @call.name)) @call
(call_expression function: (template_function name: (identifier) @call.name)) @call
(call_expression function: (qualified_identifier name: (template_function name: (identifier) @call.name))) @call
(call_expression function: (field_expression field: (template_method name: (field_identifier) @call.name))) @call
(call_expression function: (field_expression field: (qualified_identifier name: (field_identifier) @call.name))) @call
; Construction/destruction can invoke user code, but these nodes do not
; supply a precise callee token. Keep them as explicit unknown call sites.
(new_expression) @call.any
(delete_expression) @call.any

