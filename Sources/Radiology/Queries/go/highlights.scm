; Go highlights — written against tree-sitter/tree-sitter-go v0.25.0
; `src/node-types.json`, informed by that repository's `queries/highlights.scm`
; (MIT). Later patterns paint over earlier ones.

(comment) @comment

"func" @keyword.function
"return" @keyword.return
["import" "package"] @keyword.import
["if" "else" "switch" "case" "default" "select"] @keyword.conditional
["for" "range" "break" "continue" "goto" "fallthrough"] @keyword.repeat
["go" "defer"] @keyword.coroutine
["type" "struct" "interface" "map" "chan"] @keyword.type
["const" "var"] @keyword.modifier

[(interpreted_string_literal) (raw_string_literal) (rune_literal)] @string
(escape_sequence) @string.escape
[(int_literal) (float_literal) (imaginary_literal)] @number
[(true) (false) (nil) (iota)] @constant.builtin

(type_identifier) @type
((type_identifier) @type.builtin
 (#any-of? @type.builtin
   "any" "bool" "byte" "comparable" "complex64" "complex128" "error" "float32" "float64"
   "int" "int8" "int16" "int32" "int64" "rune" "string"
   "uint" "uint8" "uint16" "uint32" "uint64" "uintptr"))
(package_identifier) @namespace
(label_name) @label
(field_identifier) @property
(keyed_element (literal_element (identifier) @property))

(function_declaration name: (identifier) @function)
(method_declaration name: (field_identifier) @function.method)
(method_elem name: (field_identifier) @function.method)
(call_expression function: (identifier) @function.call)
(call_expression function: (selector_expression field: (field_identifier) @function.method))
((call_expression function: (identifier) @function.builtin)
 (#any-of? @function.builtin
   "append" "cap" "clear" "close" "complex" "copy" "delete" "imag" "len"
   "make" "max" "min" "new" "panic" "print" "println" "real" "recover"))
