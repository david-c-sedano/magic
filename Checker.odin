
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
}

Checker :: struct {
    using g: ^lex.Godlex,
    scope: ^Scope,
    mode: Addressing_Mode,
    current: ^Return_Stack,
    changed: bool,
    passes: int,

    instances: map[Instance_Hash]^Node(Function),
    template_ids: map[^Node(Function)]int,
    current_instance_id: int,
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

init_checker :: proc(c: ^Checker, g: ^lex.Godlex) {
    c.g = g
    c.instances = make(map[Instance_Hash]^Node(Function), c.allocator)
    c.template_ids = make(map[^Node(Function)]int, c.allocator)
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

global :: proc(scope: ^Scope) -> ^Scope {
    it := scope
    for it != nil {
        if it.parent == nil {
            break
        }
        it = it.parent
    }
    return it
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

operand_of :: proc(node: ^Node($T), mode: Addressing_Mode, template: ^Node(Function) = nil) -> Operand {
    node.mode = mode
    operand: Operand
    operand.expr = wrap_node(node)
    operand.constraints = node.constraints
    operand.mode = mode
    operand.template = template
    return operand
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
            if operand.mode == .NO_VALUE || operand.mode == .TEMPLATE {
                bad_node(c, arg, "recursive argument does not produce a value")
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
        callee = c.scope
        c.scope = global(c.scope)
        caller = new(Scope, c.allocator) 
        caller.symbols = make(map[string]^Entity, c.allocator)
        caller.parent = lhs.template.scope
        call.scope = caller
        c.scope = callee // restore for now
    } else {
        callee = c.scope
        caller = call.scope
    }

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
            if instantiate_parameter(c, param.token.text, caller, 
                wrap_node(param),arg
            ) == nil {
                return operand_of(call, .INVALID)
            }
            continue
        }
        // argument NOT supplied by caller, try default
        if default := node_cast(Bin_Expr, node); default != nil {
            if param := node_cast(Leaf, default.left); param != nil {
                assert(default.kind == .ASSIGN)
                assert(param.token.kind == .IDENT)

                operand: Operand
                decl: ^Node(Wrapped)
                if arg == nil {
                    c.scope = caller
                    operand = infer_node(c, default.right)
                    c.scope = callee

                    if operand.mode == .INVALID {
                        warn(c, "only global/const identifiers allowed in default args")
                        return operand_of(call, .INVALID)
                    }
                    if instantiate_parameter(c, param.token.text, caller,
                        wrap_node(default),default.right
                    ) == nil {
                        return operand_of(call, .INVALID)
                    }
                } else {
                    operand := infer_node(c, arg)

                    if operand.mode == .INVALID {
                        return operand_of(call, .INVALID)
                    }
                    if instantiate_parameter(c, param.token.text, caller,
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

    c.scope = caller
    outer := c.changed
    body := false
    for {
        c.changed = false
        operand := infer_node(c, wrap_node(call.instance.body))
        if operand.mode == .INVALID {
            bad_node(c, lhs.template, "failed to instantiate this")
            c.error_count -= 1 // count only 1 as error
            c.scope = callee
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

    if call.constraints == {} {
        bad_node(c, lhs.template, "instantiation of this cannot produce a valid type")
        c.error_count -= 1 // only 1
        c.scope = callee
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
    // I wanna say the copy is redundant
    // but not really, it's genuinely needed to do the whole inference shebang
    // on an instance that may not match anything that has been generated
    // as a penance though, `call.instance` will refer to the redundant copy
    call.instance_hash = hash
    c.scope = callee
    return operand_of(call, .RVALUE)
}

instantiate_parameter :: proc(
    c: ^Checker, 
    name: string,
    caller: ^Scope,
    param,arg: ^Node(Wrapped)
) -> ^Entity {
    if arg.mode == .NO_VALUE || arg.mode == .TEMPLATE {
        bad_node(c, arg, "argument for parameter `%s` does not produce a value!", name)
        return nil
    }

    entity := local(caller, name)
    if entity == nil {
        entity = new(Entity,c.allocator)
        entity.constraints = arg.constraints
        entity.decl = wrap_node(param)
        declare(caller, name, entity)
    } else if entity.decl != param {
        bad_node(c, param, "duplicate parameter `%s`", name)
        return nil
    }

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
    fmt.sbprintf(&b, "func_%d_", id)

    put_type_byte :: proc(b: ^strings.Builder, constraints: Unknown) -> bool {
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
            strings.write_string(b, "p") // p for "ptr"
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
        if !put_type_byte(&b, param.constraints) {
            return "", false
        }
    }
    // return type
    strings.write_string(&b, "__")
    if !put_type_byte(&b, func.constraints) {
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

seed :: proc(c: ^Checker, root: ^Node(Wrapped)) {

    assign_starting_constraints :: proc(node: ^Node(Wrapped), data: rawptr) {
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
                    bad_node(c, node, "type in cast does not exist")
                }
                type.mode = .NO_VALUE
                return
            }
        }

        if push := node_cast(Push, node); push != nil {
            push.constraints = Ptr
            push.mode = .RVALUE
            return
        }
        if list := node_cast(Arg_List, node); list != nil {
            // do not assign `Any`
            list.mode = .NO_VALUE
            return
        }
        if func := node_cast(Function, node); func != nil {
            // handled in `mark_generics`
            return
        }

        node.constraints = Any
    }

    mark_generics :: proc(node: ^Node(Wrapped), data: rawptr) {
        c := cast(^Checker) data
        insane_nested_visitor :: proc(node: ^Node(Wrapped), data: rawptr) {
            node.generic = true
        }
        if func := node_cast(Function, node); func != nil {
            pre_order_walk(node, nil, insane_nested_visitor)
            func.mode = .TEMPLATE
        }
    }

    post_order_walk(root, cast(rawptr) c, assign_starting_constraints)
    pre_order_walk(root, cast(rawptr) c, mark_generics)
}

infer_node :: proc(c: ^Checker, node: ^Node(Wrapped)) -> Operand {
    if node.mode == .INVALID {
        return operand_of(node, .INVALID) 
    }
    if push := node_cast(Push, node); push != nil {
        // already taken care of in `seed`
        return operand_of(node, push.mode) 
    }
    if layout := node_cast(Layout, node); layout != nil {
        // already taken care of in `seed` (this is todo actually)
        return operand_of(node, .NO_VALUE) 
    }
    if field := node_cast(Layout_Field, node); field != nil {
        // This should be unreachable, actually
        return operand_of(node, .NO_VALUE) 
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
    if list := node_cast(Arg_List, node); list != nil {
        // taken care of by CALL binary expr case
        // I think this is unreachable as well, w/e man
        return operand_of(list, .NO_VALUE)
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
            //NOTE: not checking for contradiction here is VERY DELIBERATE
            // because an ident can resolve to a `fu` template (like from `forward`)
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
            return operand_of(bin_expr, .RVALUE)
        }
        if is_assign_op(bin_expr.kind) != .INVALID {
            return take_care_of_assignment(c, bin_expr)
        }
        if bin_expr.kind == .CALL {
            operand := instantiate(c, bin_expr)
            if operand.mode == .INVALID {
                bad_node(c, bin_expr, "while trying to instantiate from call")
            }
            return operand
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
                        decl.constraints = Any
                    } else {
                        decl.constraints = decl.rhs.constraints
                    }
                    entity := new(Entity, c.allocator)
                    // the idea of a `const var` kind of pisses me off because its an oxymoron
                    entity.constraints = decl.constraints
                    entity.decl = wrap_node(decl)
                    if exists := declare(c.scope, decl.name.text, entity); exists != nil {
                        bad_node(c, node, "this is a redeclaration")
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
                block.mode = .INVALID
                // dont return yet! it's prolly better to accumulate errors 
            }
        }
        c.scope = old_scope
        if block.mode  == .INVALID {
            return operand_of(block, .INVALID)
        }

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
            // infer node first then declare
            // keep in mind smthn like `forward one = one + one` is allowed
            // because the `one` is already declared before being checked here
            // which is literally the entire point of `forward`
            rhs_operand = infer_node(c, decl.rhs)
            if rhs_operand.mode == .INVALID {
                warn(c, "declaration of `%s` failed!", decl.name.text)
                return operand_of(decl, .INVALID)
            }
        }
        if rhs_operand.mode == .NO_VALUE {
            bad_node(c, decl, "expression in declaration produces no value")
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
        if operand.mode == .NO_VALUE || operand.mode == .TEMPLATE {
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
        return operand_of(ret, .NO_VALUE)
    }

    if if_else := node_cast(If_Else, node); if_else != nil {
    //TODO 
    }
    if while := node_cast(While, node); while != nil {
    //TODO
    }
    if brk := node_cast(Break, node); brk != nil {
    //TODO
    }
    if cont := node_cast(Continue, node); cont != nil {
    //TODO
    }
    
    fmt.println(node.kind)
    assert(false, "unmatched node kind in `check_node`")
    return {}
}

take_care_of_assignment :: proc(c: ^Checker, expr: ^Node(Bin_Expr)) -> Operand {
    lhs := infer_node(c, expr.left)
    if lhs.mode == .INVALID {
        return operand_of(expr, .INVALID) 
    }
    if lhs.mode == .CONST {
        bad_node(c, expr.left, "cannot assign to constant (or symbols declared via `forward`)")
        return operand_of(expr, .INVALID) 
    }
    if lhs.mode != .LVALUE {
        bad_node(c, expr.left, "this is not a valid lvalue in assignment")
        return operand_of(expr, .INVALID) 
    }
    rhs := infer_node(c, expr.right)
    if rhs.mode == .INVALID {
        return operand_of(expr, .INVALID) 
    }

    if expr.kind == .ASSIGN {
        common := lhs.constraints & rhs.constraints & expr.constraints
        if common != lhs.constraints ||
           common != rhs.constraints ||
           common != expr.constraints {
            c.changed = true
        }
        lhs.expr.constraints = common
        rhs.expr.constraints = common
        expr.constraints = common
    } else {
        // result must be storable back into lhs
        common := lhs.constraints & expr.constraints
        if common != lhs.constraints || common != expr.constraints {
            c.changed = true
        }
        lhs.expr.constraints = common
        expr.constraints = common
        if infer_bin_as(expr, is_assign_op(expr.kind)) {
            c.changed = true
        }
    }
    if card(expr.constraints) == 0 {
        bad_node(c, expr, "invalid types for assignment")
        return operand_of(expr, .INVALID)
    }
    return operand_of(expr, .RVALUE)
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
        // resolve recursing hashes
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

        // `INVALID`s must be handled and the program exited before `mark_unknown_types`
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
