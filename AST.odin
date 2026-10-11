
package magic 

import lex "Godlex"
import vmem "core:mem/virtual"
import "core:fmt"
import "base:runtime"
import "core:strings"

Node :: struct($T: typeid) {
    kind: AST_Kind,
    span: [2]int, // into lex.Godlex.history
    tag: string,
    using annotation: Annotation,
    using data: T,
}

// Parser does not touch this!!
Annotation :: struct {
    constraints: Unknown,
    mode: Addressing_Mode,
    scope: ^Scope, 

    template_id: int,
    instance: ^Node(Function),
    instance_hash: Instance_Hash,
    generic: bool,
}

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
        ADDRESS_OF,
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

Wrapped :: struct{} 

Leaf :: struct {
    token: lex.Token
}

Decl :: struct {
    forward: bool,
    name: lex.Token,
    rhs: ^Node(Wrapped),
}

Return :: struct {
    result: ^Node(Wrapped)
}

Break :: distinct struct{} 
Continue :: distinct struct{} 

Bin_Expr :: struct {
    op_token: lex.Token,
    left,right: ^Node(Wrapped),
}

Unary_Expr :: struct {
    op_token: lex.Token,
    operand: ^Node(Wrapped), 
}

Arg_List :: struct {
    args: []^Node(Wrapped),
}

Block :: struct {
    code: []^Node(Wrapped),
}

If_Else :: struct {
    cond,if_body,else_body: ^Node(Wrapped),
}

While :: struct {
    cond,body: ^Node(Wrapped),
}

Function :: struct {
    params: []^Node(Wrapped),
    body: ^Node(Wrapped),
}

Layout_Field :: struct {
    name,type: string,
}

Layout :: struct {
    name: string,
    fields: []^Node(Wrapped),
}

Push :: struct {
    type: string,
}

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
    KIND_LOOKUP[Arg_List] = { start=.PARAM_LIST }
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

node_cast :: proc($T: typeid, node: ^Node(Wrapped)) -> ^Node(T) {
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

new_node :: proc($T: typeid, specify:=AST_Kind.INVALID, alloc:=context.allocator) -> ^Node(T) {
    node := new(Node(T),alloc)
    when T == Bin_Expr || T == Unary_Expr {
        assert(specify!=.INVALID)
        node.kind = specify
    } else {
        kind := KIND_LOOKUP[T].start
        node.kind = kind
    }
    return node
}

wrap_node :: proc(node: ^Node($T)) -> ^Node(Wrapped) {
    return cast(^Node(Wrapped)) node
}

pre_order_walk :: proc(node: ^Node(Wrapped), data: rawptr, visit: proc(^Node(Wrapped), rawptr)) {
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
        pre_order_walk(ret.result, data, visit)
        return
    }

    if decl := node_cast(Decl, node); decl != nil {
        pre_order_walk(decl.rhs, data, visit)
        return
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        pre_order_walk(bin_expr.left, data, visit)
        pre_order_walk(bin_expr.right, data, visit)
        return
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        pre_order_walk(unary_expr.operand, data, visit)
        return
    }

    if list := node_cast(Arg_List, node); list != nil {
        for node in list.args {
            pre_order_walk(node, data, visit)
        }
        return
    }

    if block := node_cast(Block, node); block != nil {
        for node in block.code {
            pre_order_walk(node, data, visit)
        }
        return
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        pre_order_walk(if_else.cond, data, visit)
        pre_order_walk(if_else.if_body, data, visit)
        pre_order_walk(if_else.else_body, data, visit)
        return
    }   

    if while := node_cast(While, node); while != nil {
        pre_order_walk(while.cond, data, visit)
        pre_order_walk(while.body, data, visit)
        return
    }

    if func := node_cast(Function, node); func != nil {
        for node in func.params  {
            pre_order_walk(node, data, visit)
        }
        pre_order_walk(func.body, data, visit)
        return
    }

    if layout := node_cast(Layout, node); layout != nil {
        for node in layout.fields {
            pre_order_walk(node, data, visit)
        }
        return
    }

    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `pre_order_walk`")
}

post_order_walk :: proc(node: ^Node(Wrapped), data: rawptr, visit: proc(^Node(Wrapped), rawptr)) {
    if node == nil {
        return
    }

    if leaf := node_cast(Leaf, node); leaf != nil {
        visit(node, data)
        return
    }
    if brk := node_cast(Break, node); brk != nil {
        visit(node, data)
        return
    }
    if cont := node_cast(Continue, node); cont != nil {
        visit(node, data)
        return
    }
    if push := node_cast(Push, node); push != nil {
        visit(node, data)
        return
    }
    if field := node_cast(Layout_Field, node); field != nil {
        visit(node, data)
        return
    }

    if ret := node_cast(Return, node); ret != nil {
        post_order_walk(ret.result, data, visit)
        visit(node, data)
        return
    }

    if decl := node_cast(Decl, node); decl != nil {
        post_order_walk(decl.rhs, data, visit)
        visit(node, data)
        return
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        post_order_walk(bin_expr.left, data, visit)
        post_order_walk(bin_expr.right, data, visit)
        visit(node, data)
        return
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        post_order_walk(unary_expr.operand, data, visit)
        visit(node, data)
        return
    }

    if list := node_cast(Arg_List, node); list != nil {
        for node in list.args {
            post_order_walk(node, data, visit)
        }
        visit(node, data)
        return
    }

    if block := node_cast(Block, node); block != nil {
        for node in block.code {
            post_order_walk(node, data, visit)
        }
        visit(node, data)
        return
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        post_order_walk(if_else.cond, data, visit)
        post_order_walk(if_else.if_body, data, visit)
        post_order_walk(if_else.else_body, data, visit)
        visit(node, data)
        return
    }   

    if while := node_cast(While, node); while != nil {
        post_order_walk(while.cond, data, visit)
        post_order_walk(while.body, data, visit)
        visit(node, data)
        return
    }

    if func := node_cast(Function, node); func != nil {
        for node in func.params  {
            post_order_walk(node, data, visit)
        }
        post_order_walk(func.body, data, visit)
        visit(node, data)
        return
    }

    if layout := node_cast(Layout, node); layout != nil {
        for node in layout.fields {
            post_order_walk(node, data, visit)
        }
        visit(node, data)
        return
    }

    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `post_order_walk`")
}

copy_node_recursively :: proc(node: ^Node(Wrapped), allocator := context.allocator) -> ^Node(Wrapped) {
    context.allocator = allocator
    if node == nil {
        return nil
    }

    copy_node :: proc(
        node: ^Node($T), 
        specify:=AST_Kind.INVALID, 
        allocator := context.allocator
    ) -> ^Node(T) {
        context.allocator = allocator
        if node == nil {
            return nil
        }

        copied := new_node(T, specify)
        copied^ = node^
        copied.annotation = {}
        return copied
    }

    if leaf := node_cast(Leaf, node); leaf != nil {
        return wrap_node(copy_node(leaf))
    }
    if brk := node_cast(Break, node); brk != nil {
        return wrap_node(copy_node(brk))
    }
    if cont := node_cast(Continue, node); cont != nil {
        return wrap_node(copy_node(cont))
    }
    if push := node_cast(Push, node); push != nil {
        return wrap_node(copy_node(push))
    }
    if field := node_cast(Layout_Field, node); field != nil {
        return wrap_node(copy_node(field))
    }

    if ret := node_cast(Return, node); ret != nil {
        new_ret := copy_node(ret)
        new_ret.result = copy_node_recursively(ret.result)
        return wrap_node(new_ret)
    }

    if decl := node_cast(Decl, node); decl != nil {
        new_decl := copy_node(decl)
        new_decl.rhs = copy_node_recursively(decl.rhs)
        return wrap_node(new_decl)
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        new_bin_expr := copy_node(bin_expr, bin_expr.kind)
        new_bin_expr.left = copy_node_recursively(bin_expr.left)
        new_bin_expr.right = copy_node_recursively(bin_expr.right)
        return wrap_node(new_bin_expr)
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        new_unary_expr := copy_node(unary_expr, unary_expr.kind)
        new_unary_expr.operand = copy_node_recursively(unary_expr.operand)
        return wrap_node(new_unary_expr)
    }

    if list := node_cast(Arg_List, node); list != nil {
        new_list := copy_node(list)
        new_list.args = make([]^Node(Wrapped), len(list.args))
        for node,i in list.args {
            new_list.args[i] = copy_node_recursively(node)
        }
        return wrap_node(new_list)
    }

    if block := node_cast(Block, node); block != nil {
        new_block := copy_node(block)
        new_block.code = make([]^Node(Wrapped), len(block.code))
        for node,i in block.code {
            new_block.code[i] = copy_node_recursively(node)
        }
        return wrap_node(new_block)
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        new_if_else := copy_node(if_else)
        new_if_else.cond = copy_node_recursively(if_else.cond)
        new_if_else.if_body = copy_node_recursively(if_else.if_body)
        new_if_else.else_body = copy_node_recursively(if_else.else_body)
        return wrap_node(new_if_else)
    }   

    if while := node_cast(While, node); while != nil {
        new_while := copy_node(while)
        new_while.cond = copy_node_recursively(while.cond)
        new_while.body = copy_node_recursively(while.body)
        return wrap_node(new_while)
    }

    if func := node_cast(Function, node); func != nil {
        new_func := copy_node(func)
        new_func.params = make([]^Node(Wrapped), len(func.params))
        for node,i in func.params {
            new_func.params[i] = copy_node_recursively(node)
        }
        new_func.body = copy_node_recursively(func.body)
        return wrap_node(new_func)
    }

    if layout := node_cast(Layout, node); layout != nil {
        new_layout := copy_node(layout)
        new_layout.fields = make([]^Node(Wrapped), len(layout.fields))
        for node,i in layout.fields {
            new_layout.fields[i] = copy_node_recursively(node)
        }
        return wrap_node(new_layout)
    }

    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `copy_node`")
    return nil
}

is_assign_op :: proc(kind: AST_Kind) -> AST_Kind {
    #partial switch kind {
    case .ASSIGN:             return .ASSIGN // w/e
    case .ADD_ASSIGN:         return .ADD
    case .SUB_ASSIGN:         return .SUB 
    case .MUL_ASSIGN:         return .MUL 
    case .DIV_ASSIGN:         return .DIV 
    case .BIT_AND_ASSIGN:     return .BIT_AND 
    case .BIT_OR_ASSIGN:      return .BIT_OR
    case .BIT_XOR_ASSIGN:     return .BIT_XOR
    case .SHIFT_LEFT_ASSIGN:  return .SHIFT_LEFT
    case .SHIFT_RIGHT_ASSIGN: return .SHIFT_RIGHT
    }
    return .INVALID
}

node_annotation_string :: proc(constraints: Unknown, mode: Addressing_Mode, allocator := context.allocator) -> string {
    context.allocator = allocator
    b := strings.builder_make()
    strings.write_string(&b, "{ ")
    if .BOOL  in constraints do strings.write_string(&b, "Bool, ");
    if .BYTE  in constraints do strings.write_string(&b, "Byte, ") 
    if .INT   in constraints do strings.write_string(&b, "Int, ") 
    if .FLOAT in constraints do strings.write_string(&b, "Float, ") 
    if .PTR   in constraints do strings.write_string(&b, "Ptr, ") 
    if .NONE  in constraints do strings.write_string(&b, "None, ") 

    when ODIN_DEBUG {
        fmt.sbprintf(&b, "} <-- %s", mode)
    }
    return strings.to_string(b)
}
