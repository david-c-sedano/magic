
package magic

import lex "Godlex"
import "core:fmt"

Addressing_Mode :: enum {
    UNKNOWN,
    INVALID,
    NO_VALUE,
    RVALUE,
    LVALUE, // addressable, assignable
    CONST,  // addressable, NOT assignable
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
    changed: bool,
    passes: int,
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

Any : Unknown : { .NONE, .BOOL, .BYTE, .INT, .FLOAT, .PTR } 

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
// NOTE: YES I AM AWARE THIS `RULES` DOES NOT MATCH THE SPEC AT ALL
// calm down! this is just for testing I don't really want to write out all these type cases rn
// Honestly I kind of am in favor of disallowing promotion into float anyways, we will see 

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
    c.scope.symbols = make(map[string]^Entity, c.allocator)
    c.scope.parent = parent 
}

// is shadowing REALLY that simple??
lookup :: proc(scope: ^Scope, ident: ^Node(Leaf)) -> ^Entity {
    assert(ident.token.kind == .IDENT)
    it := scope
    for it != nil {
        if entity, ok := it.symbols[ident.token.text]; ok {
            // imagine needing to special case this
            // because forward declarations fall into place too well
            if entity.decl.forward || entity.decl.span[0] < ident.span[0] {
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

global :: proc(scope: ^Scope, name: string) -> ^Entity {
    it := scope
    for it != nil {
        if it.parent == nil {
            break
        }
        it = it.parent
    }
    if entity, ok := it.symbols[name]; ok {
        return entity
    }
    return nil
}

declare :: proc(scope: ^Scope, name: string, entity: ^Entity) -> ^Entity {
    if entity, exists := scope.symbols[name]; exists {
        return entity
    }
    scope.symbols[name] = entity
    return nil
}

operand_of :: proc(node: ^Node($T), mode: Addressing_Mode) -> Operand {
    node.mode = mode
    operand: Operand
    operand.expr = wrap_node(node)
    operand.constraints = node.constraints
    operand.mode = mode
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

// I dont think it's needed to check `lex.has_error` schizophrenically 
// just keep going and accumulate errors
bad_node :: proc(c: ^Checker, node: ^Node($T), errmsg: string, format: ..any) {
    lex.error(c.g, node.span, errmsg, ..format);
}

warn :: proc(c: ^Checker, errmsg: string, format: ..any) {
    lex.warning(c.g, errmsg, ..format)
}

seed :: proc(c: ^Checker, root: ^Link) {
    // literal-value default types, layout info and casts
    // and layout info for functions and `push` 
    assign_starting_constraints :: proc(node: ^Link, data: rawptr) {
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
            // I wonder if I should just make any identifier leaf .LVALUE actually
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
                    //TODO: check into layout table and set constraints to `.PTR` 
                    // as well as layout info accordingly
                    bad_node(c, node, "unknown type you are trying to cast to")
                }
                type.mode = .NO_VALUE
                return
            }
        }

        if push := node_cast(Push, node); push != nil {
            //TODO: assign layout to stack allocation
            push.constraints += { .PTR }
            push.mode = .RVALUE
            return
        }

        if func := node_cast(Function, node); func != nil {
            //TODO: assign `callable` property of layout 
            func.constraints += { .PTR }
            func.mode = .RVALUE
            return
        }

        node.constraints = Any
    }

    collect_forwards :: proc(node: ^Link, data: rawptr) {
        c := cast(^Checker) data
        decl := node_cast(Decl, node)
        if decl == nil || !decl.forward {
            return
        }

        if decl.rhs == nil {
            decl.constraints = Any
        } else {
            decl.constraints = decl.rhs.constraints
        }
        entity := new(Entity, c.allocator)
        // the idea of a `const var` kind of pisses me off because its an oxymoron
        // but even in the case of functions, its still a variable that evalutes to a function
        entity.kind = .VARIABLE
        entity.scope = c.scope
        entity.constraints = decl.constraints
        entity.decl = decl
        if exists := declare(c.scope, decl.name.text, entity); exists != nil {
            bad_node(c, node, "this is a redeclaration")
            bad_node(c, exists.decl, "original is here")
            c.error_count -= 1 // just count it as 1 man
        }
    }

    assert(root.kind == .BLOCK)
    root.scope = c.scope
    post_order_walk(root, cast(rawptr) c, assign_starting_constraints)
    pre_order_walk(root, cast(rawptr) c, collect_forwards)
}

infer_node :: proc(c: ^Checker, node: ^Link) -> Operand {
    if node.mode == .INVALID {
        return operand_of(node, .INVALID) 
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
            if entity.decl.forward {
                leaf.mode = .CONST
            } else {
                leaf.mode = .LVALUE
            }
        }
        return operand_of(leaf, leaf.mode)
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        if is_assign_op(bin_expr.kind) != .INVALID {
            return take_care_of_assignment(c, bin_expr)
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
            // TODO: improve this errmsg
            bad_node(c, node, "type of expression is a contradiction")
            return operand_of(bin_expr, .INVALID) 
        }
        return operand_of(bin_expr, .RVALUE) //TODO: Will have to check `lhs` for subscript
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        unary_operand := infer_node(c, unary_expr.operand)
        if unary_operand.mode == .INVALID {
            return operand_of(unary_expr, .INVALID) 
        }
        if len(RULES[unary_expr.kind]) != 0 {
            if infer(unary_expr) {
                c.changed = true
            }
        }
        if card(unary_expr.constraints) == 0 {
            //TODO: improve this errmsg
            bad_node(c, node, "type of expression is a contradiction")
            return operand_of(unary_expr, .INVALID) 
        }
        return operand_of(unary_expr, .RVALUE) //TODO: Will have to check for addr-of 
    }

    // NOTE: empty blocks are rejected by the parser
    // only way its possible is in case of empty file, which is handled!!
    if block := node_cast(Block, node); block != nil {
        old_scope := c.scope
        if block.scope == nil {
            push_scope(c)
            block.scope = c.scope
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
        return operand_of(block, result.mode == .NO_VALUE ? .NO_VALUE : .RVALUE)
    }

    if decl := node_cast(Decl, node); decl != nil {
        if decl.rhs != nil {
            // infer node first then declare
            // keep in mind smthn like `forward one = one + one` is allowed
            // because the `one` is already declared before being checked here
            // which is literally the entire point of `forward`
            rhs := infer_node(c, decl.rhs)
            if rhs.mode == .INVALID {
                warn(c, "declaration of `%s` failed!", decl.name.text)
                return operand_of(decl, .INVALID)
            }
        }
        entity: ^Entity
        if !decl.forward {
            entity = local(c.scope, decl.name.text)
            if entity == nil {
                entity = new(Entity, c.allocator)
                entity.kind = .VARIABLE
                entity.scope = c.scope
                entity.constraints = decl.constraints
                entity.decl = decl
                declare(c.scope, decl.name.text, entity)
            } else if decl != entity.decl {
                bad_node(c, decl, "this is a redeclaration")
                bad_node(c, entity.decl, "original is here")
                c.error_count -= 1
                return operand_of(decl, .INVALID)
            }
        } else {
            entity = global(c.scope, decl.name.text)
            assert(entity != nil) // `collect_forward` means this CANNOT fail 
            // redeclarations of forwards already checked as well
        }
        
        if decl.rhs == nil {
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
        // honestly with how smooth this `mode` is working out for me
        // maybe I will just make all statements be `NO_VALUE` feels less edge-casey
        return operand_of(decl, .NO_VALUE) 
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
        //TODO: improve this errmsg
        bad_node(c, expr, "invalid types for assignment")
        return operand_of(expr, .INVALID)
    }
    return operand_of(expr, .RVALUE)
}

// difference between `check_node` and `infer_node`...
// is that `check_node` repeatedly bashes it's head into the wall
check_node :: proc(c: ^Checker, node: ^Link) -> Operand {
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

mark_invalid_types :: proc(c: ^Checker, root: ^Link) {
    visit :: proc(node: ^Link, data: rawptr) {
        c := cast(^Checker) data
        if node.mode == .INVALID {
            return
        }
        unknown := card(node.constraints) > 1
        supposed_to_produce_value := node.mode != .NO_VALUE || node.kind == .DECL
        // the `node.kind == .DECL` kind of an edge case, I want this for messaging
        if unknown && supposed_to_produce_value {
            bad_node(c, node, "cannot resolve type between %s", 
                node_annotation_string(node.constraints, node.mode, c.allocator)
            )
        }
    }

    root := node_cast(Block, root)
    assert(root != nil)
    // DO NOT print the entire toplevel for *every error*
    for node in root.code {
        // go pre-order so messages are not in weird order
        pre_order_walk(node, cast(rawptr) c, visit) 
    }
}
