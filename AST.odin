
package magic 

import lex "Godlex"
import vmem "core:mem/virtual"
import "core:fmt"
import "base:runtime"

Node :: struct($T: typeid) {
    kind: AST_Kind,
    pos: lex.Token,
    tag: string,
    using data: T,
}

Link :: Node(struct{})

AST_Kind :: enum {
    INVALID,
    EOF,

    LEAF,

    BIN_EXPR_BEGIN,
        ADD,
        ADD_ASSIGN,
        SUB,
        SUB_ASSIGN,
        MUL,
        MUL_ASSIGN,
        DIV,
        DIV_ASSIGN,
        MODULO,
        EQUALS,
        ASSIGN,
        NOT_EQUALS,
        LESS,
        SHIFT_LEFT,
        LESS_EQ,
        SHIFT_LEFT_ASSIGN,
        GREATER,
        SHIFT_RIGHT,
        GREATER_EQ,
        SHIFT_RIGHT_ASSIGN,
        BIT_AND,
        BIT_AND_ASSIGN,
        LOGICAL_AND,
        BIT_OR,
        BIT_OR_ASSIGN,
        LOGICAL_OR,
        BIT_XOR,
        BIT_XOR_ASSIGN,
        // SPECIAL POSTFIX
        CALL,
        SUBSCRIPT,
        DEREFERENCE,
        CAST,
    BIN_EXPR_END,

    UNARY_EXPR_BEGIN,
        NEGATE,
        BIT_NOT,
        LOGICAL_NOT,
    UNARY_EXPR_END,
   
    DECL,
    PUSH,
    RETURN,
    BREAK,
    CONTINUE,
    BIN_EXPR,
    UNARY_EXPR,
    PARAM_LIST,
    BLOCK,
    IF_ELSE,
    WHILE,
    FUNCTION,
    LAYOUT_FIELD,
    LAYOUT,
}

Leaf :: struct {
    token: lex.Token
}

Decl :: struct {
    forward: bool,
    name: lex.Token,
    rhs: ^Link,
}

Return :: struct {
    result: ^Link
}

Break :: struct{}
Continue :: struct{}

Bin_Expr :: struct {
    op_token: lex.Token,
    left,right: ^Link,
}

Unary_Expr :: struct {
    op_token: lex.Token,
    operand: ^Link, 
}

Param_List :: struct {
    params: []^Link,
}

Block :: struct {
    code: []^Link,
}

If_Else :: struct {
    cond,if_body,else_body: ^Link,
}

While :: struct {
    cond,body: ^Link,
}

Function :: struct {
    params: []^Link,
    body: ^Link,
}

Layout_Field :: struct {
    name,type: string,
}

Layout :: struct {
    name: string,
    fields: []^Link,
}

Push :: struct {
    type: string,
}

// a static table for the node system is needed
// odin doesnt do it automatically tho D:
KIND_LOOKUP: map[typeid]struct{ start,end:AST_Kind }
kind_lookup_mem: [9999]u8
kind_lookup_arena: vmem.Arena

@(init)
init_kind_lookup :: proc "contextless" () {
    context = runtime.default_context()
    _=vmem.arena_init_buffer(&kind_lookup_arena, kind_lookup_mem[:])
    KIND_LOOKUP = make(map[typeid]struct{ start,end:AST_Kind }, vmem.arena_allocator(&kind_lookup_arena))

    KIND_LOOKUP[Leaf] = { start=.LEAF }
    KIND_LOOKUP[Decl] = { start=.DECL }
    KIND_LOOKUP[Push] = { start=.PUSH }
    KIND_LOOKUP[Return] = { start=.RETURN }
    KIND_LOOKUP[Break] = { start=.BREAK }
    KIND_LOOKUP[Continue] = { start=.CONTINUE }
    KIND_LOOKUP[Param_List] = { start=.PARAM_LIST }
    KIND_LOOKUP[Block] = { start=.BLOCK }
    KIND_LOOKUP[If_Else] = { start=.IF_ELSE }
    KIND_LOOKUP[While] = { start=.WHILE }
    KIND_LOOKUP[Function] = { start=.FUNCTION }
    KIND_LOOKUP[Layout_Field] = { start=.LAYOUT_FIELD }
    KIND_LOOKUP[Layout] = { start=.LAYOUT }
    // kinds that map to MULTIPLE node types
    KIND_LOOKUP[Bin_Expr] = { .BIN_EXPR_BEGIN, .BIN_EXPR_END }
    KIND_LOOKUP[Unary_Expr] = { .UNARY_EXPR_BEGIN, .UNARY_EXPR_END }
}

node_cast :: proc($T: typeid, node: ^Link) -> ^Node(T) {
    if node == nil {
        return nil
    }

    when T == Bin_Expr || T == Unary_Expr {
        range := KIND_LOOKUP[T]
        if range.start < node.kind && node.kind < range.end {
            return cast(^Node(T)) node
        } else {
            return nil
        }
    } else {
        kind := KIND_LOOKUP[T].start
        if kind == node.kind {
            return cast(^Node(T)) node
        } else {
            return nil
        }
    }
}

new_node :: proc($T: typeid, pos: lex.Token, specify:=AST_Kind.INVALID, alloc:=context.allocator) -> ^Node(T) {
    node := new(Node(T),alloc)
    node.pos = pos
    when T == Bin_Expr || T == Unary_Expr {
        assert(specify!=.INVALID)
        node.kind = specify
    } else {
        kind := KIND_LOOKUP[T].start
        node.kind = kind
    }

    return node
}

wrap_node :: proc(node: ^Node($T)) -> ^Link {
    return cast(^Link) node
}

walk_ast :: proc(node: ^Link, data: rawptr, visit: proc(^Link, rawptr)) {
    if node == nil {
        return
    }

    visit(node, data)

    if leaf := node_cast(Leaf, node); leaf != nil {
        return
    }
    if brk := node_cast(Break, node); brk != nil {
        return
    }
    if cont := node_cast(Continue, node); cont != nil {
        return
    }
    if push := node_cast(Push, node); push != nil {
        return
    }
    if field := node_cast(Layout_Field, node); field != nil {
        return
    }

    if ret := node_cast(Return, node); ret != nil {
        walk_ast(ret.result, data, visit)
        return
    }

    if decl := node_cast(Decl, node); decl != nil {
        walk_ast(decl.rhs, data, visit)
        return
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        walk_ast(bin_expr.left, data, visit)
        walk_ast(bin_expr.right, data, visit)
        return
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        walk_ast(unary_expr.operand, data, visit)
        return
    }

    if list := node_cast(Param_List, node); list != nil {
        for node in list.params {
            walk_ast(node, data, visit)
        }
        return
    }

    if block := node_cast(Block, node); block != nil {
        for node in block.code {
            walk_ast(node, data, visit)
        }
        return
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        walk_ast(if_else.cond, data, visit)
        walk_ast(if_else.if_body, data, visit)
        walk_ast(if_else.else_body, data, visit)
        return
    }   

    if while := node_cast(While, node); while != nil {
        walk_ast(while.cond, data, visit)
        walk_ast(while.body, data, visit)
        return
    }

    if func := node_cast(Function, node); func != nil {
        for node in func.params  {
            walk_ast(node, data, visit)
        }
        walk_ast(func.body, data, visit)
        return
    }

    if layout := node_cast(Layout, node); layout != nil {
        for node in layout.fields {
            walk_ast(node, data, visit)
        }
        return
    }

    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `walk_ast`")
}
