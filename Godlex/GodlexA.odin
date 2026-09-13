
package godlex

import "base:runtime"

Godlex :: struct {
    r,rnext: rune,
    w: int,
    t: Token,
    includes,breadcrumbs: ^Lex_File,
    defines: map[string]string,
    messages: [dynamic]Message,
    error_count: int,
    allocator: runtime.Allocator,
}

Lex_File :: struct {
    path,data: string,
    depth,line_start: int,
    cursor: Source_Pos,
    // this is a stack-of-stacks (im sorry!)
    parent,next,prev: ^Lex_File,
}

Source_Pos :: struct {
    offset,line,column: int,
}

Message :: struct {
    fatal: bool,
    file: ^Lex_File,
    text: string,
    start, end: Source_Pos,
}

Token :: struct {
    file: ^Lex_File,
    start, end: Source_Pos,
    text: string,
    kind: Token_Kind,

    using value: struct #raw_union {
        as_u8: u8,
        as_int: int,
        as_float: f64,
        as_str: string,
    },
}

Token_Kind :: enum {
    INVALID,
    EOF,

    BYTE,
    INT,
    FLOAT,
    STR,

    IDENT,
    KEYWORD,

    // components of the printable ascii range:
    BANG='!',
    // double quote excluded cause that is for strings 
    HASH='#',
    DOLLAR='$',
    PERCENT='%',
    AMPERSAND='&',
    // single quote also excluded cause that is for bytes/chars
    OPEN_PAREN='(',
    CLOSE_PAREN=')',
    STAR='*',
    PLUS='+',
    COMMA=',',
    MINUS='-',
    DOT='.',
    FORWARD_SLASH='/',
    COLON=':',
    SEMICOLON=';',
    LEFT='<',
    EQUALS='=',
    RIGHT='>',
    QUESTION='?',
    AT='@',
    OPEN_BRACKET='[',
    BACKWARD_SLASH='\\',
    CLOSE_BRACKET=']',
    CARAT='^',
    // underscore excluded because that is a valid identifier char
    TICK='`',
    OPEN_BRACE='{',
    PIPE='|',
    CLOSE_BRACE='}',
    SQUIGGLY='~',

/*  -- CUSTOMIZATION! --
    There is an area in `get_token` where you can remove/add double or triple character tokens.
    Figure out the pattern and do it.
    You can also add/remove keywords in `KEYWORDS` to customize the keywords you want.
*/

    // double char tokens
    DOT_DOT,
    BANG_EQUALS,
    AMPERSAND_EQUALS,
    AMPERSAND_AMPERSAND,
    PLUS_EQUALS,
    MINUS_EQUALS,
    STAR_EQUALS,
    FORWARD_SLASH_EQUALS,
    MINUS_RIGHT,
    LEFT_EQUALS,
    LEFT_LEFT,
    EQUALS_EQUALS,
    RIGHT_EQUALS,
    RIGHT_RIGHT,
    CARAT_EQUALS,
    PIPE_EQUALS,
    PIPE_PIPE,

    // TRIPLE char tokens (yeesh)
    DOT_DOT_DOT,
    LEFT_LEFT_EQUALS,
    RIGHT_RIGHT_EQUALS,
}

KEYWORDS := [?]string {
    "true",
    "false",
    "none",
    "as",
    "decl",
    "forward",
    "push",
    "do",
    "if",
    "else",
    "while",
    "break",
    "continue",
    "fu",
    "return",
    "layout",
}
