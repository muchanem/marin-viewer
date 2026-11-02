; Rust highlights — written against tree-sitter/tree-sitter-rust v0.24.2
; `src/node-types.json`, informed by that repository's `queries/highlights.scm`
; (MIT). Later patterns paint over earlier ones.

[(line_comment) (block_comment)] @comment
(line_comment (doc_comment)) @comment.documentation
(block_comment (doc_comment)) @comment.documentation

; Keywords
"fn" @keyword.function
"return" @keyword.return
["use" "mod" "extern"] @keyword.import
["if" "else" "match"] @keyword.conditional
["for" "while" "loop" "break" "continue" "in"] @keyword.repeat
["async" "await"] @keyword.coroutine
["struct" "enum" "union" "trait" "impl" "type" "dyn"] @keyword.type
["pub" "const" "static" "unsafe" "move" "ref" "default" "raw" (mutable_specifier)] @keyword.modifier
["as" "let" "where" "yield" "gen" "macro_rules!"] @keyword
[(crate) (super)] @keyword
(use_list (self) @keyword)
(scoped_use_list (self) @keyword)
(scoped_identifier (self) @keyword)

; Literals
[(char_literal) (string_literal) (raw_string_literal)] @string
(escape_sequence) @string.escape
[(integer_literal) (float_literal)] @number
(boolean_literal) @constant.builtin
(self) @variable.builtin

; Types and members
(type_identifier) @type
(primitive_type) @type.builtin
(field_identifier) @property
(lifetime (identifier) @label)
(parameter (identifier) @variable.parameter)

; Identifier conventions: uppercase names are enum constructors or types,
; SCREAMING_CASE names are constants.
((identifier) @constructor
 (#match? @constructor "^[A-Z]"))
((scoped_identifier path: (identifier) @type)
 (#match? @type "^[A-Z]"))
((scoped_type_identifier path: (identifier) @type)
 (#match? @type "^[A-Z]"))
((identifier) @constant
 (#match? @constant "^[A-Z][A-Z0-9_]+$"))

; Functions
(function_item name: (identifier) @function)
(function_signature_item name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(call_expression function: (scoped_identifier name: (identifier) @function.call))
(call_expression function: (field_expression field: (field_identifier) @function.method))
(generic_function function: (identifier) @function.call)
(generic_function function: (scoped_identifier name: (identifier) @function.call))
(generic_function function: (field_expression field: (field_identifier) @function.method))
(macro_invocation macro: (identifier) @function.macro)
(macro_invocation "!" @function.macro)
(macro_definition name: (identifier) @function.macro)

; Attributes last: they colour the whole `#[...]` span.
[(attribute_item) (inner_attribute_item)] @attribute
