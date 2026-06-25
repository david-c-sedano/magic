
AST_Node :: struct($T: Type) {
    source: string;
    file_name: string;
    pos: Source_Loc;
    end: Source_Loc;
    hint: Type_Hint;
    kind: AST_Node_Kind;
    #if T != void using data: T;
}

AST_Node_Kind :: enum {
    INVALID;

    IDENTIFIER;

    LITERAL_BEGIN;
        NONE; 
        INTEGER;
        REAL;
        STRING;
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
    AGGREGATE;
    LOAD;
}

/* AST NODE TYPES */
Identifier :: struct {
    kind_range :: AST_Node_Kind.[ .IDENTIFIER ];
    text: string;
} @ast

Literal :: struct {
    kind_range :: AST_Node_Kind.[ .LITERAL_BEGIN, .LITERAL_END ];
    text: string;
} @ast

Binding :: struct {
    kind_range :: AST_Node_Kind.[ .BINDING ];

    forward: bool;
    name: Token;
    rhs: *AST_Node(void);
} @ast

Return :: struct {
    kind_range :: AST_Node_Kind.[ .RETURN_STATEMENT ];
    result: *AST_Node(void);
} @ast

Break :: struct {
    kind_range :: AST_Node_Kind.[ .BREAK_STATEMENT ];
} @ast

Continue :: struct {
    kind_range :: AST_Node_Kind.[ .CONTINUE_STATEMENT ];
} @ast

Expr :: struct {
    kind_range :: AST_Node_Kind.[ .EXPRESSION ];

    op: Token;
    left: *AST_Node(void);
    right: *AST_Node(void);
} @ast

Call :: struct {
    kind_range :: AST_Node_Kind.[ .CALL ];

    callee: *AST_Node(void);
    args: [..]*AST_Node(void);
} @ast

Subscript :: struct {
    kind_range :: AST_Node_Kind.[ .SUBSCRIPT ];

    container: *AST_Node(void);
    index: *AST_Node(void);
} @ast

Block :: struct {
    kind_range :: AST_Node_Kind.[ .BLOCK ];
    code: [..]*AST_Node(void);
} @ast

If_Else :: struct {
    kind_range :: AST_Node_Kind.[ .IF_ELSE ];

    cond: *AST_Node(void);
    if_body: *AST_Node(void);
    else_body: *AST_Node(void);
} @ast

While_Loop :: struct {
    kind_range :: AST_Node_Kind.[ .WHILE_LOOP ];

    cond: *AST_Node(void);
    body: *AST_Node(void);
} @ast

Function :: struct {
    kind_range :: AST_Node_Kind.[ .FUNCTION ];

    params: [..]*AST_Node(void);
    body: *AST_Node(void);
} @ast

List :: struct {
    kind_range :: AST_Node_Kind.[ .LIST ];
    items: [..]*AST_Node(void);
} @ast

Structure :: struct {
    kind_range :: AST_Node_Kind.[ .AGGREGATE ];

    members: [..]*AST_Node(void);
    values: [..]*AST_Node(void);
} @ast

Parser :: struct {
    tokenizer: Tokenizer;
    prev: Token;
    curr: Token;
    has_error: bool;

    workspace: *Compiler_Workspace;
}

node_cast :: (
    node: *AST_Node, 
    $to: Type 
) -> *AST_Node(to) {
    if node == null return null;

    /*  `kind_range` can only be 1 or 2 items, 
        else you will always get `null` from this 
    */
    #if to.kind_range.count == 1 {
        if node.kind == to.kind_range[0] {
            return cast(*AST_Node(to)) node;
        }
    }

    #if to.kind_range.count == 2 {
        if to.kind_range[0] <= node.kind && node.kind <= to.kind_range[1] {
            return cast(*AST_Node(to)) node;
        }
    }

    return null;
}

wrap_node :: (node: *AST_Node($T)) -> *AST_Node(void) {
    return cast(*AST_Node(void)) node;
}

new_node :: ($T: Type, p: *Parser, kind: AST_Node_Kind = .INVALID) -> *AST_Node(T) {
    node := New(AST_Node(T),,p.workspace.allocator);

    #if T.kind_range.count == 1 {
        node.kind = T.kind_range[0];
    }

    #if T.kind_range.count == 2 {
        assert(kind != .INVALID);
        node.kind = kind;
    }

    node.file_name = p.workspace.current_file_being_worked_on;
    node.source = get_current_file_source(p.workspace);
    return node;
}

init_parser_from_current_file :: (w: *Compiler_Workspace, parser: *Parser) -> bool {
    parser.workspace = w;
    if !init_tokenizer_from_current_file(w, *parser.tokenizer) {
        return false;
    }
    next_token(parser);
    return true;
}

next_token :: (parser: *Parser) -> Token {
    parser.prev = parser.curr;
    parser.curr = get_token(*parser.tokenizer);
    return parser.prev;
}

expect_token :: (using p: *Parser, kinds: ..Token_Kind) -> Token, bool {
    ok := array_find(kinds, curr.kind);
    next_token(p);
    if ok {
        return prev, true;
    }
    return prev, false;
}

optional_hint :: (using p: *Parser, node: *AST_Node(void)) -> Token, bool {
    if curr.kind == .HINT {
        next_token(p);
        ident, has_ident := expect_token(p, .IDENTIFIER);
        if !has_ident {
            push_location(workspace, ident.pos, ident.end,
                "expected an identifier after `@` for hint"
            );
            has_error = true;
            return .{}, false;
        }
        node.hint = get_hint_from_token(ident);
        return ident, true;
    }
    return .{}, false;
}

parse_binding :: (using p: *Parser) -> *AST_Node(Binding) {
    decl, has_decl := expect_token(p, .DECL, .FORWARD);
    assert(has_decl);

    binding := new_node(Binding, p);
    binding.pos = decl.pos;
    binding.forward = decl.kind == .FORWARD;
    ok: bool;
    binding.name, ok = expect_token(p, .IDENTIFIER);
    if !ok {
        push_location(workspace, binding.name.pos, binding.name.end,
            "expected identifier after decl keyword"
        );
        has_error = true;
        return null;
    }
    
    assign, has_assign := expect_token(p, .ASSIGN);
    if !has_assign {
        push_location(workspace, assign.pos, assign.end,
            "expected assignment in declaration"
        );
        has_error = true;
        return null;
    }

    hint, has_hint := optional_hint(p, wrap_node(binding));
    if has_error {
        return null;
    }
    if has_hint {
        binding.rhs = wrap_node(get_default_literal_from_type_hint(p, hint));
        if has_error return null;
        return binding;
    }

    binding.rhs = parse_expr(p);
    if has_error {
        return null;
    }
    binding.end = binding.rhs.end;

    optional_hint(p, wrap_node(binding));
    if has_error {
        return null;
    }
    return binding;
}

parse_return :: (using p: *Parser) -> *AST_Node(Return) {
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

parse_node :: (using p: *Parser) -> *AST_Node(void) {

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
parse_expr :: (using p: *Parser, min_prec := 0) -> *AST_Node(void) {

    parse_operand :: (using p: *Parser) -> *AST_Node(void) {
        token := curr;

        make_literal :: (kind: AST_Node_Kind) -> *AST_Node(void) #expand {
            next_token(p);
            literal := new_node(Literal, p, kind);
            literal.pos = token.pos;
            literal.end = token.end;
            literal.text = copy_string(token.text);
            return wrap_node(literal);
        }

        if token.kind == {
        case .IDENTIFIER; 
            next_token(p);
            ident := new_node(Identifier, p);
            ident.pos = token.pos;
            ident.end = token.end;
            ident.text = token.text;
            return wrap_node(ident);

        case .NONE; return make_literal(.NONE);
        case .INTEGER; return make_literal(.INTEGER);
        case .REAL; return make_literal(.REAL);
        case .STRING; return make_literal(.STRING);

        // auto-assign hint
        case .TRUE; #through;
        case .FALSE; #through;
        case .CHAR;
            literal := make_literal(.INTEGER);
            literal.hint = Type_Hint.{ size = 8, flag = .UNSIGNED };
            return wrap_node(literal);

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
                push_location(workspace, token.pos, token.end,
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
            structure := parse_struct(p);
            if has_error {
                return null;
            }
            return wrap_node(structure);

        case;
            push_location(workspace, token.pos, token.end,
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
   
            right: *AST_Node(void);
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

parse_call :: (using p: *Parser, callee: *AST_Node(void)) -> *AST_Node(Call) {
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

parse_subscript :: (using p: *Parser, subscriptee: *AST_Node(void)) -> *AST_Node(Subscript) {
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
        push_location(workspace, cbracket.pos, cbracket.end,
            "Expected a closing bracket in subscript"
        );
        has_error = true;
        return null;
    }

    subscript.end = cbracket.end;
    return subscript;
}

parse_block :: (using p: *Parser) -> *AST_Node(Block) {
    in, has_in := expect_token(p, .IN);
    if !has_in {
        push_location(workspace, in.pos, in.end,
            "Expected `in` to denote start of block"
        );
        has_error = true;
        return null;
    }

    block := new_node(Block, p);
    block.pos = in.pos;

    while 1 {
        if curr.kind == .EOF {
            push_location(workspace, in.pos, in.end,
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
parse_if_else :: (using p: *Parser) -> *AST_Node(If_Else) {
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
        push_location(workspace, in.pos, in.end,
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
            push_location(workspace, if_token.pos, if_token.end,
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
                push_location(workspace, else_token.pos, else_token.end,
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

parse_while :: (using p: *Parser) -> *AST_Node(While_Loop) {
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

parse_function :: (using p: *Parser) -> *AST_Node(Function) {
    keyw, has_keyw := expect_token(p, .FU);
    assert(has_keyw);

    oparen, has_oparen := expect_token(p, .OPEN_PAREN);
    if !has_oparen {
        push_location(workspace, oparen.pos, oparen.end, 
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

parse_list :: (using p: *Parser) -> *AST_Node(List) {
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

parse_struct :: (using p: *Parser) -> *AST_Node(Structure) {
    obrace, has_obrace := expect_token(p, .OPEN_BRACE);
    assert(has_obrace);

    structure := new_node(Structure, p);
    structure.pos = obrace.pos;
    structure.kind = .AGGREGATE;

    while 1 {
        if curr.kind == .CLOSE_BRACE {
            structure.end = curr.end;
            next_token(p);
            break;
        }

        ident, has_member := expect_token(p, .IDENTIFIER);
        if !has_member {
            push_location(workspace, ident.pos, ident.end,
                "expected an identifier as member of struct",
            );
            has_error = true;
            return null;
        }
        member := new_node(Identifier, p);
        member.pos = ident.pos;
        member.end = ident.end;
        member.text = ident.text;
        array_add(*structure.members, wrap_node(member));

        if curr.kind != .ASSIGN {
            push_location(workspace, curr.pos, curr.end,
                "expected an `=` to separate members and values in struct",
            );
            has_error = true;
            return null;
        }
        next_token(p);

        hint, has_hint := optional_hint(p, wrap_node(member));
        if has_error {
            return null;
        }
        if has_hint {
            default_value := wrap_node(get_default_literal_from_type_hint(p, hint));
            if has_error return null;
            array_add(*structure.values, default_value);
            if curr.kind == .SEMICOLON {
                next_token(p);
            }

            continue;
        }

        array_add(*structure.values, parse_expr(p));
        if has_error {
            return null;
        }
        optional_hint(p, wrap_node(member));
        if has_error {
            return null;
        }

        if curr.kind == .SEMICOLON {
            next_token(p);
        }
    }
   
    return structure;
}

