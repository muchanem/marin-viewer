; Python highlights — written against tree-sitter/tree-sitter-python v0.25.0
; `src/node-types.json`, informed by that repository's `queries/highlights.scm`
; (MIT). Later patterns paint over earlier ones.

(comment) @comment

["def" "lambda"] @keyword.function
["return" "yield"] @keyword.return
["import" "from"] @keyword.import
["if" "elif" "else" "match" "case"] @keyword.conditional
["for" "while" "break" "continue"] @keyword.repeat
["try" "except" "finally" "raise" "assert" "with"] @keyword.exception
["async" "await"] @keyword.coroutine
"class" @keyword.type
["global" "nonlocal" "pass" "del"] @keyword.modifier
["and" "or" "not" "in" "is" "as"] @keyword.operator

(string) @string
(escape_sequence) @string.escape
[(integer) (float)] @number
[(true) (false) (none)] @constant.builtin
(ellipsis) @constant.builtin

(type (identifier) @type)
(class_definition name: (identifier) @type)
(function_definition name: (identifier) @function)
(attribute attribute: (identifier) @property)
(keyword_argument name: (identifier) @variable.parameter)
(parameters (identifier) @variable.parameter)
(parameters (default_parameter name: (identifier) @variable.parameter))
(parameters (typed_parameter (identifier) @variable.parameter))
(parameters (typed_default_parameter name: (identifier) @variable.parameter))

(call function: (identifier) @function.call)
(call function: (attribute attribute: (identifier) @function.method))
((call function: (identifier) @function.builtin)
 (#any-of? @function.builtin
   "abs" "all" "any" "ascii" "bin" "bool" "bytearray" "bytes" "callable" "chr"
   "classmethod" "compile" "complex" "delattr" "dict" "dir" "divmod" "enumerate"
   "eval" "exec" "filter" "float" "format" "frozenset" "getattr" "globals"
   "hasattr" "hash" "help" "hex" "id" "input" "int" "isinstance" "issubclass"
   "iter" "len" "list" "locals" "map" "max" "memoryview" "min" "next" "object"
   "oct" "open" "ord" "pow" "print" "property" "range" "repr" "reversed" "round"
   "set" "setattr" "slice" "sorted" "staticmethod" "str" "sum" "super" "tuple"
   "type" "vars" "zip" "__import__"))

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z0-9_]+$"))
((identifier) @variable.builtin
 (#any-of? @variable.builtin "self" "cls"))

; Decorators last: they colour the whole `@name(...)` span.
(decorator) @attribute
