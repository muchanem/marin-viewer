; Resolve actual callee tokens through SCIP; computed calls stay explicit.
(call_expression function: (identifier) @call.name) @call
(call_expression function: (field_expression field: (field_identifier) @call.name)) @call
(call_expression) @call.any

