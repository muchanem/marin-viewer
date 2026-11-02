; Swift highlights — written for alex-pinkus/tree-sitter-swift.
; Capture names follow Radiology's shared vocabulary (see plans/tree-sitter.md).
; Later patterns paint over earlier ones.

(class_declaration declaration_kind: _ @keyword.type)
(protocol_declaration declaration_kind: _ @keyword.type)
(function_declaration "func" @keyword.function)
(init_declaration "init" @keyword.function)
(deinit_declaration "deinit" @keyword.function)
(import_declaration "import" @keyword.import)
(for_statement ["for" "in"] @keyword.repeat)
["while" "repeat" "continue" "break"] @keyword.repeat
(guard_statement "guard" @keyword.conditional)
(if_statement "if" @keyword.conditional)
(switch_statement "switch" @keyword.conditional)
(switch_entry "case" @keyword.conditional)
"return" @keyword.return
[(visibility_modifier) (member_modifier) (function_modifier) (property_modifier)
 (parameter_modifier) (inheritance_modifier) (mutation_modifier)] @keyword.modifier
[(comment) (multiline_comment)] @comment
[(line_str_text) (multi_line_str_text) (raw_str_part) (raw_str_end_part)] @string
[(integer_literal) (real_literal)] @number
[(boolean_literal) "nil"] @constant
(type_identifier) @type
(function_declaration name: (simple_identifier) @function)
(protocol_function_declaration name: (simple_identifier) @function)
(call_expression (simple_identifier) @function.call)
(navigation_suffix (simple_identifier) @property)
(attribute "@" @attribute (user_type (type_identifier) @attribute))
