
package magic

import lex "Godlex"
import "core:fmt"

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
    changed: bool,
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
    c.scope.parent = parent 
}

pop_scope :: proc(c: ^Checker) {
    if c.scope != nil {
        c.scope = c.scope.parent
    }
}

operand_of :: proc(node: ^Link, mode: Addressing_Mode) -> Operand {
    operand: Operand
    operand.expr = node
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

infer_bin :: proc(expr: ^Node(Bin_Expr)) -> bool {
    lhs := expr.left.constraints
    rhs := expr.right.constraints
    result := expr.constraints
    possible_lhs,possible_rhs,possible_result: Unknown
    matched := false
    for rule in RULES[expr.kind] {
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

infer :: proc {
    infer_bin,
    infer_unary,
}

// I dont think it's needed to check `lex.has_error` schizophrenically 
// just keep going and accumulate errors
bad_node :: proc(c: ^Checker, node: ^Link, errmsg: string, format: ..any) {
    lex.error(c.g, node.span, errmsg, ..format);
}

seed :: proc(c: ^Checker, root: ^Link) {

    visit :: proc(node: ^Link, data: rawptr) {
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

        // stuff that makes no value, unless it's `decl` or `return` with expression
        if field := node_cast(Layout_Field, node); field != nil {
            field.mode = .NO_VALUE
            return
        }
        if layout := node_cast(Layout, node); layout != nil {
            layout.mode = .NO_VALUE
            return
        }
        if brk := node_cast(Break, node); brk != nil {
            brk.mode = .NO_VALUE
            return
        }
        if cont := node_cast(Continue, node); cont != nil {
            cont.mode = .NO_VALUE
            return
        }
        if list := node_cast(Param_List, node); list != nil {
            // broader `CALL` expression is what gets the type
            // this is like a template instantiation
            list.mode = .NO_VALUE
            return
        }
        if ret := node_cast(Return, node); ret != nil {
            // I wonder if "break-like" return is a good way to frame it?
            if ret.result == nil {
                ret.mode = .NO_VALUE
            }
            return
        }
        if decl := node_cast(Decl, node); decl != nil {
            // I think I said that `decl` without init is `none`
            // but for now I'm not gonna add the constraint, maybe will change spec
            if decl.rhs == nil {
                decl.mode = .NO_VALUE
            }
            return
        }

        node.constraints = Any
    }

    post_order_walk(root, cast(rawptr) c, visit)
}

infer_node :: proc(c: ^Checker, node: ^Link) -> Operand {

    if leaf := node_cast(Leaf, node); leaf != nil {
        return operand_of(node, leaf.mode) // seeded 
    }

    if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
        lhs := infer_node(c, bin_expr.left)
        rhs := infer_node(c, bin_expr.right)
        if len(RULES[bin_expr.kind]) != 0 {
            if infer(bin_expr) {
                c.changed = true 
            }
        }
        return operand_of(node, .RVALUE)  //TODO: Will have to check `lhs` for subscript 
    }

    if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
        unary_operand := infer_node(c, unary_expr.operand)
        if len(RULES[unary_expr.kind]) != 0 {
            if infer(unary_expr) {
                c.changed = true
            }
        }
        return operand_of(node, .RVALUE) //TODO: Will have to check for addr-of 
    }

    if block := node_cast(Block, node); block != nil {
        // NOTE: empty blocks are rejected by the parser
        // only way its possible is in case of empty file, which is handled!!
        result: Operand
        for stmnt in block.code {
            result = infer_node(c, stmnt)
        }
        common := block.constraints & result.constraints
        if common != block.constraints || common != result.constraints {
            c.changed = true
        }
        block.constraints = common
        result.expr.constraints = common
        operand: Operand
        operand.expr = node
        operand.constraints = block.constraints
        operand.mode = result.mode
        return operand
    }

    fmt.println(node.kind)
    assert(false, "unmatched node kind in `check_node`")
    return {}
}

// difference between `check_node` and `infer_node`...
// is that `check_node` repeatedly bashes it's head into the wall
check_node :: proc(c: ^Checker, node: ^Link) -> Operand {
    operand: Operand
    for {
        c.changed = false
        operand = infer_node(c, node)
        if !c.changed {
            break
        }
    }
    return operand
}
