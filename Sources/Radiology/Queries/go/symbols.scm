; Go document outline.
(package_clause (package_identifier) @name) @symbol.module
(function_declaration name: (identifier) @name) @symbol.function
(method_declaration name: (field_identifier) @name) @symbol.method
(type_spec name: (type_identifier) @name) @symbol.type
(type_alias name: (type_identifier) @name) @symbol.typealias
(method_elem name: (field_identifier) @name) @symbol.method
(source_file (const_declaration (const_spec name: (identifier) @name) @symbol.constant))
(source_file (var_declaration (var_spec name: (identifier) @name) @symbol.variable))
