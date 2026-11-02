; JSX overlay, shared by the JavaScript (`.jsx`, and JSX inside `.js`) and TSX
; grammars. Written against the `jsx_*` node types of
; tree-sitter-javascript v0.25.0 and tree-sitter-typescript v0.23.2 (tsx),
; informed by the JavaScript repository's `queries/highlights-jsx.scm` (MIT).
(jsx_opening_element name: (identifier) @tag)
(jsx_closing_element name: (identifier) @tag)
(jsx_self_closing_element name: (identifier) @tag)
(jsx_opening_element name: (member_expression property: (property_identifier) @tag))
(jsx_closing_element name: (member_expression property: (property_identifier) @tag))
(jsx_self_closing_element name: (member_expression property: (property_identifier) @tag))
(jsx_namespace_name) @tag
(jsx_attribute (property_identifier) @attribute)
