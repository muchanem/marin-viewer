; JavaScript-only additions on top of the shared ECMAScript core.
; `field_definition` exists in tree-sitter-javascript; the TypeScript grammars
; call the same construct `public_field_definition`.
(field_definition property: (property_identifier) @property)
