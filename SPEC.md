# The Magic Programming Language
This language is designed around a small set of regular syntax. That way the language is easy to parse and implement from scratch, similar to Lisp, Forth, and to a much lesser extent C. More complex behavior should be built from primitives.

# FORMAL GRAMMAR
```
program := (statement [tag] | layout)*

layout
    := "layout" IDENTIFIER NEWLINE
       INDENT (layout_field [tag])+ DEDENT

layout_field
    := IDENTIFIER ":" ("embed" | "overlay" | "using")? IDENTIFIER

statement
    := declaration
     | return_statement
     | break_statement
     | continue_statement
     | expression

declaration
    := ("decl" | "forward") identifier ["=" expression]

tag
    := "@" IDENTIFIER

return_statement
    := "return" [expression]

break_statement
    := "break"

continue_statement
    := "continue"

expression
    := assignment

assignment
    := logical_or [assignment_op assignment]

assignment_op
    := "="
     | "+="
     | "-="
     | "*="
     | "/="
     | "&="
     | "|="
     | "^="
     | "<<="
     | ">>="

logical_or
    := logical_and ("||" logical_and)*

logical_and
    := equality ("&&" equality)*

equality
    := comparison (("==“ | "!=") comparison)*

comparison
    := bitwise_or (("<" | "<=" | ">" | ">=") bitwise_or)*

bitwise_or
    := bitwise_and (("|" | "^") bitwise_and)*

bitwise_and
    := shift ("&" shift)*

shift
    := additive (("<<" | ">>") additive)*

additive 
    := multiplicative (("+" | "-") multiplicative)*

multiplicative 
    := unary (("*" | "/" | "%") unary)* 

unary 
    := ("-" | "!" | "~" | "&") unary 
     | postfix 

postfix 
    := primary postfix_op* 

postfix_op 
    := "(" [arguments] ")" 
     | "[" expression "]"
     | "." IDENT
     | "as" IDENT

primary 
    := IDENTIFIER
     | BYTE
     | INT
     | FLOAT
     | STRING
     | "true"      
     | "false" 
     | "none" 
     | "(" expression ")" 
     | block 
     | while_expression 
     | if_expression 
     | function_expression
     | push_expression
     | size_of_expression

arguments
    := expression ("," expression)*

block
    := "do" statement [tag]
     | "do" NEWLINE INDENT (statement [tag])+ DEDENT

while_expression
    := "while" expression expression

if_expression
    := "if" expression expression ["else" expression]

function_expression
    := "def" "(" [arguments] ")" expression

push_expression
    := "push" IDENTIFIER

size_of_expression
    := "size_of" IDENTIFIER
```
First, I want to clarify that I am not a big fan of this (somewhat) formal grammar. It looks scarier than it is, because parser implementation should abuse “Pratt” parsing. You do not actually have to write out functions for all these cases.

# Expressions
Almost everything in Magic is an expression. I say almost everything because there are 4 "statements".
1. declarations: `decl myvar = some_expr`
2. return: `return some_expr` or simply `return`
3. break: `break` in loops
4. continue: `continue` also in loops
To use a statement, it must be encased in a `do` block (or used at top-level). These blocks are also expressions and will evaluate to the last value in sequence. If a block ends in a statement, the checker will mark it as having `NO_VALUE` and it may cause errors if you are trying to use it in the wrong place.

# Types
Magic has 6 types
* `bool`: true or false...
* `byte`: unsigned 8 bit type
* `int`: signed numeric type
* `float`: floating point real-number type
* `ptr`: numeric type that denotes a reference to something else
* `none`: abscence of value
The types should feel wishy-washy because they represent attributes of values and not their literal representation (except for `byte` maybe). You should be able to change the width or size of `int` types with a compiler option, for example...

# Type Inferencing
The author when designing Magic REALLY did not want to introduce types into the syntax. As a consequence, Magic runs a solver (or "checker") that will infer the types of expressions. Conceptually there are 6 types, but the checker doesn't really assign types to expressions. As far as implementation goes, "types" are more like a set that is repeatedly constrained until either 1 element survives or the set is empty which denotes a contradiction. The algorithm goes something like:
1. Constant values (integer or float literals, for example) as well as type casts are given a set with only 1 element.
2. Every other expression is given a set containing every "type".
3. The checker walks the AST and applies constraints according to the operators
4. Every time an expression's "type" is reduced, the checker will do another pass on the AST, until no change is done
5. The checker stops when no changes are done, which is guaranteed ***because the sets are finite to begin with, never widened, and only constrained***, or it reaches some kind of contradiction.

## constant value default types
* integer literals: ex. `1 123 0xabc123` are assigned `int`
* floating point literals: ex. `1.2 1.0 .23` are assigned `float`
* single characters: ex. `'a' '\xa1' '\n'` are assigned `byte`
* strings: ex. `"this is a string" "mystring!"` are assigned `ptr` (into read-only memory)
* `true` and `false` are assigned `ptr` actually. Nah im just kidding it's `bool`.

## type signatures for the basic operators
These are the source of inference for everything, other than constants and type casts of course.
```
+:
    byte, byte -> int
    byte, int -> int
    int, byte -> int
    int, int -> int
    float, float -> float
    ptr, ptr -> ptr
    ptr, int -> ptr
    int, ptr -> ptr

-:
    byte, byte -> int
    byte, int -> int
    int, byte -> int
    int, int -> int
    float, float -> float
    ptr, ptr -> ptr
    ptr, int -> ptr
    int, ptr -> ptr
    int -> int
    float -> float
   
* /:
    byte, byte -> int
    byte, int -> int
    int, byte -> int
    int, int -> int
    float, float -> float

% & | ^ << >>:
    byte, byte -> byte
    byte, int -> int
    int, byte -> int
    int, int -> int

~:
    byte -> byte
    int -> int
   
== != < > <= >=:
    byte, byte -> bool
    byte, int -> bool
    int, byte -> bool
    int, int -> bool
    int, float -> bool
    float, int -> bool
    byte, float -> bool
    float, byte -> bool
    float, float -> bool
    int, ptr -> bool
    ptr, int -> bool
    ptr, ptr -> bool 

|| &&:
    bool, bool -> bool

!: 
    bool -> bool
```
If you read the source code, you would notice the massive `RULES` table which has all these cases exactly as you see here!

# Function Instancing
The other unique feature of Magic is how functions work. It's better to think of functions as templates that are instantiated from. Take this for example:
```
decl add_three = def(a, b, c) do
    return a + b + c

add_three(1, 2, 3) // works
add_three(1.0, 2.0, 3.0) // works
add_three(1.0, 2.0, 3) // does NOT work
```
The checker will mark the entire `def(...) do ...` expression as being "generic" which means that it is allowed to not have a fully resolved type. Whenever you call `add_three` it will copy the template and do inference passes over it using each argument's type at the call site. Notice that you cannot directly name functions either. Each function instantiation is given an arbitrary symbol (or "hash") according to it's return type, parameter types, as well as the template that it instantiated from. This way **absolutely everything is generic and you don't get to have types in the syntax**.

# Dereferencing
In other languages, the dot `.` operator is some object member field access type thing that is lame. In Magic, `.` is for dereferencing, cause real men work with memory. For example take this C
```
unsigned char* my_ptr = malloc(1);
my_ptr* = 69;
```
The equivalent in Magic would be:
```
decl my_ptr = alloc(1)
my_ptr.u8 = 69
```
The C is much more complicated because you have a variable of type `unsigned char*` and, because of the type, the dereferencing implies that you are writing a single byte to it. In Magic, the variable `my_ptr` is simply of type `ptr`, and the identifier after the dot deliberately specifies the nature and size of the value you are writing to at that address.

# Layouts
You cannot define new types in Magic. What you can do is much better, you can define a memory addressing scheme (called "layouts") and use that with the dereferencing `.` operator.
```
layout Vector2
    x: s64
    y: s64

// yes this syntax is atrocious, there is a better way!
decl my_vector = alloc(size_of Vector2) as Vector2
```
Expressions that are of `ptr` type can have a layout assigned to them. You can then use the `.` operator to do fancy dereferencing. For example
```
my_vector.y = 69 // read past the "x" and write 69
(my_vector + size_of(s64)).s64 = 69 // the equivalent
```
Note that you can still dereference pointers with no layout assigned. These fields belong to every `ptr` and dereferencing will obtain whatever is at the very beggining of the memory region.
```
u8 u16 u32 u64 // zero extension, u8 will produce `byte`, the rest produce `int`
s8 s16 s32 s64 // sign extension, s8 will produce `byte`, the rest produce `int`
float32 float64 // floating point value cast, produces `float` obviously
```

## embed, overlay, and using
You can use these keywords to better describe how a memory region should be "laid out".
```
layout Example
    a: s64
    b: Vector2
    c: embed Vector2
    d: overlay s64
    e: using Vector2 // 
```
* `my_example.b` is merely just a `ptr` with `Vector2` layout
* `my_example.c` is `ptr` type, but the field points into itself (my_example.c = &my_example.c.x) and is NOT assignable
* `my_example.d` derefs to the very start of the previous field so `my_example.d = my_example.c.x`, and will add padding to fit if needed
* the fields of `Vector2` in `my_example.e` are PROMOTED so `my_example.x` is legal now, similar to odin/jai, `my_example.e` would be ptr of `my_example.x` and NOT assignable

Keep in mind that layouts also participate in instantiation. So something like
```
decl append = def(array, item) do
    if array.count+1 >= array.capacity do
        array.capacity *= 2
        realloc(array, array.capacity)
    array.data[array.count] = item
    array.count+=1
    return
```
So long as a pointer is passed with a layout that has `count`, `capacity` and `data` fields, it will work.

## type casts and size_of
You can use the `as` keyword which is very powerful. Any `as` expression is guarenteed to be the type you assign.
```
1 as float 
4.1 as byte // truncated!
```
You can also use any defined layout to pass layout information.
```
decl ptr_casted_to_vector2 = some_other_ptr as Vector2
```
Also, `size_of` also an expression in which you are allowed to use something that vaguely refers to a type. It will return an `int` according to the size of a layout.
```
layout Vector2
    x: s64
    y: s64

size_of Vector2 // same as `16`
```

## push keyword
The `push` keyword is similar to `new` from over languages. It can take either a type or a memory layout, and it allocates space on the stack for it and returns a pointer. For example:
```
decl my_vector2 = push Vector2
```
“my_vector2” will be of “ptr” type. You can use it just as you would any other “ptr” value with “Vector2” layout. Except the value lives on the stack and it will cease to exist when the function returns.

# MIXINS
The tokenizer for the Magic Programming Language has basic behavior you’d expect from a C preprocessor built in. It will automatically skip tokens and push/pop character streams as is necessary.
```
#include
#define
#ifdef
#ifndef
#else
#endif
```
Macros cannot take parameters, however. This will just cause the literal ( a ) tokens to be pasted in whenever “MY_MACRO” is encountered.
```
#define MY_MACRO(a) does not work or do any parameter substitution!
```
However, Magic provides a feature that maybe in 15 years will be debated on whether or not it was a catastrophic idea. It should be sufficient for all your meta-programming needs!
```
// THE MIXIN DIRECTIVE
 #!
```
What it does is pretty cool... it will take the rest of the line, and execute it as a shell command, then insert the output directly into the source code.

Remember the awful and verbose declaration from earlier?
```
decl my_vector2 = alloc(size_of Vector2) as Vector2
```
Well, you can just do this instead…
```
decl my_vector2 = #!new Vector2 
```
where “new” is ANOTHER compiled magic program
```
decl T = argv[1]
print("alloc(size_of(%1)) as %1", T)
```
This happens at compile time, during tokenization actually, so mixins can be a source of arbitrary code execution at compile time. These commands are not sandboxed or restricted in any way. They simply just insert the output. This is by design. If you are upset with the fact that I give power to the programmer, then use Rust or Java instead. Tools exist to be of use to the user. A groundbreaking revelation to the average software developer for sure! Tools should not be idiot-proof and enforce a worldview. Maybe one day Magic will become an example of a serious tool.
