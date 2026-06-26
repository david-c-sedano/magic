
Type_Hint :: struct {
    size: u8; // 8, 16, 32, 64
    kind: enum u8 {
        UNKNOWN;
        SIGNED;
        UNSIGNED;
        FLOAT;
    };
    key: string;
}

get_hint_from_token :: (token: Token) -> Type_Hint {
    if token.text == {
        case "s64";     return Type_Hint.{ size = 64, kind = .SIGNED,   key = token.text };
        case "s32";     return Type_Hint.{ size = 32, kind = .SIGNED,   key = token.text };
        case "s16";     return Type_Hint.{ size = 16, kind = .SIGNED,   key = token.text };
        case "s8";      return Type_Hint.{ size = 8,  kind = .SIGNED,   key = token.text };
        case "u64";     return Type_Hint.{ size = 64, kind = .UNSIGNED, key = token.text };
        case "u32";     return Type_Hint.{ size = 32, kind = .UNSIGNED, key = token.text };
        case "u16";     return Type_Hint.{ size = 16, kind = .UNSIGNED, key = token.text };
        case "u8";      return Type_Hint.{ size = 8,  kind = .UNSIGNED, key = token.text };
        case "bool";    return Type_Hint.{ size = 8,  kind = .UNSIGNED, key = token.text };
        case "float32"; return Type_Hint.{ size = 32, kind = .FLOAT,    key = token.text };
        case "float64"; return Type_Hint.{ size = 64, kind = .FLOAT,    key = token.text };
    }
    return Type_Hint.{ size = 0, kind = .UNKNOWN, key = token.text };
}
