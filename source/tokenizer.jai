
/*  Lexical Analysis   ❌ 
    Character Grouping ✅
    seriously, I don't understand why some language tokenizers go over 1000 lines
*/

Tokenizer :: struct {
    cursor: Source_Loc;
    text: string;
    r: u32;
    w: u32;
    line_offset: int;

    workspace: *Compiler_Workspace;
}

Token :: struct {
    using pos: Source_Loc;
    end: Source_Loc;
    text: string;
    kind: Token_Kind;
}

Token_Kind :: enum {
    INVALID;
    EOF;

    INTEGER;
    REAL;
    STRING;
    CHAR;

    DOT;
    PLUS;
    MINUS;
    MUL;
    DIV;
    MODULO;
    EXPONENT;
    ASSIGN;
    EQUALITY;
    LOGICAL_NOT;
    NOT_EQUALS;
    LESS;
    LESS_EQ;
    SHIFT_LEFT;
    GREATER;
    GREATER_EQ;
    SHIFT_RIGHT;
    BIT_AND;
    LOGICAL_AND;
    BIT_OR;
    LOGICAL_OR;
    BIT_NOT;
    SEMICOLON;
    COLON;
    COMMA;
    OPEN_PAREN;
    CLOSE_PAREN;
    OPEN_BRACKET;
    CLOSE_BRACKET;
    OPEN_BRACE;
    CLOSE_BRACE;
    HINT;

    IDENTIFIER;

    NONE;
    TRUE;
    FALSE;
    DECL;
    FORWARD;
    RETURN;
    BREAK;
    CONTINUE;
    IN;
    END;
    IF;
    ELSE;
    WHILE;
    FU;
    LOAD;
}

init_tokenizer_from_current_file :: (w: *Compiler_Workspace, t: *Tokenizer) -> bool {
    t.workspace = w;
    t.cursor.line = 1;
    ok: bool;
    t.text, ok = get_current_file_source(w);
    if !ok {
        return false;
    }
    next_rune(t);
    return true;
}

next_rune :: (using t: *Tokenizer) -> u32 {
    if cursor.offset < text.count {
        cursor.offset += w;
        r = character_utf8_to_utf32(text.data + cursor.offset, text.count);
        w = trailingBytesForUTF8[text.data[cursor.offset]] + 1;
        cursor.column = (cursor.offset - line_offset) + 1;
    }

    if cursor.offset >= text.count {
        r = ~(cast(u32) 0);
        w = 1;
    }

    return r;
}

skip_white_space :: (using t: *Tokenizer) {
    while cursor.offset < text.count {
        if r == {
            case #char " ";  #through;
            case #char "\r"; #through;
            case #char "\t";
                next_rune(t);
                continue;
            
            case #char "\n";
                next_rune(t);
                cursor.line += 1;
                line_offset = cursor.offset;
                cursor.column = 1;
                continue;
        }

        break;
    }
}

skip_digits :: (using t: *Tokenizer) {
    while cursor.offset < text.count {
        if #char "0" <= r && r <= #char "9" {
            next_rune(t);
            continue;
        }
        break;
    }
}

skip_hex_digits :: (using t: *Tokenizer) {
    while cursor.offset < text.count {
        if #char "0" <= r && r <= #char "9" {
            next_rune(t);
            continue;
        }

        if #char "A" <= r && r <= #char "F" {
            next_rune(t);
            continue;
        }

        if #char "a" <= r && r <= #char "f" {
            next_rune(t);
            continue;
        }
        break;
    }
}

skip_past_next_quote :: (using t: *Tokenizer) -> bool {
    start := cursor;
    while cursor.offset < text.count+1 {
        // ignore escaped quotes
        if r == #char "\\" {
            next_rune(t);
            if r == #char "\"" {
                next_rune(t);
            }
            continue;
        }
        
        if r == #char "\n" {
            push_location(workspace, start, cursor,
                "straight newline in string literal is not allowed. (watch your unclosed strings!)"
            );
            return false;
        }

        if r == ~(cast(u32) 0) {
            push_location(workspace, start, cursor,
                "unclosed string beyond End Of File"
            );
            return false;
        }

        if r == #char "\"" || r == #char "'" {
            break;
        }
        next_rune(t);
    }

    next_rune(t); // go thru closing quote
    return true;
}

skip_past_end_of_multiline_string :: (using t: *Tokenizer) -> bool {
    start := cursor;
    while cursor.offset < text.count+1 {
        if r == ~(cast(u32) 0) {
            push_location(workspace, start, cursor,
                "unclosed multi-line string beyond End Of File"
            );
            return false;
        }

        if r == #char "'" {
            next_rune(t);
            if r == #char "'" {
                next_rune(t);
                break;
            }
            continue;
        }

        next_rune(t);
    }
    return true;
}

unescape_string :: (using t: *Tokenizer, s: string) -> string, bool {
    b: String_Builder;
    b.allocator = workspace.allocator;
    if s.count < 2 {
        return "", false;
    }
    quote := s[0];
    if s[0] != s[s.count-1] {
        return "", false;
    }
    if !(quote == #char "\"" || quote == #char "'") {
        return "", false;
    }
    str := slice(s, 1, s.count - 2);

    i := 0;
    while i < str.count {
        c := str[i];
        if c == #char "\\" {
            i += 1;
            if i >= str.count {
                return "", false;
            }

            if str[i] == {
            case #char "n"; append(*b, "\n");
            case #char "t"; append(*b, "\t");
            case #char "r"; append(*b, "\r");
            case #char "\\"; append(*b, "\\");
            case #char "\""; append(*b, "\"");

            case;
                return "", false;
            }

            i += 1;
            continue;
        }

        r := character_utf8_to_utf32(str.data + i, str.count);
        w := trailingBytesForUTF8[str.data[i]] + 1;
        append(*b, cast(*u8) *r, w);
        i += w;
    }

    return builder_to_string(*b, do_reset = false), true;
}

is_identifier_char :: (r: u32) -> bool {
    if #char "A" <= r && r <= #char "Z" {
        return true;
    }

    if #char "a" <= r && r <= #char "z" {
        return true;
    }

    if #char "0" <= r && r <= #char "9" {
        return true;
    }

    if r == {
        //case #char "-"; #through;
        case #char "_";
            return true;
    }

    return false;
}

skip_identifier_chars :: (using t: *Tokenizer) {
    while cursor.offset < text.count {
        if is_identifier_char(r) {
            next_rune(t);
            continue;
        }
        break;
    }
}

get_token :: (using t: *Tokenizer) -> Token {
    skip_white_space(t);

    token: Token;
    token.pos = cursor;
    token.kind = .INVALID;

    r0 := r;
    r1 := next_rune(t);

    if r0 == {
    case ~(cast(u32) 0); 
        token.kind = .EOF;

    case #char "0"; 
        // short circuit and return hex value
        if r1 == #char "x" {
            token.kind = .INTEGER;
            next_rune(t); // skip the `x`
            skip_hex_digits(t);
            token.text = slice(text, token.offset, cursor.offset - token.offset);
            token.end = cursor;
            token.end.column -= 1;
            return token;
        } 
        #through;

    case #char "1"; #through;
    case #char "2"; #through;
    case #char "3"; #through;
    case #char "4"; #through;
    case #char "5"; #through;
    case #char "6"; #through;
    case #char "7"; #through;
    case #char "8"; #through;
    case #char "9";
        token.kind = .INTEGER;
        skip_digits(t);
        if r == #char "." {
            token.kind = .REAL;
            next_rune(t); // skip the dot
            skip_digits(t);
        }

    case #char "."; // edge case
        if #char "0" <= r1 && r1 <= #char "9" {
            token.kind = .REAL;
            next_rune(t);
            skip_digits(t);
            token.text = slice(text, token.offset, cursor.offset - token.offset);
            token.end = cursor;
            token.end.column -= 1;
            return token;
        } else {
            token.kind = .DOT;
        }

    case #char "'"; #through;
    case #char "\"";
        token.kind = .STRING;

        // multi line string 
        if r1 == #char "'" {
            ok := skip_past_end_of_multiline_string(t);
            if !ok {
                return Token.{ kind = .INVALID, pos = token.pos, end = cursor };
            }
            unescaped: string;
            unescaped, ok = unescape_string(t,
                slice(text, token.offset+1, cursor.offset-token.offset-2)
            );
            if !ok {
                push_location(workspace, token.pos, cursor,
                    "invalid string or escape sequence in string"
                );
                return Token.{ kind = .INVALID, pos = token.pos, end = cursor };
            }

            token.text = unescaped;
            token.end = cursor;
            token.end.column -= 1;
            return token;
        }

        single_quote := r0 == #char "'";
        ok := skip_past_next_quote(t);
        if !ok {
            return Token.{ kind = .INVALID, pos = token.pos, end = cursor };
        }

        unescaped: string;
        unescaped, ok = unescape_string(t, slice(text, token.offset, cursor.offset - token.offset));
        if !ok {
            push_location(workspace, token.pos, cursor,
                "invalid string or escape sequence in string"
            );
            return Token.{ kind = .INVALID, pos = token.pos, end = cursor };
        }

        token.text = unescaped;
        if single_quote && token.text.count == 1 {
            token.kind = .CHAR;
        }
        token.end = cursor;
        token.end.column -= 1;
        return token;

    case #char "+"; token.kind = .PLUS;
    case #char "-"; token.kind = .MINUS;
    case #char "*"; token.kind = .MUL;
    case #char "/"; token.kind = .DIV;
    case #char "%"; token.kind = .MODULO;
    case #char "^"; token.kind = .EXPONENT;
    case #char "="; 
        token.kind = .ASSIGN;
        if r1 == #char "=" {
            token.kind = .EQUALITY;
            next_rune(t);
        }
    case #char "!"; 
        token.kind = .LOGICAL_NOT;
        if r1 == #char "=" {
            token.kind = .NOT_EQUALS;
            next_rune(t);
        }
    case #char "<";
        token.kind = .LESS;
        if r1 == #char "=" {
            token.kind = .LESS_EQ;
            next_rune(t);
        }
        if r1 == #char "<" {
            token.kind = .SHIFT_LEFT;
            next_rune(t);
        }
    case #char ">";
        token.kind = .GREATER;
        if r1 == #char "=" {
            token.kind = .GREATER_EQ;
            next_rune(t);
        }
        if r1 == #char ">" {
            token.kind = .SHIFT_RIGHT;
            next_rune(t);
        }
    case #char "&"; 
        token.kind = .BIT_AND;
        if r1 == #char "&" {
            token.kind = .LOGICAL_AND;
            next_rune(t);
        }
    case #char "|"; 
        token.kind = .BIT_OR;
        if r1 == #char "|" {
            token.kind = .LOGICAL_OR;
            next_rune(t);
        }
    case #char "~"; token.kind = .BIT_NOT;
    case #char ";"; token.kind = .SEMICOLON;
    case #char ":"; token.kind = .COLON;
    case #char ","; token.kind = .COMMA;
    case #char "("; token.kind = .OPEN_PAREN;
    case #char ")"; token.kind = .CLOSE_PAREN;
    case #char "["; token.kind = .OPEN_BRACKET;
    case #char "]"; token.kind = .CLOSE_BRACKET;
    case #char "{"; token.kind = .OPEN_BRACE;
    case #char "}"; token.kind = .CLOSE_BRACE;
    case #char "@"; token.kind = .HINT;

    /*  NOTE: I am NOT doing block comments in this language
        instead it will be python-style with multi-line strings serving as "comments"
        why? because comment nesting is annoying 
        and I'd like the tokenizer (character grouper) to be as dumb as possible
    */
    case #char "#"; 
        while r != #char "\n" {
            next_rune(t);
            if r == ~(cast(u32) 0) {
                return Token.{ kind = .EOF };
            }
        }
        return get_token(t);

    case;
        if is_identifier_char(r0) {
            token.kind = .IDENTIFIER;
            skip_identifier_chars(t);
        }

        if slice(text, token.offset, cursor.offset - token.offset) == {
        case "none";   token.kind = .NONE;
        case "true";   token.kind = .TRUE;
        case "false";  token.kind = .FALSE;

        case "decl";      token.kind = .DECL;
        case "forward";   token.kind = .FORWARD;
        case "return";    token.kind = .RETURN;
        case "break";     token.kind = .BREAK;
        case "continue";  token.kind = .CONTINUE;
        case "in";        token.kind = .IN;
        case "end";       token.kind = .END;
        case "if";        token.kind = .IF;
        case "else";      token.kind = .ELSE;
        case "while";     token.kind = .WHILE;
        case "fu";        token.kind = .FU;
        case "load";      token.kind = .LOAD;
        }
    }

    token.text = slice(text, token.offset, cursor.offset - token.offset);
    token.end = cursor;
    token.end.column -= 1;
    return token;
}

pprint_token :: (token: Token) -> string {
    // HACK: IDK HOW TO ESCAPE THE `%` IN THIS CASE!!
    if token.text == "%" {
        return "[MOD]";
    }
    return sprint("[% %]", token.text, token.kind);
}

