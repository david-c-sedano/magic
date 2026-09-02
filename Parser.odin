
package magic

import lex "Godlex"
import "core:fmt"

MAX_PREC :: 9999 // for single operand prefix/postfix

prec_level :: proc(op: lex.Token) -> (AST_Kind, int, /* right binding */ bool) {
    #partial switch op.kind {
    case .EQUALS:               return .ASSIGN,              1, true
    case .PLUS_EQUALS:          return .ADD_ASSIGN,          1, true
    case .MINUS_EQUALS:         return .SUB_ASSIGN,          1, true
    case .STAR_EQUALS:          return .MUL_ASSIGN,          1, true
    case .FORWARD_SLASH_EQUALS: return .DIV_ASSIGN,          1, true
    case .AMPERSAND_EQUALS:     return .BIT_AND_ASSIGN,      1, true
    case .PIPE_EQUALS:          return .BIT_OR_ASSIGN,       1, true
    case .CARAT_EQUALS:         return .BIT_XOR_ASSIGN,      1, true
    case .LEFT_LEFT_EQUALS:     return .SHIFT_LEFT_ASSIGN,   1, true
    case .RIGHT_RIGHT_EQUALS:   return .SHIFT_RIGHT_ASSIGN,  1, true
    case .PIPE_PIPE:            return .LOGICAL_OR,         10, false
    case .AMPERSAND_AMPERSAND:  return .LOGICAL_AND,        15, false
    case .EQUALS_EQUALS:        return .EQUALS,             20, false
    case .BANG_EQUALS:          return .NOT_EQUALS,         20, false
    case .LEFT:                 return .LESS,               25, false
    case .LEFT_EQUALS:          return .LESS_EQ,            25, false
    case .RIGHT:                return .GREATER,            25, false
    case .RIGHT_EQUALS:         return .GREATER_EQ,         25, false
    case .PIPE:                 return .BIT_OR,             30, false
    case .CARAT:                return .BIT_XOR,            30, false
    case .AMPERSAND:            return .BIT_AND,            35, false
    case .LEFT_LEFT:            return .SHIFT_LEFT,         40, false
    case .RIGHT_RIGHT:          return .SHIFT_RIGHT,        40, false
    case .PLUS:                 return .ADD,                50, false
    case .MINUS:                return .SUB,                50, false
    case .STAR:                 return .MUL,                60, false
    case .FORWARD_SLASH:        return .DIV,                60, false
    case .PERCENT:              return .MODULO,             60, false
    }

    return .INVALID, -1, false // token is not infix operator
}

// Go Left Sometimes Parsing Technology (R)(TM)(C)
parse_expr :: proc(g: ^lex.Godlex, min_prec := 0) -> ^Link {
    
    parse_operand :: proc(g: ^lex.Godlex)  -> ^Link {
        token := lex.group_ahead(g,1)

        #partial switch token.kind {
        case .BYTE,.INT,.FLOAT,.STR,.IDENT:
            lex.group(g)
            leaf := new_node(Leaf, token, alloc=g.allocator)
            leaf.token = token
            return wrap_node(leaf)

        case .MINUS,.BANG,.SQUIGGLY:
            unary_op := lex.group(g)
            operand := parse_expr(g, MAX_PREC) 
            if lex.has_error(g) {
                return nil
            }
            // map tokens to unary ops here
            kind: AST_Kind
            #partial switch unary_op.kind {
            case .MINUS:    kind = .NEGATE
            case .BANG:     kind = .LOGICAL_NOT
            case .SQUIGGLY: kind = .BIT_NOT
            }
            unary := new_node(Unary_Expr, token, kind, g.allocator)
            unary.op_token = unary_op
            unary.operand = operand
            return wrap_node(unary)

        case .OPEN_PAREN:
            lex.group(g)
            expr := parse_expr(g)
            if lex.has_error(g) {
                return nil
            }
            cparen := lex.group_ahead(g, 1, .CLOSE_PAREN)
            if cparen.kind == .INVALID {
                lex.error(g, cparen, "expected closing parentheses here")
                return nil
            }
            return expr

        case .KEYWORD:
            switch token.text {
            case "true","false","none":
                lex.group(g)
                leaf := new_node(Leaf, token, alloc=g.allocator)
                leaf.token = token
                return wrap_node(leaf)

            case "do":
                lex.group(g)
                block := parse_block(g, token)
                if lex.has_error(g) {
                    return nil
                }
                return wrap_node(block)

            case "while":
                while := parse_while(g)
                if lex.has_error(g) {
                    return nil
                }
                return wrap_node(while)

            case "if":
                if_else := parse_if_else(g)
                if lex.has_error(g) {
                    return nil
                }
                return wrap_node(if_else)

            case "fu":
                func := parse_func(g)
                if lex.has_error(g) {
                    return nil
                }
                return wrap_node(func)
            }
        }

        lex.error(g, token, "unexpected token while parsing expression")
        return nil
    }

    left := parse_operand(g)
    if lex.has_error(g) {
        return nil
    }

    expr_parse: for {
        op_token := lex.group_ahead(g,1)
        #partial switch op_token.kind {
        case .EOF:
            break expr_parse

        case .OPEN_PAREN:
            if MAX_PREC < min_prec do break expr_parse
            params := parse_param_list(g)
            if lex.has_error(g) {
                return nil
            }
            call := new_node(Bin_Expr, op_token, .CALL, g.allocator)
            call.op_token.text = "()" 
            call.left = left
            call.right = wrap_node(params)
            left = wrap_node(call)
            continue

        case .OPEN_BRACKET:
            if MAX_PREC < min_prec do break expr_parse
            lex.group(g)
            index := parse_expr(g)
            if lex.has_error(g) {
                return nil
            }
            cbracket := lex.group(g, .CLOSE_BRACKET)
            if cbracket.kind == .INVALID {
                lex.error(g, cbracket, "expected closing `]` here")
                return nil
            }
            subscript := new_node(Bin_Expr, op_token, .SUBSCRIPT, g.allocator)
            subscript.op_token.text = "[]"
            subscript.left = left
            subscript.right = index
            left = wrap_node(subscript)
            continue
        }

        op, prec, right_binding := prec_level(op_token)
        if prec > 0 {
            if prec < min_prec {
                break expr_parse
            }
            lex.group(g)

            right: ^Link
            if right_binding {
                right = parse_expr(g, prec)
            } else {
                right = parse_expr(g, prec+1)
            }
            if lex.has_error(g) {
                return nil
            }

            expr := new_node(Bin_Expr, op_token, op, g.allocator)
            expr.op_token = op_token
            expr.left = wrap_node(left)
            expr.right = right
            left = wrap_node(expr)
        } else {
            break
        }
    }
    return left
}

parse_block :: proc(g: ^lex.Godlex, block_start_token: lex.Token) -> ^Node(Block) {
    block := new_node(Block, block_start_token, alloc=g.allocator)
    code := make([dynamic]^Link, g.allocator)
   
    first_token := lex.peek_no_preproc(g)
    first := parse_statement(g)
    if lex.has_error(g) {
        return nil
    }
    append(&code, first)
    // allow for single statement 1 line `do` to make `if` expressions more convenient
    if first_token.start.line == block_start_token.start.line {
        block.code = code[:]
        return block
    }

    column := first_token.start.column
    next := lex.peek_no_preproc(g)
    end := first_token.end
    if next.start.line == end.line {
        lex.error(g, next, "expected statement to end the current line")
    }
    for next.kind != .EOF {
        if next.start.line <= end.line {
            break
        }
        if next.start.column < column {
            break
        }

        if next.start.column > column {
            lex.error(g, next, "unexpected indentation in `do` notation")
            return nil
        }

        stmnt := parse_statement(g)
        if lex.has_error(g) {
            return nil
        }
        append(&code, stmnt)
        end = next.end
        next = lex.peek_no_preproc(g)
        if next.start.line == end.line {
            lex.error(g, next, "expected statement to end the current line")
        }
    }
    block.code = code[:]
    return block
}

parse_statement :: proc(g: ^lex.Godlex) -> ^Link {
    next := lex.group_ahead(g,1)
    if next.kind == .KEYWORD {
        switch next.text {
        case "decl","forward":
            decl := parse_decl(g)
            if lex.has_error(g) {
                return nil
            }
            return wrap_node(decl)

        case "return":
            lex.group(g) 
            ret := new_node(Return, next, alloc=g.allocator)
            mayb_expr := lex.peek_no_preproc(g)
            if mayb_expr.start.line == next.start.line {
                result := parse_expr(g) 
                if lex.has_error(g) {
                    return nil
                }
                ret.result = result
            }
            return wrap_node(ret)

        case "break":
            lex.group(g)
            brk := new_node(Break, next, alloc=g.allocator)
            brk.pos = next
            return wrap_node(brk)
        case "continue":
            lex.group(g)
            cont := new_node(Continue, next, alloc=g.allocator)
            cont.pos = next
            return wrap_node(cont)
        }
    }

    expr := parse_expr(g)
    if lex.has_error(g) {
        return nil
    }
    return expr
}

parse_decl :: proc(g: ^lex.Godlex) -> ^Node(Decl) {
    decl_keyw := lex.group(g)

    name := lex.group(g, .IDENT)
    if name.kind == .INVALID {
        lex.error(g, decl_keyw, "expected some form of `decl <name> = <expr>`")
        return nil
    }

    decl := new_node(Decl, decl_keyw, alloc=g.allocator)
    decl.name = name
    decl.forward = decl_keyw.text == "forward"

    eq := lex.group_ahead(g, 1, .EQUALS)
    if eq.kind != .INVALID {
        decl.rhs = parse_expr(g)
        if lex.has_error(g) {
            return nil
        }
    }
    return decl
}

parse_while :: proc(g: ^lex.Godlex) -> ^Node(While) {
    while_keyw := lex.group(g)
    cond := parse_expr(g) 
    if lex.has_error(g) {
        return nil
    }
    body := parse_expr(g)
    if lex.has_error(g) {
        return nil
    }
    // lmaooo I get to use `while` as an identifier!!
    while := new_node(While, while_keyw, alloc=g.allocator)
    while.cond = cond
    while.body = body
    return while
}

parse_if_else :: proc(g: ^lex.Godlex) -> ^Node(If_Else) {
    if_keyw := lex.group(g)
    cond := parse_expr(g)
    if lex.has_error(g) {
        return nil
    }
    if_body := parse_expr(g)
    if lex.has_error(g) {
        return nil
    }

    else_body: ^Link
    lex.snapshot(g)
    else_keyw := lex.group(g) 
    if else_keyw.kind == .KEYWORD && else_keyw.text == "else" {
        lex.commit(g)
        // make it so that newline after `else` automatically starts a new block
        next := lex.peek_no_preproc(g)
        if next.start.line > else_keyw.start.line {
            else_body = wrap_node(parse_block(g, else_keyw))
        } else {
            else_body = parse_expr(g)
        }
        if lex.has_error(g) {
            return nil
        }
    } else {
        lex.restore(g)
    }

    if_else := new_node(If_Else, if_keyw, alloc=g.allocator)
    if_else.cond = cond
    if_else.if_body = if_body
    if_else.else_body = else_body
    return if_else
}

parse_param_list :: proc(g: ^lex.Godlex) -> ^Node(Param_List) {
    oparen := lex.group(g)
    params := make([dynamic]^Link, g.allocator)

    for {
        next := lex.group_ahead(g,1)
        if next.kind == .CLOSE_PAREN {
            break
        }

        if next.kind == .COMMA {
            append(&params, nil)
            lex.group(g)
            continue
        }

        arg := parse_expr(g)
        if lex.has_error(g) {
            return nil
        }
        append(&params, arg)

        next = lex.group_ahead(g,1)
        if next.kind == .COMMA {
            lex.group(g)
        } else if next.kind != .CLOSE_PAREN {
            lex.error(g,next, "expected comma `,` or closing `)`")
            return nil
        }
    }
    lex.group(g)
    list := new_node(Param_List, oparen, alloc=g.allocator)
    list.params = params[:]
    return list 
}

parse_func :: proc(g: ^lex.Godlex) -> ^Node(Function) {
    fu_keyw := lex.group(g)
    oparen := lex.group(g, .OPEN_PAREN)
    if oparen.kind == .INVALID {
        lex.error(g, oparen, "expected param list after `fu`")
        return nil
    }

    params := make([dynamic]^Link, g.allocator)
    next := lex.group_ahead(g,1)
    for {
        next := lex.group_ahead(g,1)
        if next.kind == .CLOSE_PAREN {
            break
        }

        arg := parse_expr(g)
        if lex.has_error(g) {
            return nil
        }
        append(&params, arg)

        next = lex.group_ahead(g,1)
        if next.kind == .COMMA {
            lex.group(g)
        } else if next.kind != .CLOSE_PAREN {
            lex.error(g,next, "expected comma `,` or closing `)`")
            return nil
        }
    }
    lex.group(g)

    body := parse_expr(g)
    if lex.has_error(g) {
        return nil
    }

    func := new_node(Function, fu_keyw, alloc=g.allocator)
    func.params = params[:]
    func.body = body
    return func 
}
