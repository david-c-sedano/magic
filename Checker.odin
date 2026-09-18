
package magic

import lex "Godlex"

Addressing_Mode :: enum {
    INVALID,
    NO_VALUE,
    RVALUE,
    LVALUE,
}

Operand :: struct {
    expr: ^Link,
    constraints: Unknown,
    mode: Addressing_Mode,
}

Entity_Kind :: enum {
    INVALID,
    NONE,
    VARIABLE,
    FUNCTION,
}

Entity :: struct {
    kind: Entity_Kind,
    scope: ^Scope,
    span: [2]int,
    name: string,
    constraints: Unknown,
    decl: ^Node(Decl),
    //TODO: instance: Instance (function instantiating at call site)
    //TODO: layout: Layout_Info
}

Scope :: struct {
    parent: ^Scope,
    symbols: map[string]^Entity,
}

Checker :: struct {
    using g: ^lex.Godlex,
    scope: ^Scope,
    mode: Addressing_Mode,
    current: ^Entity,
    //TODO: layouts: map[string]Layout_Info
}

Type :: enum {
    NONE,
    BOOL,
    BYTE,
    INT,
    FLOAT,
    PTR,
}

// unknown is resolved when only 1 field is set
// otherwise it is an invalid type 
Unknown :: bit_set[Type]

Unary_Type_Rule :: struct {
    operand,result: Unknown,
}

Bin_Type_Rule :: struct {
    lhs,rhs,result: Unknown,
}

Type_Rule :: union {
    Unary_Type_Rule,
    Bin_Type_Rule,
}

None  : Unknown : { .NONE }
Bool  : Unknown : { .BOOL }
Byte  : Unknown : { .BYTE }
Int   : Unknown : { .INT }
Float : Unknown : { .FLOAT }
Ptr   : Unknown : { .PTR }

Numeric : Unknown : { .BYTE, .INT, .FLOAT }

/*  NOTE:
    addr-of, assignments and `SUBSCRIPT` are special cased because lvalue-ness is what is being checked
    `CAST` is also special cased because that hard sets a type
    `DEREFERENCE` operates on layouts so that is certainly special cased
    and `CALL` does instantiating and needs to check function body 
*/
RULES := #partial [AST_Kind][]Type_Rule {
    .ADD = {
        Bin_Type_Rule { Numeric, Numeric, Numeric },
        Bin_Type_Rule { Ptr, Int, Ptr },
        Bin_Type_Rule { Int, Ptr, Ptr },
    },
    .SUB = {
        Unary_Type_Rule { Numeric, Numeric },
        Bin_Type_Rule { Numeric, Numeric, Numeric },
        Bin_Type_Rule { Ptr, Int, Ptr },
        Bin_Type_Rule { Int, Ptr, Ptr },
    },
    .MUL = {
        Bin_Type_Rule { Numeric, Numeric, Numeric },
    },
    .DIV = {
        Bin_Type_Rule { Numeric, Numeric, Numeric },
    },
    .MODULO = {
        Bin_Type_Rule { Int, Int, Int },
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Byte, Int, Int },
    },
    .BIT_AND = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
    },
    .BIT_OR = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
    },
    .BIT_XOR = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
    },
    .SHIFT_LEFT = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
    },
    .SHIFT_RIGHT = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
    },
    .BIT_NOT = {
        Unary_Type_Rule { Byte, Byte },
        Unary_Type_Rule { Int, Int },
    },
    .LESS = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
    },
    .LESS_EQ = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
    },
    .GREATER = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
    },
    .GREATER_EQ = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
    },
    .EQUALS = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
        Bin_Type_Rule { Bool, Bool, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .NOT_EQUALS = {
        Bin_Type_Rule { Numeric, Numeric, Bool },
        Bin_Type_Rule { Bool, Bool, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .LOGICAL_AND = {
        Bin_Type_Rule { Bool, Bool, Bool },
    },
    .LOGICAL_OR = {
        Bin_Type_Rule { Bool, Bool, Bool },
    },
    .LOGICAL_NOT = {
        Unary_Type_Rule { Bool, Bool },
    },
}

init_checker :: proc(c: ^Checker, g: ^lex.Godlex) {
    c.g = g
    push_scope(c)
}

push_scope :: proc(c: ^Checker) {
    parent: ^Scope
    if c.scope != nil { 
        parent = c.scope
    }
    c.scope = new(Scope,c.allocator)
    c.scope.parent = parent 
}

pop_scope :: proc(c: ^Checker) {
    if c.scope != nil {
        c.scope = c.scope.parent
    }
}

seed :: proc(c: ^Checker, root: ^Link) {

    visit :: proc(node: ^Link, data: rawptr) {
        checker := cast(^Checker) data
    }
    // TODO: alot is already known in the AST
    // like leaves/constants have default types
    // so something like `1 + 2 * 3 / 4` can immediately be inferred
    // also casts immediately assign types
    // and maybe other things IDK ATM
    post_order_walk(root, cast(rawptr) c, visit)
}
