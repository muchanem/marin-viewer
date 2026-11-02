; TypeScript additions on top of the shared ECMAScript core. Written against
; tree-sitter/tree-sitter-typescript v0.23.2 `typescript/src/node-types.json`,
; informed by that repository's `queries/highlights.scm` (MIT).

["interface" "type" "enum" "namespace" "module" "declare" "abstract" "implements"
 "keyof" "infer" "is" "satisfies" "asserts"] @keyword.type
["readonly" "public" "private" "protected" "override"] @keyword.modifier

(type_identifier) @type
(predefined_type) @type.builtin
(nested_type_identifier name: (type_identifier) @type)
(type_annotation (type_identifier) @type)

(interface_declaration name: (type_identifier) @type)
(type_alias_declaration name: (type_identifier) @type)
(enum_declaration name: (identifier) @type)
(abstract_class_declaration name: (type_identifier) @type)

(method_signature name: (property_identifier) @function.method)
(abstract_method_signature name: (property_identifier) @function.method)
(function_signature name: (identifier) @function)
(property_signature name: (property_identifier) @property)
(public_field_definition name: (property_identifier) @property)
(enum_body (property_identifier) @constant)
(enum_assignment name: (property_identifier) @constant)

(required_parameter pattern: (identifier) @variable.parameter)
(optional_parameter pattern: (identifier) @variable.parameter)
