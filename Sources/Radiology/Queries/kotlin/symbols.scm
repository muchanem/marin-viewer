; Kotlin document outline. The grammar exposes no field names, so each
; declaration is matched through its direct children.
(class_declaration (type_identifier) @name) @symbol.type
(object_declaration (type_identifier) @name) @symbol.type
(companion_object (type_identifier) @name) @symbol.type
(function_declaration (simple_identifier) @name) @symbol.function
(source_file (property_declaration (variable_declaration (simple_identifier) @name)) @symbol.property)
(class_body (property_declaration (variable_declaration (simple_identifier) @name)) @symbol.property)
(enum_class_body (property_declaration (variable_declaration (simple_identifier) @name)) @symbol.property)
(type_alias (type_identifier) @name) @symbol.typealias
(enum_entry (simple_identifier) @name) @symbol.case
(secondary_constructor "constructor" @name) @symbol.initializer
(anonymous_initializer "init" @name) @symbol.initializer
