; Kotlin call sites: a bare name, or the last navigation suffix of a chain.
(call_expression (simple_identifier) @call.name) @call
(call_expression (navigation_expression (navigation_suffix (simple_identifier) @call.name))) @call

; Every call, so computed callees count as unresolved sites.
(call_expression) @call.any
