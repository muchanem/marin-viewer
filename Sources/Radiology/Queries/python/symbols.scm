; Python document outline.
(function_definition name: (identifier) @name) @symbol.function
(class_definition name: (identifier) @name) @symbol.type
(module (expression_statement (assignment left: (identifier) @name) @symbol.variable))
(type_alias_statement left: (type (identifier) @name)) @symbol.typealias
