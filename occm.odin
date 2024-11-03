package occm

import "core:fmt"
import "core:strings"
import "core:os"
import "core:strconv"
import "core:slice"
import path "core:path/filepath"
import "core:container/queue"

LOG :: #config(LOG, false)

Token_Type :: enum {
    EndOfFile,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Minus,
    MinusMinus, // --
    Bang,
    QuestionMark,
    Colon,
    Tilde,
    Star,
    Percent,
    Carat,
    ForwardSlash,
    Plus,
    Comma,
    PlusPlus, // ++
    And,
    DoubleAnd, // &&
    Pipe,
    DoublePipe, // ||
    More,
    Less,
    MoreEqual, // >=
    LessEqual, // <=
    Equal,
    DoubleEqual,
    BangEqual, // !=
    LessLess,  // <<
    MoreMore,  // >>
    PlusEqual, // +=
    MinusEqual, // -=
    StarEqual, // *=
    SlashEqual, // /=
    PercentEqual, // %=
    CaratEqual, // ^=
    PipeEqual, // |=
    AndEqual, // &=
    LessLessEqual, // <<=
    MoreMoreEqual, // >>=

    IntKeyword,
    VoidKeyword,
    ReturnKeyword,
    IfKeyword,
    ElseKeyword,
    GotoKeyword,
    WhileKeyword,
    DoKeyword,
    ForKeyword,
    ContinueKeyword,
    BreakKeyword,
    SwitchKeyword,
    CaseKeyword,
    DefaultKeyword,
    Ident,
    IntConstant,
    Semicolon,
}

Token_Data :: union {int}

Token :: struct {
    type: Token_Type,
    text: string,
    data: Token_Data,

    // For lexical error messages
    line: int,
    char: int,
}

CONSUMED_SIZE :: 8
Lexer :: struct {
    code: string,
    code_index: int,

    // For lexical error messages
    file: string,
    line: int,
    char: int,

    // Queue of consumed tokens
    // This is to avoid having to construct a temporary lexer when peeking tokens
    consumed: [CONSUMED_SIZE]Token,
    consumed_head: int,
    consumed_tail: int,
}

lexer_advance :: proc(lexer: ^Lexer) {
    c := lexer.code[lexer.code_index]
    lexer.code_index += 1
    if c == '\n' {
        lexer.line += 1
        lexer.char = 0
    }
    else {
        lexer.char += 1
    }
}

lexer_eat_whitespace :: proc(lexer: ^Lexer) {
    for lexer.code_index < len(lexer.code) && is_ascii_whitespace_byte(lexer.code[lexer.code_index]) {
        lexer_advance(lexer)
    }
}

lexer_eat_until_newline :: proc(lexer: ^Lexer) {
    for lexer.code_index < len(lexer.code) && lexer.code[lexer.code_index] != '\n' {
        lexer_advance(lexer)
    }
}

lexer_eat_multiline_comment :: proc(lexer: ^Lexer) {
    assert(lexer.code[lexer.code_index] == '/' && lexer.code[lexer.code_index + 1] == '*')
    lexer_advance(lexer)
    lexer_advance(lexer)

    for lexer.code_index < len(lexer.code) - 1 \
        && !(lexer.code[lexer.code_index] == '*' && lexer.code[lexer.code_index + 1] == '/') {
        lexer_advance(lexer)
    }

    lexer_advance(lexer)
    lexer_advance(lexer)
}

consumed_is_empty :: proc(lexer: ^Lexer) -> bool {
    return lexer.consumed_head == lexer.consumed_tail
}

consumed_is_full :: proc(lexer: ^Lexer) -> bool {
    return (lexer.consumed_head == 0 && lexer.consumed_tail == CONSUMED_SIZE - 1) || lexer.consumed_tail == lexer.consumed_head - 1
}

push_to_consumed :: proc(lexer: ^Lexer, token: Token) {
    assert(!consumed_is_full(lexer))
    lexer.consumed[lexer.consumed_tail] = token
    lexer.consumed_tail += 1
    if lexer.consumed_tail >= CONSUMED_SIZE do lexer.consumed_tail = 0
}

consumed_at :: proc(lexer: ^Lexer, index: int) -> Token {
    assert(index < consumed_len(lexer))
    buffer_index := lexer.consumed_head + index
    if buffer_index >= CONSUMED_SIZE {
        buffer_index -= CONSUMED_SIZE
    }
    return lexer.consumed[buffer_index]
}

consumed_len :: proc(lexer: ^Lexer) -> int {
    if lexer.consumed_head <= lexer.consumed_tail {
        return lexer.consumed_tail - lexer.consumed_head
    }
    else {
        start_len := lexer.consumed_tail
        end_len := CONSUMED_SIZE - lexer.consumed_head
        return start_len + end_len
    }
}

pop_from_consumed :: proc(lexer: ^Lexer) -> Token {
    assert(!consumed_is_empty(lexer))
    token := lexer.consumed[lexer.consumed_head]
    lexer.consumed_head += 1
    if lexer.consumed_head >= CONSUMED_SIZE do lexer.consumed_head = 0
    return token
}

lex_error :: proc(lexer: ^Lexer) {
    fmt.printfln("%v(%v:%v) Syntax error: Unexpected character %c", lexer.file, lexer.line + 1, lexer.char + 1, lexer.code[lexer.code_index])
    os.exit(2)
}

consume_int_constant_token :: proc(lexer: ^Lexer) {
    assert(is_ascii_digit_byte(lexer.code[lexer.code_index]))

    start_index := lexer.code_index
    for lexer.code_index < len(lexer.code) && is_ascii_digit_byte(lexer.code[lexer.code_index]) {
        lexer_advance(lexer)
    }

    // We need to catch identifiers that start with a number here, and are therefore invalid.
    if lexer.code_index < len(lexer.code) && is_ascii_alpha_byte(lexer.code[lexer.code_index]) {
        lex_error(lexer)
    }

    text := lexer.code[start_index:lexer.code_index]
    token := Token {
        type = .IntConstant,
        text = text,
        data = strconv.atoi(text),
        line = lexer.line,
        char = lexer.char,
    }
    push_to_consumed(lexer, token)
}

consume_keyword_or_ident_token :: proc(lexer: ^Lexer) {
    assert(is_ident_start_byte(lexer.code[lexer.code_index]))
    start_index := lexer.code_index 
    lexer_advance(lexer)

    for lexer.code_index < len(lexer.code) && is_ident_tail_byte(lexer.code[lexer.code_index]) {
        lexer_advance(lexer)
    }

    text := lexer.code[start_index:lexer.code_index]
    token: Token = ---
    switch {
        case text == "return":
            token = Token{
                type = .ReturnKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "int":
            token = Token{
                type = .IntKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "void":
            token = Token{
                type = .VoidKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "if":
            token = Token{
                type = .IfKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "else":
            token = Token{
                type = .ElseKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "goto":
            token = Token{
                type = .GotoKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "while":
            token = Token{
                type = .WhileKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "do":
            token = Token{
                type = .DoKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "for":
            token = Token{
                type = .ForKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }


        case text == "continue":
            token = Token{
                type = .ContinueKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }


        case text == "break":
            token = Token{
                type = .BreakKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }


        case text == "switch":
            token = Token{
                type = .SwitchKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }


        case text == "case":
            token = Token{
                type = .CaseKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case text == "default":
            token = Token{
                type = .DefaultKeyword,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }

        case:
            token = Token{
                type = .Ident,
                text = text,
                line = lexer.line,
                char = lexer.char,
            }
    }
    push_to_consumed(lexer, token)
}

is_ascii_digit_byte :: proc(c: u8) -> bool {
    return '0' <= c && c <= '9'
}

is_ascii_alpha_byte :: proc(c: u8) -> bool {
    return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

is_ascii_whitespace_byte :: proc(c: u8) -> bool {
    return c == '\n' || c == '\r' || c == ' ' || c == '\f' || c == '\t'
}

is_ident_start_byte :: proc(c: u8) -> bool {
    return is_ascii_alpha_byte(c) || c == '_'
}

is_ident_tail_byte :: proc(c: u8) -> bool {
    return is_ascii_alpha_byte(c) || is_ascii_digit_byte(c) || c == '_'
}

consume_token :: proc(lexer: ^Lexer) {
    // @TODO: This for loop is kind of gross. Is there a better way here?
    token: Token = ---
    for {
        lexer_eat_whitespace(lexer)
        if lexer.code_index >= len(lexer.code) {
            push_to_consumed(lexer, Token{
                type = .EndOfFile,
                line = lexer.line,
                char = lexer.char
            })
            return
        }

        if is_ascii_digit_byte(lexer.code[lexer.code_index]) {
            consume_int_constant_token(lexer)
            return
        }
        else if is_ident_start_byte(lexer.code[lexer.code_index]) {
            consume_keyword_or_ident_token(lexer)
            return
        }

        switch lexer.code[lexer.code_index] {
            case '(':
                token = Token{
                    type = .LParen,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case ')':
                token = Token{
                    type = .RParen,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case '{':
                token = Token{
                    type = .LBrace,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)
               
            case '}':
                token = Token{
                    type = .RBrace,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case ';':
                token = Token{
                    type = .Semicolon,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)
            
            case '-':
                if lexer.code[lexer.code_index + 1] == '-' {
                    token = Token{
                        type = .MinusMinus,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .MinusEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Minus,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '!':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .BangEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Bang,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '?':
                token = Token{
                    type = .QuestionMark,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case ':':
                token = Token{
                    type = .Colon,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case '~':
                token = Token{
                    type = .Tilde,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case '*':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .StarEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Star,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '%':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .PercentEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Percent,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '/':
                if lexer.code[lexer.code_index + 1] == '/' {
                    lexer_eat_until_newline(lexer)
                    continue
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .SlashEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '*' {
                    lexer_eat_multiline_comment(lexer)
                    continue
                }
                else {
                    token = Token{
                        type = .ForwardSlash,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            // @HACK: We skip preprocessor directives for now, since they are more complicated than we are ready for
            case '#':
                lexer_eat_until_newline(lexer)
                continue

            case '^':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .CaratEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Carat,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '+':
                if lexer.code[lexer.code_index + 1] == '+' {
                    token = Token{
                        type = .PlusPlus,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .PlusEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Plus,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case ',':
                token = Token{
                    type = .Comma,
                    text = lexer.code[lexer.code_index:lexer.code_index + 1],
                    line = lexer.line,
                    char = lexer.char,
                }
                lexer_advance(lexer)

            case '>':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .MoreEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '>' {
                    if lexer.code[lexer.code_index + 2] == '=' {
                        token = Token{
                            type = .MoreMoreEqual,
                            text = lexer.code[lexer.code_index:lexer.code_index + 3],
                            line = lexer.line,
                            char = lexer.char,
                        }
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                    }
                    else {
                        token = Token{
                            type = .MoreMore,
                            text = lexer.code[lexer.code_index:lexer.code_index + 2],
                            line = lexer.line,
                            char = lexer.char,
                        }
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                    }
                }
                else {
                    token = Token{
                        type = .More,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '<':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .LessEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '<' {
                    if lexer.code[lexer.code_index + 2] == '=' {
                        token = Token{
                            type = .LessLessEqual,
                            text = lexer.code[lexer.code_index:lexer.code_index + 3],
                            line = lexer.line,
                            char = lexer.char,
                        }
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                    }
                    else {
                        token = Token{
                            type = .LessLess,
                            text = lexer.code[lexer.code_index:lexer.code_index + 2],
                            line = lexer.line,
                            char = lexer.char,
                        }
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                    }
                }
                else {
                    token = Token{
                        type = .Less,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '&':
                if lexer.code[lexer.code_index + 1] == '&' {
                    token = Token{
                        type = .DoubleAnd,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .AndEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .And,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '|':
                if lexer.code[lexer.code_index + 1] == '|' {
                    token = Token{
                        type = .DoublePipe,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .PipeEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Pipe,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case '=':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = Token{
                        type = .DoubleEqual,
                        text = lexer.code[lexer.code_index:lexer.code_index + 2],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = Token{
                        type = .Equal,
                        text = lexer.code[lexer.code_index:lexer.code_index + 1],
                        line = lexer.line,
                        char = lexer.char,
                    }
                    lexer_advance(lexer)
                }

            case: lex_error(lexer)
        }
        break
    }

    push_to_consumed(lexer, token)
}

take_token :: proc(lexer: ^Lexer) -> Token {
    if consumed_is_empty(lexer) {
        consume_token(lexer)
    }

    token := consumed_at(lexer, 0)
    if token.type == .EndOfFile {
        return token
    }
    else {
        token := pop_from_consumed(lexer)
        return token 
    }
}

look_ahead :: proc(lexer: ^Lexer, steps: int) -> Token {
    assert(steps < CONSUMED_SIZE)
    for consumed_len(lexer) < steps {
        consume_token(lexer)
    }
    return consumed_at(lexer, steps - 1)
}

Parser :: struct {
    lexer: Lexer,
}

parse_error :: proc(parser: ^Parser, message: string) {
    fmt.printfln("%v(%v:%v) Parse error! %v", parser.lexer.file, parser.lexer.line + 1, parser.lexer.char + 1, message)
    os.exit(3)
}

parse_program :: proc(parser: ^Parser) -> Program {
    children := make([dynamic]^Ast_Node)

    for {
        next_token := look_ahead(&parser.lexer, 1)
        if next_token.type == .EndOfFile do break
        function := parse_function_definition_or_declaration(parser)
        append(&children, function)
    }

    return Program{children}
}

parse_function_definition_or_declaration :: proc(parser: ^Parser) -> ^Ast_Node {
    signature := parse_function_signature(parser)

    token := take_token(&parser.lexer)
    if token.type == .Semicolon {
        return make_node_2(Function_Declaration_Node, signature.name, signature.params)
    }

    if token.type != .LBrace do parse_error(parser, "Expected a semicolon or block item list after function signature.")
    body := parse_block_item_list(parser)
    return make_node_3(Function_Definition_Node, signature.name, signature.params, body)
}

Function_Signature :: struct {
    name: string,
    params: [dynamic]string,
}

parse_function_signature :: proc(parser: ^Parser) -> Function_Signature {
    token := take_token(&parser.lexer)
    if token.type != .IntKeyword do parse_error(parser, "Expected 'int' as start of function signature.")

    token = take_token(&parser.lexer)
    if token.type != .Ident do parse_error(parser, "Expected an identifier in function signature.")
    name := token.text

    token = take_token(&parser.lexer)
    if token.type != .LParen do parse_error(parser, "Expected parameters in function signature.")

    params := make([dynamic]string)
    token = take_token(&parser.lexer)
    if token.type == .IntKeyword {
        token = take_token(&parser.lexer)
        if token.type != .Ident do parse_error(parser, "Expected an identifier after parameter type.")
        append(&params, token.text)
        for {
            token = take_token(&parser.lexer)
            if token.type == .RParen do break

            if token.type != .Comma do parse_error(parser, "Expected a comma separating function parameters.")
            token = take_token(&parser.lexer)
            if token.type != .IntKeyword do parse_error(parser, "Expected a type preceding function parameter.")
            token = take_token(&parser.lexer)
            if token.type != .Ident do parse_error(parser, "Expected an identifier after parameter type.")
            append(&params, token.text)
        }
    }
    else if token.type == .VoidKeyword {
        token = take_token(&parser.lexer)
        if token.type != .RParen do parse_error(parser, "If signatures contain 'void', they must not contain any other parameters.")
    }

    return Function_Signature{name, params}
}

parse_block_item_list :: proc(parser: ^Parser) -> [dynamic]^Ast_Node {
    list := make([dynamic]^Ast_Node)
    for {
        token := look_ahead(&parser.lexer, 1)
        if token.type == .RBrace do break

        // Skip null statements
        if token.type == .Semicolon {
            take_token(&parser.lexer)
            continue
        }

        block_item := parse_block_item(parser)
        append(&list, block_item)
    }

    token := take_token(&parser.lexer)
    if token.type != .RBrace do parse_error(parser, "Expected a '}' after block item list.")
    return list
}

parse_block_item :: proc(parser: ^Parser) -> ^Ast_Node {
    labels := parse_labels(parser)

    #partial switch look_ahead(&parser.lexer, 1).type {
        case .IntKeyword:
            if len(labels) > 0 do parse_error(parser, "Declarations cannot have labels.")
            token_1 := look_ahead(&parser.lexer, 2)
            token_2 := look_ahead(&parser.lexer, 3)
            if token_1.type != .Ident do parse_error(parser, "Expected an identifier after type.")
            var_name := token_1.text

            if token_2.type == .Semicolon {
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                return make_node_1(Decl_Node, var_name)
            }
            else if token_2.type == .Equal {
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                right := parse_expression(parser)
                statement := make_node_2(Decl_Assign_Node, var_name, right)
                token := take_token(&parser.lexer)
                if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after statement.")
                return statement
            }
            else if token_2.type == .LParen {
                return parse_function_declaration(parser)
            }
            else {
                parse_error(parser, "Expected a function or variable declaration.")
            }

        case:
            return parse_statement(parser, labels)
    }
    
    panic("Unreachable")
}

parse_labels :: proc(parser: ^Parser) -> [dynamic]Label {
    labels := make([dynamic]Label)

    loop: for {
        token := look_ahead(&parser.lexer, 1) 
        #partial switch token.type {
            case .DefaultKeyword:
                take_token(&parser.lexer)
                token = take_token(&parser.lexer)
                if token.type != .Colon do parse_error(parser, "Expected a colon after label.")
                append(&labels, Default_Label{})

            case .CaseKeyword:
                take_token(&parser.lexer)
                token = take_token(&parser.lexer)
                if token.type == .Colon do parse_error(parser, "Expected a constant in 'case' label")
                if token.type != .IntConstant do semantic_error() // @Temporary
                constant := token.data.(int)
                token = take_token(&parser.lexer)
                if token.type != .Colon do parse_error(parser, "Expected a colon after label.")
                append(&labels, constant)

            case .Ident:
                next := look_ahead(&parser.lexer, 2)
                if next.type != .Colon do break loop
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                append(&labels, token.text)

            case:
                break loop
        }
    }

    return labels
}

op_precs := map[Token_Type]int {
    .Equal = 7,
    .PlusEqual = 7,
    .MinusEqual = 7,
    .StarEqual = 7,
    .SlashEqual = 7,
    .PercentEqual = 7,
    .CaratEqual = 7,
    .PipeEqual = 7,
    .AndEqual = 7,
    .LessLessEqual = 7,
    .MoreMoreEqual = 7,
    .QuestionMark = 8,
    .DoublePipe = 9,
    .DoubleAnd = 10,
    .Pipe = 13,
    .Carat = 14,
    .And = 15,
    .DoubleEqual = 20,
    .BangEqual = 20,
    .Less = 30,
    .LessEqual = 30,
    .More = 30,
    .MoreEqual = 30,
    .LessLess = 35,
    .MoreMore = 35,
    .Minus = 40,
    .Plus = 40,
    .ForwardSlash = 50,
    .Star = 50,
    .Percent = 50,
}

bin_ops := bit_set[Token_Type] {
    .DoubleAnd,
    .DoublePipe,
    .DoubleEqual,
    .BangEqual,
    .Less,
    .LessEqual,
    .More,
    .MoreEqual,
    .Minus,
    .Plus,
    .Star,
    .ForwardSlash,
    .Percent,
    .And,
    .Pipe,
    .Carat,
    .LessLess,
    .MoreMore
}

assign_ops := bit_set[Token_Type] {
    .Equal,
    .PlusEqual,
    .MinusEqual,
    .StarEqual,
    .SlashEqual,
    .PercentEqual,
    .CaratEqual,
    .PipeEqual,
    .AndEqual,
    .LessLessEqual,
    .MoreMoreEqual,
}

make_binary_op_node :: proc(type: Token_Type, left: ^Ast_Node, right: ^Ast_Node) -> ^Ast_Node {
    node := new(Ast_Node)

    #partial switch type {
        case .Minus:
            node.variant = Subtract_Node{left, right}

        case .Plus:
            node.variant = Add_Node{left, right} 

        case .Star:
            node.variant = Multiply_Node{left, right}

        case .Percent:
            node.variant = Modulo_Node{left, right}

        case .ForwardSlash:
            node.variant = Divide_Node{left, right}

        case .DoubleAnd:
            node.variant = Boolean_And_Node{left, right}

        case .DoublePipe:
            node.variant = Boolean_Or_Node{left, right}

        case .DoubleEqual:
            node.variant = Boolean_Equal_Node{left, right}

        case .BangEqual:
            node.variant = Boolean_Not_Equal_Node{left, right}

        case .LessEqual:
            node.variant = Less_Equal_Node{left, right}

        case .Less:
            node.variant = Less_Node{left, right}

        case .MoreEqual:
            node.variant = More_Equal_Node{left, right}

        case .More:
            node.variant = More_Node{left, right}

        case .And:
            node.variant = Bit_And_Node{left, right}

        case .Pipe:
            node.variant = Bit_Or_Node{left, right}

        case .Carat:
            node.variant = Bit_Xor_Node{left, right}

        case .LessLess:
            node.variant = Shift_Left_Node{left, right}

        case .MoreMore:
            node.variant = Shift_Right_Node{left, right}

        case .Equal:
            node.variant = Equal_Node{left, right}

        case .PlusEqual:
            node.variant = Plus_Equal_Node{left, right}

        case .MinusEqual:
            node.variant = Minus_Equal_Node{left, right}
        
        case .StarEqual:
            node.variant = Times_Equal_Node{left, right}

        case .SlashEqual:
            node.variant = Divide_Equal_Node{left, right}

        case .PercentEqual:
            node.variant = Modulo_Equal_Node{left, right}

        case .CaratEqual:
            node.variant = Xor_Equal_Node{left, right}

        case .PipeEqual:
            node.variant = Or_Equal_Node{left, right}

        case .AndEqual:
            node.variant = And_Equal_Node{left, right}

        case .LessLessEqual:
            node.variant = Shift_Left_Equal_Node{left, right}

        case .MoreMoreEqual:
            node.variant = Shift_Right_Equal_Node{left, right}

        case:
            fmt.eprintln(type)
            panic("Not a valid binary operator!")
    }

    return node 
}

parse_expression :: proc(parser: ^Parser, min_prec := 0) -> ^Ast_Node {
    leaf := parse_expression_leaf(parser)
    token := look_ahead(&parser.lexer, 1)

    for (token.type in assign_ops || token.type in bin_ops || token.type == .QuestionMark) \
        && op_precs[token.type] >= min_prec {

        take_token(&parser.lexer)
        if (token.type in assign_ops) {
            prec := op_precs[token.type]
            right := parse_expression(parser, prec)
            op := make_binary_op_node(token.type, leaf, right)
            leaf = op
        }
        else if token.type in bin_ops {
            prec := op_precs[token.type]
            // @TODO: Handle associativity here (see https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing)
            right := parse_expression(parser, prec + 1)
            op := make_binary_op_node(token.type, leaf, right)
            leaf = op
        }
        else {
            prec := op_precs[token.type]
            if_true := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .Colon do parse_error(parser, "Expected a colon after ternary condition.")
            if_false := parse_expression(parser, prec)
            op := make_node_3(Ternary_Node, leaf, if_true, if_false)
            leaf = op
        }

        token = look_ahead(&parser.lexer, 1)
    }

    return leaf
}

semantic_error :: proc(location := #caller_location) {
    fmt.printfln("Semantic error in %v", location)
    os.exit(4)
}

parse_function_declaration :: proc(parser: ^Parser) -> ^Ast_Node {
    signature := parse_function_signature(parser)

    token := take_token(&parser.lexer)
    if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after function declaration.")
    return make_node_2(Function_Declaration_Node, signature.name, signature.params)
}

parse_statement :: proc(parser: ^Parser, labels: [dynamic]Label = nil) -> ^Ast_Node {
    labels := labels
    if labels == nil {
        labels = parse_labels(parser)
    }
    token := look_ahead(&parser.lexer, 1)

    result: ^Ast_Node = ---

    #partial switch token.type {
        case .ReturnKeyword:
            take_token(&parser.lexer)
            expr := parse_expression(parser)
            result = make_node_1(Return_Node, expr)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'return' statement.")

        case .IfKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before if condition.")
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after if condition.")

            if_true := parse_statement(parser)

            token = look_ahead(&parser.lexer, 1)
            if token.type == .ElseKeyword {
                take_token(&parser.lexer)
                if_false := parse_statement(parser)
                result = make_node_3(If_Else_Node, condition, if_true, if_false)
            }
            else {
                result = make_node_2(If_Node, condition, if_true)
            }

        case .GotoKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .Ident do parse_error(parser, "Expected a label name after 'goto'.")
            label := token.text
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'goto' statement.")
            result = make_node_1(Goto_Node, label)

        case .WhileKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop condition.")
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop condition.")
            if_true := parse_statement(parser)
            result = make_node_2(While_Node, condition, if_true)

        case .DoKeyword:
            take_token(&parser.lexer)
            if_true := parse_statement(parser)
            token = take_token(&parser.lexer)
            if token.type != .WhileKeyword do parse_error(parser, "Expected a 'while' after 'do' loop body.")
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop condition.")
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop condition.")
            result = make_node_2(Do_While_Node, condition, if_true)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'do' loop.")

        case .ForKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop conditions.")
            pre_condition := parse_for_precondition(parser)

            condition: ^Ast_Node = ---
            token = look_ahead(&parser.lexer, 1)
            fmt.println(token)
            if token.type == .Semicolon {
                condition = make_node_1(Int_Constant_Node, 1) // If expression is empty, replace it with a condition that is always true
            }
            else {
                condition = parse_expression(parser)
            }
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'for' loop condition.")

            post_condition: ^Ast_Node
            token = look_ahead(&parser.lexer, 1)
            if token.type != .RParen {
                post_condition = parse_expression(parser)
            }

            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop conditions.")
            if_true := parse_statement(parser)
            result = make_node_4(For_Node, pre_condition, condition, post_condition, if_true)

        case .ContinueKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'continue' statement.")
            result = make_node_0(Continue_Node)

        case .BreakKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'break' statement.")
            result = make_node_0(Break_Node)

        case .SwitchKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before 'switch' expression.")
            expr := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after 'switch' expression.")
            block := parse_statement(parser) //@TODO: This is not correct. Switch bodiess must be compound statements
            result = make_node_2(Switch_Node, expr, block)

        case .Semicolon:
            take_token(&parser.lexer)
            result = make_node_0(Null_Statement_Node)

        case .LBrace:
            take_token(&parser.lexer)
            statements := parse_block_item_list(parser)
            result = make_node_1(Compound_Statement_Node, statements)

        case:
            result = parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after expression statement.")
    }

    result.labels = labels
    return result
}

parse_expression_leaf :: proc(parser: ^Parser) -> ^Ast_Node {
    token := look_ahead(&parser.lexer, 1)

    #partial switch token.type {
        case .Minus:
            take_token(&parser.lexer)
            inner := parse_expression_leaf(parser)
            return make_node_1(Negate_Node, inner)

        case .Tilde:
            take_token(&parser.lexer)
            inner := parse_expression_leaf(parser)
            return make_node_1(Bit_Negate_Node, inner)

        case .Bang:
            take_token(&parser.lexer)
            inner := parse_expression_leaf(parser)
            return make_node_1(Boolean_Negate_Node, inner)

        case .MinusMinus:
            take_token(&parser.lexer)
            inner := parse_expression_leaf(parser)
            return make_node_1(Pre_Decrement_Node, inner)

        case .PlusPlus:
            take_token(&parser.lexer)
            inner := parse_expression_leaf(parser)
            return make_node_1(Pre_Increment_Node, inner)

        case .IntConstant:
            take_token(&parser.lexer)
            inner := make_node_1(Int_Constant_Node, token.data.(int))
            return parse_postfix_operators(parser, inner)

        case .Ident:
            name := token.text
            token = look_ahead(&parser.lexer, 2)

            if token.type == .LParen {
                // Parse a function call
                take_token(&parser.lexer)
                take_token(&parser.lexer)
                params := make([dynamic]^Ast_Node)
                token = look_ahead(&parser.lexer, 1)

                if token.type != .RParen {
                    expr := parse_expression(parser)
                    append(&params, expr)
                    for {
                        token = take_token(&parser.lexer)
                        if token.type == .RParen do break

                        if token.type != .Comma do parse_error(parser, "Expected a ',' separating function arguments.")
                        expr := parse_expression(parser)
                        append(&params, expr)
                    }
                }
                else {
                    take_token(&parser.lexer)
                }

                return make_node_2(Function_Call_Node, name, params)
            }
            else {
                take_token(&parser.lexer)
                inner := make_node_1(Ident_Node, name)
                return parse_postfix_operators(parser, inner)
            }

        case .LParen:
            take_token(&parser.lexer)
            expr := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Mismatched brackets in expression.")
            return parse_postfix_operators(parser, expr)

        case:
            parse_error(parser, "Expected an expression term.")
    }

    panic("Unreachable")
}

parse_for_precondition :: proc(parser: ^Parser) -> ^Ast_Node {
    token := look_ahead(&parser.lexer, 1)

    statement: ^Ast_Node = ---
    if token.type == .IntKeyword {
        token_1 := look_ahead(&parser.lexer, 2)
        token_2 := look_ahead(&parser.lexer, 3)
        if token_1.type != .Ident do parse_error(parser, "Expected an identifier in declaration.")
        var_name := token_1.text

        if token_2.type == .Semicolon {
            take_token(&parser.lexer)
            take_token(&parser.lexer)
            take_token(&parser.lexer)
            statement = make_node_1(Decl_Node, var_name)
        }
        else if token_2.type == .Equal {
            take_token(&parser.lexer)
            take_token(&parser.lexer)
            take_token(&parser.lexer)
            right := parse_expression(parser)
            statement = make_node_2(Decl_Assign_Node, var_name, right)
        }
        else {
            parse_error(parser, "Invalid 'for' loop precondition.")
        }
    }
    else {
        statement = parse_statement(parser) // @TODO: Statements are more than we need here.
    }

    token = take_token(&parser.lexer)
    if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after loop precondition.")
    return statement
}

parse_postfix_operators :: proc(parser: ^Parser, inner: ^Ast_Node) -> ^Ast_Node {
    inner := inner

    for {
        token := look_ahead(&parser.lexer, 1)
        if token.type == .PlusPlus {
            op := make_node_1(Post_Increment_Node, inner)
            inner = op
        }
        else if token.type == .MinusMinus {
            op := make_node_1(Post_Decrement_Node, inner)
            inner = op
        }
        else do break

        take_token(&parser.lexer)
    }

    return inner
}

/*
parse_function_definition :: proc(tokens: []Token) -> (^Ast_Node, []Token) {
    signature, tokens := parse_function_signature(tokens)

    token: Token = ---
    token, tokens = take_first_token(tokens)
    if token.type != .LBrace do parse_error(token, tokens)

    body: [dynamic]^Ast_Node = ---
    body, tokens = parse_block_statement_list(tokens)

    return make_node_3(Function_Definition_Node, signature.name, signature.params, body), tokens
}
*/

contains :: proc(elem: $E, list: $L/[]E) -> bool {
    for e in list {
        if e == elem do return true
    }
    return false
}

validate_and_gather_block_statement_labels :: proc(block_statement: ^Ast_Node, labels: ^[dynamic]Label) {
    for label in block_statement.labels {
        if _, is_normal := label.(string); is_normal && contains(label, labels[:]) do semantic_error()
        append(labels, label)
    }

    #partial switch stmt in block_statement.variant {
        case If_Node:
            validate_and_gather_block_statement_labels(stmt.if_true, labels)

        case If_Else_Node:
            validate_and_gather_block_statement_labels(stmt.if_true, labels)
            validate_and_gather_block_statement_labels(stmt.if_false, labels)

        case While_Node:
            validate_and_gather_block_statement_labels(stmt.if_true, labels)            

        case Do_While_Node:
            validate_and_gather_block_statement_labels(stmt.if_true, labels)            

        case For_Node:
            validate_and_gather_block_statement_labels(stmt.if_true, labels)            

        case Switch_Node:
            validate_and_gather_block_statement_labels(stmt.block, labels)

        case Compound_Statement_Node:
            for statement in stmt.statements {
                validate_and_gather_block_statement_labels(statement, labels)
            }
    }
}

validate_and_gather_function_labels :: proc(function: Function_Definition_Node) -> [dynamic]Label {
    labels := make([dynamic]Label)

    for block_statement in function.body {
        validate_and_gather_block_statement_labels(block_statement, &labels)
    }

    return labels
}

get_offset :: proc(offsets: ^Scoped_Variable_Offsets, var_name: string) -> int {
    offset, ok := offsets.var_offsets[var_name]
    if ok {
        return offset
    }
    else {
        return get_offset(offsets.parent, var_name)
    }
}

is_defined :: proc(offsets: ^Scoped_Variable_Offsets, var_name: string) -> bool {
    if offsets.parent == nil do return var_name in offsets.var_offsets

    if var_name in offsets.var_offsets {
        return true
    }
    else {
        return is_defined(offsets.parent, var_name)
    }
}

validate_lvalue :: proc(offsets: ^Scoped_Variable_Offsets, lvalue: ^Ast_Node) {
    ident, is_ident := lvalue.variant.(Ident_Node)
    if !is_ident do semantic_error()
    if !is_defined(offsets, ident.var_name) do semantic_error()
}

Loop_Labels :: struct {
    continue_label: int,
    break_label: int,
}

Switch_Info :: struct {
    start_label: int,
    current_label: int,
    labels: [dynamic]Label,
    has_default: bool,
}

switch_end_label :: proc(info: Switch_Info) -> int {
    end_label := info.start_label + len(info.labels)
    return end_label
}

Containing_Control_Flow :: enum {
    Loop,
    Switch,
}

Emit_Info :: struct {
    labels: []Label,
    loop_labels: [dynamic]Loop_Labels,
    variable_offset: int, // Offset of previously allocated stack variables
    switch_infos: [dynamic]Switch_Info,
    containing_control_flows: [dynamic]Containing_Control_Flow,
}

current_label := 1

emit_label :: proc(builder: ^strings.Builder, label := -1) {
    if label == -1 {
        fmt.sbprintfln(builder, "L%v:", current_label)
        current_label += 1
    }
    else {
        fmt.sbprintfln(builder, "L%v:", label)
    }
}

emit_unary_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info) {
    #partial switch o in op.variant {
        case Negate_Node:
            emit_expr(builder, o.expr, offsets, info)
            fmt.sbprintln(builder, "  neg %eax")

        case Bit_Negate_Node:
            emit_expr(builder, o.expr, offsets, info)
            fmt.sbprintln(builder, "  not %eax")

        case Boolean_Negate_Node:
            emit_expr(builder, o.expr, offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")

        case Pre_Decrement_Node:
            validate_lvalue(offsets, o.expr)
            fmt.sbprintfln(builder, "  decl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Pre_Increment_Node:
            validate_lvalue(offsets, o.expr)
            fmt.sbprintfln(builder, "  incl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Decrement_Node:
            validate_lvalue(offsets, o.expr)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  decl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Increment_Node:
            validate_lvalue(offsets, o.expr)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  incl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case:
            fmt.println(op)
            panic("Not a valid unary operator!")
    }
}

emit_binary_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, vars: ^Scoped_Variable_Offsets, info: ^Emit_Info) {
    #partial switch o in op.variant {
        case Add_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  add %ebx, %eax")
        
        case Subtract_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  sub %eax, %ebx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")

        case Multiply_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  push %rdx") // rdx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  imul %ebx")
            fmt.sbprintln(builder, "  pop %rdx")

        case Modulo_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  push %rcx") // rcx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  push %rdx") // rdx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  idiv %ecx")
            fmt.sbprintln(builder, "  mov %edx, %eax")
            fmt.sbprintln(builder, "  pop %rdx")
            fmt.sbprintln(builder, "  pop %rcx")

        case Divide_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  push %rcx") // rcx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  push %rdx") // rdx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  idiv %ecx")
            fmt.sbprintln(builder, "  pop %rdx")
            fmt.sbprintln(builder, "  pop %rcx")

        case Boolean_And_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 1
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            fmt.sbprintln(builder, "  mov $1, %eax")
            emit_label(builder, label)

        case Boolean_Or_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 2 
            fmt.sbprintfln(builder, "  jne L%v", label)
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 1)
            emit_label(builder, label)
            fmt.sbprintln(builder, "    mov $1, %eax")
            emit_label(builder, label + 1)

        case Boolean_Equal_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")

        case Boolean_Not_Equal_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setne %al")

        case Less_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnge %al")

        case Less_Equal_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setle %al")

        case More_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnle %al")

        case More_Equal_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setge %al")

        case Bit_And_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  and %ebx, %eax")

        case Bit_Or_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  or %ebx, %eax")

        case Bit_Xor_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %ebx, %eax")

        // @TODO: This will need some semantics passes, but we are skipping them for now until we have type checking since a lot of the semantics depends on this
        case Shift_Left_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  push %rcx") // rcx may be a function parameter
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  shl %cl, %eax")
            fmt.sbprintln(builder, "  pop %rcx")

        case Shift_Right_Node:
            emit_expr(builder, o.left, vars, info)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars, info)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  push %rcx") // rcx may be a function parameter
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            // @TODO: Whether this is a logical or arithmetic shift depends on the type of the left expression. Since we assume everything is a signed int for now,
            // we do an arithmetic shift right.
            fmt.sbprintln(builder, "  sar %cl, %eax")
            fmt.sbprintln(builder, "  pop %rcx")

        case:
            fmt.println(op)
            panic("Not a valid binary operator!")
    }
}

emit_assign_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info) {
    #partial switch o in op.variant {
        case Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Plus_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  add %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            
        case Minus_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  sub %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Times_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  push %rdx") // rdx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  imul %ebx, %eax")
            fmt.sbprintln(builder, "  pop %rdx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Divide_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Modulo_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%edx, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  mov %edx, %eax")

        case Xor_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Or_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  or %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case And_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  and %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Left_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  push %rcx") // rcx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  shl %cl, %eax")
            fmt.sbprintln(builder, "  pop %rcx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Right_Equal_Node:
            validate_lvalue(offsets, o.left)
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  push %rcx") // rcx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  shr %cl, %eax")
            fmt.sbprintln(builder, "  pop %rcx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case:
            fmt.println(op)
            panic("Not a valid assignment operator!")
    }
}

emit_expr :: proc(builder: ^strings.Builder, expr: ^Ast_Node, vars: ^Scoped_Variable_Offsets, info: ^Emit_Info) {
    #partial switch e in expr.variant {
        case Int_Constant_Node:
            fmt.sbprintfln(builder, "  mov $%v, %%eax", e.value)

        case Ident_Node:
            if !is_defined(vars, e.var_name) do semantic_error()
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(vars, e.var_name))

        case Negate_Node: emit_unary_op(builder, expr, vars, info)
        case Bit_Negate_Node: emit_unary_op(builder, expr, vars, info)
        case Boolean_Negate_Node: emit_unary_op(builder, expr, vars, info)
        case Pre_Decrement_Node: emit_unary_op(builder, expr, vars, info)
        case Pre_Increment_Node: emit_unary_op(builder, expr, vars, info)
        case Post_Decrement_Node: emit_unary_op(builder, expr, vars, info)
        case Post_Increment_Node: emit_unary_op(builder, expr, vars, info)
            

        case Add_Node: emit_binary_op(builder, expr, vars, info)
        case Subtract_Node: emit_binary_op(builder, expr, vars, info)
        case Multiply_Node: emit_binary_op(builder, expr, vars, info)
        case Modulo_Node: emit_binary_op(builder, expr, vars, info)
        case Divide_Node: emit_binary_op(builder, expr, vars, info)
        case Boolean_And_Node: emit_binary_op(builder, expr, vars, info)
        case Boolean_Or_Node: emit_binary_op(builder, expr, vars, info)
        case Boolean_Equal_Node: emit_binary_op(builder, expr, vars, info)
        case Boolean_Not_Equal_Node: emit_binary_op(builder, expr, vars, info)
        case Less_Node: emit_binary_op(builder, expr, vars, info)
        case Less_Equal_Node: emit_binary_op(builder, expr, vars, info)
        case More_Node: emit_binary_op(builder, expr, vars, info)
        case More_Equal_Node: emit_binary_op(builder, expr, vars, info)
        case Bit_And_Node: emit_binary_op(builder, expr, vars, info)
        case Bit_Or_Node: emit_binary_op(builder, expr, vars, info)
        case Bit_Xor_Node: emit_binary_op(builder, expr, vars, info)
        case Shift_Left_Node: emit_binary_op(builder, expr, vars, info)
        case Shift_Right_Node: emit_binary_op(builder, expr, vars, info)

        case Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Plus_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Minus_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Times_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Divide_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Modulo_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Xor_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Or_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case And_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Shift_Left_Equal_Node: emit_assign_op(builder, expr, vars, info)
        case Shift_Right_Equal_Node: emit_assign_op(builder, expr, vars, info)

        case Ternary_Node:
            label := current_label
            current_label += 2
            emit_expr(builder, e.condition, vars, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_expr(builder, e.if_true, vars, info)
            fmt.sbprintfln(builder, "  jmp L%v", label + 1)
            emit_label(builder, label)
            emit_expr(builder, e.if_false, vars, info)
            emit_label(builder, label + 1)

        case Function_Call_Node:
            // x64 calling convention
            // - First argument in rcx
            // - Second argument in rdx
            // - Third argument in r8
            // - Fourth argument in r9
            // - Remaining args pushed right-to-left to stack
            if len(e.args) > 0 {
                emit_expr(builder, e.args[0], vars, info)
                fmt.sbprintln(builder, "  mov %rax, %rcx")
            }
            if len(e.args) > 1 {
                emit_expr(builder, e.args[1], vars, info)
                fmt.sbprintln(builder, "  mov %rax, %rdx")
            }
            if len(e.args) > 2 {
                emit_expr(builder, e.args[2], vars, info)
                fmt.sbprintln(builder, "  mov %rax, %r8")
            }
            if len(e.args) > 3 {
                emit_expr(builder, e.args[3], vars, info)
                fmt.sbprintln(builder, "  mov %rax, %r9")
            }
            if len(e.args) > 4 {
                #reverse for arg in e.args[4:] {
                    emit_expr(builder, arg, vars, info)
                    fmt.sbprintln(builder, "  push %rax")
                }
            }
            fmt.sbprintfln(builder, "  call %v", e.name)
            if len(e.args) > 4 {
                fmt.sbprintfln(builder, "  add $%v, %%rsp", len(e.args[4:]) * 8)
            }

        case:
            fmt.println(expr)
            panic("Not a valid expression!")
    }
}

emit_block_statement :: proc(builder: ^strings.Builder, block_statement: ^Ast_Node, offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info, function_name: string) {
    #partial switch stmt in block_statement.variant {
        case Decl_Assign_Node:
            if stmt.var_name in offsets.var_offsets do semantic_error()
            offsets.var_offsets[stmt.var_name] = info.variable_offset
            info.variable_offset -= 8
            emit_expr(builder, stmt.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, stmt.var_name))

        case Decl_Node: // Space on the stack is already allocated by emit_function
            if stmt.var_name in offsets.var_offsets do semantic_error()
            offsets.var_offsets[stmt.var_name] = info.variable_offset
            info.variable_offset -= 8

        case Function_Declaration_Node: // Do nothing

        case:
            emit_statement(builder, block_statement, offsets, info, function_name)
    }

}

emit_statement :: proc(builder: ^strings.Builder, statement: ^Ast_Node, parent_offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info, function_name: string) {
    for label in statement.labels {
        switch l in label {
            case string:
                fmt.sbprintfln(builder, "_%v@%v:", l, function_name)
            case int, Default_Label:
                if len(info.switch_infos) == 0 do semantic_error()
                switch_info := slice.last_ptr(info.switch_infos[:])
                emit_label(builder, switch_info.current_label)
                switch_info.current_label += 1
        }
    }

    #partial switch stmt in statement.variant {
        case Null_Statement_Node: // Do nothing

        case Return_Node:
            emit_expr(builder, stmt.expr, parent_offsets, info)
            fmt.sbprintfln(builder, "  jmp %v_done", function_name)

        case If_Node:
            label := current_label
            current_label += 1
            emit_expr(builder, stmt.condition, parent_offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_statement(builder, stmt.if_true, parent_offsets, info, function_name)
            emit_label(builder, label)

        case If_Else_Node:
            label := current_label
            current_label += 2
            emit_expr(builder, stmt.condition, parent_offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_statement(builder, stmt.if_true, parent_offsets, info, function_name)
            fmt.sbprintfln(builder, "  jmp L%v", label + 1)
            emit_label(builder, label)
            emit_statement(builder, stmt.if_false, parent_offsets, info, function_name)
            emit_label(builder, label + 1)

        case While_Node:
            label := current_label
            current_label += 2
            append(&info.loop_labels, Loop_Labels{continue_label = label, break_label = label + 1})
            append(&info.containing_control_flows, Containing_Control_Flow.Loop)
            emit_label(builder, label)
            emit_expr(builder, stmt.condition, parent_offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 1)
            emit_statement(builder, stmt.if_true, parent_offsets, info, function_name)
            fmt.sbprintfln(builder, "  jmp L%v", label)
            emit_label(builder, label + 1)
            pop(&info.containing_control_flows)
            pop(&info.loop_labels)

        case Do_While_Node:
            label := current_label
            current_label += 3
            append(&info.loop_labels, Loop_Labels{continue_label = label + 1, break_label = label + 2})
            append(&info.containing_control_flows, Containing_Control_Flow.Loop)
            emit_label(builder, label)
            emit_statement(builder, stmt.if_true, parent_offsets, info, function_name)
            emit_label(builder, label + 1)
            emit_expr(builder, stmt.condition, parent_offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 2)
            fmt.sbprintfln(builder, "  jmp L%v", label)
            emit_label(builder, label + 2)
            pop(&info.containing_control_flows)
            pop(&info.loop_labels)

        case For_Node:
            offsets := make_scoped_variable_offsets(parent_offsets)

            label := current_label
            current_label += 3
            append(&info.loop_labels, Loop_Labels{continue_label = label + 1, break_label = label + 2})
            append(&info.containing_control_flows, Containing_Control_Flow.Loop)
            emit_block_statement(builder, stmt.pre_condition, offsets, info, function_name)
            emit_label(builder, label)
            emit_expr(builder, stmt.condition, offsets, info)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 2)
            emit_statement(builder, stmt.if_true, offsets, info, function_name)
            emit_label(builder, label + 1)
            if stmt.post_condition != nil {
                emit_expr(builder, stmt.post_condition, offsets, info)
            }
            fmt.sbprintfln(builder, "  jmp L%v", label)
            emit_label(builder, label + 2)
            pop(&info.containing_control_flows)
            pop(&info.loop_labels)

        case Continue_Node:
            if len(info.loop_labels) == 0 do semantic_error()
            fmt.sbprintfln(builder, "  jmp L%v", slice.last(info.loop_labels[:]).continue_label)

        case Break_Node:
            if len(info.containing_control_flows) == 0 do semantic_error()
            last_control_flow := slice.last(info.containing_control_flows[:])
            if last_control_flow == .Loop {
                fmt.sbprintfln(builder, "  jmp L%v", slice.last(info.loop_labels[:]).break_label)
            }
            else {
                fmt.sbprintfln(builder, "  jmp L%v", switch_end_label(slice.last(info.switch_infos[:])))
            }

        case Goto_Node:
            if !contains(cast(Label)stmt.label, info.labels) do semantic_error()
            fmt.sbprintfln(builder, "  jmp _%v@%v", stmt.label, function_name)

        case Switch_Node:
            switch_info := get_switch_info(stmt, info)
            append(&info.switch_infos, switch_info) 
            append(&info.containing_control_flows, Containing_Control_Flow.Switch)
            current_label = switch_end_label(switch_info) + 1

            emit_expr(builder, stmt.expr, parent_offsets, info)
            for label, i in switch_info.labels {
                switch l in label {
                    case int:
                        fmt.sbprintfln(builder, "  cmp $%v, %%eax", l)
                        fmt.sbprintfln(builder, "  je L%v", switch_info.start_label + i)

                    case Default_Label:
                        fmt.sbprintfln(builder, "  jmp L%v", switch_info.start_label + i)

                    case string:
                        panic("Unreachable")
                }
            }
            fmt.sbprintfln(builder, "  jmp L%v", switch_end_label(switch_info))

            emit_statement(builder, stmt.block, parent_offsets, info, function_name)
            emit_label(builder, switch_end_label(switch_info))
            pop(&info.containing_control_flows)
            pop(&info.switch_infos)

        case Compound_Statement_Node:
            offsets := make_scoped_variable_offsets(parent_offsets)
            for block_statement in stmt.statements {
                emit_block_statement(builder, block_statement, offsets, info, function_name)
            }

        case:
            emit_expr(builder, statement, parent_offsets, info)
    }
}

Scoped_Variable_Offsets :: struct {
    parent: ^Scoped_Variable_Offsets,
    var_offsets: map[string]int,
}

make_scoped_variable_offsets :: proc(parent: ^Scoped_Variable_Offsets) -> ^Scoped_Variable_Offsets {
    vars := new(Scoped_Variable_Offsets)
    vars.parent = parent
    vars.var_offsets = make(map[string]int)
    return vars
}

count_function_variable_declarations :: proc(function: Function_Definition_Node) -> int {
    declarations := 0

    for block_statement in function.body {
        declarations += count_block_statement_variable_declarations(block_statement)
    }

    return declarations
}

count_block_statement_variable_declarations :: proc(block_statement: ^Ast_Node) -> int {
    declarations := 0

    #partial switch stmt in block_statement.variant {
        case Decl_Node, Decl_Assign_Node:
            declarations += 1

        case If_Node:
            declarations += count_block_statement_variable_declarations(stmt.if_true)

        case If_Else_Node:
            declarations += count_block_statement_variable_declarations(stmt.if_true)
            declarations += count_block_statement_variable_declarations(stmt.if_false)

        case While_Node:
            declarations += count_block_statement_variable_declarations(stmt.if_true)            

        case Do_While_Node:
            declarations += count_block_statement_variable_declarations(stmt.if_true)            

        case For_Node:
            #partial switch pre in stmt.pre_condition.variant {
                case Decl_Node, Decl_Assign_Node:
                    declarations += 1
            }
            declarations += count_block_statement_variable_declarations(stmt.if_true)            
        case Switch_Node:
            declarations += count_block_statement_variable_declarations(stmt.block)

        case Compound_Statement_Node:
            for statement in stmt.statements {
                declarations += count_block_statement_variable_declarations(statement)
            }
    }

    return declarations
}

get_switch_info :: proc(statement: Switch_Node, info: ^Emit_Info) -> Switch_Info {
    result: Switch_Info
    result.start_label = current_label
    result.labels = make([dynamic]Label)
    get_switch_labels(&result, statement.block)
    result.current_label = result.start_label
    return result
}

get_switch_labels :: proc(info: ^Switch_Info, statement: ^Ast_Node) {
    for label in statement.labels {
        #partial switch l in label {
            case int, Default_Label:
                if contains(label, info.labels[:]) do semantic_error()
                append(&info.labels, label)
        }
    }

    #partial switch stmt in statement.variant {
        case If_Node:
            get_switch_labels(info, stmt.if_true)

        case If_Else_Node:
            get_switch_labels(info, stmt.if_true)
            get_switch_labels(info, stmt.if_false)

        case While_Node:
            get_switch_labels(info, stmt.if_true)            

        case Do_While_Node:
            get_switch_labels(info, stmt.if_true)            

        case For_Node:
            get_switch_labels(info, stmt.if_true)            

        case Compound_Statement_Node:
            for statement in stmt.statements {
                get_switch_labels(info, statement)
            }
    }
}

emit_function :: proc(builder: ^strings.Builder, function: Function_Definition_Node, parent_offsets: ^Scoped_Variable_Offsets) {
    labels := validate_and_gather_function_labels(function)

    fmt.sbprintfln(builder, ".globl %v", function.name)
    fmt.sbprintfln(builder, "%v:", function.name)
    fmt.sbprintln(builder, "  push %rbp")
    fmt.sbprintln(builder, "  mov %rsp, %rbp")

    // Function parameters follow the x64 calling convention
    // "Note that space is always allocated for the register parameters, even if the parameters themselves are never homed to the stack;
    // a callee is guaranteed that space has been allocated for all its parameters."
    rsp_decrement := count_function_variable_declarations(function) * 8 + 32 // 32 = 8 * 4 is the space for the register variables
    fmt.sbprintfln(builder, "  sub $%v, %%rsp", rsp_decrement)

    info := Emit_Info{
        labels = labels[:],
        loop_labels = make([dynamic]Loop_Labels),
        variable_offset = -40, // Just after the register variables
        switch_infos = make([dynamic]Switch_Info),
        containing_control_flows = make([dynamic]Containing_Control_Flow)
    }

    offsets := make_scoped_variable_offsets(parent_offsets)
    if len(function.params) > 0 {
        fmt.sbprintln(builder, "  mov %rcx, -8(%rbp)")
        offsets.var_offsets[function.params[0]] = -8
    }
    if len(function.params) > 1 {
        fmt.sbprintln(builder, "  mov %rdx, -16(%rbp)")
        offsets.var_offsets[function.params[1]] = -16
    }
    if len(function.params) > 2 {
        fmt.sbprintln(builder, "  mov %r8, -24(%rbp)")
        offsets.var_offsets[function.params[2]] = -24
    }
    if len(function.params) > 3 {
        fmt.sbprintln(builder, "  mov %r9, -32(%rbp)")
        offsets.var_offsets[function.params[3]] = -32
    }
    if len(function.params) > 4 {
        #reverse for param, i in function.params[4:] {
            offsets.var_offsets[param] = i * 8 + 16 // Add 16 to allow for the CALL instruction pushing RIP and flags on the stack
        }
    }

    for statement in function.body {
        emit_block_statement(builder, statement, offsets, &info, function.name)
    }

    if function.name == "main" {
        fmt.sbprintln(builder, "  xor %eax, %eax")
    }

    fmt.sbprintfln(builder, "%v_done:", function.name)
    fmt.sbprintfln(builder, "  add $%v, %%rsp", rsp_decrement)
      
    fmt.sbprintln(builder, "  pop %rbp")
    fmt.sbprintln(builder, "  ret")
}

emit :: proc(program: Program) -> string {
    builder: strings.Builder
    offsets := make_scoped_variable_offsets(nil) // Global scope has no parent

    for node in program.children {
        if def, is_def := node.variant.(Function_Definition_Node); is_def {
            emit_function(&builder, def, offsets)
        }
    }

    return strings.to_string(builder)
}

compile_to_assembly :: proc(source_file: string) -> (asm_file: string) {
    file_base := path.stem(path.base(source_file))
    asm_file = fmt.aprintf("%v.s", file_base)

    code, ok := os.read_entire_file(source_file)
    if !ok {
        fmt.eprintfln("Could not read from %v", source_file)
        return ""
    }

    parser := Parser{Lexer{code = string(code[:]), file = source_file}}
    program := parse_program(&parser)
    when LOG {
        fmt.println("------ AST ------")
        pretty_print_program(program)
    }

    assembly := emit(program)
    when LOG {
        fmt.println("\n\n------ ASSEMBLY ------")
        fmt.println(assembly)
    }

    when LOG {
        fmt.printfln("Assembling to %v", asm_file)
    }
    ok = os.write_entire_file(asm_file, transmute([]u8)assembly)
    if !ok {
        fmt.eprintfln("Could not write to %v", asm_file)
        os.exit(1)
    }

    return asm_file
}

compile_from_file :: proc(source_file: string) -> (exec_file: string) {
    asm_file := compile_to_assembly(source_file)
    defer delete(asm_file)

    file_base := path.stem(path.base(source_file))
    out_file := fmt.aprintf("%v.exe", file_base)

    when LOG {
        fmt.printfln("Compiling %v to %v using gcc", asm_file, out_file)
    }
    compile_with_gcc(asm_file, out_file)
    
    when LOG {
        fmt.printfln("Deleting %v", asm_file)
    }
    os.remove(asm_file)

    return out_file
}

compile_with_gcc :: proc(in_file: string, out_file: string) {
    exit_code := run_command_as_process("gcc %v -o %v", in_file, out_file)
    if exit_code != 0 {
        fmt.eprintfln("Failed to compile %v with gcc", in_file)
    }
}

usage :: proc() {
    fmt.eprintln("USAGE: occm [-assembly] <source_file>")
    fmt.eprintln("source_file:")
    fmt.eprintln("  Name of the c source file to compile")
    fmt.eprintln("-assembly:")
    fmt.eprintln("  Generate an assembly file instead of an executable")
}

main :: proc() {
    filename: string = ---
    assembly := false
    if len(os.args) == 2 {
        filename = os.args[1]
    }
    else if len(os.args) == 3 {
        assembly = true
        filename = os.args[2]
    }
    else {
        usage()
        return
    }

    if assembly do compile_to_assembly(filename)
    else        do compile_from_file(filename)
}
