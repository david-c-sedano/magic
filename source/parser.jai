
Parse_Node :: struct($T: Type) {
    source: string;
    file_name: string;
    pos: Source_Loc;
    end: Source_Loc;
    kind: Parse_Node_Kind;
    #if T != void using data: T;
}

Parse_Node_Kind :: enum {
    INVALID;

    IDENTIFIER;

    LITERAL_BEGIN;
        NONE; 
        BOOLEAN;
        INTEGER;
        REAL;
        STRING;
        CHAR;
    LITERAL_END;

    BINDING;
    RETURN_STATEMENT;
    BREAK_STATEMENT;
    CONTINUE_STATEMENT;
    EXPRESSION;
    CALL;
    SUBSCRIPT;
    BLOCK;
    IF_ELSE;
    WHILE_LOOP;
    FUNCTION;
    LIST;
    MAP;
}

/* AST NODE TYPES */
Identifier :: struct {
    kind_range :: Parse_Node_Kind.[ .IDENTIFIER ];
    text: string;
} @parse_node

Literal :: struct {
    kind_range :: Parse_Node_Kind.[ .LITERAL_BEGIN, .LITERAL_END ];
    text: string;
} @parse_node

Binding :: struct {
    kind_range :: Parse_Node_Kind.[ .BINDING ];

    forward: bool;
    name: Token;
    rhs: *Parse_Node(void);
} @parse_node

Return :: struct {
    kind_range :: Parse_Node_Kind.[ .RETURN_STATEMENT ];
    result: *Parse_Node(void);
} @parse_node

Break :: struct {
    kind_range :: Parse_Node_Kind.[ .BREAK_STATEMENT ];
} @parse_node

Continue :: struct {
    kind_range :: Parse_Node_Kind.[ .CONTINUE_STATEMENT ];
} @parse_node

Expr :: struct {
    kind_range :: Parse_Node_Kind.[ .EXPRESSION ];

    op: Token;
    left: *Parse_Node(void);
    right: *Parse_Node(void);
} @parse_node

Call :: struct {
    kind_range :: Parse_Node_Kind.[ .CALL ];

    callee: *Parse_Node(void);
    args: [..]*Parse_Node(void);
} @parse_node

Subscript :: struct {
    kind_range :: Parse_Node_Kind.[ .SUBSCRIPT ];

    container: *Parse_Node(void);
    index: *Parse_Node(void);
} @parse_node

Block :: struct {
    kind_range :: Parse_Node_Kind.[ .BLOCK ];
    code: [..]*Parse_Node(void);
} @parse_node

If_Else :: struct {
    kind_range :: Parse_Node_Kind.[ .IF_ELSE ];

    cond: *Parse_Node(void);
    if_body: *Parse_Node(void);
    else_body: *Parse_Node(void);
} @parse_node

While_Loop :: struct {
    kind_range :: Parse_Node_Kind.[ .WHILE_LOOP ];

    cond: *Parse_Node(void);
    body: *Parse_Node(void);
} @parse_node

Function :: struct {
    kind_range :: Parse_Node_Kind.[ .FUNCTION ];

    params: [..]*Parse_Node(void);
    body: *Parse_Node(void);
} @parse_node

List :: struct {
    kind_range :: Parse_Node_Kind.[ .LIST ];
    items: [..]*Parse_Node(void);
} @parse_node

Map :: struct {
    kind_range :: Parse_Node_Kind.[ .MAP ];

    keys: [..]*Parse_Node(void);
    values: [..]*Parse_Node(void);
} @parse_node

Parser :: struct {
    using t: Tokenizer;
    prev: Token;
    curr: Token;
    has_error: bool;
    arena: Flat_Pool;
}

node_cast :: (
    node: *Parse_Node, 
    $to: Type 
) -> *Parse_Node(to) {
    if node == null return null;

    /*  `kind_range` can only be 1 or 2 items, 
        else you will always get `null` from this 
    */
    #if to.kind_range.count == 1 {
        if node.kind == to.kind_range[0] {
            return cast(*Parse_Node(to)) node;
        }
    }

    #if to.kind_range.count == 2 {
        if to.kind_range[0] <= node.kind && node.kind <= to.kind_range[1] {
            return cast(*Parse_Node(to)) node;
        }
    }

    return null;
}

wrap_node :: (node: *Parse_Node($T)) -> *Parse_Node(void) {
    return cast(*Parse_Node(void)) node;
}

new_node :: ($T: Type, p: Parser, kind: Parse_Node_Kind = .INVALID) -> *Parse_Node(T) {
    node := New(Parse_Node(T));

    #if T.kind_range.count == 1 {
        node.kind = T.kind_range[0];
    }

    #if T.kind_range.count == 2 {
        assert(kind != .INVALID);
        node.kind = kind;
    }

    node.source = context.source;
    node.file_name = context.file_name;
    return node;
}

init_parser :: (p: *Parser) {
    init_tokenizer(*p.t, context.source);
    next_token(p);
}

next_token :: (using p: *Parser) -> Token {
    free_token(prev);
    prev = curr;
    curr = get_token(*t);
    return prev;
}

expect_token :: (using p: *Parser, kinds: ..Token_Kind) -> Token, bool {
    ok := array_find(kinds, curr.kind);
    next_token(p);
    if ok {
        return prev, true;
    }
    return prev, false;
}

parse_binding :: (using p: *Parser) -> *Parse_Node(Binding) {
    decl, has_decl := expect_token(p, .DECL, .FORWARD);
    assert(has_decl);

    binding := new_node(Binding, p);
    binding.pos = decl.pos;
    binding.forward = decl.kind == .FORWARD;
    ok: bool;
    binding.name, ok = expect_token(p, .IDENTIFIER);
    if !ok {
        push_location(binding.name.pos, binding.name.end,
            "expected identifier after decl keyword"
        );
        has_error = true;
        return null;
    }
    
    assign, has_assign := expect_token(p, .ASSIGN);
    if !has_assign {
        push_location(assign.pos, assign.end,
            "expected assignment in declaration"
        );
        has_error = true;
        return null;
    }

    binding.rhs = parse_expr(p);
    if has_error {
        return null;
    }
    binding.end = binding.rhs.end;
    return binding;
}

parse_return :: (using p: *Parser) -> *Parse_Node(Return) {
    return_token, has_return := expect_token(p, .RETURN);
    assert(has_return);

    return_stmnt := new_node(Return, p);
    return_stmnt.pos = return_token.pos;
    
    if curr.kind != .SEMICOLON {
        return_stmnt.result = parse_expr(p);
        if has_error {
            return null;
        }
        return_stmnt.end = return_stmnt.result.end;
    } else {
        return_stmnt.end = return_token.end;
    }

    return return_stmnt;
}

parse_node :: (using p: *Parser) -> *Parse_Node(void) {

    optional_semicolon :: () #expand {
        if `curr.kind == .SEMICOLON {
            next_token(p);
        }
    }

    if curr.kind == {
    case .DECL; #through;
    case .FORWARD;
        binding := parse_binding(p);
        optional_semicolon();
        return wrap_node(binding);

    case .RETURN;
        return_stmnt := parse_return(p);
        optional_semicolon();
        return wrap_node(return_stmnt);

    case .BREAK;
        // WHO NEEDS A FUNCTION FOR THIS?
        break_stmnt := new_node(Break, p);
        break_stmnt.pos = curr.pos;
        break_stmnt.end = curr.end;
        next_token(p);
        optional_semicolon();
        return wrap_node(break_stmnt);

    case .CONTINUE;
        /*  SCREW YOUR "DRY" PRINCIPLES, WE WRITE "WET" CODE HERE
            (We Enjoy Typing)
        */
        cont_stmnt := new_node(Continue, p);
        cont_stmnt.pos = curr.pos;
        cont_stmnt.end = curr.end;
        next_token(p);
        optional_semicolon();
        return wrap_node(cont_stmnt);
    }

    /* DEFAULT TO EXPR CAUSE WE GOT EVERYTHING IN EXPR LEVEL!!! */
    expr := parse_expr(p);
    optional_semicolon();
    return expr;
}

/* EXPRESSIONS */
prec_level :: (op: Token) -> int, right_binding: bool {
    if op.kind == {
    case .ASSIGN;      return 1,  true;
    case .LOGICAL_OR;  return 10, false;
    case .LOGICAL_AND; return 15, false;
    case .EQUALITY;    return 20, false;
    case .NOT_EQUALS;  return 20, false;
    case .LESS;        return 25, false;
    case .LESS_EQ;     return 25, false;
    case .GREATER;     return 25, false;
    case .GREATER_EQ;  return 25, false;
    case .BIT_OR;      return 30, false;
    case .BIT_AND;     return 35, false;
    case .SHIFT_LEFT;  return 40, false;
    case .SHIFT_RIGHT; return 40, false;
    case .PLUS;        return 50, false;
    case .MINUS;       return 50, false;
    case .MUL;         return 60, false;
    case .DIV;         return 60, false;
    case .MODULO;      return 60, false;
    case .EXPONENT;    return 70, true;
    case .DOT;         return 80, false;
    }

    return -1, false; // token is not infix operator
}

// Go Left Sometimes Parsing Technology (R)(TM)(C)
parse_expr :: (using p: *Parser, min_prec := 0) -> *Parse_Node(void) {

    parse_operand :: (using p: *Parser) -> *Parse_Node(void) {
        token := curr;

        make_literal :: (kind: Parse_Node_Kind) #expand {
            next_token(p);
            literal := new_node(Literal, p, kind);
            literal.pos = token.pos;
            literal.end = token.end;
            literal.text = copy_string(token.text);
            `return wrap_node(literal);
        }

        if token.kind == {
        case .IDENTIFIER; 
            next_token(p);
            ident := new_node(Identifier, p);
            ident.pos = token.pos;
            ident.end = token.end;
            ident.text = token.text;
            return wrap_node(ident);

        case .NONE; make_literal(.NONE);
        case .TRUE; make_literal(.BOOLEAN);
        case .FALSE; make_literal(.BOOLEAN);
        case .INTEGER; make_literal(.INTEGER);
        case .REAL; make_literal(.REAL);
        case .STRING; make_literal(.STRING);
        case .CHAR; make_literal(.CHAR);

        case .MINUS;       #through;
        case .LOGICAL_NOT; #through;
        case .BIT_NOT;
            unary_op := next_token(p);
            operand := parse_expr(p);
            if operand == null {
                return null;
            }
            unary := new_node(Expr, p);
            unary.op = unary_op;
            unary.pos = unary_op.pos;
            unary.left = operand;
            unary.end = operand.end;
            return wrap_node(unary);

        case .OPEN_PAREN;
            next_token(p);
            expr := parse_expr(p, 0);
            if has_error {
                return null;
            }

            cparen, has_close_paren := expect_token(p, .CLOSE_PAREN);
            if !has_close_paren {
                push_location(token.pos, token.end,
                    "expected closing paren in expression"
                );
                has_error = true;
                return null;
            }

            expr.end = cparen.pos;
            return expr;

        case .IN;
            block := parse_block(p);
            if has_error {
                return null;
            }
            return wrap_node(block);

        case .IF;
            if_else := parse_if_else(p);
            if has_error {
                return null;
            }
            return wrap_node(if_else);
    
        case .WHILE;
            while_loop := parse_while(p);
            if has_error {
                return null;
            }
            return wrap_node(while_loop);

        case .FU;
            function := parse_function(p);
            if has_error {
                return null;
            }
            return wrap_node(function);

        case .OPEN_BRACKET;
            list := parse_list(p);
            if has_error {
                return null;
            }
            return wrap_node(list);

        case .OPEN_BRACE;
            map := parse_map(p);
            if has_error {
                return null;
            }
            return wrap_node(map);

        case;
            push_location(token.pos, token.end,
                "Got unexpected token `%` while parsing expression", 
                token.kind
            );
            has_error = true;
            return null;
        }
    }

    left := parse_operand(p);
    if has_error || left == null {
        return null;
    }

    while 1 {
        op := curr;
        if op.kind == .EOF break;
        if op.kind == .SEMICOLON break;

        /*  ah yes my postfix expression parsing technique
            haven't used this since the Heian Era
        */
        if op.kind == {
        case .OPEN_PAREN;
            call := parse_call(p, left);
            if has_error {
                return null;
            }
            left = wrap_node(call);
            continue;

        case .OPEN_BRACKET;
            subscr := parse_subscript(p, left);
            if has_error {
                return null;
            }
            left = wrap_node(subscr);
            continue;
        }
 
        prec, right_binding := prec_level(op);
        if prec > 0 { // if we have an op
            if prec < min_prec {
                break;
            }
            next_token(p);
   
            right: *Parse_Node(void);
            if right_binding {
                right = parse_expr(p, prec);
            } else {
                right = parse_expr(p, prec + 1);
            }
            if has_error {
                return null;
            }

            op_node := new_node(Expr, p);
            op_node.op = op;
            op_node.pos = left.pos;
            op_node.left = left;
            op_node.end = right.end;
            op_node.right = right;
            
            left = wrap_node(op_node);
        } else {
            break;
        }
    }

    return left;
}

parse_call :: (using p: *Parser, callee: *Parse_Node(void)) -> *Parse_Node(Call) {
    _,has_oparen := expect_token(p, .OPEN_PAREN);
    assert(has_oparen);

    call := new_node(Call, p);
    call.callee = callee;
    call.pos = callee.pos;
    if curr.kind != .CLOSE_PAREN {
        while 1 {
            if curr.kind == .COMMA {
                array_add(*call.args, null);
                /* DONT SKIP THE COMMA HERE ELSE `( ,` DOESNT COUNT AS AN EMPTY SLOT
                   WE SKIP THE COMMA LATER OK */
            } else {
                array_add(*call.args, parse_expr(p));
                if has_error {
                    return null;
                }
            }

            if curr.kind == .COMMA {
                next_token(p);
                // GOTTA MAKE `, )` COUNT AS AN EMPTY SLOT AS WELL
                if curr.kind == .CLOSE_PAREN {
                    array_add(*call.args, null);
                }
            }

            if curr.kind == .CLOSE_PAREN {
                call.end = curr.end;
                next_token(p);
                break;
            }
        }
    } else {
        call.end = curr.end;
        next_token(p); // call with no args like `func()`
    }

    return call;
}

parse_subscript :: (using p: *Parser, subscriptee: *Parse_Node(void)) -> *Parse_Node(Subscript) {
    _,has_obracket := expect_token(p, .OPEN_BRACKET);
    assert(has_obracket);

    subscript := new_node(Subscript, p);
    subscript.container = subscriptee;
    subscript.pos = subscriptee.pos;
    subscript.index = parse_expr(p);
    if has_error {
        return null;
    }

    cbracket, has_cbracket := expect_token(p, .CLOSE_BRACKET);
    if !has_cbracket {
        push_location(cbracket.pos, cbracket.end,
            "Expected a closing bracket in subscript"
        );
        has_error = true;
        return null;
    }

    subscript.end = cbracket.end;
    return subscript;
}

parse_block :: (using p: *Parser) -> *Parse_Node(Block) {
    in, has_in := expect_token(p, .IN);
    if !has_in {
        push_location(in.pos, in.end,
            "Expected `in` to denote start of block"
        );
        has_error = true;
        return null;
    }

    block := new_node(Block, p);
    block.pos = in.pos;

    while 1 {
        if curr.kind == .EOF {
            push_location(in.pos, in.end,
                "Unexpected End Of File while parsing block"
            );
            has_error = true;
            return null;
        }

        if curr.kind == .END {
            block.end = curr.end;
            next_token(p);
            break;
        }

        node := parse_node(p);
        array_add(*block.code, node);
        if has_error {
            return null;
        }
    }

    return block;
}

/*  if-else is a massive pain in this language because there is syntax-sugar in reality
    if there was no sugar, itd look like this

    if <cond> in 
        <body>
    end else if <cond> in
        <body>
    end else in
        <body>
    end

    but no, we want

    if <cond> in
        <body>
    else if <cond> in
        <body>
    else
        <body>
    end

    now, if-else is not a chain of conditions + blocks, like a switch statement or w/e
    its more like a whole new if-else in an else branch and so on, the tree gets DEEPER, not longer
    `pprint_if_else` makes it way easier to understand than any explanation though..
*/
parse_if_else :: (using p: *Parser) -> *Parse_Node(If_Else) {
    if_token, has_if_token := expect_token(p, .IF);
    assert(has_if_token);

    if_else := new_node(If_Else, p);
    if_else.pos = if_token.pos;

    /* PARSE CONDITION */
    if_else.cond = parse_expr(p);
    if has_error {
        return null;
    }
    in, has_in := expect_token(p, .IN);
    if !has_in {
        push_location(in.pos, in.end,
            "expected `in` after condition in if statement"
        );
        has_error = true;
        return null;
    }

    /* PARSE BLOCKS */
    has_else := false;
    else_token: Token; // for error messaging
    if_body := new_node(Block, p);
    if_body.pos = in.pos;
    while 1 {
        if curr.kind == .EOF {
            push_location(if_token.pos, if_token.end,
                "Unexpected End Of File while parsing body of if-statement"
            );
            has_error = true;
            return null;
        }

        if curr.kind == .END {
            if_body.end = curr.end;
            if_else.end = curr.end;
            next_token(p);
            break;
        }

        if curr.kind == .ELSE {
            if_body.end = curr.end;
            has_else = true;
            else_token = next_token(p);
            break;
        }

        node := parse_node(p);
        array_add(*if_body.code, node);
        if has_error {
            return null;
        }
    }
    if_else.if_body = wrap_node(if_body);

    if has_else {
        else_body := new_node(Block, p);
        else_body.pos = else_token.pos;
        is_else_if := false;
        while 1 {
            if curr.kind == .IF is_else_if = true;

            if curr.kind == .EOF {
                push_location(else_token.pos, else_token.end,
                    "Unexpected End Of File while parsing else-statement"
                );
                has_error = true;
                return null;
            }

            if curr.kind == .END {
                else_body.end = curr.end;
                if_else.end = curr.end;
                next_token(p);
                break;
            }

            node := parse_node(p);
            array_add(*else_body.code, node);
            if has_error {
                return null;
            }

            if is_else_if {
                else_body.end = else_token.end;
                if_else.end = else_token.end;
                break;
            }
        }
        if_else.else_body = wrap_node(else_body);
    }

    return if_else;
}

parse_while :: (using p: *Parser) -> *Parse_Node(While_Loop) {
    while_token, has_while_token := expect_token(p, .WHILE);
    assert(has_while_token);

    while_loop := new_node(While_Loop, p);
    while_loop.pos = while_token.pos;
    while_loop.cond = parse_expr(p);
    if has_error {
        return null;
    }

    while_loop.body = wrap_node(parse_block(p)); 
    if has_error {
        return null;
    }

    while_loop.end = while_loop.body.end;
    return while_loop;
}

parse_function :: (using p: *Parser) -> *Parse_Node(Function) {
    keyw, has_keyw := expect_token(p, .FU);
    assert(has_keyw);

    oparen, has_oparen := expect_token(p, .OPEN_PAREN);
    if !has_oparen {
        push_location(oparen.pos, oparen.end, 
            "expected parameters in function"
        );
        has_error = true;
        return null;
    }

    func := new_node(Function, p);
    func.pos = keyw.pos;

    // parse params
    while 1 {
        if curr.kind == .CLOSE_PAREN {
            next_token(p);
            break;
        }

        // evaluator/checker needs to enforce either identifiers or assignments
        param := parse_expr(p);
        if has_error {
            return null;
        }
        array_add(*func.params, param); 

        if curr.kind == .COMMA {
            next_token(p);
        }
    }

    func.body = parse_expr(p);
    if has_error {
        return null;
    }
    func.end = func.body.end;

    return func;
}

parse_list :: (using p: *Parser) -> *Parse_Node(List) {
    obracket, has_obracket := expect_token(p, .OPEN_BRACKET);
    assert(has_obracket);

    list := new_node(List, p);
    list.pos = obracket.pos;
    while 1 {
        if curr.kind == .CLOSE_BRACKET {
            list.end = curr.end;
            next_token(p);
            break;
        }

        array_add(*list.items, parse_expr(p));
        if has_error {
            return null;
        }

        if curr.kind == .COMMA {
            next_token(p);
        }
    }
   
    return list;
}

parse_map :: (using p: *Parser) -> *Parse_Node(Map) {
    obrace, has_obrace := expect_token(p, .OPEN_BRACE);
    assert(has_obrace);

    map := new_node(Map, p);
    map.pos = obrace.pos;
    map.kind = .MAP;

    while 1 {
        if curr.kind == .CLOSE_BRACE {
            map.end = curr.end;
            next_token(p);
            break;
        }

        array_add(*map.keys, parse_expr(p));
        if has_error {
            return null;
        }

        if curr.kind != .COLON {
            push_location(curr.pos, curr.end,
                "expected a colon to separate keys and values in map",
            );
            has_error = true;
            return null;
        }
        next_token(p);

        array_add(*map.values, parse_expr(p));
        if has_error {
            return null;
        }

        if curr.kind == .COMMA {
            next_token(p);
        }
    }
   
    return map;
}

