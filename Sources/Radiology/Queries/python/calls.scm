; Python call sites.
(call function: (identifier) @call.name) @call
(call function: (attribute attribute: (identifier) @call.name)) @call

; Every call, so computed callees count as unresolved sites.
(call) @call.any
