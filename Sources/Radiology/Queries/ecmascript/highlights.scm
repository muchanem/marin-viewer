; ECMAScript highlights shared by the JavaScript, TypeScript, and TSX grammars.
; Written against tree-sitter/tree-sitter-javascript v0.25.0 and
; tree-sitter/tree-sitter-typescript v0.23.2 `src/node-types.json`, informed by
; the JavaScript repository's `queries/highlights.scm` (MIT). Only node types
; present in all three grammars appear here; dialect-only patterns live in the
; `javascript`, `typescript`, and `jsx` overlays. Later patterns paint over
; earlier ones.

(comment) @comment
(hash_bang_line) @comment

["function" "get" "set"] @keyword.function
"return" @keyword.return
["import" "export" "from" "as"] @keyword.import
["if" "else" "switch" "case" "default"] @keyword.conditional
["for" "while" "do" "break" "continue" "of" "in"] @keyword.repeat
["try" "catch" "finally" "throw"] @keyword.exception
["async" "await" "yield"] @keyword.coroutine
["class" "extends" "new"] @keyword.type
["const" "let" "var" "static"] @keyword.modifier
["delete" "typeof" "instanceof" "void" "debugger" "with" "target"] @keyword

[(string) (template_string)] @string
(escape_sequence) @string.escape
(regex) @string.special
(number) @number
[(true) (false) (null) (undefined)] @constant.builtin
[(this) (super)] @variable.builtin

(property_identifier) @property
(shorthand_property_identifier) @property
(private_property_identifier) @property
(statement_identifier) @label

(class_declaration name: (_) @type)
(function_declaration name: (identifier) @function)
(generator_function_declaration name: (identifier) @function)
(function_expression name: (identifier) @function)
(method_definition name: (property_identifier) @function.method)
(variable_declarator name: (identifier) @function value: [(function_expression) (arrow_function)])
(pair key: (property_identifier) @function.method value: [(function_expression) (arrow_function)])
(assignment_expression
  left: (member_expression property: (property_identifier) @function.method)
  right: [(function_expression) (arrow_function)])

(call_expression function: (identifier) @function.call)
(call_expression function: (member_expression property: (property_identifier) @function.method))
(new_expression constructor: (identifier) @constructor)

((identifier) @constructor
 (#match? @constructor "^[A-Z]"))
([(identifier) (shorthand_property_identifier)] @constant
 (#match? @constant "^[A-Z][A-Z0-9_]+$"))
((identifier) @variable.builtin
 (#any-of? @variable.builtin "arguments" "console" "document" "globalThis" "module" "process" "window"))

(decorator) @attribute
