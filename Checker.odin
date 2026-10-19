
package magic

import lex "Godlex"
import "core:fmt"
import "core:strings"

Addressing_Mode :: enum {
    INVALID = 1,
    NO_VALUE,
    RVALUE,
    LVALUE,
    CONST,
    TEMPLATE,
}

Operand :: struct {
    expr: ^Node(Wrapped),
    constraints: Unknown,
    mode: Addressing_Mode,
    template: ^Node(Function),
    instance: Instance_Hash,
    layout: ^Layout_Info,
}

Layout_Info :: struct {
    size: int,
    fields: map[string]^Field_Info,
    resolving,done: bool,
    node: ^Node(Layout),
}

Field_Info :: struct {
    offset,size: int,
    result: Type, 
    layout: ^Layout_Info, // non-nil only if `result = .PTR` and it has a layout assigned
    embed,overlay,use: bool, // `while` is a valid identifier in odin but not `using` ?
    node: ^Node(Layout_Field),
}

Entity :: struct {
    using operand: Operand,
    decl: ^Node(Wrapped),
}

Scope :: struct {
    parent: ^Scope,
    symbols: map[string]^Entity,
}

Return_Stack :: struct {
    prev: ^Return_Stack,
    template: ^Node(Function),
    instance: ^Node(Function),
    constraints: Unknown,
    loop_depth: int,
}

Checker :: struct {
    using g: ^lex.Godlex,
    scope: ^Scope,
    current: ^Return_Stack,
    loop_depth: int,
    changed: bool,
    passes: int,

    instances: map[Instance_Hash]^Node(Function),
    template_ids: map[^Node(Function)]int,
    current_instance_id: int,

    ptr_size: int,
    layouts: map[string]^Layout_Info,
    layout_ids: map[^Layout_Info]int,
    current_layout_id: int,
}

Instance_Hash :: distinct string

Type :: enum {
    NONE,
    BOOL,
    BYTE,
    INT,
    FLOAT,
    PTR,
}

// unknown is resolved when only 1 field is set
// otherwise it is an unknown/invalid type 
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

Any : Unknown : { .NONE, .BOOL, .BYTE, .INT, .FLOAT, .PTR, } 

/*  NOTE:
    addr-of, assignments and `SUBSCRIPT` are special cased because lvalue-ness is what is being checked
    `CAST` is also special cased because that hard sets a type
    `DEREFERENCE` operates on layouts so that is certainly special cased
    and `CALL` does instantiating and needs to check function body 
*/
RULES := #partial [AST_Kind][]Type_Rule {
    .ADD = {
        Bin_Type_Rule { Byte, Byte, Int },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },

        Bin_Type_Rule { Float, Float, Float },

        Bin_Type_Rule { Ptr, Int, Ptr },
        Bin_Type_Rule { Int, Ptr, Ptr },
        Bin_Type_Rule { Ptr, Ptr, Ptr },
    },
    .SUB = {
        Bin_Type_Rule { Byte, Byte, Int },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },

        Bin_Type_Rule { Float, Float, Float },

        Bin_Type_Rule { Ptr, Int, Ptr },
        Bin_Type_Rule { Int, Ptr, Ptr },
        Bin_Type_Rule { Ptr, Ptr, Ptr },
    },
    .NEGATE = {
        Unary_Type_Rule { Int, Int },
        Unary_Type_Rule { Float, Float },
    },
    .MUL = {
        Bin_Type_Rule { Byte, Byte, Int },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },

        Bin_Type_Rule { Float, Float, Float },
    },
    .DIV = {
        Bin_Type_Rule { Byte, Byte, Int },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },

        Bin_Type_Rule { Float, Float, Float },
    },
    .MODULO = {
        Bin_Type_Rule { Byte, Byte, Byte },
        Bin_Type_Rule { Byte, Int, Int },
        Bin_Type_Rule { Int, Byte, Int },
        Bin_Type_Rule { Int, Int, Int },
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
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .LESS_EQ = {
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .GREATER = {
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .GREATER_EQ = {
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .EQUALS = {
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Bool, Bool, Bool },
        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
        Bin_Type_Rule { Ptr, Ptr, Bool },
    },
    .NOT_EQUALS = {
        Bin_Type_Rule { Byte, Byte, Bool },
        Bin_Type_Rule { Byte, Int, Bool },
        Bin_Type_Rule { Int, Byte, Bool },
        Bin_Type_Rule { Int, Int, Bool },

        Bin_Type_Rule { Int, Float, Bool },
        Bin_Type_Rule { Float, Int, Bool },
        Bin_Type_Rule { Byte, Float, Bool },
        Bin_Type_Rule { Float, Byte, Bool },
        Bin_Type_Rule { Float, Float, Bool },

        Bin_Type_Rule { Bool, Bool, Bool },
        Bin_Type_Rule { Int, Ptr, Bool },
        Bin_Type_Rule { Ptr, Int, Bool },
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

init_checker :: proc(c: ^Checker, g: ^lex.Godlex, ptr_size := 8) {
    c.g = g
    c.instances = make(map[Instance_Hash]^Node(Function), c.allocator)
    c.template_ids = make(map[^Node(Function)]int, c.allocator)
    c.layouts = make(map[string]^Layout_Info, c.allocator)
    c.layout_ids = make(map[^Layout_Info]int, c.allocator)
    c.current_layout_id = 1 // 0 is reserved for "no layout"
    c.ptr_size = ptr_size
}

push_scope :: proc(c: ^Checker) -> ^Scope {
    parent: ^Scope
    if c.scope != nil { 
        parent = c.scope
    }
    c.scope = new(Scope,c.allocator)
    c.scope.symbols = make(map[string]^Entity, c.allocator)
    c.scope.parent = parent 
    return c.scope
}

// is shadowing REALLY that simple??
lookup :: proc(scope: ^Scope, ident: ^Node(Leaf)) -> ^Entity {
    assert(ident.token.kind == .IDENT)
    it := scope
    for it != nil {
        if entity, ok := it.symbols[ident.token.text]; ok {
            // multi-pass design mandates this check :O 
            if is_forward(entity.decl) || entity.decl.span[0] < ident.span[0] {
                return entity
            }
        }
        it = it.parent
    }
    return nil
}

local :: proc(scope: ^Scope, name: string) -> ^Entity {
    if entity, ok := scope.symbols[name]; ok {
        return entity
    }
    return nil
}

is_forward :: proc(decl: ^Node(Wrapped)) -> bool {
    if not_from_params := node_cast(Decl, decl); not_from_params != nil {
        return not_from_params.forward
    }
    return false
}

declare :: proc(scope: ^Scope, name: string, entity: ^Entity) -> ^Entity {
    if entity, exists := scope.symbols[name]; exists {
        return entity
    }
    scope.symbols[name] = entity
    return nil
}

set_layout :: proc(c: ^Checker, node: ^Node($T), layout: ^Layout_Info) {
    if node.layout != layout {
        node.layout = layout
        c.changed = true
    }
}

operand_of :: proc(
    node: ^Node($T), 
    mode: Addressing_Mode, 
    template: ^Node(Function) = nil
) -> Operand {
    node.mode = mode
    operand: Operand
    operand.expr = wrap_node(node)
    operand.constraints = node.constraints
    operand.layout = node.layout
    operand.mode = mode
    operand.template = template
    return operand
}

produces_value :: proc(mode: Addressing_Mode) -> bool {
    return mode != .NO_VALUE && mode != .TEMPLATE
}

/* TYPE OPERATIONS */
overlap_one_and_result :: proc(operand,result: Unknown, rule: Unary_Type_Rule) -> bool {
    return card(operand & rule.operand) != 0 && 
           card(result & rule.result) != 0
}

overlap_two_and_result :: proc(lhs,rhs,result: Unknown, rule: Bin_Type_Rule) -> bool {
    return card(lhs & rule.lhs) != 0 && 
           card(rhs & rule.rhs) != 0 && 
           card(result & rule.result) != 0
}

overlaps :: proc {
    overlap_one_and_result, 
    overlap_two_and_result,
}

infer_unary :: proc(expr: ^Node(Unary_Expr)) -> bool {
    operand := expr.operand.constraints
    result := expr.constraints
    possible_operand,possible_result: Unknown
    matched := false
    for rule in RULES[expr.kind] {
        switch unary_rule in rule {
        case Bin_Type_Rule: // skip
        case Unary_Type_Rule:
            if overlaps(operand,result,unary_rule) {
                matched = true
                possible_operand += unary_rule.operand
                possible_result += unary_rule.result
            }
        }
    }

    if !matched {
        changed := card(expr.constraints) != 0
        expr.constraints = {} // CONTRADICTION
        return changed 
    }
    new_operand := operand & possible_operand 
    new_result := result & possible_result 
    changed := new_operand != operand || new_result != result
    expr.operand.constraints = new_operand
    expr.constraints = new_result
    return changed
}

infer_bin_as :: proc(expr: ^Node(Bin_Expr), kind: AST_Kind) -> bool {
    lhs := expr.left.constraints
    rhs := expr.right.constraints
    result := expr.constraints
    possible_lhs,possible_rhs,possible_result: Unknown
    matched := false
    for rule in RULES[kind] {
        switch bin_rule in rule {
        case Unary_Type_Rule: // skip
        case Bin_Type_Rule:
            if overlaps(lhs,rhs,result,bin_rule) {
                matched = true
                possible_lhs += bin_rule.lhs
                possible_rhs += bin_rule.rhs
                possible_result += bin_rule.result
            }
        }
    }

    if !matched {
        changed := card(expr.constraints) != 0
        expr.constraints = {} // YOU MESSED UP, BROTHER
        return changed 
    }
    new_lhs := lhs & possible_lhs
    new_rhs := rhs & possible_rhs
    new_result := result & possible_result 
    changed := new_lhs != lhs || new_rhs != rhs || new_result != result
    expr.left.constraints = new_lhs
    expr.right.constraints = new_rhs
    expr.constraints = new_result
    return changed 
}

infer_bin :: proc(expr: ^Node(Bin_Expr)) -> bool {
    return infer_bin_as(expr, expr.kind)
}

infer :: proc {
    infer_bin,
    infer_unary,
}

// I hit a mad flow state, and ended up writing the hardest function in my entire carreer atm
instantiate :: proc(c: ^Checker, call: ^Node(Bin_Expr)) -> Operand {
    lhs := infer_node(c, call.left)
    if lhs.mode == .INVALID {
        return operand_of(call, .INVALID)
    }
    if lhs.mode != .TEMPLATE {
        if card(lhs.constraints) == 0 {
            return operand_of(call, .RVALUE) // must resolve to TEMPLATE else its error
        }
        bad_node(c, call.left, "expression is not callable")
        return operand_of(call, .INVALID)
    }
    id := register_template_hash(c, lhs.template) // muy importante!
    call.template_id = id
    list := node_cast(Arg_List, call.right)
    assert(list != nil) // parser cannot allow this!
    infer_node(c, call.right) // set `.NO_VALUE`

    if len(lhs.template.params) != len(list.args) {
        bad_node(c, call.right, "function expects %d args but caller provided %d",
            len(lhs.template.params), len(list.args)       
        )
        // for trailing default args you have to specify like `empty_slots_at_end(1,2,3,,,)`
        return operand_of(call, .INVALID)
    }

    // check recursion
    for active := c.current; active != nil; active = active.prev {
        if active.template != lhs.template {
            continue
        }
        // MATCHED SOME RECURSION!
        for arg,i in list.args {
            original := active.instance.params[i]
            // uses the default argument, nothing to constrain, and `original` already gets inferred
            if arg == nil {
                if default := node_cast(Bin_Expr, original); default == nil {
                    bad_node(c, call.right, 
                        "argument not supplied when function default arg does not exist"
                    )
                    return operand_of(call, .INVALID)
                }
                continue
            }

            operand := infer_node(c, arg)
            if operand.mode == .INVALID {
                return operand_of(call, .INVALID)
            }
            if !produces_value(operand.mode) {
                bad_node(c, arg, "recursive argument does not produce a value")
                return operand_of(call, .INVALID)
            }
            if operand.layout != original.layout {
                bad_node(c, arg, "recursive call cannot change the layout of parameters")
                return operand_of(call, .INVALID)
            }

            common := operand.constraints & original.constraints
            if card(common) == 0 {
                warn(c, "recursive call cannot change paramater types")
                return operand_of(call, .INVALID)
            }
            if common != arg.constraints ||
               common != original.constraints {
                c.changed = true
            }
            arg.constraints = common
            original.constraints = common
        }

        // recursive call shares return type
        common := call.constraints & active.constraints
        if card(common) == 0 {
            warn(c, "recursive call's return type does not match that of the outer function")
            return operand_of(call, .INVALID)
        }
        if common != call.constraints || common != active.constraints {
            c.changed = true
        }
        call.constraints = common
        active.constraints = common
        call.instance = active.instance
        set_layout(c, call, active.instance.layout)
        return operand_of(call, .RVALUE)
    }

    if call.instance == nil {
        fresh := copy_node_recursively(wrap_node(lhs.template), c.allocator)
        instance := node_cast(Function, fresh)
        for param in instance.params {
            seed(c, param)
        }
        seed(c, instance.body)
        call.instance = instance
    }

    // allocate caller scope
    caller: ^Scope
    callee: ^Scope
    if call.scope == nil {
        caller = c.scope
        callee = new(Scope, c.allocator) 
        callee.symbols = make(map[string]^Entity, c.allocator)
        callee.parent = lhs.template.scope
        call.scope = callee
        c.scope = caller // restore for now
    } else {
        caller = c.scope
        callee = call.scope
    }

    call.instance.scope = callee
    for node,i in call.instance.params {
        param := node_cast(Leaf, node)
        arg := list.args[i]
        // argument supplied by caller
        if param != nil && arg != nil {
            assert(param.token.kind == .IDENT)

            operand := infer_node(c, arg)
            if operand.mode == .INVALID {
                return operand_of(call, .INVALID)
            }
            if instantiate_parameter(c, param.token.text, callee, 
                wrap_node(param),arg
            ) == nil {
                return operand_of(call, .INVALID)
            }
            continue
        }
        if default := node_cast(Bin_Expr, node); default != nil {
            if param := node_cast(Leaf, default.left); param != nil {
                assert(default.kind == .ASSIGN)
                assert(param.token.kind == .IDENT)

                operand: Operand
                decl: ^Node(Wrapped)
                // argument NOT supplied by caller, try default
                if arg == nil {
                    c.scope = callee
                    operand = infer_node(c, default.right)
                    c.scope = caller

                    if operand.mode == .INVALID {
                        warn(c, "only global/const identifiers allowed in default args")
                        return operand_of(call, .INVALID)
                    }
                    if instantiate_parameter(c, param.token.text, callee,
                        wrap_node(default),default.right
                    ) == nil {
                        return operand_of(call, .INVALID)
                    }
                } else {
                    // You have to mark this otherwise `finalize` will get pissed off
                    // in this case, the instance's default value is not used, so just do this
                    default.right.mode = .NO_VALUE

                    operand := infer_node(c, arg)
                    if operand.mode == .INVALID {
                        return operand_of(call, .INVALID)
                    }
                    if instantiate_parameter(c, param.token.text, callee,
                        wrap_node(default),arg
                    ) == nil {
                        return operand_of(call, .INVALID)
                    }
                }
                continue
            } else {
                // function syntax check in `infer_node` did not work??
                assert(false)
            }
        }

        bad_node(c, call.right, "argument not supplied when function default arg does not exist")
        return operand_of(call, .INVALID)
    }

    // this is an insane power move btw, epic stack in call stack
    current: Return_Stack 
    current.prev = c.current
    current.template = lhs.template
    current.instance = call.instance
    current.constraints = call.constraints
    c.current = &current
    defer c.current = current.prev

    c.scope = callee
    outer := c.changed
    body := false
    for {
        c.changed = false
        operand := infer_node(c, wrap_node(call.instance.body))
        if operand.mode == .INVALID {
            bad_node(c, lhs.template, "failed to instantiate this")
            c.error_count -= 1 // count only 1 as error
            c.scope = caller
            return operand_of(call, .INVALID)
        }
        do_it_again := c.changed
        body = body || do_it_again
        if !do_it_again {
            break
        }
        c.passes += 1 // you know what, lets count these as a pass, it looks fancier!
    }
    c.changed = outer || body

    common := call.constraints & call.instance.body.constraints & current.constraints
    if common != call.constraints    ||
       common != current.constraints ||
       common != call.instance.body.constraints {
        c.changed = true
    }
    call.constraints = common
    call.instance.constraints = common
    call.instance.body.constraints = common
    // if no explicit return
    if call.instance.layout == nil {
        set_layout(c, call.instance, call.instance.body.layout)
    }
    set_layout(c, call, call.instance.layout)

    if call.constraints == {} {
        bad_node(c, lhs.template, "instantiation of this cannot produce a valid type")
        c.error_count -= 1 // only 1
        c.scope = caller
        return operand_of(call, .INVALID)
    }

    // reuse instance if already been generated
    hash, ok := get_instance_hash(c, call.instance, id)
    if ok {
        if hash not_in c.instances {
            c.instances[hash] = call.instance
        }
        call.instance_hash = hash
    } else {
        call.instance_hash = ""
    }
    // I wanna say the copy is redundant and wasteful
    // but maybe not? it should be needed to do the whole inference shebang
    // since any instance may not match anything that has been generated...
    call.instance_hash = hash
    c.scope = caller
    return operand_of(call, .RVALUE)
}

instantiate_parameter :: proc(
    c: ^Checker, 
    name: string,
    callee: ^Scope,
    param,arg: ^Node(Wrapped)
) -> ^Entity {
    if !produces_value(arg.mode) {
        bad_node(c, arg, "argument for parameter `%s` does not produce a value!", name)
        return nil
    }

    entity := local(callee, name)
    if entity == nil {
        entity = new(Entity,c.allocator)
        entity.constraints = arg.constraints
        entity.decl = wrap_node(param)
        declare(callee, name, entity)
    } else if entity.decl != param {
        bad_node(c, param, "duplicate parameter `%s`", name)
        return nil
    }

    if entity.layout != arg.layout {
        entity.layout = arg.layout
        c.changed = true
    }
    set_layout(c, param, arg.layout)

    common := entity.constraints & arg.constraints & param.constraints
    if default := node_cast(Bin_Expr, param); default != nil {
        // propogate to identifier on lhs of paramter decl as well
        default.left.constraints = common
        default.left.mode = .NO_VALUE
    }

    if common != entity.constraints || 
       common != arg.constraints    ||
       common != param.constraints {
        c.changed = true
    }
    entity.constraints = common
    arg.constraints = common
    param.constraints = common
    return entity
}

register_template_hash :: proc(c: ^Checker, template: ^Node(Function)) -> int {
    if template not_in c.template_ids {
        c.template_ids[template] = c.current_instance_id
        c.current_instance_id += 1
    }
    return c.template_ids[template]
}

get_instance_hash :: proc(c: ^Checker, func: ^Node(Function), id: int) -> (Instance_Hash, bool) {
    b := strings.builder_make(c.allocator)
    fmt.sbprintf(&b, "instance_%d_", id)

    put_type_byte :: proc(b: ^strings.Builder, constraints: Unknown, layout_id:=0) -> bool {
        if card(constraints) != 1 {
            return false
        }

        if .BOOL  in constraints {
            strings.write_string(b, "b") // b for "bool"
            return true
        }
        if .BYTE  in constraints {
            strings.write_string(b, "c") // c for "char"
            return true
        }
        if .INT   in constraints {
            strings.write_string(b, "i") // i for "int" 
            return true
        }
        if .FLOAT in constraints {
            strings.write_string(b, "f") // f for "float"
            return true
        }
        if .PTR   in constraints {
            if layout_id != 0 {
                fmt.sbprintf(b, "p%d", layout_id)
            } else {
                strings.write_string(b, "p") // p for "ptr"
            }
            return true
        }
        if .NONE  in constraints {
            strings.write_string(b, "n") // n for "none"
            return true
        }
        return false
    }

    // paramters
    for param in func.params {
        ok: bool
        if param.layout != nil {
            ok = put_type_byte(&b, param.constraints, c.layout_ids[param.layout])
        } else {
            ok = put_type_byte(&b, param.constraints)
        }
        if !ok {
            return "", false
        }
    }

    // return type
    strings.write_string(&b, "__")
    ok: bool
    if func.layout != nil {
        ok = put_type_byte(&b, func.constraints, c.layout_ids[func.layout])
    } else {
        ok = put_type_byte(&b, func.constraints)
    }
    if !ok {
        return "", false
    }
    return cast(Instance_Hash) strings.to_string(b), true
}

// I dont think it's needed to check `lex.has_error` schizophrenically 
// just keep going and accumulate errors
bad_node :: proc(c: ^Checker, node: ^Node($T), errmsg: string, format: ..any) {
    lex.error(c.g, node.span, errmsg, ..format);
}

warn :: proc(c: ^Checker, errmsg: string, format: ..any) {
    lex.warning(c.g, errmsg, ..format)
}

seed :: proc(c: ^Checker, node: ^Node(Wrapped), toplevel := false) {
    // since layouts can only appear at top level, dont even need a visitor
    if toplevel {
        root := node_cast(Block, node)
        assert(root != nil)

        // pass 1: collect+allocate layouts
        for mayb_layout in root.code {
            if layout := node_cast(Layout, mayb_layout); layout != nil {
                if _, exists := c.layouts[layout.name]; exists {
                    bad_node(c, layout, "duplicate layout `%s`", layout.name)
                    return
                }

                layout_info := new(Layout_Info, c.allocator)
                layout_info.node = layout
                c.layouts[layout.name] = layout_info 
                layout_info.fields = make(map[string]^Field_Info, c.allocator)
                c.layout_ids[layout_info] = c.current_layout_id
                c.current_layout_id += 1

                for field in layout.fields {
                    field_node := node_cast(Layout_Field, field)
                    assert(field_node != nil)

                    field_info := new(Field_Info, c.allocator)
                    field_info.node = field_node
                    field_info.embed = field_node.embed
                    field_info.overlay = field_node.overlay
                    field_info.use = field_node.use

                    assert(field_info.node != nil)

                    name := field_info.node.name
                    switch name {
                    case "u8","u16","u32","u64",
                         "s8","s16","s32","s64",
                         "f32","f64":
                        bad_node(c, layout, "reserved field name `%s` in layout", field_node.name)
                        return
                    }
                    _,exists := layout_info.fields[name]
                    if exists {
                        bad_node(c, layout, "duplicate field name `%s` in layout", name)
                        return
                    }

                    layout_info.fields[name] = field_info
                }
            }
        }

        // pass 2: MORE RECURSIVE NONESE: SOMEONE PLEASE SABE MEEEEE
        for _, layout in c.layouts {
            if !resolve_layout(c, layout) {
                return
            }
        }
    }

    visit :: proc(node: ^Node(Wrapped), data: rawptr) {
        c := cast(^Checker) data
        
        if leaf := node_cast(Leaf, node); leaf != nil {
            #partial switch leaf.token.kind {
            case .BYTE:  leaf.constraints += Byte 
            case .INT:   leaf.constraints += Int 
            case .FLOAT: leaf.constraints += Float 
            case .STR:   leaf.constraints += Ptr 
            case .IDENT: leaf.constraints = Any
            case .KEYWORD:
                switch leaf.token.text {
                case "true":  leaf.constraints += Bool 
                case "false": leaf.constraints += Bool 
                case "none":  leaf.constraints += None
                }
            }
            if leaf.token.kind != .IDENT {
                leaf.mode = .RVALUE
            }
            return
        }

        if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
            if bin_expr.kind == .CAST {
                type := node_cast(Leaf, bin_expr.right)
                assert(type.token.kind == .IDENT) // parser only enforces identifiers here!
                switch type.token.text {
                // do not need to throw error for `none` because `none` is a keyword
                // since it's not an identifier, it's rejected by the parser
                case "bool":  bin_expr.constraints += Bool 
                case "byte":  bin_expr.constraints += Byte 
                case "int":   bin_expr.constraints += Int 
                case "float": bin_expr.constraints += Float 
                case "ptr":   bin_expr.constraints += Ptr 
                case:
                    layout,exists := c.layouts[type.token.text]
                    if exists {
                        bin_expr.constraints += Ptr
                        bin_expr.layout = layout
                    } else {
                        bad_node(c, bin_expr, "type or layout in cast does not exist")
                    }
                }
                type.mode = .NO_VALUE
                return
            }
        }

        if push := node_cast(Push, node); push != nil {
            push.constraints = Ptr
            layout,exists := c.layouts[push.type]
            if exists {
                push.layout = layout
            } else {
                bad_node(c, push, "layout in stack alloc does not exist")
            }
            push.mode = .RVALUE
            return
        }

        if sizeof := node_cast(Size_Of, node); sizeof != nil {
            sizeof.constraints = Int
            layout,exists := c.layouts[sizeof.type]
            if exists {
                sizeof.layout = layout
            } else {
                bad_node(c, sizeof, "layout in `size_of` does not exist")
            }
            sizeof.mode = .RVALUE
            return
        }

        if func := node_cast(Function, node); func != nil {
            insane_nested_visitor :: proc(node: ^Node(Wrapped), data: rawptr) {
                node.generic = true
            }
            // non-instance functions are generic no matter what
            pre_order_walk(node, nil, insane_nested_visitor)
            func.mode = .TEMPLATE
            return
        }

        node.constraints = Any
    }

    post_order_walk(node, cast(rawptr) c, visit)
}

resolve_layout :: proc(c: ^Checker, layout: ^Layout_Info) -> bool {
    if layout.done {
        return true
    }
    if layout.resolving {
        bad_node(c, layout.node, "recursive embedded layout")
        return false
    }
    layout.resolving = true
    defer layout.resolving = false

    counter := 0
    group_offset := 0
    group_size := 0

    for ast_field in layout.node.fields {
        field_node := node_cast(Layout_Field, ast_field)
        assert(field_node != nil)
        field := layout.fields[field_node.name]
        type_name := field.node.type
        size := 0
        switch type_name {
        case "u8": size = 1; field.result = .BYTE
        case "s8": size = 1; field.result = .INT
        case "u16","s16": size = 2; field.result = .INT
        case "u32","s32": size = 4; field.result = .INT
        case "u64","s64": size = 8; field.result = .INT

        case "f32": size = 4; field.result = .FLOAT
        case "f64": size = 8; field.result = .FLOAT
        case "ptr": size = c.ptr_size; field.result = .PTR

        case:
            other, ok := c.layouts[type_name]
            if !ok {
                bad_node(c, field.node, "undeclared layout `%s`", type_name)
                return false
            }

            field.result = .PTR
            field.layout = other
            if field.embed || field.use {
                // of course you need to recurse for this!
                if !resolve_layout(c, other) {
                    return false
                }
                size = other.size
            } else {
                size = c.ptr_size
            }
        }

        field.size = size
        if !field.overlay {
            counter += group_size
            group_offset = counter
            group_size = size
        } else {
            group_size = max(group_size, size)
        }
        field.offset = group_offset
    }

    // promote 'using` fields
    for ast_field in layout.node.fields {
        field_node := node_cast(Layout_Field, ast_field)
        assert(field_node != nil)
        field := layout.fields[field_node.name]
        if !field.use {
            continue
        }

        if field.layout == nil {
            bad_node(c, field.node, "field of type `%s` has no fields to promote!", 
                field.node.type, 
            )
            return false
        }

        assert(field.layout.done)
        for name, child in field.layout.fields {
            if _, exists := layout.fields[name]; exists {
                bad_node(c, field.node, "promoted field `%s` in `%s` already exists", 
                    name, field.layout.node.name
                )
                return false
            }
            promoted := new(Field_Info, c.allocator)
            promoted^ = child^
            promoted.offset = field.offset + child.offset
            layout.fields[name] = promoted
        }
    }

    // NO PADDING!!! IMAGINE LYING TO THE PROGRAMMER
    // if you want padding do ts manually
    layout.size = counter + group_size
    layout.done = true
    return true
}

infer_node :: proc(c: ^Checker, node: ^Node(Wrapped)) -> Operand {
    if node.mode == .INVALID {
        return operand_of(node, .INVALID) 
    }
    if layout := node_cast(Layout, node); layout != nil {
        for field in layout.fields {
            infer_node(c, field)
        }
        return operand_of(layout, .NO_VALUE) 
    }
    if field := node_cast(Layout_Field, node); field != nil {
        return operand_of(field, .NO_VALUE) 
    }
    if push := node_cast(Push, node); push != nil {
        return operand_of(push, push.mode) 
    }
    if sizeof := node_cast(Size_Of, node); sizeof != nil {
        return operand_of(sizeof, sizeof.mode) 
    }
    if list := node_cast(Arg_List, node); list != nil {
        return operand_of(list, .NO_VALUE)
    }

    if func := node_cast(Function, node); func != nil {
        if func.scope == nil {
            func.scope = c.scope
        }

        // I forget I allow any expr in function parameters
        // because it is convenient for writing the parser and allowing default args xD
        for param in func.params {
            valid := false 
            if leaf := node_cast(Leaf, param); leaf != nil {
                valid = leaf.token.kind == .IDENT
            } else if bin_expr := node_cast(Bin_Expr, param); bin_expr != nil {
                if bin_expr.kind == .ASSIGN {
                    if leaf := node_cast(Leaf, bin_expr.left); leaf != nil {
                        valid = leaf.token.kind == .IDENT
                    }
                }
            }

            if !valid {
                bad_node(c, param, "expected either an identifier or default arg assignment")
                return operand_of(func, .INVALID)
            }
        }

        return operand_of(func, .TEMPLATE, func)
    }

    if leaf := node_cast(Leaf, node); leaf != nil {
        if leaf.mode == .NO_VALUE {
            return operand_of(leaf, .NO_VALUE)
        }
        if leaf.token.kind == .IDENT {
            entity := lookup(c.scope, leaf)
            if entity == nil {
                bad_node(c, leaf, "undeclared identifier `%s`", leaf.token.text)
                return operand_of(leaf, .INVALID) 
            }

            if entity.mode == .TEMPLATE {
                leaf.constraints = {} // no longer produces value
                return operand_of(leaf, .TEMPLATE, entity.template)
            }

            // allow facts to propagate to the declaration as well
            common := leaf.constraints & entity.constraints & entity.decl.constraints
            if common != leaf.constraints   || 
               common != entity.constraints ||
               common != entity.decl.constraints {
                c.changed = true
            }
            leaf.constraints = common
            entity.constraints = common
            entity.decl.constraints = common
            if is_forward(entity.decl) {
                leaf.mode = .CONST
            } else {
                leaf.mode = .LVALUE
            }
            set_layout(c, leaf, entity.layout)
            //NOTE: not checking for contradiction here is VERY DELIBERATE
            // because an ident can resolve to a `def` template (like from `forward`)
            // which doesn't produce value and has no type
        }
        return operand_of(leaf, leaf.mode)
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        // SPECIAL CASES!!
        if bin_expr.kind == .CAST {
            lhs := infer_node(c, bin_expr.left)
            if lhs.mode == .INVALID {
                return operand_of(bin_expr, .INVALID) 
            }
            // reject casts the code generator cannot do!
            if card(lhs.constraints) == 1 {
                switch {
                case .BOOL in lhs.constraints && .PTR in bin_expr.constraints:
                    bad_node(c, bin_expr, "why are u trying to cast `bool` to `ptr`")
                    return operand_of(bin_expr, .INVALID)
                case .BYTE in lhs.constraints && .PTR in bin_expr.constraints:
                    bad_node(c, bin_expr, "why are u trying to cast `byte` to `ptr`")
                    return operand_of(bin_expr, .INVALID)
                case .FLOAT in lhs.constraints && .PTR in bin_expr.constraints:
                    bad_node(c, bin_expr, "imagine directly casting casting `float` to `ptr`")
                    return operand_of(bin_expr, .INVALID)
                case .PTR in lhs.constraints && .BYTE in bin_expr.constraints:
                    bad_node(c, bin_expr, "cannot cast `ptr` to `byte`. Just truncate it manually.")
                    return operand_of(bin_expr, .INVALID)
                case .PTR in lhs.constraints && .FLOAT in bin_expr.constraints:
                    bad_node(c, bin_expr, 
                        "im genuinely curious what use there is to casting `ptr` -> `float`"
                    )
                    return operand_of(bin_expr, .INVALID)
                }
            }

            return operand_of(bin_expr, .RVALUE)
        }
        if is_assign_op(bin_expr.kind) != .INVALID {
            return lvalue_check_and_assign(c, bin_expr)
        }
        if bin_expr.kind == .CALL {
            operand := instantiate(c, bin_expr)
            if operand.mode == .INVALID {
                bad_node(c, bin_expr, "while trying to instantiate from call")
            }
            return operand
        }
        if bin_expr.kind == .DEREFERENCE {
            return lvalue_check_and_dereference(c, bin_expr)
        }
        if bin_expr.kind == .SUBSCRIPT {
            bad_node(c, bin_expr, "subscripting is todo! sorry!")
            return operand_of(bin_expr, .INVALID)
        }

        lhs := infer_node(c, bin_expr.left)
        if lhs.mode == .INVALID {
            return operand_of(bin_expr, .INVALID) 
        }
        rhs := infer_node(c, bin_expr.right)
        if rhs.mode == .INVALID {
            return operand_of(bin_expr, .INVALID) 
        }
        if len(RULES[bin_expr.kind]) != 0 {
            if infer(bin_expr) {
                c.changed = true 
            }
        }
        if card(bin_expr.constraints) == 0 {
            bad_node(c, node, "type of expression is a contradiction")
            return operand_of(bin_expr, .INVALID) 
        }
        return operand_of(bin_expr, .RVALUE)
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        unary_operand := infer_node(c, unary_expr.operand)
        if unary_operand.mode == .INVALID {
            return operand_of(unary_expr, .INVALID) 
        }
        // special: addr-of
        if unary_expr.kind == .ADDRESS_OF {
            if unary_operand.mode != .LVALUE {
                bad_node(c, node, "expected an lvalue when taking memory address")
                return operand_of(unary_expr, .INVALID)
            }
            unary_expr.constraints = Ptr
            return operand_of(unary_expr, .RVALUE)
        }

        if len(RULES[unary_expr.kind]) != 0 {
            if infer(unary_expr) {
                c.changed = true
            }
        }
        if card(unary_expr.constraints) == 0 {
            bad_node(c, node, "type of expression is a contradiction")
            return operand_of(unary_expr, .INVALID) 
        }
        return operand_of(unary_expr, .RVALUE)
    }

    // NOTE: empty blocks are rejected by the parser
    // only way its possible is in case of empty file, which is handled!!
    if block := node_cast(Block, node); block != nil {
        old_scope := c.scope
        if block.scope == nil {
            push_scope(c)
            block.scope = c.scope

            for stmnt in block.code {
                if decl := node_cast(Decl, stmnt); decl != nil {
                    if !decl.forward {
                        continue
                    }

                    if decl.rhs == nil {
                        bad_node(c, decl, "forward declaration must have initializer!")
                        return operand_of(block, .INVALID)
                    } else {
                        decl.constraints = decl.rhs.constraints
                    }
                    entity := new(Entity, c.allocator)
                    // the idea of a `const var` kind of pisses me off because its an oxymoron
                    entity.constraints = decl.constraints
                    entity.decl = wrap_node(decl)
                    if exists := declare(c.scope, decl.name.text, entity); exists != nil {
                        bad_node(c, decl, "this is a redeclaration")
                        bad_node(c, exists.decl, "original is here")
                        c.error_count -= 1
                        return operand_of(block, .INVALID)
                    }
                }
            }
        }

        c.scope = block.scope
        result: Operand
        for stmnt in block.code {
            result = infer_node(c, stmnt)
            if result.mode == .INVALID {
                // go calm w/ the error messages mkay
                c.scope = old_scope
                return operand_of(block, .INVALID)
            }
        }
        c.scope = old_scope

        common := block.constraints & result.constraints
        if common != block.constraints || common != result.constraints {
            c.changed = true
        }
        block.constraints = common
        if result.expr != nil {
            result.expr.constraints = common
        }
        operand := operand_of(block, .NO_VALUE)
        if result.mode == .RVALUE || result.mode == .LVALUE || result.mode == .CONST {
            block.mode = .RVALUE 
            operand.mode = .RVALUE
            operand.expr = result.expr
            set_layout(c, block, result.layout)
            operand.layout = result.layout
        } else if result.mode == .TEMPLATE {
            // in case block "evaluates" to a function
            // this is pure polish BTW
            block.mode = .TEMPLATE 
            operand.mode = .TEMPLATE 
            operand.template = result.template
        }
        return operand
    }

    if decl := node_cast(Decl, node); decl != nil {
        rhs_operand: Operand
        if decl.rhs != nil {
            rhs_operand = infer_node(c, decl.rhs)
            if rhs_operand.mode == .INVALID {
                warn(c, "declaration of `%s` failed!", decl.name.text)
                return operand_of(decl, .INVALID)
            }
        }
        if rhs_operand.mode == .NO_VALUE {
            bad_node(c, decl, "expression in declaration produces no value or function..")
            return operand_of(decl, .INVALID)
        }

        entity := local(c.scope, decl.name.text)
        if decl.forward {
            assert(entity != nil)
            assert(entity.decl == wrap_node(decl))
        } else if entity == nil {
            entity = new(Entity, c.allocator)
            entity.constraints = decl.constraints
            entity.decl = wrap_node(decl)
            declare(c.scope, decl.name.text, entity)
        } else if wrap_node(decl) != entity.decl {
            bad_node(c, decl, "this is a redeclaration")
            bad_node(c, entity.decl, "original is here")
            c.error_count -= 1
            return operand_of(decl, .INVALID)
        }

        if decl.rhs == nil {
            return operand_of(decl, .NO_VALUE)
        }

        if rhs_operand.mode == .TEMPLATE {
            if entity.mode != .TEMPLATE || entity.template != rhs_operand.template {
                c.changed = true
            }

            entity.mode = .TEMPLATE
            entity.template = rhs_operand.template 
            if decl.constraints != {} {
                c.changed = true
            }
            decl.constraints = {}
            entity.constraints = {}
            return operand_of(decl, .NO_VALUE)
        }

        common := decl.constraints & decl.rhs.constraints & entity.constraints
        if common != decl.constraints     || 
           common != decl.rhs.constraints || 
           common != entity.constraints {
            c.changed = true
        }
        decl.constraints = common
        decl.rhs.constraints = common
        entity.constraints = common
        if entity.layout != rhs_operand.layout {
            entity.layout = rhs_operand.layout
            c.changed = true
        }
        return operand_of(decl, .NO_VALUE) 
    }

    if ret := node_cast(Return, node); ret != nil {
        if c.current == nil {
            bad_node(c, ret, "return outside function")
            return operand_of(ret, .INVALID)
        }

        if ret.result == nil {
            common := c.current.constraints & None
            if common != c.current.constraints {
                c.changed = true
            }
            c.current.constraints = common
            return operand_of(ret, .NO_VALUE)
        }

        operand := infer_node(c, ret.result)
        if !produces_value(operand.mode) {
            bad_node(c, ret, "return does not produce value!")
            return operand_of(ret, .INVALID)
        }

        common := c.current.constraints & operand.constraints
        if common != c.current.constraints ||
           common != operand.constraints {
            c.changed = true
        }
        c.current.constraints = common
        operand.expr.constraints = common

        if c.current.instance.layout == nil {
            set_layout(c, c.current.instance, operand.layout)
        } else if c.current.instance.layout != operand.layout {
            bad_node(c, ret, "layout return value cannot change")
            return operand_of(ret, .INVALID)
        }

        return operand_of(ret, .NO_VALUE)
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
        cond := infer_node(c, if_else.cond)
        if cond.mode == .INVALID {
            return operand_of(if_else, .INVALID)
        }
        if !produces_value(cond.mode) {
            bad_node(c, if_else, "condition does not produce value!")
            return operand_of(if_else, .INVALID)
        }
        common := cond.constraints & Bool
        if common == {} {
            bad_node(c, if_else.cond, "condition must be a boolean")
            return operand_of(if_else, .INVALID)
        }
        if common != if_else.cond.constraints {
            c.changed = true
        }
        if_else.cond.constraints = common

        if_operand := infer_node(c, if_else.if_body)
        if if_operand.mode == .INVALID {
            return operand_of(if_else, .INVALID)
        }
        // if without else produces no value
        if if_else.else_body == nil { 
            return operand_of(if_else, .NO_VALUE)
        }
        else_operand  := infer_node(c, if_else.else_body)
        if else_operand.mode == .INVALID {
            return operand_of(if_else, .INVALID)
        }

        if !produces_value(if_operand.mode) || !produces_value(else_operand.mode) {
            return operand_of(if_else, .NO_VALUE)
        }
        common = if_operand.constraints   & 
                 else_operand.constraints & 
                 if_else.constraints
        if common != if_operand.constraints   ||
           common != else_operand.constraints || 
           common != if_else.constraints {
            c.changed = true
        }
        if_else.if_body.constraints = common
        if_else.else_body.constraints = common
        if_else.constraints = common

        // if both if and else bodies exist, and theyre the same type
        // then `if .. do .. else ..` can return value
        if card(common) == 0 {
            bad_node(c, if_else, "branch types are not the same")
            return operand_of(if_else, .INVALID)
        }
        if if_operand.layout == else_operand.layout {
            set_layout(c, if_else, if_operand.layout)
        } else {
            set_layout(c, if_else, nil)
        }
        return operand_of(if_else, .RVALUE)
    }

    if while := node_cast(While, node); while != nil {
        cond := infer_node(c, while.cond)
        if cond.mode == .INVALID {
            return operand_of(while, .INVALID)
        }
        if !produces_value(cond.mode) {
            bad_node(c, while, "condition does not produce value!")
            return operand_of(while, .INVALID)
        }
        common := cond.constraints & Bool
        if common == {} {
            bad_node(c, while.cond, "condition must be a boolean")
            return operand_of(while, .INVALID)
        }
        if common != while.cond.constraints {
            c.changed = true
        }
        while.cond.constraints = common

        // I swear bro, the `Return_Stack` is peak coding
        depth := &c.loop_depth
        if c.current != nil {
            depth = &c.current.loop_depth
        }
        depth^ += 1
        defer depth^ -= 1

        operand := infer_node(c, while.body)
        if operand.mode == .INVALID {
            return operand_of(while, .INVALID)
        }
        // loops don't return values, im not dealing with this halting problem bullsh**
        return operand_of(while, .NO_VALUE)
    }

    if brk := node_cast(Break, node); brk != nil {
        depth := c.loop_depth
        if c.current != nil {
            depth = c.current.loop_depth
        }
        if depth == 0 {
            bad_node(c, brk, "`break` outside loop")
            return operand_of(brk, .INVALID)
        }
        return operand_of(brk, .NO_VALUE)
    }

    if cont := node_cast(Continue, node); cont != nil {
        depth := c.loop_depth
        if c.current != nil {
            depth = c.current.loop_depth
        }
        if depth == 0 {
            bad_node(c, cont, "`continue` outside loop")
            return operand_of(cont, .INVALID)
        }
        return operand_of(cont, .NO_VALUE)
    }
    
    fmt.println(node.kind)
    assert(false, "unmatched node kind in `check_node`")
    return {}
}

lvalue_check_and_assign :: proc(c: ^Checker, assign: ^Node(Bin_Expr)) -> Operand {
    lhs := infer_node(c, assign.left)
    if lhs.mode == .INVALID {
        return operand_of(assign, .INVALID) 
    }
    if lhs.mode == .CONST {
        bad_node(c, assign.left, "cannot assign to constant (or symbols declared via `forward`)")
        return operand_of(assign, .INVALID) 
    }
    if lhs.mode != .LVALUE {
        bad_node(c, assign.left, "this is not a valid lvalue in assignment")
        return operand_of(assign, .INVALID) 
    }
    rhs := infer_node(c, assign.right)
    if rhs.mode == .INVALID {
        return operand_of(assign, .INVALID) 
    }

    if assign.kind == .ASSIGN {
        common := lhs.constraints & rhs.constraints & assign.constraints
        if common != lhs.constraints ||
           common != rhs.constraints ||
           common != assign.constraints {
            c.changed = true
        }
        lhs.expr.constraints = common
        rhs.expr.constraints = common
        assign.constraints = common
    } else {
        // result must be storable back into lhs
        common := lhs.constraints & assign.constraints
        if common != lhs.constraints || common != assign.constraints {
            c.changed = true
        }
        lhs.expr.constraints = common
        assign.constraints = common
        if infer_bin_as(assign, is_assign_op(assign.kind)) {
            c.changed = true
        }
    }
    if card(assign.constraints) == 0 {
        bad_node(c, assign, "invalid types for assignment")
        return operand_of(assign, .INVALID)
    }
    // keep it simple, don't overwrite layout
    return operand_of(assign, .RVALUE)
}

lvalue_check_and_dereference :: proc(c: ^Checker, deref: ^Node(Bin_Expr)) -> Operand {
    lhs := infer_node(c, deref.left)
    if lhs.mode == .INVALID {
        return operand_of(deref, .INVALID) 
    }
    if !produces_value(lhs.mode) {
        bad_node(c, deref.left, "expected a pointer value")
        return operand_of(deref, .INVALID) 
    }

    common := lhs.constraints & Ptr
    if common == {} {
        bad_node(c, deref.left, "can only dereference `ptr` types")
        return operand_of(deref, .INVALID)
    }
    if deref.left.constraints != common {
        c.changed = true
        deref.left.constraints = common
    }
    right := node_cast(Leaf, deref.right)
    assert(right != nil)
    right.mode = .NO_VALUE

    name := right.token.text
    result: Type
    builtin := true // HACK: allow "s64" and friends to go thru
    switch name {
    case "u8": 
        result = .BYTE
    case "s8",
         "u16","s16",
         "u32","s32",
         "u64","s64":
        result = .INT
    case "f32","f64": 
        result = .FLOAT
    case "ptr":
        result = .PTR
    case:
        builtin = false
    }

    if builtin {
        expect := Unknown {result}
        common := deref.constraints & expect
        if common == {} {
            bad_node(c, deref.right, "result of dereference is contradiction")
            return operand_of(deref, .INVALID)
        }
        if common != deref.constraints {
            c.changed = true
        }
        deref.constraints = common
        return operand_of(deref, .LVALUE)
    }

    if lhs.layout == nil {
        bad_node(c, deref.left, "pointer has no layout assigned to it for dereference!")
        return operand_of(deref, .INVALID)
    }
    field, ok := lhs.layout.fields[name]
    if !ok {
        bad_node(c, deref.right, "field does not exist in layout `%s`", lhs.layout.node.name)
        return operand_of(deref, .INVALID)
    }

    expect := Unknown {field.result}
    common = deref.constraints & expect
    if common == {} {
        bad_node(c, deref.right, "result of dereference is contradiction")
        return operand_of(deref, .INVALID)
    }
    if common != deref.constraints {
        c.changed = true
    }
    deref.constraints = common
    set_layout(c, deref, field.layout)
    if field.embed || field.use {
        return operand_of(deref, .RVALUE) // weird as crap, but yes this is like addr-of
    }
    return operand_of(deref, .LVALUE)
}

// difference between `check_node` and `infer_node`...
// is that `check_node` repeatedly bashes it's head into the wall
check_node :: proc(c: ^Checker, node: ^Node(Wrapped)) -> Operand {
    operand: Operand
    for {
        c.changed = false
        operand = infer_node(c, node)
        c.passes += 1
        if !c.changed {
            break
        }
    }
    return operand
}

finalize :: proc(c: ^Checker, root: ^Node(Wrapped)) {
    visit :: proc(node: ^Node(Wrapped), data: rawptr) {
        c := cast(^Checker) data
        // resolve hashes of recursive calls that were set to the same instance
        if node.instance != nil && node.instance_hash == "" {
            hash,ok := get_instance_hash(c, node.instance, node.template_id)
            if !ok {
                bad_node(c, node, "cannot resolve function instantiation")
                if card(node.instance.constraints) > 1 {
                    warn(c, "cannot resolve type between %s",
                        node_annotation_string(node.constraints, node.mode, c.allocator)
                    )
                }
                return
            }
            node.instance_hash = hash
        }

        // `INVALID`s must be handled and the program exited before `finalize`
        // also `generic=true` means unknown is allowed, this is why annotation has `instance`
        if node.mode == .INVALID || node.mode == .TEMPLATE || node.generic {
            return
        }
        n := card(node.constraints) 
        if node.mode != .NO_VALUE {
            if n > 1 {
                bad_node(c, node, "cannot resolve type between %s", 
                    node_annotation_string(node.constraints, node.mode, c.allocator)
                )
            } else if n == 0 {
                bad_node(c, node, "expression has no valid type")
            }
        }
    }

    root := node_cast(Block, root)
    assert(root != nil)
    // DO NOT print the entire toplevel for *every error*
    for node in root.code {
        // go pre-order so messages are not in weird order
        pre_order_walk(node, cast(rawptr) c, visit) 
    }
    for hash,instance in c.instances {
        when ODIN_DEBUG {
            fmt.printf("generated %s\n", hash)
        }
        pre_order_walk(wrap_node(instance), cast(rawptr) c, visit) 
    }
    when ODIN_DEBUG do fmt.println()
}
