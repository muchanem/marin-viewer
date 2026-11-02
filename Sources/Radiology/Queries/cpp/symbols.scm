(class_specifier name: (_) @name) @symbol.type
(namespace_definition name: (_) @name) @symbol.module
(alias_declaration name: (type_identifier) @name) @symbol.typealias
(field_declaration declarator: (_) @name) @symbol.method
(field_declaration_list (function_definition declarator: (_) @name) @symbol.method)

