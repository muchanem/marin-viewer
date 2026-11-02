; ECMAScript document outline shared by JavaScript, TypeScript, and TSX.
(function_declaration name: (identifier) @name) @symbol.function
(generator_function_declaration name: (identifier) @name) @symbol.function
(class_declaration name: (_) @name) @symbol.type
(method_definition name: (property_identifier) @name) @symbol.method
(variable_declarator name: (identifier) @name value: [(function_expression) (arrow_function)]) @symbol.function
(program (lexical_declaration (variable_declarator name: (identifier) @name) @symbol.variable))
(program (variable_declaration (variable_declarator name: (identifier) @name) @symbol.variable))
(export_statement declaration: (lexical_declaration (variable_declarator name: (identifier) @name) @symbol.variable))
