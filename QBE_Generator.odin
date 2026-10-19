
package magic

import "core:fmt"
import "core:strings"
import "base:runtime"

Emitter :: struct {
    code: strings.Builder,
    data: strings.Builder,
    instances: strings.Builder,
    out: ^strings.Builder,
    indents: int,

    terminated: bool,
    exit: QBE_Operand,
    has_exit: bool,

    next_temp: int,
    next_label: int,
    next_rdonly: int, // string literals

    breaks: [dynamic]string,
    conts: [dynamic]string,
    current_scope: ^Scope,
    locals: map[^Node(Wrapped)]QBE_Operand,
    allocator: runtime.Allocator,
}

QBE_Operand :: struct {
    mode: QBE_Addr_Mode,
    type: QBE_Type,
    id: int,
    literal: string,
    acc: Access_Kind,
}

QBE_Addr_Mode :: enum {
    NONE,
    GLOBAL,
    TEMP,
    IMM_INT,
    IMM_FLOAT,
    ADDR,
}

QBE_Type :: enum {
    W,L,S,D // We Light Sour Deisel 
}

Access_Kind :: enum {
    U8, U16, U32, U64,
    S8, S16, S32, S64,
    F32, F64, PTR,
}

init_emitter :: proc(e: ^Emitter, root: ^Node(Wrapped), allocator := context.allocator) {
    e.code = strings.builder_make(allocator)
    e.data = strings.builder_make(allocator)
    e.instances = strings.builder_make(allocator)
    e.breaks = make([dynamic]string, allocator)
    e.conts = make([dynamic]string, allocator)
    assert(node_cast(Block, root) != nil)
    e.current_scope = root.scope
    e.locals = make(map[^Node(Wrapped)]QBE_Operand, allocator)
    e.allocator = allocator

    e.out = &e.code
    fmt.sbprintf(
        e.out,
`export function w $main() {{
@start
`
    )
    e.indents = 1
}

// these helpers are important because they should be who "owns" the newline
emit_instr :: proc(e: ^Emitter, line: string, args: ..any) {
    for i in 0 ..< e.indents {
        strings.write_string(e.out, "    ")
    }
    fmt.sbprintf(e.out, line, ..args)
    strings.write_byte(e.out, '\n')
}

emit_rdonly_string :: proc(e: ^Emitter, id: int, str: string) {
    fmt.sbprintf(&e.data, "data $str_%d = {{ b ", id)
    bites := transmute([]u8) str
    for b in bites {
        fmt.sbprintf(&e.data, "%d ", b)
    }
    fmt.sbprintf(&e.data, "0 }}\n")
}

emit_label :: proc(e: ^Emitter, id: int) {
    fmt.sbprintf(e.out, "@label%d\n", id)
    e.terminated = false
}

emit_store :: proc(e: ^Emitter, local,value: QBE_Operand) {
    assert(local.mode == .ADDR)
    assert(local.type == value.type)

    opcode: string
    switch local.acc {
    case .U8, .S8:   opcode = "storeb"
    case .U16, .S16: opcode = "storeh"
    case .U32, .S32: opcode = "storew"

    case .U64, .S64, .PTR: opcode = "storel"

    case .F64: opcode = "stored"
    case .F32:
        single := new_temp(e, .S)
        emit_instr(e, "%s =s truncd %s", single.literal, value.literal)
        emit_instr(e, "stores %s, %s", single.literal, local.literal)
        return
    }
    emit_instr(e, "%s %s, %s",
        opcode, value.literal, local.literal
    )
}

emit_load :: proc(e: ^Emitter, location: QBE_Operand) -> QBE_Operand {
    assert(location.mode == .ADDR)

    opcode: string
    switch location.acc {
    case .U8:  opcode = "loadub"
    case .S8:  opcode = "loadsb"
    case .U16: opcode = "loaduh"
    case .S16: opcode = "loadsh"
    case .U32: opcode = "loaduw"
    case .S32: opcode = "loadsw"
    case .F64: opcode = "loadd"
    case .F32:
        single := new_temp(e, .S)
        emit_instr(e, "%s =s loads %s", single.literal, location.literal)
        result := new_temp(e, .D)
        emit_instr(e, "%s =d exts %s", result.literal, single.literal)
        return result

    case .U64, .S64, .PTR: opcode = "loadl"
    }

    result := new_temp(e, location.type)
    emit_instr(e, "%s =%s %s %s",
        result.literal, qbe_type_string(result.type), opcode, location.literal
    )
    return result
}

// LVALUES!!!
emit_addr :: proc(e: ^Emitter, node: ^Node(Wrapped)) -> QBE_Operand {
    assert(node.mode == .LVALUE || (node.kind == .DEREFERENCE && node.mode == .RVALUE))

    if leaf := node_cast(Leaf, node); leaf != nil {
        assert(leaf.token.kind == .IDENT)

        scope := e.current_scope
        for scope != nil {
            entity := lookup(scope, leaf)
            operand, ok := e.locals[entity.decl]
            if ok {
                assert(operand.mode == .ADDR)
                return operand
            }
            scope = scope.parent
        }
        assert(false, "no local?")
    }

    if node.kind == .DEREFERENCE {
        deref := node_cast(Bin_Expr, node)
        assert(deref != nil)

        base := emit(e, deref.left)
        right := node_cast(Leaf, deref.right)
        assert(right != nil)
        name := right.token.text
        offset := 0
        acc_name := name

        switch name {
        case "u8","u16","u32","u64",
             "s8","s16","s32","s64",
             "f32","f64",
             "ptr":
            // ok
        case:
            layout := deref.left.layout
            field, ok := layout.fields[name]
            assert(ok)
            offset = field.offset
            acc_name = field.node.type
        }
        address := base
        if offset != 0 {
            address = new_temp(e, .L)
            emit_instr(e, "%s =l add %s, %d",
                address.literal, base.literal, offset
            )
        }
        address.mode = .ADDR
        address.type = qbe_type(deref)

        switch acc_name {
        case "u8":  address.acc = .U8
        case "u16": address.acc = .U16
        case "u32": address.acc = .U32
        case "u64": address.acc = .U64
        case "s8":  address.acc = .S8
        case "s16": address.acc = .S16
        case "s32": address.acc = .S32
        case "s64": address.acc = .S64
        case "f32": address.acc = .F32
        case "f64": address.acc = .F64
        case:       address.acc = .PTR
        }

        return address
    }

    assert(false, "bad lvalue")
    return {}
}

//TODO: fix this redundant garbage 
emit_call_args :: proc(e: ^Emitter, call: ^Node(Bin_Expr)) -> string {
    list := node_cast(Arg_List, call.right)
    assert(list != nil)

    caller_scope := e.current_scope
    caller_locals := e.locals

    default_locals := make(map[^Node(Wrapped)]QBE_Operand)
    //copy map
    for k,v in caller_locals {
        default_locals[k]=v
    }
    defer {
        e.current_scope = caller_scope
        e.locals = caller_locals
        delete(default_locals)
    }

    b := strings.builder_make(e.allocator)
    for arg, i in list.args {
        if i > 0 {
            strings.write_string(&b, ", ")
        }
        param := call.instance.params[i]
        value: QBE_Operand
        if arg != nil {
            // belong to caller
            e.current_scope = caller_scope
            e.locals = caller_locals
            value = emit(e, arg)
        } else {
            default := node_cast(Bin_Expr, param)
            assert(default != nil)
            e.current_scope = call.instance.scope
            e.locals = default_locals
            value = emit(e, default.right)
        }
        e.locals = default_locals
        local := new_local(e, resolved_type(param))
        emit_store(e, local, value)
        default_locals[param] = local
        fmt.sbprintf(&b, "%s %s", qbe_type_string(qbe_type(param)), value.literal)
    }
    return strings.to_string(b)
}

emit_instance :: proc(e: ^Emitter, hash: Instance_Hash, instance: ^Node(Function)) {
    old_out := e.out
    old_scope := e.current_scope
    old_locals := e.locals
    old_breaks := e.breaks
    old_conts := e.conts
    old_terminated := e.terminated
    old_temp := e.next_temp
    old_label := e.next_label

    defer {
        e.out = old_out
        e.current_scope = old_scope
        e.locals = old_locals
        e.breaks = old_breaks
        e.conts = old_conts
        e.terminated = old_terminated
        e.next_temp = old_temp
        e.next_label = old_label
    }

    e.current_scope = instance.scope
    assert(e.current_scope != nil)
    e.out = &e.instances
    e.locals = make(map[^Node(Wrapped)]QBE_Operand, e.allocator)
    e.breaks = make([dynamic]string, e.allocator)
    e.conts = make([dynamic]string, e.allocator)
    e.next_temp = 0
    e.next_label = 0
    e.terminated = false

    if resolved_type(instance) == .NONE {
        fmt.sbprintf(e.out, "function $%s(", hash)
    } else {
        fmt.sbprintf(e.out, "function %s $%s(", 
            qbe_type_string(qbe_type(instance)), hash
        )
    }
    for param, i in instance.params {
        if i>0 {
            fmt.sbprintf(e.out, ", ")
        }
        fmt.sbprintf(e.out, "%s %%arg%d",
            qbe_type_string(qbe_type(param)), i
        )
    }
    fmt.sbprintf(e.out, ") {{\n@start\n")
    
    for param, i in instance.params {
        local := new_local(e, resolved_type(param))
        e.locals[param] = local
        incoming := new_temp(e, qbe_type(param))
        incoming.literal = fmt.aprintf(
            "%%arg%d", i, allocator=e.allocator
        )
        emit_store(e, local, incoming)
    }

    result := emit(e, instance.body)
    if !e.terminated {
        if resolved_type(instance) == .NONE {
            emit_instr(e, "ret")
        } else {
            emit_instr(e, "ret %s", result.literal)
        }
    }
    fmt.sbprintf(e.out, "}}\n")
}

new_label :: proc(e: ^Emitter) -> int {
    id := e.next_label
    e.next_label += 1
    return id
}

new_temp :: proc(e: ^Emitter, type: QBE_Type) -> QBE_Operand {
    id := e.next_temp
    e.next_temp += 1

    operand: QBE_Operand
    operand.mode = .TEMP
    operand.type = type
    operand.id = id
    operand.literal = fmt.aprintf("%%temp%d", id, allocator=e.allocator)
    return operand
}

new_local :: proc(e: ^Emitter, t: Type) -> QBE_Operand {
    addr := new_temp(e, .L)
    size := 8
    if t == .BYTE || t == .BOOL {
        size = 1
    }
    emit_instr(e, "%s =l alloc8 %d", addr.literal, size)
    
    operand: QBE_Operand
    operand.mode = .ADDR

    if t == .BYTE || t == .BOOL {
        operand.type = .W
    } else if t == .FLOAT {
        operand.type = .D
    } else {
        operand.type = .L
    }

    switch t {
    case .INT:   operand.acc = .S64
    case .FLOAT: operand.acc = .F64
    case .PTR:   operand.acc = .PTR
    case .BOOL, .BYTE: operand.acc = .U8
    case .NONE: assert(false, "trying to allocate for `none`?")
    }
    operand.literal = addr.literal
    return operand
}

qbe_type :: proc(node: ^Node($T)) -> QBE_Type {
    assert(card(node.constraints)==1, "checker just crapped the bed")

    switch {
    case .BOOL  in node.constraints: return .W
    case .BYTE  in node.constraints: return .W
    case .INT   in node.constraints: return .L
    case .FLOAT in node.constraints: return .D
    case .PTR   in node.constraints: return .L
    }

    fmt.println(node.constraints)
    assert(false,"unreachable, did u get `none`?")
    return .W
}

qbe_type_string :: proc(type: QBE_Type) -> string {
    switch type {
    case .W: return "w"
    case .L: return "l"
    case .S: return "s"
    case .D: return "d"
    }
    return "wtf this is unreachable Odin is very anal about non `#partial` switch?"
}

coerce :: proc(e: ^Emitter, value: QBE_Operand, source: Type, target: Type) -> QBE_Operand {
    // POINTERS ARE JUST NUMBERS XD
    if (source == .INT && target == .PTR) || (source == .PTR && target == .INT) {
        assert(value.type == .L)
        return value
    }

    if source == target {
        return value
    }

    if target == .BOOL {
        result := new_temp(e, .W)
        #partial switch source {
        case .BYTE:
            emit_instr(e, "%s =w cnew %s, 0", result.literal, value.literal)
        case .INT, .PTR:
            emit_instr(e, "%s =w cnel %s, 0", result.literal, value.literal)
        case .FLOAT:
            emit_instr(e, "%s =w cned %s, 0", result.literal, value.literal)
        case:
            assert(false, "bad boolean coercion")
        }
        return result
    }
    if source == .BOOL {
        return coerce(e, value, .BYTE, target)
    }

    opcode: string
    dest_t: QBE_Type

    switch {
    case source == .BYTE && target == .INT:
        opcode = "extub"
        dest_t = .L

    case source == .BYTE && target == .FLOAT:
        wide := coerce(e, value, .BYTE, .INT)
        return coerce(e, wide, .INT, .FLOAT)

    case source == .INT && target == .FLOAT:
        opcode = "sltof"
        dest_t = .D

    case source == .FLOAT && target == .INT:
        opcode = "dtosi"
        dest_t = .L

    case source == .INT && target == .BYTE:
        opcode = "extub"
        dest_t = .W

    case source == .FLOAT && target == .BYTE:
        wide := coerce(e, value, .FLOAT, .INT)
        return coerce(e, wide, .INT, .BYTE)

    case:
        // checker should reject the truly odd casts like `ptr` -> `float`
        assert(false, "bad coercion?")
        return {}
    }

    result := new_temp(e, dest_t)
    emit_instr(e, "%s =%s %s %s", result.literal, qbe_type_string(dest_t), opcode, value.literal)
    return result
}

normalize_operands :: proc(e: ^Emitter, lhs,rhs: ^Node(Wrapped), o1,o2: ^QBE_Operand, target: Type) {
    source1 := resolved_type(lhs)
    source2 := resolved_type(rhs)
    o1^ = coerce(e, o1^, source1, target)
    o2^ = coerce(e, o2^, source2, target)
}

pick_two_operand_instr :: proc(kind: AST_Kind, operand_t: Type) -> string {
    #partial switch kind {
    case .ADD: return "add"
    case .SUB: return "sub"
    case .MUL: return "mul"

    case .DIV:
        return operand_t == .BYTE ? "udiv" : "div"
    case .MODULO:
        return operand_t == .BYTE ? "urem" : "rem"

    case .BIT_AND: return "and"
    case .BIT_OR:  return "or"
    case .BIT_XOR: return "xor"

    case .SHIFT_LEFT: return "shl"
    case .SHIFT_RIGHT:
        // QBE should truncate to `w` if needed
        return operand_t == .BYTE ? "shr" : "sar"
    }
    assert(false, "not an arithmetic op?")
    return ""
}

pick_comparison_instr :: proc(kind: AST_Kind, operand_t: Type, allocator := context.allocator) -> string {
    relation: string
    floating := operand_t == .FLOAT
    unsigned := operand_t == .BYTE || operand_t == .PTR

    #partial switch kind {
    case .EQUALS: relation = "eq"
    case .NOT_EQUALS: relation = "ne"
    case .LESS: 
        if floating {
            relation = "lt"
        } else if unsigned {
            relation = "ult"
        } else {
            relation = "slt"
        }
    case .LESS_EQ: 
        if floating {
            relation = "le"
        } else if unsigned {
            relation = "ule"
        } else {
            relation = "sle"
        }
    case .GREATER: 
        if floating {
            relation = "gt"
        } else if unsigned {
            relation = "ugt"
        } else {
            relation = "sgt"
        }
    case .GREATER_EQ: 
        if floating {
            relation = "ge"
        } else if unsigned {
            relation = "uge"
        } else {
            relation = "sge"
        }
    case: assert(false, "no comparison?")
    }

    t: QBE_Type
    if operand_t == .BYTE {
        t = .W
    } else if operand_t == .FLOAT {
        t = .D
    } else {
        t = .L
    }
    suffix := qbe_type_string(t)
    return fmt.aprintf("c%s%s", relation, suffix, allocator=allocator)
}

// sorry I wrote the checker WAY to fast, need to blanket code gen with asserts...
type_is :: proc(node: ^Node($T), type: Type, loc:=#caller_location) -> bool {
    if card(node.constraints) != 1 {
        fmt.println(loc)
        assert(false, "checker just crapped the bed")
    }
    return type in node.constraints
}

resolved_type :: proc(node: ^Node($T), loc:=#caller_location) -> Type {
    if card(node.constraints) != 1 {
        fmt.println(loc)
        assert(false, "checker just crapped the bed")
    }
    switch {
    case .BOOL  in node.constraints: return .BOOL
    case .BYTE  in node.constraints: return .BYTE
    case .INT   in node.constraints: return .INT
    case .FLOAT in node.constraints: return .FLOAT
    case .PTR   in node.constraints: return .PTR
    case .NONE  in node.constraints: return .NONE
    }
    return .NONE // literally unreachable
}

emit :: proc(e: ^Emitter, node: ^Node(Wrapped)) -> QBE_Operand {

    if leaf := node_cast(Leaf, node); leaf != nil {
        context.allocator = e.allocator
        operand: QBE_Operand
        #partial switch leaf.token.kind {
        case .KEYWORD:
            switch leaf.token.text {
            case "true":
                operand.mode = .IMM_INT
                operand.type = .W
                operand.literal = "1" 
                return operand
            case "false":
                operand.mode = .IMM_INT
                operand.type = .W
                operand.literal = "0"
                return operand
            }
            fmt.println(leaf.token.text)
            assert(false,"not sure what other keyword is a leaf")

        case .INT:
            operand.mode = .IMM_INT
            operand.type = .L
            operand.literal = fmt.aprintf("%d", leaf.token.as_int) 
            return operand
        case .FLOAT:
            operand.mode = .IMM_FLOAT
            operand.type = .D
            operand.literal = fmt.aprintf("d_%f", leaf.token.as_float)
            return operand
        case .BYTE:
            operand.mode = .IMM_INT
            operand.type = .W
            operand.literal = fmt.aprintf("%d", leaf.token.as_u8)
            return operand

        case .STR:
            id := e.next_rdonly
            e.next_rdonly += 1
            emit_rdonly_string(e, id, leaf.token.as_str)
            operand.mode = .GLOBAL
            operand.literal = fmt.aprintf("$str_%d", id)
            operand.type = .L
            operand.id = id
            
            if leaf.tag == "puts" {
                emit_instr(e, "call $puts(l %s)", operand.literal)
            }
            return operand

        case .IDENT:
            operand := emit_load(e, emit_addr(e, wrap_node(leaf)))
            if type_is(leaf, .INT) && leaf.tag == "exit" {
                e.exit = operand
                e.has_exit = true
            }
            return operand
        }
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        // case 1: DAMN SHORT CIRCUITING!!! (wait wtf, this is actually easy?)
        if bin_expr.kind == .LOGICAL_AND || bin_expr.kind == .LOGICAL_OR {
            assert(type_is(bin_expr, .BOOL))
            context.allocator = e.allocator
            lhs := emit(e, bin_expr.left)
            result := new_temp(e, .W)

            rhs_label := new_label(e) 
            end_label := new_label(e) 
            if bin_expr.kind == .LOGICAL_AND {
                emit_instr(e, "%s =w copy 0", result.literal)
                emit_instr(e, "jnz %s, @label%d, @label%d", lhs.literal, rhs_label, end_label)
            } else {
                emit_instr(e, "%s =w copy 1", result.literal)
                emit_instr(e, "jnz %s, @label%d, @label%d", lhs.literal, end_label, rhs_label)
            }
            emit_label(e, rhs_label)
            rhs := emit(e, bin_expr.right)
            emit_instr(e, "%s =w copy %s", result.literal, rhs.literal)
            emit_instr(e, "jmp @label%d", end_label)
            emit_label(e, end_label)
            return result
        }

        // case 2: assignments...
        if is_assign_op(bin_expr.kind) != .INVALID {
            assert(bin_expr.left.mode == .LVALUE)

            compound_op := is_assign_op(bin_expr.kind)
            lhs := emit_addr(e, bin_expr.left)
            rhs := emit(e, bin_expr.right)
            target := resolved_type(bin_expr)

            if compound_op == .ASSIGN {
                emit_store(e, lhs, rhs)
                return rhs
            }

            old := emit_load(e, lhs)
            result := new_temp(e, lhs.type)
            opcode := pick_two_operand_instr(compound_op, resolved_type(bin_expr))
            // THANK YOU QBE FOR *NOT* FORCING SSA!!
            emit_instr(e, "%s =%s %s %s, %s",
                result.literal, qbe_type_string(result.type), opcode, old.literal, rhs.literal
            )
            emit_store(e, lhs, result)
            return result
        }

        // case 3: DEREFERENCE
        // a little annoying but it's needed to match this here
        if bin_expr.kind == .DEREFERENCE {
            addr := emit_addr(e, node)
            // fields with `using` or `embed` behave more like addr-of 
            if bin_expr.mode == .RVALUE {
                addr.mode = .TEMP
                addr.type = .L
                return addr
            }
            return emit_load(e, addr)
        }

        // case 4: instances/`CALL`s
        if bin_expr.kind == .CALL {
            hash := bin_expr.instance_hash
            assert(hash != "")
            args := emit_call_args(e, bin_expr)

            if type_is(bin_expr, .NONE) {
                emit_instr(e, "call $%s(%s)", hash, args)
                return {}
            }

            result := new_temp(e, qbe_type(bin_expr))
            emit_instr(e, "%s =%s call $%s(%s)",
                result.literal, qbe_type_string(result.type), hash, args
            )
            return result
        }

        // case 5: casts
        if bin_expr.kind == .CAST {
            value := emit(e, bin_expr.left)
            return coerce(e, value, resolved_type(bin_expr.left), resolved_type(bin_expr))
        }

        // case 6: comparison ops
        #partial switch bin_expr.kind {
        case .EQUALS,.NOT_EQUALS,.LESS,.LESS_EQ,.GREATER,.GREATER_EQ:
            assert(type_is(bin_expr, .BOOL))

            lhs := emit(e, bin_expr.left)
            rhs := emit(e, bin_expr.right)
            lhs_t := resolved_type(bin_expr.left)
            rhs_t := resolved_type(bin_expr.right)
            target: Type
            if lhs_t == .FLOAT || rhs_t == .FLOAT {
                target = .FLOAT
            } else if lhs_t == .PTR || rhs_t == .PTR {
                target = .PTR
            } else if lhs_t == .INT || rhs_t == .INT {
                target = .INT 
            } else {
                target = .BYTE
            }
            normalize_operands(e, bin_expr.left, bin_expr.right, &lhs, &rhs, target)
            
            result := new_temp(e, .W)
            opcode := pick_comparison_instr(bin_expr.kind, target, e.allocator)
            emit_instr(e, "%s =w %s %s, %s",
                result.literal, opcode, lhs.literal, rhs.literal
            )
            return result
        }

        // case 7: normal value producing arithmetic-type expressions :D!
        lhs := emit(e, bin_expr.left)
        rhs := emit(e, bin_expr.right)
        target := resolved_type(bin_expr)
        normalize_operands(e, bin_expr.left, bin_expr.right, &lhs, &rhs, target)

        id := e.next_temp
        e.next_temp += 1
        opcode := pick_two_operand_instr(bin_expr.kind, resolved_type(bin_expr))

        context.allocator = e.allocator
        operand: QBE_Operand
        operand.mode = .TEMP
        operand.id = id
        operand.literal = fmt.aprintf("%%temp%d", id)
        operand.type = qbe_type(bin_expr)
        emit_instr(e, "%%temp%d =%s %s %s, %s", 
            id, qbe_type_string(operand.type), opcode, lhs.literal, rhs.literal
        )
        return operand
    }

    // thank goodness there are only 4 unary exprs
    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        if unary_expr.kind == .ADDRESS_OF {
            addr := emit_addr(e, unary_expr.operand)
            addr.mode = .TEMP
            addr.type = .L
            return addr
        }

        value := emit(e, unary_expr.operand)
        result := new_temp(e, qbe_type(unary_expr))

        #partial switch unary_expr.kind {
        case .NEGATE:
            emit_instr(e, "%s =%s neg %s",
                result.literal, qbe_type_string(result.type), value.literal
            )
        case .BIT_NOT:
            mask := "-1"
            if type_is(unary_expr, .BYTE) {
                mask = "255"
            }
            emit_instr(e, "%s =%s xor %s, %s",
                result.literal, qbe_type_string(result.type), value.literal, mask 
            )
        case .LOGICAL_NOT:
            emit_instr(e, "%s =w ceqw %s, 0",
                result.literal, value.literal
            )
        case:
            assert(false, "bad unary operation")
        }
        return result
    }

    // `decl`s are marked with NO_VALUE!
    if decl := node_cast(Decl, node); decl != nil {
        if card(decl.constraints) != 1 {
            // checker actually allows this
            // this just means the declaration is not used or is a template
            if decl.rhs != nil {
                /*  `emit` still may be able to do something useful
                    example:
                    ```
                    decl why_would_anyone_do_this = do
                        print("lmao get trolled xD")
                        def() 
                            "deez_nuts"
                    ```
                */
                emit(e, decl.rhs)
            }
            return {}
        }
        if decl.forward {
            if decl.rhs != nil {
                value := emit(e, decl.rhs)
                local, ok := e.locals[node]
                assert(ok, "no stack slot for `forward`?")
                emit_store(e, local, value)
            }
            return {}
        }
    
        // CHECKER should set the `decl` type/constraint accordingly even if `mode=NO_VALUE`
        // in other words: at this point: `decl.constraints` good! `decl.mode` bad!
        value: QBE_Operand
        if decl.rhs != nil {
            value = emit(e, decl.rhs)
        }
        local := new_local(e, resolved_type(decl))
        e.locals[node] = local
        if decl.rhs != nil && decl.rhs.mode != .TEMPLATE {
            emit_store(e, local, value)
        }
        return {}
    }

    if block := node_cast(Block, node); block != nil {
        result: QBE_Operand
        prev := e.current_scope
        e.current_scope = block.scope
        // resolve forwards
        for child in block.code {
            if decl := node_cast(Decl, child); decl != nil {
                if !decl.forward {
                    continue
                }
                if card(decl.constraints) != 1 {
                    // is template or w/e
                    continue
                }
                e.locals[child] = new_local(e, resolved_type(decl))
            }
        }

        for child in block.code {
            if e.terminated {
                break
            }
            result = emit(e, child)
        }
        e.current_scope = prev
        return result
    }

    if push := node_cast(Push, node); push != nil {
        result := new_temp(e, .L)
        emit_instr(e, "%s =l alloc8 %d", result.literal, max(push.layout.size, 1))
        return result
    }

    if sizeof := node_cast(Size_Of, node); sizeof != nil {
        operand: QBE_Operand
        operand.mode = .IMM_INT
        operand.type = .L
        operand.literal = fmt.aprintf("%d", sizeof.layout.size, allocator=e.allocator)
        return operand
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        cond := emit(e, if_else.cond)
        then_label := new_label(e)
        end_label := new_label(e)
        has_else := if_else.else_body != nil
        else_label := end_label
        if has_else {
            else_label = new_label(e)
        }
        has_value := node.mode == .RVALUE

        result: QBE_Operand
        if has_value {
            result = new_temp(e, qbe_type(node))
        }
        emit_instr(e, "jnz %s, @label%d, @label%d", cond.literal, then_label, else_label)
        e.terminated = true

        //THEN
        emit_label(e, then_label)
        then_value := emit(e, if_else.if_body)
        then_terminated := e.terminated

        if !then_terminated {
            if has_value {
                emit_instr(e, "%s =%s copy %s",
                    result.literal, qbe_type_string(result.type), then_value.literal
                )
            }
            emit_instr(e, "jmp @label%d", end_label)
            e.terminated = true
        }

        //ELSE
        else_terminated := false
        if has_else {
            emit_label(e, else_label)
            else_value := emit(e, if_else.else_body)
            else_terminated = e.terminated
            if !else_terminated {
                if has_value {
                    emit_instr(e, "%s =%s copy %s",
                        result.literal, qbe_type_string(result.type), else_value.literal
                    )
                }
                emit_instr(e, "jmp @label%d", end_label)
                e.terminated = true
            }
        }

        // merge
        if !has_else || !then_terminated || !else_terminated {
            emit_label(e, end_label)
        } else {
            // both branches terminate
            e.terminated = true
        }
        return result
    }

    if while := node_cast(While, node); while != nil {
        cond_label := new_label(e)
        body_label := new_label(e)
        end_label  := new_label(e)

        emit_instr(e, "jmp @label%d", cond_label)
        e.terminated = true
        emit_label(e, cond_label)
        cond := emit(e, while.cond)
        emit_instr(e, "jnz %s, @label%d, @label%d",
            cond.literal, body_label, end_label
        )
        e.terminated = true

        emit_label(e, body_label)
        append(&e.breaks, fmt.aprintf("@label%d", end_label, allocator=e.allocator))
        append(&e.conts, fmt.aprintf("@label%d", cond_label, allocator=e.allocator))
        defer {
            pop(&e.breaks)
            pop(&e.conts)
        }
        emit(e, while.body)

        if !e.terminated {
            emit_instr(e, "jmp @label%d", cond_label)
            e.terminated = true
        }
        emit_label(e, end_label)
        return {}
    }

    if brk := node_cast(Break, node); brk != nil {
        assert(len(e.breaks) > 0)
        target := e.breaks[len(e.breaks)-1]
        emit_instr(e, "jmp %s", target)
        e.terminated = true
        return {}
    }
    if cont := node_cast(Continue, node); cont != nil {
        assert(len(e.conts) > 0)
        target := e.conts[len(e.conts)-1]
        emit_instr(e, "jmp %s", target)
        e.terminated = true
        return {}
    }

    if ret := node_cast(Return, node); ret != nil {
        if ret.result != nil {
            result := emit(e, ret.result)

            if type_is(ret.result, .NONE) {
                emit_instr(e, "ret")
            } else {
                emit_instr(e, "ret %s", result.literal)
            }
        } else {
            emit_instr(e, "ret")
        }
        e.terminated = true
        return {}
    }

    if func := node_cast(Function, node); func != nil {
        // you can 100% ignore these
        // past the checker stage they do nothing
        // because each call has an `instance_hash` that points to a specialized function
        return {}
    }

    if list := node_cast(Arg_List, node); list != nil {
        // also skippable
        // should be taken care of in `bin_expr` case when `kind = .CALL`
        // cause that's the only place it should exist
        return {}
    }

    if layout := node_cast(Layout, node); layout != nil {
        // worthelss
        // also if `Layout_Field` is encountered the assert below failing deserves to happen
        return {}
    }
   
    //TODO: literally everything else
    fmt.printf("%v\n", node.kind)
    assert(false, "unknown AST_Kind in `qbe.emit`")
    return {}
}


generate :: proc(e: ^Emitter, c: ^Checker, root: ^Node(Wrapped)) -> string {
    emit(e, root)
    if !e.terminated {
        if e.has_exit {
            emit_instr(e, "ret %s", e.exit.literal)
        } else {
            emit_instr(e, "ret 0")
        }
    }
    fmt.sbprintf(e.out, "}}\n")

    for hash, instance in c.instances {
        emit_instance(e, hash, instance)
    }

    owari_da := strings.builder_make()
    strings.write_string(&owari_da, strings.to_string(e.code))
    strings.write_string(&owari_da, strings.to_string(e.instances))
    strings.write_string(&owari_da, strings.to_string(e.data))
    return strings.to_string(owari_da)
}

