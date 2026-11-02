; ECMAScript structural folds shared by JavaScript, TypeScript, and TSX.
(statement_block) @fold.block
(function_declaration body: (statement_block) @fold.function)
(generator_function_declaration body: (statement_block) @fold.function)
(function_expression body: (statement_block) @fold.function)
(arrow_function body: (statement_block) @fold.function)
(method_definition body: (statement_block) @fold.function)
(class_body) @fold.type
(object) @fold.block
(array) @fold.block
(switch_body) @fold.block
(template_string) @fold.block
(comment) @fold.comment
