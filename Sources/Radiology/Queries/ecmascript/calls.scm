; ECMAScript call sites shared by JavaScript, TypeScript, and TSX.
(call_expression function: (identifier) @call.name) @call
(call_expression function: (member_expression property: (property_identifier) @call.name)) @call
(new_expression constructor: (identifier) @call.name) @call

; Every call and construction, so computed callees count as unresolved sites.
(call_expression) @call.any
(new_expression) @call.any
