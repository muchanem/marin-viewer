; Python structural folds. Indentation makes almost every block worth folding.
(block) @fold.block
(function_definition body: (block) @fold.function)
(class_definition body: (block) @fold.type)
(string) @fold.comment
(list) @fold.block
(dictionary) @fold.block
(set) @fold.block
(tuple) @fold.block
(argument_list) @fold.block
