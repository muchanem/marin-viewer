; Go lexical scopes.
(function_declaration) @scope.function
(method_declaration) @scope.function
(func_literal) @scope.closure
(struct_type) @scope.type
(interface_type) @scope.type
(type_declaration) @scope.type
(block) @scope.block
