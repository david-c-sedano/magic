
package godlex

import "base:runtime"

import "core:strings"
import "core:strconv"
import "core:unicode/utf8"
import "core:os"
import "core:fmt"

import vmem "core:mem/virtual"

MAX_INCLUDE_DEPTH :: 69

push_lex_file :: proc(g: ^Godlex) -> ^Lex_File {
    file := new(Lex_File,g.allocator)
    file.parent = g.includes 
    file.cursor.line = 1
    if g.includes != nil {
        file.depth = g.includes.depth+1
    } else {
        file.depth = -1
    }
    g.includes = file
    return file
}

do_include :: proc(g: ^Godlex, path: string, data: string) -> ^Lex_File {
    if g.includes != nil && g.includes.depth >= MAX_INCLUDE_DEPTH {
        warning(g, "cyclic macro/include recursion detected")
        return nil
    }

    file := push_lex_file(g)
    file.path = path
    file.data = data
    load_rune(g)
    return file 
}

pop_lex_file :: proc(g: ^Godlex) -> ^Lex_File {
    flush_messages(g)
    file := g.includes 
    if file == nil {
        return nil
    }
    g.includes = file.parent
    return g.includes
}

current_file :: proc(g: ^Godlex) -> ^Lex_File {
    if g.includes == nil {
        return nil
    }
    file := g.includes
    for file.next != nil {
        file = file.next
    }
    return file
}

// `parent`,`next`, and `prev` form a kind of matrix/grid
// `snapshot` pushes an ENTIRE include-chain axis
snapshot :: proc(g: ^Godlex) {
    // I could've done something like
    // Lex_Breadcrumb { file: ^Lex_File, prev: ^Lex_Breadcrumb }
    // but I just reuse the `next` and `parent` fields
    // breadcrumbs are a helper to tell you which axis to return to
    crumb := new(Lex_File,g.allocator)
    crumb.next = g.includes
    crumb.parent = g.breadcrumbs
    g.breadcrumbs = crumb

    include := g.includes
    for include != nil {
        file := include
        for file.next != nil {
            file = file.next
        }
        snapshot := new(Lex_File,g.allocator)
        snapshot^ = file^
        file.next = snapshot
        snapshot.prev = file
        include = include.parent
    }
    append(&g.prev_hist_sizes, len(g.history))
}

// `restore/commit` will pop an entire axis
// allowing for infinite lookahead even across `do_include` boundaries
restore :: proc(g: ^Godlex) {
    crumb := g.breadcrumbs
    if crumb == nil do return
    g.includes = crumb.next
    g.breadcrumbs = crumb.parent

    include := g.includes
    for include != nil {
        file := include
        for file.next != nil {
            file = file.next
        }
        if file.prev != nil {
            file.prev.next = nil
        }
        include = include.parent
    }
    load_rune(g)

    prev_hist_size,ok := pop_safe(&g.prev_hist_sizes)
    assert(ok)
    resize(&g.history, prev_hist_size)
}

commit :: proc(g: ^Godlex) {
    crumb := g.breadcrumbs
    if crumb == nil do return
    include := crumb.next
    g.breadcrumbs = crumb.parent

    hist_start := g.prev_hist_sizes[len(g.prev_hist_sizes)-1]

    for include != nil {
        file := include
        for file.next != nil {
            file = file.next
        }
        if file.prev != nil {
            target := file.prev
            // patch tokens in the history so they point to the committed file 
            for &token in g.history[hist_start:] {
                if token.file == file {
                    token.file = target
                }
            }
            older := target.prev
            target^ = file^
            target.prev = older
            target.next = nil
            if older != nil {
                older.next = target
            }
        }
        include = include.parent
    }
    pop(&g.prev_hist_sizes)
}

make_character_grouper :: proc(path: string, data: string, a: runtime.Allocator) -> (^Godlex, ^Lex_File) {
    g := new(Godlex)
    g.allocator = a
    g.messages = make([dynamic]Message, g.allocator)
    g.history = make([dynamic]Token, g.allocator)
    g.prev_hist_sizes = make([dynamic]int, g.allocator)
    file := push_lex_file(g)
    file.path = path
    file.data = data
    next_rune(g) // CHEAT a character of lookeahead
    return g, file
}

delete_character_grouper :: proc(g: ^Godlex) {
    delete(g.defines)
    free(g)
}

load_rune :: proc(g: ^Godlex) {
    file := current_file(g) 
    if file.cursor.offset < len(file.data) {
        g.r, g.w = utf8.decode_rune_in_string(file.data[file.cursor.offset:])
    } else {
        g.r = utf8.RUNE_EOF
        g.w = 1
    }
    if file.cursor.offset + g.w < len(file.data) {
        g.rnext,_ = utf8.decode_rune_in_string(file.data[file.cursor.offset+g.w:])
    } else {
        g.rnext = utf8.RUNE_EOF
    }
}

next_rune :: proc(g: ^Godlex) -> rune {
    file := current_file(g) 
	if file.cursor.offset < len(file.data) {
		file.cursor.offset += g.w
        load_rune(g)
		file.cursor.column = (file.cursor.offset - file.line_start) + 1
	}

	if file.cursor.offset >= len(file.data) {
		g.r = utf8.RUNE_EOF
		g.w = 1
	}
	return g.r
}

skip_whitespace :: proc(g: ^Godlex) -> (newline: bool) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        switch g.r {
        case ' ', '\t', '\r':
            next_rune(g)

        case '\n':
            newline = true
            next_rune(g)
            file.cursor.line += 1
            file.line_start = file.cursor.offset
            file.cursor.column = 1

        case:
            return
        }
    }
    return
}

skip_hex_digits :: proc(g: ^Godlex) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        switch g.r {
        case '0'..='9', 'a'..='f', 'A'..='F':
            next_rune(g)
        case:
            return
        }
    }
}

skip_digits :: proc(g: ^Godlex) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        switch g.r {
        case '0'..='9':
            next_rune(g)
        case:
            return
        }
    }
}

skip_in_string :: proc(g: ^Godlex, delim: rune) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        switch g.r {
        case '\\':
            next_rune(g)
            if g.r != utf8.RUNE_EOF {
                next_rune(g)
            }

        case utf8.RUNE_EOF, delim:
            next_rune(g)
            return

        // MAYBE this is a bad idea? LOL
        case '\n':
            next_rune(g)
            file.cursor.line += 1
            file.line_start = file.cursor.offset
            file.cursor.column = 1

        case:
            next_rune(g)
        }
    }
}

is_identifier_char :: proc(r: rune) -> bool {
    switch r {
    case '0'..='9', 'A'..='Z', 'a'..='z', '_':
        return true
    }
    return false
}

skip_identifier_chars :: proc(g: ^Godlex) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        if is_identifier_char(g.r) {
            next_rune(g)
            continue
        }
        break
    }
}

skip_past_newline :: proc(g: ^Godlex) {
    file := current_file(g) 
    for file.cursor.offset < len(file.data) {
        if g.r == '\n' {
            next_rune(g)
            file.cursor.line += 1
            file.line_start = file.cursor.offset
            file.cursor.column = 1
            return
        }
        next_rune(g)
    }
}

skip_block_comment :: proc(g: ^Godlex) {
    file := current_file(g)
    next_rune(g) // go thru the `*`

    depth := 1 // IT REALLY IS THAT SIMPLE!!!

    for file.cursor.offset < len(file.data) {
        if g.r == '/' && g.rnext == '*' {
            next_rune(g)
            next_rune(g)
            depth += 1
            continue
        }

        if g.r == '*' && g.rnext == '/' {
            next_rune(g)
            next_rune(g)
            depth -= 1
            if depth == 0 {
                return
            }
            continue
        }

        if g.r == '\n' {
            next_rune(g)
            file.cursor.line += 1
            file.line_start = file.cursor.offset
            file.cursor.column = 1
            continue
        }

        next_rune(g)
    }
}

get_token :: proc(g: ^Godlex, newline := false) -> Token {
    file := current_file(g) 
    newline := skip_whitespace(g) || newline

    token: Token
    token.newline = newline
    token.file = file
    token.start = file.cursor
    token.kind = .INVALID

    r0 := g.r
    r1 := next_rune(g)
    r2 := g.rnext

    switch r0 {
    case '/': 
        token.kind = .FORWARD_SLASH
        if r1 == '=' {
            token.kind = .FORWARD_SLASH_EQUALS
            next_rune(g)
        }
        if r1 == '/' {
            next_rune(g)
            skip_past_newline(g)
            return get_token(g, true)
        }
        if r1 == '*' {
            line_b4 := file.cursor.line
            skip_block_comment(g)
            crossed := file.cursor.line > line_b4
            return get_token(g, newline || crossed)
        }

    case utf8.RUNE_EOF:
        file := g.includes
        if file.parent != nil {
            pop_lex_file(g)
            load_rune(g)
            return get_token(g, newline)
        }
        token.kind = .EOF
        token.end = token.start
        return token

    case '0':
        if r1 == 'x' {
            _,ok := to_nibble(r2)
            if !ok {
                token.kind = .INT
                break
            }
            token.kind = .INT
            next_rune(g)
            skip_hex_digits(g)
            break
        }
        fallthrough
    case '1'..='9':
        token.kind = .INT
        skip_digits(g)
        if g.r == '.' {
            token.kind = .FLOAT
            next_rune(g); // skip the dot
            skip_digits(g);
        }

    case '\'':
        token.kind = .BYTE
        skip_in_string(g, '\'')

    case '"':
        token.kind = .STR
        skip_in_string(g, '"') 

    case '.': 
        // annoying edge case
        if '0' <= r1 && r1 <= '9' {
            token.kind = .FLOAT
            next_rune(g);
            skip_digits(g);
            break
        }
/* ---------- GODLEX CHARACTER CASES BEGIN  ---------- */
        token.kind = .DOT
        if r1 == '.' {
            token.kind = .DOT_DOT
            next_rune(g)
            if r2 == '.' {
                token.kind = .DOT_DOT_DOT
                next_rune(g)
            }
        }
        
    case '!':  token.kind = .BANG
        if r1 == '=' {
            token.kind = .BANG_EQUALS 
            next_rune(g)
        }
    case '#': token.kind = .HASH
    case '$': token.kind = .DOLLAR
    case '%': token.kind = .PERCENT
    case '&': token.kind = .AMPERSAND
        if r1 == '=' {
            token.kind = .AMPERSAND_EQUALS 
            next_rune(g)
        }
        if r1 == '&' {
            token.kind = .AMPERSAND_AMPERSAND
            next_rune(g)
        }
    case '(': token.kind = .OPEN_PAREN
    case ')': token.kind = .CLOSE_PAREN
    case '*': token.kind = .STAR
        if r1 == '=' {
            token.kind = .STAR_EQUALS
            next_rune(g)
        }
    case '+': token.kind = .PLUS
        if r1 == '=' {
            token.kind = .PLUS_EQUALS
            next_rune(g)
        }
    case ',': token.kind = .COMMA
    case '-': token.kind = .MINUS
        if r1 == '=' {
            token.kind = .MINUS_EQUALS
            next_rune(g)
        }
        if r1 == '>' {
            token.kind = .MINUS_RIGHT
            next_rune(g)
        }
    case ':': token.kind = .COLON
    case ';': token.kind = .SEMICOLON
    case '<': token.kind = .LEFT
        if r1 == '=' {
            token.kind = .LEFT_EQUALS
            next_rune(g)
        }
        if r1 == '<' {
            token.kind = .LEFT_LEFT
            next_rune(g)
            if r2 == '=' {
                token.kind = .LEFT_LEFT_EQUALS
                next_rune(g)
            }
        }
    case '=': token.kind = .EQUALS
        if r1 == '=' {
            token.kind = .EQUALS_EQUALS
            next_rune(g)
        }
    case '>': token.kind = .RIGHT
        if r1 == '=' {
            token.kind = .RIGHT_EQUALS
            next_rune(g)
        }
        if r1 == '>' {
            token.kind = .RIGHT_RIGHT
            next_rune(g)
            if r2 == '=' {
                token.kind = .RIGHT_RIGHT_EQUALS
                next_rune(g)
            }
        }
    case '?': token.kind = .QUESTION
    case '@': token.kind = .AT
    case '[': token.kind = .OPEN_BRACKET
    case '\\': token.kind = .BACKWARD_SLASH
    case ']': token.kind = .CLOSE_BRACKET
    case '^': token.kind = .CARAT
        if r1 == '=' {
            token.kind = .CARAT_EQUALS 
            next_rune(g)
        }
    case '`': token.kind = .TICK
    case '{': token.kind = .OPEN_BRACE
    case '|': token.kind = .PIPE
        if r1 == '=' {
            token.kind = .PIPE_EQUALS 
            next_rune(g)
        }
        if r1 == '|' {
            token.kind = .PIPE_PIPE
            next_rune(g)
        }
    case '}': token.kind = .CLOSE_BRACE
    case '~': token.kind = .SQUIGGLY

    case:
        if is_identifier_char(r0) {
            token.kind = .IDENT
            skip_identifier_chars(g)
        }
    }

    token.text = file.data[token.start.offset:file.cursor.offset]
    token.end = file.cursor
    token.end.column -= 1

    #partial switch token.kind {
    case .IDENT:
        for word in KEYWORDS {
            if token.text == word {
                token.kind = .KEYWORD
                break
            }
        }
    case .BYTE:
        unescaped, ok := unescape(g, token.text)
        if !ok || len(unescaped) != 1 {
            bad_token(g, token, "invalid byte literal")
            token.kind = .INVALID
            return token
        }
        token.as_u8 = unescaped[0] 
    case .INT:
        value, sug := strconv.parse_int(token.text)
        assert(sug, token.text) // if this (or `parse_f64`) fails its a bug
        token.as_int = value 
    case .FLOAT:
        value, sug := strconv.parse_f64(token.text)
        assert(sug, token.text)
        token.as_float = value 
    case .STR:
        unescaped, ok := unescape(g, token.text)
        if !ok {
            bad_token(g, token, "unclosed/invalid string")
            token.kind = .INVALID
            return token
        }
        token.as_str = unescaped
    }
    return token
}

to_nibble :: proc(r: rune) -> (u8, bool) {
    switch {
    case '0' <= r && r <= '9':
        return u8(r - '0'), true
    case 'a' <= r && r <= 'f':
        return u8(r - 'a' + 10), true
    case 'A' <= r && r <= 'F':
        return u8(r - 'A' + 10), true
    }

    return 0, false
}

unescape :: proc(g: ^Godlex, str: string) -> (string, bool) {
    if len(str) < 2 || str[0] != str[len(str)-1] {
        return "", false // unclosed string
    }
	b := strings.builder_make(allocator=g.allocator)

    src := str[1:len(str)-1]
    i := 0
	for {
        if i >= len(src) {
            break
        }
        c := src[i]

		if c != '\\' {
            strings.write_byte(&b, c)
            i += 1
			continue
		}

		if i >= len(src)-1 {
            strings.write_byte(&b, '\\')
			break
		}

		escaped := src[i+1] 
		switch escaped {
    	case '0':  strings.write_byte(&b, 0);    i+=2
        case '\'': strings.write_byte(&b, '\''); i+=2
        case '`':  strings.write_byte(&b, '`');  i+=2
		case '\\': strings.write_byte(&b, '\\'); i+=2
		case '"':  strings.write_byte(&b, '"');  i+=2
		case 'n':  strings.write_byte(&b, '\n'); i+=2
		case 'r':  strings.write_byte(&b, '\r'); i+=2
		case 't':  strings.write_byte(&b, '\t'); i+=2
		case 'x', 'X':
			value: u8
			digits := 0
            i+=2
			for digits < 2 && i < len(src) {
				nibble, ok := to_nibble(cast(rune) src[i])
				if !ok {
					break
				}
				value = value << 4 | nibble
				digits += 1
                i+=1
			}
            strings.write_byte(&b, value)

		case:
            strings.write_byte(&b, '\\')
            i+=1
		}
	}

	return strings.to_string(b), true 
}

group :: proc(g: ^Godlex, expect := Token_Kind.INVALID) -> Token { 
    newline := false
    column := -1

    for {
        g.t = get_token(g)
        newline = newline || g.t.newline
        if column < 0 || g.t.newline {
            column = g.t.start.column
        }
        if g.t.kind == .IDENT {
            name := g.t
            if name.text in g.defines {
                tempfname := fmt.aprintf("MACRO:%s",name.text,allocator=g.allocator)
                include := do_include(g, tempfname, g.defines[name.text])
                if include == nil {
                    bad_token(g, name, "while expanding macro")
                    return Token { kind = .INVALID, start=name.start, end=name.end }
                }
                continue
            }
            break
        }
        if g.t.kind != .HASH {
            break
        }

        hash := g.t
        directive := get_token(g)
        /* PREPROCESSOR */
        switch directive.text {
        case "include":
            path := get_token(g)
            if path.kind != .STR {
                bad_token(g, path, "expected string after `#include`")
                return Token { kind = .INVALID, start=hash.start, end=path.end }
            }
            data, err := os.read_entire_file(path.as_str,context.allocator)
            if err != nil {
                bad_token(g, path, "cannot `#include` file that doesn't exist")
                return Token { kind = .INVALID, start=hash.start, end=path.end }
            }
            include := do_include(g, path.as_str, cast(string) data)
            if include == nil {
                bad_token(g, path, "while including")
                return Token { kind = .INVALID, start=hash.start, end=path.end }
            }
            continue

        case "define":
            name := get_token(g)
            if name.kind != .IDENT {
                bad_token(g, name, "expected macro name after `#define`")
                return Token { kind = .INVALID, start=hash.start, end=name.end }
            }
            file := current_file(g)
            start := file.cursor.offset
            end := start
            for end < len(file.data) && file.data[end] != '\n' {
                end+=1
            }
            g.defines[name.text] = file.data[start:end]
            for file.cursor.offset < end {
                next_rune(g)
            }
            continue

        case "ifdef":
            define := get_token(g)
            if define.kind != .IDENT {
                bad_token(g, define, "expected macro/symbol name after `#ifdef`")
                return Token { kind = .INVALID, start=hash.start, end=define.end }
            }
            if !(define.text in g.defines) {
                skip_branch(g)
            }
            continue

        case "ifndef":
            define := get_token(g)
            if define.kind != .IDENT {
                bad_token(g, define, "expected macro/symbol name after `#ifdef`")
                return Token { kind = .INVALID, start=hash.start, end=define.end }
            }
            if define.text in g.defines {
                skip_branch(g)
            }
            continue

        case "else":
            skip_branch(g) // LOL
            continue
        case "endif":
            // yes this is an absolute war crime, im sorry!
            continue

        case: 
            bad_token(g, directive, "unknown preprocessor directive")
            return Token { kind = .INVALID, start=hash.start, end=directive.end }
        }
    }

    g.t.newline = newline
    g.t.column = column
    append(&g.history,g.t)
    if expect != .INVALID && g.t.kind != expect {
        wrong := g.t
        wrong.kind = .INVALID
        return wrong
    }
    return g.t
}

skip_branch :: proc(g: ^Godlex) {
    file := current_file(g)
    depth := 0

    for file.cursor.offset < len(file.data) {
        // cause of `const char* shrekt = "lmao #endif get trolled";` 
        if g.r == '"' || g.r == '\'' {
            delim := g.r
            next_rune(g)
            skip_in_string(g, delim)
            continue
        }
        // similar reason
        if g.r == '/' && g.rnext == '*' {
            next_rune(g)
            skip_block_comment(g)
            continue
        }
        if g.r == '/' && g.rnext == '/' {
            skip_past_newline(g)
            continue
        }

        if g.r == '#' {
            snapshot(g)
            hash := get_token(g)
            directive := get_token(g)
            if hash.kind == .HASH {
                switch directive.text {
                case "ifdef","ifndef":
                    depth+=1

                case "endif":
                    if depth == 0 {
                        commit(g)
                        return
                    }
                    depth-=1

                case "else":
                    if depth == 0 {
                        commit(g)
                        return
                    }
                }
            }
            restore(g) 
        }

        // WE DO NOT FOLLOW *DRY* [[DONT REPEAT YOURSELF]] PROPAGANDA HERE!!!
        // INSTEAD, WRITE *WET* [[WE ENJOY TYPING]] CODE!!!
        if g.r == '\n' {
            next_rune(g)
            file.cursor.line += 1
            file.line_start = file.cursor.offset
            file.cursor.column = 1
        } else {
            next_rune(g)
        }
    }
}

group_ahead :: proc(g: ^Godlex, n: int, expect := Token_Kind.INVALID) -> Token {
    assert(n>=1)
    snapshot(g)
    token := group(g, expect)
    for _ in 0..<n-1 {
        token = group(g) 
    }
    if expect == .INVALID {
        restore(g)
        return token
    }
    if token.kind != .INVALID {
        commit(g)
    } else {
        restore(g)
    }
    return token
}

warning :: proc(g: ^Godlex, msg_text: string, format: ..any) {
    msg: Message
    msg.file = current_file(g)
    msg.text = fmt.aprintf(msg_text, ..format, allocator=g.allocator)
    append(&g.messages, msg)
}

bad_token :: proc(g: ^Godlex, token: Token, msg_text: string, format: ..any) {
    msg: Message
    msg.fatal = true
    msg.file = token.file 
    msg.text = fmt.aprintf(msg_text, ..format, allocator=g.allocator)
    msg.start,msg.end = token.start,token.end
    g.error_count += 1
    append(&g.messages, msg)
}

error :: proc(g: ^Godlex, span: [2]int, msg_text: string, format: ..any) {
    msg: Message
    msg.fatal = true 
    msg.file = nil
    msg.span = span
    msg.text = fmt.aprintf(msg_text, ..format, allocator=g.allocator)
    append(&g.messages, msg)
    g.error_count += 1
}

flush_messages :: proc(g: ^Godlex) {
    for msg in g.messages {
        if !msg.fatal {
            fmt.printf("[WARNING] %s from `%s`\n", msg.text, msg.file.path)
            continue
        }
        // if message does not span multiple tokens across many files
        if msg.file != nil {
            fmt.printf("[SYNTAX ERROR] %s\n", msg.text)
            fmt.printf("  --> here from (%d:%d) to (%d:%d) in `%s`\n", 
                msg.start.line, msg.start.column, msg.end.line, msg.end.column,
                msg.file.path 
            )

            assert(msg.start.line == msg.end.line)
            assert(msg.start.column <= msg.end.column)
            fmt.printf("\n\t%s\n", get_line_text(msg.file.data, msg.start.line))
            underline := caret_line(g, msg.start, msg.end)
            fmt.printf("\t%s\n", underline)
            continue
        }
        // else print expanded source view
        fmt.printf("[ERROR] %s\n", msg.text)
        spans := make(map[^Lex_File][dynamic]Token,g.allocator)
        for token in g.history[msg.span[0]:msg.span[1]] {
            if token.file not_in spans {
                spans[token.file] = make([dynamic]Token,g.allocator)
            }
            append(&spans[token.file], token)
        }
        for file, span in spans {
            print_source_view(g, file, span[0].start, span[len(span)-1].end)
            fmt.println()
        }
    }
    clear(&g.messages)
}

print_source_view :: proc(g: ^Godlex, file: ^Lex_File, start,end: Source_Pos) {
    fmt.printf("  --> from (%d:%d) to (%d:%d) in stream `%s`\n", 
        start.line, start.column, end.line, end.column,
        file.path 
    )
    b := strings.builder_make(allocator=g.allocator)
    strings.write_string(&b, "\x1b[31m") //RED
    for line_num in start.line..=end.line {
        line := get_line_text(file.data, line_num)
        strings.write_string(&b, "\t")
        for c, i in line {
            column := i+1
            strings.write_rune(&b, c)
        }
        strings.write_byte(&b, '\n')
    }
    strings.write_string(&b, "\x1b[0m")
    fmt.print(strings.to_string(b))
}

get_line_text :: proc(source: string, line: int) -> string {
    start := 0
    curr_line := 1
    outer: for r, i in source {
        if curr_line == line {
            end := i
            inner: for j in i..=len(source) {
                if j >= len(source) || source[j] == '\n' {
                    end = j
                    break inner
                }
            }
            return source[start:end]
        }
        if r == '\n' {
            curr_line += 1
            start = i + 1
        }
    }
    return ""
}

caret_line :: proc(g: ^Godlex, start,end: Source_Pos) -> string {
    b := strings.builder_make(allocator=g.allocator) 
    strings.write_string(&b, "\x1b[31m")
    for i in 1..=end.column { 
        if i >= start.column {
            strings.write_byte(&b, '^')
        } else {
            strings.write_byte(&b, ' ')
        }
    }
    strings.write_string(&b, "\x1b[0m")
    return strings.to_string(b)
}

has_error :: proc(g: ^Godlex) -> bool {
    if g.error_count > 0 {
        flush_messages(g)
        return true
    }
    return false
}
