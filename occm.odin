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
    Slash,
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

construct_token :: proc(lexer: ^Lexer, type: Token_Type, length: int, data: Token_Data = nil) -> Token {
    text := lexer.code[lexer.code_index - length:lexer.code_index]
    return Token{
        type = type,
        text = text,
        data = data,
        line = lexer.line,
        char = lexer.char - len(text)
    }
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

Span :: struct {
    line: int,
    char_start: int,
    char_end: int,
}

find_line :: proc(code: string, line_index: int) -> string {
    code := code
    index := 0
    line: string

    for l in strings.split_lines_iterator(&code) {
        if index == line_index {
            line = l
        }
        index += 1
    }

    return line
}

mark_span :: proc(code: string, span: Span) {
    line := find_line(code, span.line)
    prefix := fmt.tprintf("    %v  | ", span.line + 1)
    fmt.printfln("%v%v", prefix, line)
    for _ in 0..<len(prefix) + span.char_start {
        fmt.print(" ")
    }
    for _ in span.char_start..<span.char_end {
        fmt.print("^")
    }
    fmt.println()
}

span_token :: proc(token: Token) -> Span {
    if token.type == .EndOfFile {
        return Span{token.line, token.char, token.char + 1}
    }
    else {
        return Span{token.line, token.char, token.char + len(token.text)}
    }
}

lex_error :: proc(lexer: ^Lexer) {
    fmt.eprintfln("%v(%v:%v) Lex error! Unexpected character %c", lexer.file, lexer.line + 1, lexer.char + 1, lexer.code[lexer.code_index])
    mark_span(lexer.code, Span{lexer.line, lexer.char, lexer.char + 1})
    os.exit(1)
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
    push_to_consumed(lexer, construct_token(lexer, .IntConstant, len(text), strconv.atoi(text)))
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
            token = construct_token(lexer, .ReturnKeyword, len("return"))

        case text == "int":
            token = construct_token(lexer, .IntKeyword, len("int"))

        case text == "void":
            token = construct_token(lexer, .VoidKeyword, len("void"))

        case text == "if":
            token = construct_token(lexer, .IfKeyword, len("if"))

        case text == "else":
            token = construct_token(lexer, .ElseKeyword, len("else"))

        case text == "goto":
            token = construct_token(lexer, .GotoKeyword, len("goto"))

        case text == "while":
            token = construct_token(lexer, .WhileKeyword, len("while"))

        case text == "do":
            token = construct_token(lexer, .DoKeyword, len("do"))

        case text == "for":
            token = construct_token(lexer, .ForKeyword, len("for"))

        case text == "continue":
            token = construct_token(lexer, .ContinueKeyword, len("continue"))

        case text == "break":
            token = construct_token(lexer, .BreakKeyword, len("break"))

        case text == "switch":
            token = construct_token(lexer, .SwitchKeyword, len("switch"))

        case text == "case":
            token = construct_token(lexer, .CaseKeyword, len("case"))

        case text == "default":
            token = construct_token(lexer, .DefaultKeyword, len("default"))

        case:
            token = construct_token(lexer, .Ident, len(text))
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
                char = lexer.char,
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
                lexer_advance(lexer)
                token = construct_token(lexer, .LParen, 1)

            case ')':
                lexer_advance(lexer)
                token = construct_token(lexer, .RParen, 1)

            case '{':
                lexer_advance(lexer)
                token = construct_token(lexer, .LBrace, 1)
               
            case '}':
                lexer_advance(lexer)
                token = construct_token(lexer, .RBrace, 1)

            case ';':
                lexer_advance(lexer)
                token = construct_token(lexer, .Semicolon, 1)
            
            case '-':
                if lexer.code[lexer.code_index + 1] == '-' {
                    token = construct_token(lexer, .MinusMinus, 2)
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    token = construct_token(lexer, .MinusEqual, 2)
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = construct_token(lexer, .Minus, 1)
                    lexer_advance(lexer)
                }

            case '!':
                if lexer.code[lexer.code_index + 1] == '=' {
                    token = construct_token(lexer, .BangEqual, 2)
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                }
                else {
                    token = construct_token(lexer, .Bang, 1)
                    lexer_advance(lexer)
                }

            case '?':
                token = construct_token(lexer, .QuestionMark, 1)
                lexer_advance(lexer)

            case ':':
                token = construct_token(lexer, .Colon, 1)
                lexer_advance(lexer)

            case '~':
                token = construct_token(lexer, .Tilde, 1)
                lexer_advance(lexer)

            case '*':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .StarEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Star, 1)
                }

            case '%':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .PercentEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Percent, 1)
                }

            case '/':
                if lexer.code[lexer.code_index + 1] == '/' {
                    lexer_eat_until_newline(lexer)
                    continue
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .SlashEqual, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '*' {
                    lexer_eat_multiline_comment(lexer)
                    continue
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Slash, 1)
                }

            // @HACK: We skip preprocessor directives for now, since they are more complicated than we are ready for
            case '#':
                lexer_eat_until_newline(lexer)
                continue

            case '^':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .CaratEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Carat, 1)
                }

            case '+':
                if lexer.code[lexer.code_index + 1] == '+' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .PlusPlus, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .PlusEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Plus, 1)
                }

            case ',':
                lexer_advance(lexer)
                token = construct_token(lexer, .Comma, 1)

            case '>':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .MoreEqual, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '>' {
                    if lexer.code[lexer.code_index + 2] == '=' {
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        token = construct_token(lexer, .MoreMoreEqual, 3)
                    }
                    else {
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        token = construct_token(lexer, .MoreMore, 2)
                    }
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .More, 1)
                }

            case '<':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .LessEqual, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '<' {
                    if lexer.code[lexer.code_index + 2] == '=' {
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        token = construct_token(lexer, .LessLessEqual, 3)
                    }
                    else {
                        lexer_advance(lexer)
                        lexer_advance(lexer)
                        token = construct_token(lexer, .LessLess, 2)
                    }
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Less, 1)
                }

            case '&':
                if lexer.code[lexer.code_index + 1] == '&' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .DoubleAnd, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .AndEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .And, 1)
                }

            case '|':
                if lexer.code[lexer.code_index + 1] == '|' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .DoublePipe, 2)
                }
                else if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .PipeEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Pipe, 1)
                }

            case '=':
                if lexer.code[lexer.code_index + 1] == '=' {
                    lexer_advance(lexer)
                    lexer_advance(lexer)
                    token = construct_token(lexer, .DoubleEqual, 2)
                }
                else {
                    lexer_advance(lexer)
                    token = construct_token(lexer, .Equal, 1)
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

parse_error :: proc(parser: ^Parser, message: string, span: Span = {}) {
    fmt.eprintfln("%v(%v:%v) Parse error! %v", parser.lexer.file, parser.lexer.line + 1, parser.lexer.char + 1, message)
    if span != {} {
        mark_span(parser.lexer.code, span)
    }
    os.exit(1)
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
    title := parse_function_title(parser)

    token := take_token(&parser.lexer)
    if token.type == .Semicolon {
        return make_node_2(Function_Declaration_Node, title.name, title.params)
    }

    if token.type != .LBrace do parse_error(parser, "Expected a semicolon or block item list after function title.", span_token(token))
    body := parse_block_item_list(parser)
    return make_node_3(Function_Definition_Node, title.name, title.params, body)
}

Function_Title :: struct {
    name: string,
    params: [dynamic]string,
}

parse_function_title :: proc(parser: ^Parser) -> Function_Title {
    token := take_token(&parser.lexer)
    if token.type != .IntKeyword do parse_error(parser, "Expected 'int' as start of function title.", span_token(token))

    token = take_token(&parser.lexer)
    if token.type != .Ident do parse_error(parser, "Expected an identifier in function title.", span_token(token))
    name := token.text

    token = take_token(&parser.lexer)
    if token.type != .LParen do parse_error(parser, "Expected parameters in function title.", span_token(token))

    params := make([dynamic]string)
    token = take_token(&parser.lexer)
    if token.type == .IntKeyword {
        token = take_token(&parser.lexer)
        if token.type != .Ident do parse_error(parser, "Expected an identifier after parameter type.", span_token(token))
        append(&params, token.text)
        for {
            token = take_token(&parser.lexer)
            if token.type == .RParen do break

            if token.type != .Comma do parse_error(parser, "Expected a comma separating function parameters.", span_token(token))
            token = take_token(&parser.lexer)
            if token.type != .IntKeyword do parse_error(parser, "Expected a type preceding function parameter.", span_token(token))
            token = take_token(&parser.lexer)
            if token.type != .Ident do parse_error(parser, "Expected an identifier after parameter type.", span_token(token))
            append(&params, token.text)
        }
    }
    else if token.type == .VoidKeyword {
        token = take_token(&parser.lexer)
        if token.type != .RParen do parse_error(parser, "If titles contain 'void', they must not contain any other parameters.", span_token(token))
    }

    return Function_Title{name, params}
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
    if token.type != .RBrace do parse_error(parser, "Expected a '}' after block item list.", span_token(token))
    return list
}

parse_block_item :: proc(parser: ^Parser) -> ^Ast_Node {
    labels := parse_labels(parser)

    token := look_ahead(&parser.lexer, 1)

    #partial switch token.type {
        case .IntKeyword:
            if len(labels) > 0 do parse_error(parser, "Declarations cannot have labels.") //@TODO: What do we span here?
            token_1 := look_ahead(&parser.lexer, 2)
            token_2 := look_ahead(&parser.lexer, 3)
            if token_1.type != .Ident do parse_error(parser, "Expected an identifier after type.", span_token(token_1))
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
                if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after statement.", span_token(token))
                return statement
            }
            else if token_2.type == .LParen {
                return parse_function_definition_or_declaration(parser)
            }
            else {
                parse_error(parser, "Expected a function or variable declaration.", span_token(token))
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
                if token.type != .Colon do parse_error(parser, "Expected a colon after label.", span_token(token))
                append(&labels, Default_Label{})

            case .CaseKeyword:
                take_token(&parser.lexer)
                token = take_token(&parser.lexer)
                if token.type == .Colon do parse_error(parser, "Expected a constant in 'case' label", span_token(token))
                if token.type != .IntConstant do semantic_error("'case' label must contain a constant") // @Temporary
                constant := token.data.(int)
                token = take_token(&parser.lexer)
                if token.type != .Colon do parse_error(parser, "Expected a colon after label.", span_token(token))
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
    .Slash = 50,
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
    .Slash,
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

        case .Slash:
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
            if token.type != .Colon do parse_error(parser, "Expected a colon after ternary condition.", span_token(token))
            if_false := parse_expression(parser, prec)
            op := make_node_3(Ternary_Node, leaf, if_true, if_false)
            leaf = op
        }

        token = look_ahead(&parser.lexer, 1)
    }

    return leaf
}

semantic_error :: proc(message: string) {
    fmt.eprintfln("Semantic error! %v", message)
    os.exit(1)
}

parse_function_declaration :: proc(parser: ^Parser) -> ^Ast_Node {
    title := parse_function_title(parser)

    token := take_token(&parser.lexer)
    if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after function declaration.", span_token(token))
    return make_node_2(Function_Declaration_Node, title.name, title.params)
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
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'return' statement.", span_token(token))

        case .IfKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before if condition.", span_token(token))
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after if condition.", span_token(token))

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
            if token.type != .Ident do parse_error(parser, "Expected a label name after 'goto'.", span_token(token))
            label := token.text
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'goto' statement.", span_token(token))
            result = make_node_1(Goto_Node, label)

        case .WhileKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop condition.", span_token(token))
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop condition.", span_token(token))
            if_true := parse_statement(parser)
            result = make_node_2(While_Node, condition, if_true)

        case .DoKeyword:
            take_token(&parser.lexer)
            if_true := parse_statement(parser)
            token = take_token(&parser.lexer)
            if token.type != .WhileKeyword do parse_error(parser, "Expected a 'while' after 'do' loop body.", span_token(token))
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop condition.", span_token(token))
            condition := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop condition.", span_token(token))
            result = make_node_2(Do_While_Node, condition, if_true)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'do' loop.", span_token(token))

        case .ForKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before loop conditions.", span_token(token))
            pre_condition := parse_for_precondition(parser)

            condition: ^Ast_Node = ---
            token = look_ahead(&parser.lexer, 1)
            if token.type == .Semicolon {
                condition = make_node_1(Int_Constant_Node, 1) // If expression is empty, replace it with a condition that is always true
            }
            else {
                condition = parse_expression(parser)
            }
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'for' loop condition.", span_token(token))

            post_condition: ^Ast_Node
            token = look_ahead(&parser.lexer, 1)
            if token.type != .RParen {
                post_condition = parse_expression(parser)
            }

            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after loop conditions.", span_token(token))
            if_true := parse_statement(parser)
            result = make_node_4(For_Node, pre_condition, condition, post_condition, if_true)

        case .ContinueKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'continue' statement.", span_token(token))
            result = make_node_0(Continue_Node)

        case .BreakKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after 'break' statement.", span_token(token))
            result = make_node_0(Break_Node)

        case .SwitchKeyword:
            take_token(&parser.lexer)
            token = take_token(&parser.lexer)
            if token.type != .LParen do parse_error(parser, "Expected a '(' before 'switch' expression.", span_token(token))
            expr := parse_expression(parser)
            token = take_token(&parser.lexer)
            if token.type != .RParen do parse_error(parser, "Expected a ')' after 'switch' expression.", span_token(token))
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
            if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after expression statement.", span_token(token))
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

                        if token.type != .Comma do parse_error(parser, "Expected a ',' separating function arguments.", span_token(token))
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
            if token.type != .RParen do parse_error(parser, "Mismatched brackets in expression.", span_token(token)) //@TODO: Should this span the entire expression?
            return parse_postfix_operators(parser, expr)

        case:
            parse_error(parser, "Expected an expression term.", span_token(token))
    }

    panic("Unreachable")
}

parse_for_precondition :: proc(parser: ^Parser) -> ^Ast_Node {
    token := look_ahead(&parser.lexer, 1)

    if token.type == .IntKeyword {
        token_1 := look_ahead(&parser.lexer, 2)
        token_2 := look_ahead(&parser.lexer, 3)
        if token_1.type != .Ident do parse_error(parser, "Expected an identifier in declaration.", span_token(token))
        var_name := token_1.text

        statement: ^Ast_Node = ---
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
            parse_error(parser, "Invalid 'for' loop precondition.", span_token(token)) //@TODO: Should this span the entire precondition?
        }

        token = take_token(&parser.lexer)
        if token.type != .Semicolon do parse_error(parser, "Expected a semicolon after loop precondition.", span_token(token))
        return statement
    }
    else {
        return parse_statement(parser) // @TODO: Statements are more than we need here.
    }

    panic("Unreachable")
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

contains :: proc(elem: $E, list: $L/[]E) -> bool {
    for e in list {
        if e == elem do return true
    }
    return false
}

// NOTE: This could be more efficient, but it is currently used on small lists.
contains_duplicate :: proc(list: $L/[]$E) -> bool {
    for i in 0..<len(list) {
        for j in i + 1..<len(list) {
            if list[i] == list[j] do return true
        }
    }
    return false
}

validate_and_gather_block_item_labels :: proc(block_item: ^Ast_Node, labels: ^[dynamic]Label) {
    for label in block_item.labels {
        if _, is_normal := label.(string); is_normal && contains(label, labels[:]) do semantic_error("Duplicate labels not allowed.")
        append(labels, label)
    }

    #partial switch stmt in block_item.variant {
        case If_Node:
            validate_and_gather_block_item_labels(stmt.if_true, labels)

        case If_Else_Node:
            validate_and_gather_block_item_labels(stmt.if_true, labels)
            validate_and_gather_block_item_labels(stmt.if_false, labels)

        case While_Node:
            validate_and_gather_block_item_labels(stmt.if_true, labels)            

        case Do_While_Node:
            validate_and_gather_block_item_labels(stmt.if_true, labels)            

        case For_Node:
            validate_and_gather_block_item_labels(stmt.if_true, labels)            

        case Switch_Node:
            validate_and_gather_block_item_labels(stmt.block, labels)

        case Compound_Statement_Node:
            for statement in stmt.statements {
                validate_and_gather_block_item_labels(statement, labels)
            }
    }
}

validate_and_gather_function_labels :: proc(function: Function_Definition_Node) -> [dynamic]Label {
    labels := make([dynamic]Label)

    for block_item in function.body {
        validate_and_gather_block_item_labels(block_item, &labels)
    }

    return labels
}

get_offset :: proc(offsets: ^Scoped_Variable_Offsets, var_name: string) -> int {
    offsets := offsets
    for offsets != nil {
        defer offsets = offsets.parent
        
        if offset, ok := offsets.offsets[var_name]; ok {
            return offset
        }
    }
    panic("Unreachable")
}

is_lvalue :: proc(info: ^Scoped_Validation_Info, lvalue: ^Ast_Node) -> bool {
    ident, is_ident := lvalue.variant.(Ident_Node)
    if is_ident {
        ident_found, ident_type := get_ident_type(info, ident.var_name)
        return ident_found && ident_type == .Variable
    }
    else {
        return false
    }
}

String_Set :: map[string]struct{}

Function_Signature :: struct {
    name: string,
    return_type: string,
    param_types: []string,
}

Validation_Info :: struct {
    control_flows: [dynamic]Containing_Control_Flow,
    function_signatures: [dynamic]Function_Signature,
    function_defs: [dynamic]string,
}

Ident_Type :: enum {
    Function,
    Variable,
}

Scoped_Validation_Info :: struct {
    parent: ^Scoped_Validation_Info,
    identifiers: map[string]Ident_Type,
}

get_ident_type :: proc(scoped_info: ^Scoped_Validation_Info, name: string) -> (found: bool, type: Ident_Type) {
    scoped_info := scoped_info
    for scoped_info != nil {
        defer scoped_info = scoped_info.parent

        if type, found = scoped_info.identifiers[name]; found {
            return true, type 
        }
    }

    return false, nil 
}

is_in_same_scope_of_type :: proc(scoped_info: ^Scoped_Validation_Info, name: string, type: Ident_Type) -> bool {
    assert(scoped_info != nil)
    if ident_type, ident_found := scoped_info.identifiers[name]; ident_found {
        return ident_type == type
    }
    else {
        return false
    }
}

has_conflicting_function_signature :: proc(info: ^Validation_Info, signature: Function_Signature) -> bool {
    for sig in info.function_signatures {
        if sig.name == signature.name {
            if sig.return_type != signature.return_type do return true
            if len(signature.param_types) != len(sig.param_types) do return true
            for i in 0..<len(signature.param_types) {
                if signature.param_types[i] != sig.param_types[i] do return true
            }
        }
    }
    return false
}

get_function_signature :: proc(info: ^Validation_Info, name: string) -> Function_Signature {
    for sig in info.function_signatures {
        if sig.name == name do return sig
    }

    return Function_Signature{}
}

make_scoped_validation_info :: proc(parent: ^Scoped_Validation_Info) -> ^Scoped_Validation_Info {
    scoped_info := new(Scoped_Validation_Info)
    scoped_info.parent = parent
    scoped_info.identifiers = make(map[string]Ident_Type)
    return scoped_info
}

delete_scoped_validation_info :: proc(scoped_info: ^Scoped_Validation_Info) {
    delete(scoped_info.identifiers)
    free(scoped_info)
}

validate_program :: proc(program: Program) {
    scoped_info := make_scoped_validation_info(nil)
    defer delete_scoped_validation_info(scoped_info)
    
    info := Validation_Info{
        make([dynamic]Containing_Control_Flow),
        make([dynamic]Function_Signature),
        make([dynamic]string),
    }
    defer delete(info.control_flows)

    for function in program.children {
        #partial switch func in function.variant {
            case Function_Declaration_Node:
                if contains_duplicate(func.params[:]) do semantic_error("Duplicate function parameters not allowed")
                param_types := make([]string, len(func.params))
                for i in 0..<len(func.params) {
                    param_types[i] = "int"
                }
                signature := Function_Signature{func.name, "int", param_types}
                if has_conflicting_function_signature(&info, signature) do semantic_error("Conflicting function types")
                scoped_info.identifiers[func.name] = .Function
                append(&info.function_signatures, signature)

            case Function_Definition_Node:
                if contains_duplicate(func.params[:]) do semantic_error("Duplicate function parameters not allowed")
                labels := validate_and_gather_function_labels(func)
                param_types := make([]string, len(func.params))
                for i in 0..<len(func.params) {
                    param_types[i] = "int"
                }
                signature := Function_Signature{func.name, "int", param_types}
                for def in info.function_defs {
                    if def == func.name do semantic_error("Duplicate definition of function with the same name")
                }
                if has_conflicting_function_signature(&info, signature) do semantic_error("Conflicting function types")
                scoped_info.identifiers[func.name] = .Function
                append(&info.function_signatures, signature)
                append(&info.function_defs, func.name)

                new_scoped_info := make_scoped_validation_info(scoped_info)
                defer delete_scoped_validation_info(new_scoped_info)
                for param in func.params {
                    new_scoped_info.identifiers[param] = .Variable
                }

                for block_item in func.body {
                    validate_block_item(block_item, &info, new_scoped_info, labels[:])
                }

            case:
                panic("Unreachable")
        }
    }
}

validate_block_item :: proc(block_item: ^Ast_Node, info: ^Validation_Info, scoped_info: ^Scoped_Validation_Info, labels: []Label) {
    #partial switch item in block_item.variant {
        case Decl_Assign_Node:
            if is_in_same_scope_of_type(scoped_info, item.var_name, .Variable) do semantic_error("Duplicate declarations of the same variable is not allowed")
            if is_in_same_scope_of_type(scoped_info, item.var_name, .Function) do semantic_error("Variable names must be distinct from function names")
            scoped_info.identifiers[item.var_name] = .Variable
            validate_expr(item.right, info, scoped_info)

        case Decl_Node: // Space on the stack is already allocated by emit_function
            if is_in_same_scope_of_type(scoped_info, item.var_name, .Variable) do semantic_error("Duplicate declarations of the same variable is not allowed")
            if is_in_same_scope_of_type(scoped_info, item.var_name, .Function) do semantic_error("Variable names must be distinct from function names")
            scoped_info.identifiers[item.var_name] = .Variable

        case Function_Declaration_Node:
            if is_in_same_scope_of_type(scoped_info, item.name, .Variable) do semantic_error("Function names must be distinct from variable names")
            param_types := make([]string, len(item.params))
            for i in 0..<len(item.params) {
                param_types[i] = "int"
            }
            signature := Function_Signature{item.name, "int", param_types}
            if has_conflicting_function_signature(info, signature) do semantic_error("Conflicting function types")
            scoped_info.identifiers[item.name] = .Function
            append(&info.function_signatures, signature)

        case Function_Definition_Node:
            semantic_error("Function definitions cannot be nested in scopes")

        case:
            validate_statement(block_item, info, scoped_info, labels)
    }
}

validate_statement :: proc(statement: ^Ast_Node, info: ^Validation_Info, scoped_info: ^Scoped_Validation_Info, labels: []Label) {
    #partial switch stmt in statement.variant {
        case Null_Statement_Node: // Do nothing

        case Return_Node:
            validate_expr(stmt.expr, info, scoped_info)

        case If_Node:
            validate_expr(stmt.condition, info, scoped_info)
            validate_statement(stmt.if_true, info, scoped_info, labels)

        case If_Else_Node:
            validate_expr(stmt.condition, info, scoped_info)
            validate_statement(stmt.if_true, info, scoped_info, labels)
            validate_statement(stmt.if_false, info, scoped_info, labels)

        case While_Node:
            append(&info.control_flows, Containing_Control_Flow.Loop)
            validate_expr(stmt.condition, info, scoped_info)
            validate_statement(stmt.if_true, info, scoped_info, labels)
            pop(&info.control_flows)

        case Do_While_Node:
            append(&info.control_flows, Containing_Control_Flow.Loop)
            validate_expr(stmt.condition, info, scoped_info)
            validate_statement(stmt.if_true, info, scoped_info, labels)
            pop(&info.control_flows)

        case For_Node:
            append(&info.control_flows, Containing_Control_Flow.Loop)
            new_scoped_info := make_scoped_validation_info(scoped_info)
            defer delete_scoped_validation_info(new_scoped_info)
            validate_block_item(stmt.pre_condition, info, new_scoped_info, labels) // @TODO: This is much too strong of a function here
            validate_expr(stmt.condition, info, new_scoped_info)
            if stmt.post_condition != nil {
                validate_expr(stmt.post_condition, info, new_scoped_info)
            }
            validate_statement(stmt.if_true, info, new_scoped_info, labels)
            pop(&info.control_flows)

        case Continue_Node:
            out_of_loop := true
            for control in info.control_flows {
                if control == .Loop do out_of_loop = false
            }
            if out_of_loop do semantic_error("'continue' statements must be inside a loop")

        case Break_Node:
            if len(info.control_flows) == 0 do semantic_error("'break' statements must be inside a 'switch' or a loop")

        case Goto_Node:
            if !contains(cast(Label)stmt.label, labels) do semantic_error("Label does not exist")

        case Switch_Node:
            append(&info.control_flows, Containing_Control_Flow.Switch)
            validate_expr(stmt.expr, info, scoped_info)
            validate_statement(stmt.block, info, scoped_info, labels)
            pop(&info.control_flows)

        case Compound_Statement_Node:
            new_scoped_info := make_scoped_validation_info(scoped_info)
            defer delete_scoped_validation_info(new_scoped_info)

            for block_item in stmt.statements {
                validate_block_item(block_item, info, new_scoped_info, labels)
            }

        case:
            validate_expr(statement, info, scoped_info)
    }
}

validate_expr :: proc(expr: ^Ast_Node, info: ^Validation_Info, scoped_info: ^Scoped_Validation_Info) {
    #partial switch e in expr.variant {
        case Int_Constant_Node: // Do nothing

        case Ident_Node:
            if found, type := get_ident_type(scoped_info, e.var_name); !found || type != .Variable {
                semantic_error("Variable is used before it is declared")
            }

        case Negate_Node:
            validate_expr(e.expr, info, scoped_info)
        case Bit_Negate_Node:
            validate_expr(e.expr, info, scoped_info)
        case Boolean_Negate_Node:
            validate_expr(e.expr, info, scoped_info)
        case Pre_Decrement_Node:
            if !is_lvalue(scoped_info, e.expr) do semantic_error("Not an lvalue")
            validate_expr(e.expr, info, scoped_info)
        case Pre_Increment_Node:
            if !is_lvalue(scoped_info, e.expr) do semantic_error("Not an lvalue")
            validate_expr(e.expr, info, scoped_info)
        case Post_Decrement_Node:
            if !is_lvalue(scoped_info, e.expr) do semantic_error("Not an lvalue")
            validate_expr(e.expr, info, scoped_info)
        case Post_Increment_Node:
            if !is_lvalue(scoped_info, e.expr) do semantic_error("Not an lvalue")
            validate_expr(e.expr, info, scoped_info)
            

        case Add_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Subtract_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Multiply_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Modulo_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Divide_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Boolean_And_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Boolean_Or_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Boolean_Equal_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Boolean_Not_Equal_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Less_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Less_Equal_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case More_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case More_Equal_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Bit_And_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Bit_Or_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Bit_Xor_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Shift_Left_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Shift_Right_Node:
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)

        case Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Plus_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Minus_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Times_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Divide_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Modulo_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Xor_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Or_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case And_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Shift_Left_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)
        case Shift_Right_Equal_Node:
            if !is_lvalue(scoped_info, e.left) do semantic_error("Not an lvalue")
            validate_expr(e.left, info, scoped_info)
            validate_expr(e.right, info, scoped_info)

        case Ternary_Node:
            validate_expr(e.condition, info, scoped_info)
            validate_expr(e.if_true, info, scoped_info)
            validate_expr(e.if_false, info, scoped_info)

        case Function_Call_Node:
            found, type := get_ident_type(scoped_info, e.name)
            if !found do semantic_error("Function used before it is declared")
            if found && type == .Variable do semantic_error("Cannot call a variable as a function")
            signature := get_function_signature(info, e.name)
            if len(e.args) != len(signature.param_types) do semantic_error("Function called with wrong number of arguments")
            for arg in e.args {
                validate_expr(arg, info, scoped_info)
            }

        case:
            fmt.println(expr)
            panic("Not a valid expression!")
    }
}

Loop_Labels :: struct {
    continue_label: int,
    break_label: int,
}

Switch_Info :: struct {
    start_label: int,
    current_label: int,
    labels: [dynamic]Label,
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

Scoped_Variable_Offsets :: struct {
    parent: ^Scoped_Variable_Offsets,
    offsets: map[string]int,
}

make_scoped_variable_offsets :: proc(parent: ^Scoped_Variable_Offsets) -> ^Scoped_Variable_Offsets {
    offsets := new(Scoped_Variable_Offsets)
    offsets.parent = parent
    offsets.offsets = make(map[string]int)
    return offsets
}

delete_scoped_variable_offsets :: proc(offsets: ^Scoped_Variable_Offsets) {
    delete(offsets.offsets)
    free(offsets)
}

current_label := 1 //@TODO: Put this in Emit_Info

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
            fmt.sbprintfln(builder, "  decl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Pre_Increment_Node:
            fmt.sbprintfln(builder, "  incl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Decrement_Node:
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  decl %v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Increment_Node:
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
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Plus_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  add %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            
        case Minus_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  sub %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Times_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  push %rdx") // rdx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  imul %ebx, %eax")
            fmt.sbprintln(builder, "  pop %rdx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Divide_Equal_Node:
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
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Or_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  or %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case And_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  and %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Left_Equal_Node:
            emit_expr(builder, o.right, offsets, info)
            fmt.sbprintln(builder, "  push %rcx") // rcx could be a function parameter, so we need to save it
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov %v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  shl %cl, %eax")
            fmt.sbprintln(builder, "  pop %rcx")
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Right_Equal_Node:
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

emit_block_item :: proc(builder: ^strings.Builder, block_item: ^Ast_Node, offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info, function_name: string) {
    #partial switch item in block_item.variant {
        case Decl_Assign_Node:
            offsets.offsets[item.var_name] = info.variable_offset
            info.variable_offset -= 8
            emit_expr(builder, item.right, offsets, info)
            fmt.sbprintfln(builder, "  mov %%eax, %v(%%rbp)", get_offset(offsets, item.var_name))

        case Decl_Node: // Space on the stack is already allocated by emit_function
            offsets.offsets[item.var_name] = info.variable_offset
            info.variable_offset -= 8

        case Function_Declaration_Node: // Do nothing

        case Function_Definition_Node: // This is a semantic error, but will be caught in the validation step
            panic("Unreachable")

        case:
            emit_statement(builder, block_item, offsets, info, function_name)
    }

}

emit_statement :: proc(builder: ^strings.Builder, statement: ^Ast_Node, parent_offsets: ^Scoped_Variable_Offsets, info: ^Emit_Info, function_name: string) {
    for label in statement.labels {
        switch l in label {
            case string:
                fmt.sbprintfln(builder, "_%v@%v:", l, function_name)
            case int, Default_Label:
                if len(info.switch_infos) == 0 do semantic_error("'case' and 'default' labels must be in a 'switch'")
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
            emit_block_item(builder, stmt.pre_condition, offsets, info, function_name)
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
            fmt.sbprintfln(builder, "  jmp L%v", slice.last(info.loop_labels[:]).continue_label)

        case Break_Node:
            last_control_flow := slice.last(info.containing_control_flows[:])
            if last_control_flow == .Loop {
                fmt.sbprintfln(builder, "  jmp L%v", slice.last(info.loop_labels[:]).break_label)
            }
            else {
                fmt.sbprintfln(builder, "  jmp L%v", switch_end_label(slice.last(info.switch_infos[:])))
            }

        case Goto_Node:
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
            for block_item in stmt.statements {
                emit_block_item(builder, block_item, offsets, info, function_name)
            }

        case:
            emit_expr(builder, statement, parent_offsets, info)
    }
}

count_function_variable_declarations :: proc(function: Function_Definition_Node) -> int {
    declarations := 0

    for block_item in function.body {
        declarations += count_block_item_variable_declarations(block_item)
    }

    return declarations
}

count_block_item_variable_declarations :: proc(block_item: ^Ast_Node) -> int {
    declarations := 0

    #partial switch stmt in block_item.variant {
        case Decl_Node, Decl_Assign_Node:
            declarations += 1

        case If_Node:
            declarations += count_block_item_variable_declarations(stmt.if_true)

        case If_Else_Node:
            declarations += count_block_item_variable_declarations(stmt.if_true)
            declarations += count_block_item_variable_declarations(stmt.if_false)

        case While_Node:
            declarations += count_block_item_variable_declarations(stmt.if_true)            

        case Do_While_Node:
            declarations += count_block_item_variable_declarations(stmt.if_true)            

        case For_Node:
            #partial switch pre in stmt.pre_condition.variant {
                case Decl_Node, Decl_Assign_Node:
                    declarations += 1
            }
            declarations += count_block_item_variable_declarations(stmt.if_true)            
        case Switch_Node:
            declarations += count_block_item_variable_declarations(stmt.block)

        case Compound_Statement_Node:
            for statement in stmt.statements {
                declarations += count_block_item_variable_declarations(statement)
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
                if contains(label, info.labels[:]) do semantic_error("Duplicate 'case' or 'default' label")
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
        offsets.offsets[function.params[0]] = -8
    }
    if len(function.params) > 1 {
        fmt.sbprintln(builder, "  mov %rdx, -16(%rbp)")
        offsets.offsets[function.params[1]] = -16
    }
    if len(function.params) > 2 {
        fmt.sbprintln(builder, "  mov %r8, -24(%rbp)")
        offsets.offsets[function.params[2]] = -24
    }
    if len(function.params) > 3 {
        fmt.sbprintln(builder, "  mov %r9, -32(%rbp)")
        offsets.offsets[function.params[3]] = -32
    }
    if len(function.params) > 4 {
        #reverse for param, i in function.params[4:] {
            offsets.offsets[param] = i * 8 + 16 // Add 16 to allow for the CALL instruction pushing RIP and flags on the stack
        }
    }

    for statement in function.body {
        emit_block_item(builder, statement, offsets, &info, function.name)
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
    // No need to compile assembly files
    if path.ext(source_file) == ".s" do return source_file

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

    validate_program(program)

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

compile_from_files :: proc(source_files: []string) -> (exec_file: string) {
    file_base := path.stem(path.base(source_files[0]))
    out_file := fmt.aprintf("%v.exe", file_base)

    asm_files: [dynamic]string
    to_delete: [dynamic]string
    defer delete(asm_files)

    for file in source_files {
        asm_file := compile_to_assembly(file)
        append(&asm_files, asm_file)
        if asm_file != file {
            append(&to_delete, asm_file)
        }

        when LOG {
            fmt.printfln("Compiling %v to assembly...", asm_file)
        }
    }
    compile_with_gcc(asm_files[:], out_file)
    
    when LOG {
        fmt.println("Deleting asm files...")
    }
    for file in to_delete do os.remove(file)

    return out_file
}

compile_with_gcc :: proc(in_files: []string, out_file: string) {
    command: strings.Builder
    strings.builder_init_none(&command, context.temp_allocator)
    fmt.sbprintf(&command, "gcc ")
    for file in in_files {
        fmt.sbprintf(&command, "%v ", file)
    }
    fmt.sbprintf(&command, "-o %v", out_file)
    exit_code := run_command_as_process(strings.to_string(command))
    if exit_code != 0 {
        fmt.eprintfln("Failed to compile with gcc")
    }
}

usage :: proc() {
    fmt.eprintln("USAGE: occm [-assembly] <source_files>")
    fmt.eprintln("source_files:")
    fmt.eprintln("  Names of the c source files to compile")
    fmt.eprintln("-assembly:")
    fmt.eprintln("  Generate assembly files instead of an executable")
}

main :: proc() {
    filenames: []string = ---
    assembly := false
    if len(os.args) <= 1 {
        usage()
        return
    }
    else if os.args[1] == "-assembly" {
        if len(os.args) <= 2 {
            usage()
            return
        }
        else {
            assembly = true
            filenames = os.args[2:]
        }
    }
    else {
        filenames = os.args[1:]
    }

    if assembly {
        for filename in filenames do compile_to_assembly(filename)
    }
    else do compile_from_files(filenames)
}
