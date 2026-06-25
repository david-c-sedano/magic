
Type_Hint :: struct {
    size: u8; // 8, 16, 32, 64
    flag: enum u8 {
        UNKNOWN;
        SIGNED;
        UNSIGNED;
        FLOAT;
    };
    key: string;
}

get_hint_from_token :: (token: Token) -> Type_Hint {
    if token.text == {
        case "s64"; return Type_Hint.{ size = 64, flag = .SIGNED };
        case "s32"; return Type_Hint.{ size = 32, flag = .SIGNED };
        case "s16"; return Type_Hint.{ size = 16, flag = .SIGNED };
        case "s8";  return Type_Hint.{ size = 8,  flag = .SIGNED };
        case "u64"; return Type_Hint.{ size = 64, flag = .UNSIGNED };
        case "u32"; return Type_Hint.{ size = 32, flag = .UNSIGNED };
        case "u16"; return Type_Hint.{ size = 16, flag = .UNSIGNED };
        case "u8";   return Type_Hint.{ size = 8, flag = .UNSIGNED };
        case "bool"; return Type_Hint.{ size = 8, flag = .UNSIGNED };

        case "float32"; return Type_Hint.{ size = 32, flag = .FLOAT };
        case "float64"; return Type_Hint.{ size = 64, flag = .FLOAT };
    }

    return Type_Hint.{ size = 0, flag = .UNKNOWN, key = token.text };
}

/*  This is more of the parsers job but I wanna put it here
    because it has to do with type rules 
*/
get_default_literal_from_type_hint :: (p: *Parser, ident_hint: Token) -> *AST_Node(Literal) {
    if ident_hint.text == {
    case "s64"; #through;
    case "s32"; #through;
    case "s16"; #through;
    case "s8"; #through;
    case "u64"; #through;
    case "u32"; #through;
    case "u16"; #through;
    case "u8"; #through;
    case "bool";
        literal := new_node(Literal, p, .INTEGER);
        literal.pos = ident_hint.pos;
        literal.end = ident_hint.end;
        literal.text = "0";
        return literal;

    case "float32"; #through;
    case "float64";
        literal := new_node(Literal, p, .REAL);
        literal.pos = ident_hint.pos;
        literal.end = ident_hint.end;
        literal.text = "0.0";
        return literal;
    }

    push_location(p.workspace, ident_hint.pos, ident_hint.end,
        "hint `%` does not make sense as an expression because it's not associated with a default value", ident_hint.text 
    );
    p.has_error = true;
    return null;
}
