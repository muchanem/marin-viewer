; Rust document outline.
(function_item name: (identifier) @name) @symbol.function
(function_signature_item name: (identifier) @name) @symbol.function
(struct_item name: (type_identifier) @name) @symbol.type
(union_item name: (type_identifier) @name) @symbol.type
(enum_item name: (type_identifier) @name) @symbol.enum
(enum_variant name: (identifier) @name) @symbol.case
(trait_item name: (type_identifier) @name) @symbol.protocol
(mod_item name: (identifier) @name) @symbol.module
(type_item name: (type_identifier) @name) @symbol.typealias
(const_item name: (identifier) @name) @symbol.constant
(static_item name: (identifier) @name) @symbol.constant
(macro_definition name: (identifier) @name) @symbol.macro
(impl_item type: (_) @name) @symbol.extension
