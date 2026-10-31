; C structural folds; function bodies retain their own kind for x/default folds.
(compound_statement) @fold.block
(function_definition body: (compound_statement) @fold.function)
(field_declaration_list) @fold.type
(enumerator_list) @fold.type
(initializer_list) @fold.block
(comment) @fold.comment

