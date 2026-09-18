# The Magic Programming Language
This language is designed around a small set of regular syntax. That way the language is easy to parse and implement from scratch, similar to Lisp, Forth, and to a much lesser extent C. More complex behavior should be built from primitives.

# FORMAL GRAMMAR
```
program := (statement [tag] | layout)*

layout
    := "layout" IDENTIFIER NEWLINE
       INDENT (layout_field [tag])+ DEDENT

layout_field
    := IDENTIFIER ":" IDENTIFIER

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
    := "fu" "(" [arguments] ")" expression

push_expression
    := "push" IDENTIFIER
```
First, I want to clarify that I am not a big fan of this (somewhat) formal grammar. It looks scarier than it is, because parser implementation should abuse “Pratt” parsing. You do not actually have to write out functions for all these cases.

# Types
Magic has only 6 types:
* bool (unsigned 8 bit, either 1 or 0, “true” and “false” keywords are values of this type)
* byte (unsigned 8 bit value)
* int (signed 64 bit integer)
* float (64 bit floating point)
* ptr (unsigned 64 bit integer meant to store pointers)
* none (zero-sized type, equivalent to “void” or “u0” in HolyC)

# Expressions
Almost everything in Magic is an expression. I say almost everything because these are the exceptions.
* Declarations
* Return statement
* Break statement
* Continue statement

Syntactically, you can use these statements at the top level, or within a “do” block which will sequence statements together. Blocks evaluate to the last statement in the sequence. Declarations evaluate to the value that was used to initialize (or “none” if no assignment). In the case of “return”, that is illegal outside function bodies. In the case of “break” and “continue”, those are illegal outside of loops, and loops always return “none”. 

Expressions themselves can count as statements as well, and can have side effects. This isn’t Haskell, bruh.

# Type Inferencing
While it’s true that this is not Haskell, it is also true that Magic has type inferencing. I wholeheartedly apologize for this, it’s just that type-inferencing is a cool problem and I wanted to have fun. The algorithm goes something like:
1. Every identifier is given an “unknown” type
2. Constant values are given a default type
3. The type checker walks through the AST
4. Each operator assigns constraints to identifiers
5. The constraints are merged
6. Expressions are either rejected, or in the case of function parameters: ambiguity can be resolved by the types of the arguments at the call site.

## Constant value default types
```
true, false <==> bool (keywords)
1, 123, 69420, 0xb1gc0cc <==> int (integer literals)
1.0, 1.23, 69.420 <==> float (floating-point literals)
'a', 'b', '\xAB' <==> byte (characters, can be escaped)
"string" <==> ptr (string constants are read-only, actually)
```

## Type Promotions
The types “byte”, “int” and “float” are numeric, and “float” will take the highest precedence when doing arithmetic..
```
byte, byte  -> int
byte, int   -> int
byte, float -> float
int,  float -> float
// and vice-versa
```

## Explicit Type Casts
You can use the “as” keyword, which is parsed as a postfix op, to do casts. Casts work universally across all types (truncating when casting down to “byte”), except for “as none” which is illegal. Casting to bool has “truthy” behavior, so if the value is 0, the cast will result in 0. If it’s not zero, it results in 1.
```
decl i_want_this_to_be_a_float = 69 as float
decl i_want_this_to_be_a_ptr = 0xdeadbeef as ptr
```

## Functions
Due to this type inferencing behavior, functions are better thought of as these abstract little templates of magic. That’s why it’s called the Magic programming language!! For example:
```
decl add_three = fu(a, b, c) do 
    return a + b + c
```
The variables “a”, “b”, and “c” do not necessarily have types. Due to the addition however, it can be inferred that “a”, “b”, and “c” are numeric. So you can do either
```
add_three(1, 2, 3) // returns "int"
add_three(1.0, 2.0, 3.0) // returns "float"
add_three(1 as ptr, 2, 4) // returns "ptr"
```
However, this one below will not compile. That call will instantiate its own function with values of types “ptr”, “float”, and “float”. Then it will fail because arithmetic between “ptr” and “float” is disallowed.
```
add_three(1 as ptr, 2.0, 3.0) 
```

## Type Signatures for the basic operators
This is basically the source of inference for everything, other than the defaults for constants and explicit casts.
```
+:
    numeric, numeric -> numeric
    ptr, int -> ptr
    int, ptr -> ptr

-:
    numeric -> numeric 
    numeric, numeric -> numeric
    ptr, int -> ptr
    ptr, ptr -> int

* /:
    numeric -> numeric

%:
    int, int -> int
    byte, byte -> byte
    int, byte -> int
    byte, int -> int

& | ^ << >>:
    byte, byte -> byte
    byte, int -> int
    int, byte -> int
    int, int -> int

~:
    byte -> byte
    int -> int

< <= > >=:
    numeric, numeric -> bool

== !=:
    numeric, numeric -> bool
    bool, bool -> bool
    ptr, ptr -> bool

&& ||:
    bool, bool -> bool
   
!:
    bool -> bool
```

# “Forward” Declarations
A declaration can use the “forward” keyword instead of “decl”. This makes the identifier available before it can be encountered in the source when compiling. The compiler will literally do an entire pass and collect these declarations so they are usable anywhere in the program.
```
print("%", factorial(5)) // prints out 120
// this will compile even though "factorial" is used before declared
forward factorial = fu(n)
    if n == 0 do 1 else n * factorial(n-1)
```

# Lvalues
An “lvalue” is an expression which denotes a writeable storage location. Basically what that means, is that it can appear on the left-hand-side of an assignment (hence the term “lvalue”). Keep in mind that assignments count as expressions and are parsed as such, they evaluate to the value on the right hand side (value that was just assigned).

# The dot (dereferencing) operator
The “dot” operator produces lvalues. It is parsed as a postfix operator in the same way that function calls and subscripts are. You can think of the dot operator in Magic as the dereferencing operator. For example, take this C
```
unsigned char* my_ptr = malloc(1);
my_ptr* = 69;
```
This would be equivalent in Magic
```
decl my_ptr = alloc(1)
my_ptr.u8 = 69
```
Semantically, the C is much more complicated because you have a variable of type “unsigned char*” and, because of the type, the dereferencing implies that you are writing a single byte to it. In Magic, the variable “my_ptr” is simply of type “ptr”, and the identifier after the dot deliberately specifies the nature and size of the value you are writing to at that address. Because the dot operator works on any value of “ptr” type, you could very well do
```
decl my_ptr = alloc(1)
my_ptr.float64 = 69.0
```
and it would copy “69.0” as a floating point value to the address in “my_ptr”. It feels like it would crash because writing a “float” means writing 8 bytes, so you are writing past allocated memory. In practice though, probably not because that’s just how allocators work by getting pages from the OS.

## Address-of (&)
Similar to C, ‘&’ is a unary operator that only works on assignable lvalues, and gives you the numeric address (value of type “ptr”) to the location of the lvalue.  

# Layouts
You CANNOT declare new types in Magic. However, the dot operator is incredibly overpowered and can use information from “layouts” to do extremely fancy dereferencing. Layouts describe how memory should be accessed (or “laid out”). They are just additional information attached to pointers.
```
layout Vector2
    x: s64
    y: s64
```
You can then use this in a cast to assign the layout information to a value of “ptr” type. Note that casting in this manner is akin to casting to “ptr”. Casting with new layout information always overrides its current layout.
```
decl my_vector2 = alloc(size_of(Vector2)) as Vector2
// NOTE: this syntax is verbose and horrible, but there is a better way! stay tuned...
```
So you when you access the fields, the dot operator will offset the pointer and do the reads/writes automatically. For example, the two expressions below do the same thing.
```
my_vector2.y = 69 // read past the "x" and write 69
(my_vector2 + size_of(s64)).s64 = 69
```
These are the default layout fields for every “ptr” value. Dereferencing with these fields will do sign/zero extension and floating point casts when necessary.
```
u8
u16 u32 u64 // zero extension
s8 s16 s32 s64 // sign extension
float32 float64 // floating point value cast
```

## Layout inferencing
Layouts can also be inferred when passing pointers as function parameters.
1. A dereference (use of dot operator) immediately constrains that the operand is of “ptr” type
2. The field names being accessed are added as constraints
3. These field constraints are then compared with the layout information of the value supplied at the call site. This resolves ambiguity between layouts with the same field names.

## Layout Field Modifiers
TODO, “using”, “as” and “overlay”. These ideas are plagiarized from Jai/Odin, “overlay” is how unions would be done.

## Function types
So does Magic have function types? Are functions "first-class citizens?" Not really. This is kinda of TODO right now, but the idea is that:  
```
decl myfunc = fu(a,b,c,d) a + b * c / d
```
"myfunc" will have type "ptr", but it's layout information will have some "callable" flag set to true. This "function=ptr" idea raises some questions about treating arbitrary arrays/pointers as functions, which is very cool and maybe simplifies doing C interop, though I'd imagine you'd need extra syntax to distinguish instantiating and calling a function from "invoking" it.

# NOTE about “tags”
I have tags listed in the grammar. Normally, multiple statements/expressions on the same line is not allowed. However after each statement or layout field you can have a “tag”
```
do
    1+2 @tag1
    decl tagged = "tagged" @tag2
    deez_nuts() @tagged_again

layout thingymabob
    foo: s8
    bar: int69 @user_defined_layout_somewhere
    pippo: float32
    titzio: float64
```
They do not do anything currently. Since Magic is so dirt easy to parse though, I want to leave them in the language and current parser because maybe you can do cool code analysis type stuff with it.

# Push keyword
The “push” keyword is similar to “new” from over languages. It is parsed as its own expression. It can take either a type or a memory layout, and it allocates space on the stack for it and returns a pointer. For example:
```
decl my_vector2 = push Vector2
```
“my_vector2” will be of “ptr” type. You can use it just as you would any other “ptr” value with “Vector2” layout. Except the value lives on the stack and it will cease to exist when the function returns. So unfortunately, our quest for better individual allocation syntax continues…. 

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
Macros cannot take parameters, however. This will just cause the literal `( a )` tokens to be pasted in whenever “MY_MACRO” is encountered.
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
decl my_vector2 = alloc(size_of(Vector2)) as Vector2
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
