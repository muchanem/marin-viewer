; Rust structural folds.
(block) @fold.block
(function_item body: (block) @fold.function)
(closure_expression body: (block) @fold.function)
(declaration_list) @fold.type
(field_declaration_list) @fold.type
(ordered_field_declaration_list) @fold.type
(enum_variant_list) @fold.type
(match_block) @fold.block
(use_list) @fold.imports
(block_comment) @fold.comment
