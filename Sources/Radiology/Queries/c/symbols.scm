; Declarators are recursive (pointer returns, function pointers). The worker
; follows only their declarator spine to select the actual name token.
(function_definition declarator: (_) @name) @symbol.function
(declaration declarator: (_) @name) @symbol.function
(struct_specifier name: (type_identifier) @name) @symbol.type
(union_specifier name: (type_identifier) @name) @symbol.type
(enum_specifier name: (type_identifier) @name) @symbol.enum
(enumerator name: (identifier) @name) @symbol.case
(type_definition declarator: (_) @name) @symbol.typealias
(preproc_def name: (identifier) @name) @symbol.constant
(preproc_function_def name: (identifier) @name) @symbol.macro

