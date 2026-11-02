; Kotlin highlights — written against fwcd/tree-sitter-kotlin 0.3.8
; `src/node-types.json`, informed by that repository's `queries/highlights.scm`,
; which is itself derived from nvim-treesitter (Apache-2.0). Later patterns
; paint over earlier ones.

[(line_comment) (multiline_comment) (shebang_line)] @comment

"fun" @keyword.function
["return" "return@" "break" "continue"] @keyword.return
"import" @keyword.import
["if" "else" "when"] @keyword.conditional
["for" "do" "while"] @keyword.repeat
["try" "catch" "throw" "finally"] @keyword.exception
["val" "var" "class" "object" "interface" "enum"] @keyword.type
(type_alias "typealias" @keyword.type)
[(class_modifier) (member_modifier) (function_modifier) (property_modifier)
 (platform_modifier) (variance_modifier) (parameter_modifier) (visibility_modifier)
 (reification_modifier) (inheritance_modifier)] @keyword.modifier
["is" "!is" "in" "!in" "as" "as?"] @keyword.operator

(string_literal) @string
(character_literal) @string
(character_escape_seq) @string.escape
[(integer_literal) (long_literal) (hex_literal) (bin_literal)
 (unsigned_literal) (real_literal)] @number
[(boolean_literal) "null"] @constant.builtin
[(this_expression) (super_expression)] @variable.builtin
(label) @label

(type_identifier) @type
((type_identifier) @type.builtin
 (#any-of? @type.builtin
   "Any" "Array" "Boolean" "BooleanArray" "Byte" "ByteArray" "Char" "CharArray"
   "Double" "DoubleArray" "Float" "FloatArray" "Int" "IntArray" "List" "Long"
   "LongArray" "Map" "MutableList" "MutableMap" "MutableSet" "Nothing" "Number"
   "Set" "Short" "ShortArray" "String" "UByte" "UInt" "ULong" "UShort" "Unit"))
(package_header (identifier) @namespace)

(class_parameter (simple_identifier) @property)
(class_body (property_declaration (variable_declaration (simple_identifier) @property)))
(navigation_suffix (simple_identifier) @property)
(enum_entry (simple_identifier) @constant)
(parameter (simple_identifier) @variable.parameter)
(parameter_with_optional_type (simple_identifier) @variable.parameter)

(function_declaration . (simple_identifier) @function)
(call_expression . (simple_identifier) @function.call)
(call_expression (navigation_expression (navigation_suffix (simple_identifier) @function.method) .))
(constructor_invocation (user_type (type_identifier) @constructor))
(secondary_constructor "constructor" @constructor)
(anonymous_initializer "init" @constructor)
(getter "get" @function)
(setter "set" @function)

(annotation "@" @attribute (user_type (type_identifier) @attribute))
(annotation (constructor_invocation (user_type (type_identifier) @attribute)))
(file_annotation (user_type (type_identifier) @attribute))
