; Swift document outline.
(class_declaration name: (_) @name) @symbol.type
(protocol_declaration name: (_) @name) @symbol.protocol
(function_declaration name: (simple_identifier) @name) @symbol.function
(protocol_function_declaration name: (simple_identifier) @name) @symbol.function
(init_declaration "init" @name) @symbol.initializer
(deinit_declaration "deinit" @name) @symbol.deinitializer
(typealias_declaration name: (type_identifier) @name) @symbol.typealias
