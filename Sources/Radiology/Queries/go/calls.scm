; Go call sites.
(call_expression function: (identifier) @call.name) @call
(call_expression function: (selector_expression field: (field_identifier) @call.name)) @call

; Every call, so computed callees count as unresolved sites.
(call_expression) @call.any
