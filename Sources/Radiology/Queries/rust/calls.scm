; Rust call sites. `@call.name` is the callee's name token; it is resolved
; to the SCIP occurrence at that byte, never by spelling. `@call` or
; `@call.macro` spans the whole site. Macro arguments are token trees, so
; calls inside them are not sites.
(call_expression function: (identifier) @call.name) @call
(call_expression function: (scoped_identifier name: (identifier) @call.name)) @call
(call_expression function: (field_expression field: (field_identifier) @call.name)) @call
(call_expression function: (generic_function function: (identifier) @call.name)) @call
(call_expression function: (generic_function function: (scoped_identifier name: (identifier) @call.name))) @call
(call_expression function: (generic_function function: (field_expression field: (field_identifier) @call.name))) @call
(macro_invocation macro: (identifier) @call.name) @call.macro
(macro_invocation macro: (scoped_identifier name: (identifier) @call.name)) @call.macro

; Every call and macro site, including shapes above do not name: a
; parenthesized or computed callee is recorded as an unresolved site.
(call_expression) @call.any
(macro_invocation) @call.any
