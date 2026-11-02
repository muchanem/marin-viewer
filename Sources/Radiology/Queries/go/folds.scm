; Go structural folds. Only delimiter-wrapped nodes are captured, so a
; collapsed body still reads as `{}` or `(…)`.
(block) @fold.block
(function_declaration body: (block) @fold.function)
(method_declaration body: (block) @fold.function)
(func_literal body: (block) @fold.function)
(struct_type (field_declaration_list) @fold.type)
(import_spec_list) @fold.imports
(literal_value) @fold.block
(comment) @fold.comment
