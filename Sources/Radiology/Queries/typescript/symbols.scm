; TypeScript outline additions.
(interface_declaration name: (type_identifier) @name) @symbol.protocol
(type_alias_declaration name: (type_identifier) @name) @symbol.typealias
(enum_declaration name: (identifier) @name) @symbol.enum
(abstract_class_declaration name: (type_identifier) @name) @symbol.type
(method_signature name: (property_identifier) @name) @symbol.method
(abstract_method_signature name: (property_identifier) @name) @symbol.method
(function_signature name: (identifier) @name) @symbol.function
(property_signature name: (property_identifier) @name) @symbol.property
(public_field_definition name: (property_identifier) @name) @symbol.property
(internal_module name: (identifier) @name) @symbol.module
(module name: (identifier) @name) @symbol.module
(enum_assignment name: (property_identifier) @name) @symbol.case
(enum_body (property_identifier) @name) @symbol.case
