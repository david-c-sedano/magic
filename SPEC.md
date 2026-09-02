# The Magic Programming Language
This language is designed around a small set of regular syntax. That way the language is easy to parse and implement from scratch, similar to Lisp, Forth, and to much lesser extent C. More complex behavior should be built from simple primitives.

## FORMAL GRAMMAR
```
program := statement*

statement
    := declaration
     | return_statement
     | break_statement
     | continue_statement
     | expression

declaration
    := "decl" identifier ["=" expression] [tag]

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
    := ("-" | "!" | "~") unary 
     | postfix 

postfix 
    := primary postfix_op* 

postfix_op 
    := "(" [arguments] ")" 
     | "[" expression "]"
     | "." IDENT

primary 
    := IDENTIFIER
     | BYTE
     | INT
     | FLOAT
     | STRING
     | "true"       | "false" 
     | "none" 
     | "(" expression ")" 
     | block 
     | while_expression 
     | if_expression 
     | function_expression

arguments
    := expression ("," expression)*

block
    := "do" statement
     | "do" NEWLINE INDENT statement+ DEDENT

while_expression
    := "while" expression expression

if_expression
    := "if" expression expression ["else" expression]

function_expression
    := "fu" "(" [arguments] ")" expression
```
First, I want to clarify that I am not a big fan of this formal grammar. It looks scarier than it is, because parser implementation should abuse “Pratt” parsing. You do not actually have to write out functions for all these cases.

Also note that nearly everything is an expression. The only four statements are “decl”, “break”, “continue” and “return”. The top level, as well as “do”, are the escape hatches which allows a sequence of statements or expressions. In the case of “do”, it is really an expression yielding a block. 

For example
```
if condition do print("yes")

if condition do
    print("yes")
    x+=1
```
These are all instances of
```
if <expr> <expr>
```

## Layouts
In languages like C/Java, the dot “.” operator is like a member access, you are “selecting”, by name, a value of a subtype from a larger value. In the case of Java it is very gross, in the case of C, it is very useful but perhaps a bit too high level. In Magic, the dot operator is just a dereference. But it does useful and fancy pointer math for you.
```
decl ptr = alloc(8) // 64 bit value
ptr.u8 = 69 // write 1 byte into memory
ptr.s32 = 420 // write 4 bytes, sign-extend to 32 bits
ptr.u64 = 676767 // write 8 bytes, zero-extend to 64 bits
However, you can write “layouts” to describe more complex operations with the dot operator. For example:
layout Vector2
    x: s64
    y: s64
The layout grammar is like
layout
    := "layout" identifier NEWLINE
     | INDENT layout_field+ DEDENT

layout_field
    := identifier ":" identifier
```
These do not compile to anything, are global, and only usable at top-level, otherwise the parser encounters a “layout” token and it’s an error. You can “tag” declarations to give the dot operator more information to work with.
```
// NOTE: yes, this repeat of `Vector2` is java-like and diabolical
// there is a better way, but for now this illustrates the point 
decl myvector = alloc(size_of(Vector2)) @Vector2
myvector2.y = 69 // offset by 8 bytes past the "x" and write 8 bytes
```
So there is type-checking phase before code generation, but it’s easy because there is literally only 5 types. 

Also, these are the default “layout” selectors, any value of type ptr can be dereferenced with these.
```
u8             // zero-extension, rvalue resolve to byte
u16 u32 u64    // zero-extension, rvalue resolves to int
s8 s16 s32 s64 // sign-extension, rvalue resolves to int
float          // 64 bit floating point cast, rvalue resolves to float
```

### Address-of and lvalues
Often, you will need to take the address of a “struct” member. Similar to C, it is the unary `&` address-of operator. The type checking phase will recursively propagate lvalue-ness through expressions to ensure it’s valid. So, any expression that can be on the left hand side of an assignment can also have address-of be used on it.
```
v    // maybe lvalue
v.y  // lvalue: memory at v + offset(y)
&v.y // rvalue: numeric address
```

## Type Checking
I mentioned a type-checking phase, and this is it. It’s more complicated that I wish it was, but type-inferencing is a cool problem and I wanted to make it fun for myself, I wholeheartedly apologize.

There are only 5 types
```
bool  // 8 bits, only 1 or 0, distinct from byte
byte  // unsigned 8 bit value
int   // 64 bit signed integer
float // 64 bit floating point value
ptr   // 64 bit unsigned integer
```
These are the automatic promotions for the three numeric types
```
byte, byte  -> int
byte, int   -> int
byte, float -> float
int,  float -> float
// and vice-versa
```
The signatures for all the binary and unary expressions are as follows
```
+:
    numeric, numeric -> numeric
    ptr, int -> ptr
    int, ptr -> ptr

-:
    numeric -> numeric 
    numeric, numeric -> numeric
    ptr, int -> ptr
    ptr, ptr -> int  * /:
    numeric, numeric -> numeric

%:
    int, int -> int
    byte, byte -> byte

& | << >>:
    byte, byte -> byte
    byte, int -> int
    int, byte -> int
    int, int -> int

~:
    byte -> byte
    int -> int

<= <= > >=:
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
Where by “numeric” I just mean, either byte, integer or float, and promotion is done as necessary.

### Functions
You never have to specify the types of parameters to a function. There is no syntax for this. They are inferred. To describe this process:
1. Every parameter is given an unknown type variable
2. The checker walks through the function body
3. Every operation adds constraints to each identifier’s unknown type
4. The constraints are merged
5. Any remaining ambiguity is resolved via the types of the values at the call site
There are no first class functions in Magic. A function “decays” to a ptr type, but the compiler sees it as “callable”. When checking if a call is valid, the compiler checks that the callee is a pointer type and tagged as “callable”.

### Layout Inferencing
The “layout” of memory can also be inferred.
1. Dot operator immediately implies that the operand is of type ptr
2. The field name being accessed is added as a constraint
3. The call site parameter supplies a concrete layout, and it must match the constraints
The important takeaway is that 1 single function you write can compile to multiple functions, depending the amount of times you call it and the types of parameters you call it with. I suppose the academics call this “monomorphization” and “specialization”….

## The Pseudo Preprocessor
The tokenizer for Magic has basic behavior you’d expect from a C preprocessor:
```
#include
#define
#ifdef
#ifndef
#else
```
Though, defines/macros CANNOT take parameters, cause let’s be honest, that is terrible design. Instead, we have a feature where in 15 years there will be a consensus whether or not it was a massive mistake.
```
// THE INCREDIBLE MIXIN DIRECTIVE
#!
```
Anyways, instead of doing this war crime:
```
decl myvector2 = alloc(size_of(Vector2)) @Vector2
```
you can just use a mixin
```
decl myvector2 = #!new Vector2
```
Where “new” is a another compiled magic program
```
decl T = argv[1]
print("alloc(size_of(%)) @%", T)
```
Because mixins have the incredible behavior of executing a shell command, and injecting its output directly into the source code.

# CONCLUSION
This is the “Magic” programming language because that’s what compilers are, they’re magic. Stop trying to understand them, and let the wizards take care of it.

