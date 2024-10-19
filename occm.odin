package occm

import "core:fmt"
import "core:strings"
import "core:os"
import "core:strconv"
import "core:slice"
import path "core:path/filepath"

LOG :: #config(LOG, false)

Token_Type :: enum {
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
    ReturnKeyword,
    IfKeyword,
    ElseKeyword,
    GotoKeyword,
    Ident,
    IntConstant,
    Semicolon,
}

Token_Data :: union {int}

Token :: struct {
    type: Token_Type,
    text: string,
    data: Token_Data,
}

lex_error :: proc(c: u8) {
    fmt.printfln("Unexpected token: %c", c)
    os.exit(2)
}

get_int_constant_token :: proc(input: string) -> (token: Token, rest: string) {
    byte_index: int

    for byte_index = 0; byte_index < len(input); byte_index += 1 {
        if !is_ascii_digit_byte(input[byte_index]) do break
    }

    if is_ascii_alpha_byte(input[byte_index]) do lex_error(input[byte_index])

    data := strconv.atoi(input[:byte_index])
    return Token{.IntConstant, input[:byte_index], data}, input[byte_index:]
}

get_keyword_or_ident_token :: proc(input: string) -> (token: Token, rest: string) {
    assert(is_ident_start_byte(input[0]))
    byte_index := 1

    for byte_index < len(input) && is_ident_tail_byte(input[byte_index]) {
        byte_index += 1
    }

    text := input[:byte_index]
    if text == "return" do return Token{.ReturnKeyword, text, {}}, input[byte_index:]
    else if text == "int" do return Token{.IntKeyword, text, {}}, input[byte_index:]
    else if text == "if" do return Token{.IfKeyword, text, {}}, input[byte_index:]
    else if text == "else" do return Token{.ElseKeyword, text, {}}, input[byte_index:]
    else if text == "goto" do return Token{.GotoKeyword, text, {}}, input[byte_index:]
    else do return Token{.Ident, text, {}}, input[byte_index:]
}

is_ascii_digit_byte :: proc(c: u8) -> bool {
    return '0' <= c && c <= '9'
}

is_ascii_alpha_byte :: proc(c: u8) -> bool {
    return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

is_ident_start_byte :: proc(c: u8) -> bool {
    return is_ascii_alpha_byte(c) || c == '_'
}

is_ident_tail_byte :: proc(c: u8) -> bool {
    return is_ascii_alpha_byte(c) || is_ascii_digit_byte(c) || c == '_'
}

lex :: proc(code: string) -> [dynamic]Token {
    code := code

    tokens := make([dynamic]Token)

    for {
        code = strings.trim_left_space(code)
        if code == "" do break

        switch (code[0]) {
            case '(':
                append(&tokens, Token{.LParen, code[:1], {}})
                code = code[1:]
                continue

            case ')':
                append(&tokens, Token{.RParen, code[:1], {}})
                code = code[1:]
                continue

            case '{':
                append(&tokens, Token{.LBrace, code[:1], {}})
                code = code[1:]
                continue
               
            case '}':
                append(&tokens, Token{.RBrace, code[:1], {}})
                code = code[1:]
                continue

            case ';':
                append(&tokens, Token{.Semicolon, code[:1], {}})
                code = code[1:]
                continue
            
            case '-':
                if code[1] == '-' {
                    append(&tokens, Token{.MinusMinus, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '=' {
                    append(&tokens, Token{.MinusEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Minus, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '!':
                if code[1] == '=' {
                    append(&tokens, Token{.BangEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Bang, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '?':
                append(&tokens, Token{.QuestionMark, code[:1], {}})
                code = code[1:]
                continue

            case ':':
                append(&tokens, Token{.Colon, code[:1], {}})
                code = code[1:]
                continue

            case '~':
                append(&tokens, Token{.Tilde, code[:1], {}})
                code = code[1:]
                continue

            case '*':
                if code[1] == '=' {
                    append(&tokens, Token{.StarEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Star, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '%':
                if code[1] == '=' {
                    append(&tokens, Token{.PercentEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Percent, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '/':
                if code[1] == '/' {
                    // Single line comments
                    i := 2
                    for code[i] != '\n' do i += 1
                    code = code[i + 1:]
                }
                else if code[1] == '=' {
                    append(&tokens, Token{.SlashEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '*' {
                    // Multi-line comments
                    i := 2
                    for code[i] != '*' || code[i + 1] != '/' do i += 1
                    code = code[i + 2:]
                }
                else {
                    append(&tokens, Token{.ForwardSlash, code[:1], {}})
                    code = code[1:]
                }
                continue

            // @HACK: We skip preprocessor directives for now, since they are more complicated than we are ready for
            case '#':
                i := 1
                for code[i] != '\n' do i += 1
                code = code[i + 1:]
                continue

            case '^':
                if code[1] == '=' {
                    append(&tokens, Token{.CaratEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Carat, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '+':
                if code[1] == '+' {
                    append(&tokens, Token{.PlusPlus, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '=' {
                    append(&tokens, Token{.PlusEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Plus, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '>':
                if code[1] == '=' {
                    append(&tokens, Token{.MoreEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '>' {
                    if code[2] == '=' {
                        append(&tokens, Token{.MoreMoreEqual, code[:3], {}})
                        code = code[3:]
                        continue
                    }
                    else {
                        append(&tokens, Token{.MoreMore, code[:2], {}})
                        code = code[2:]
                        continue
                    }
                }
                else {
                    append(&tokens, Token{.More, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '<':
                if code[1] == '=' {
                    append(&tokens, Token{.LessEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '<' {
                    if code[2] == '=' {
                        append(&tokens, Token{.LessLessEqual, code[:3], {}})
                        code = code[3:]
                        continue
                    }
                    else {
                        append(&tokens, Token{.LessLess, code[:2], {}})
                        code = code[2:]
                        continue
                    }
                }
                else {
                    append(&tokens, Token{.Less, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '&':
                if code[1] == '&' {
                    append(&tokens, Token{.DoubleAnd, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '=' {
                    append(&tokens, Token{.AndEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.And, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '|':
                if code[1] == '|' {
                    append(&tokens, Token{.DoublePipe, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else if code[1] == '=' {
                    append(&tokens, Token{.PipeEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Pipe, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case '=':
                if code[1] == '=' {
                    append(&tokens, Token{.DoubleEqual, code[:2], {}})
                    code = code[2:]
                    continue
                }
                else {
                    append(&tokens, Token{.Equal, code[:1], {}})
                    code = code[1:]
                    continue
                }

            case: // Not a punctuation. Fall through to below
        }

        token: Token
        if is_ascii_digit_byte(code[0]) {
            token, code = get_int_constant_token(code)
            append(&tokens, token)
        }
        else if is_ident_start_byte(code[0]) {
            token, code = get_keyword_or_ident_token(code)
            append(&tokens, token)
        }
        else {
            lex_error(code[0]);
        }
    }

    return tokens
}

take_first_token :: proc(tokens: []Token) -> (token: Token, rest: []Token) {
    if len(tokens) == 0 do parse_error(token, tokens)
    return slice.split_first(tokens)
}

peek_first_token :: proc(tokens: []Token) -> Token {
    if len(tokens) == 0 do parse_error({}, {})
    return tokens[0]
}

parse_error :: proc(current: Token, rest: []Token, location := #caller_location) {
    fmt.printfln("Unsuccessful parse in %v:%v", location.procedure, location.line)
    fmt.printfln("Current token: %v", current)
    fmt.printfln("The rest: %v", rest)
    os.exit(3)
}

parse_expression_leaf :: proc(tokens: []Token) -> (^Ast_Node, []Token) {
    token := peek_first_token(tokens)
    tokens := tokens

    #partial switch token.type {
        case .Minus:
            inner: ^Ast_Node = ---
            inner, tokens = parse_expression_leaf(tokens[1:])
            return make_node_1(Negate_Node, inner), tokens

        case .Tilde:
            inner: ^Ast_Node = ---
            inner, tokens = parse_expression_leaf(tokens[1:])
            return make_node_1(Bit_Negate_Node, inner), tokens

        case .Bang:
            inner: ^Ast_Node = ---
            inner, tokens = parse_expression_leaf(tokens[1:])
            return make_node_1(Boolean_Negate_Node, inner), tokens

        case .MinusMinus:
            inner: ^Ast_Node = ---
            inner, tokens = parse_expression_leaf(tokens[1:])
            return make_node_1(Pre_Decrement_Node, inner), tokens

        case .PlusPlus:
            inner: ^Ast_Node = ---
            inner, tokens = parse_expression_leaf(tokens[1:])
            return make_node_1(Pre_Increment_Node, inner), tokens

        case .IntConstant:
            inner := make_node_1(Int_Constant_Node, token.data.(int))
            return parse_postfix_operators(inner, tokens[1:])

        case .Ident:
            inner := make_node_1(Ident_Node, token.text)
            return parse_postfix_operators(inner, tokens[1:])

        case .LParen:
            expr: ^Ast_Node = ---
            expr, tokens = parse_expression(tokens[1:])
            token, tokens = take_first_token(tokens)
            if token.type != .RParen do parse_error(token, tokens)
            return parse_postfix_operators(expr, tokens)

        case:
            parse_error(token, tokens)
    }

    panic("Unreachable")
}

parse_postfix_operators :: proc(inner: ^Ast_Node, tokens: []Token) -> (^Ast_Node, []Token) {
    inner := inner
    tokens := tokens

    for token := peek_first_token(tokens); token.type == .PlusPlus || token.type == .MinusMinus; token = peek_first_token(tokens) {
        if token.type == .PlusPlus {
            op := make_node_1(Post_Increment_Node, inner)
            inner = op
        }
        else {
            op := make_node_1(Post_Decrement_Node, inner)
            inner = op
        }
        tokens = tokens[1:]
    }

    return inner, tokens
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

parse_expression :: proc(tokens: []Token, min_prec := 0) -> (^Ast_Node, []Token) {
    leaf, tokens := parse_expression_leaf(tokens)
    token := peek_first_token(tokens)

    for (token.type in assign_ops || token.type in bin_ops || token.type == .QuestionMark) \
        && op_precs[token.type] >= min_prec {
        if (token.type in assign_ops) {

            prec := op_precs[token.type]
            right: ^Ast_Node = ---
            right, tokens = parse_expression(tokens[1:], prec)
            op := make_binary_op_node(token.type, leaf, right)
            leaf = op
        }
        else if token.type in bin_ops {
            prec := op_precs[token.type]
            right: ^Ast_Node = ---
            // @TODO: Handle associativity here (see https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing)
            right, tokens = parse_expression(tokens[1:], prec + 1)
            op := make_binary_op_node(token.type, leaf, right)
            leaf = op
        }
        else {
            prec := op_precs[token.type]
            if_true: ^Ast_Node = ---
            if_false: ^Ast_Node = ---
            if_true, tokens = parse_expression(tokens[1:])
            token, tokens = take_first_token(tokens)
            if token.type != .Colon do parse_error(token, tokens)
            if_false, tokens = parse_expression(tokens, prec)
            op := make_node_3(Ternary_Node, leaf, if_true, if_false)
            leaf = op
        }

        token = peek_first_token(tokens)
    }

    return leaf, tokens
}

parse_labels :: proc(tokens: []Token) -> ([dynamic]string, []Token) {
    tokens := tokens
    labels := make([dynamic]string)

    for token := peek_first_token(tokens); token.type == .Ident && tokens[1].type == .Colon; token = peek_first_token(tokens) {
        append(&labels, token.text)
        tokens = tokens[2:]
    }

    return labels, tokens
}

parse_block_statement :: proc(tokens: []Token) -> (^Ast_Node, []Token) {
    labels, tokens := parse_labels(tokens)
    token := peek_first_token(tokens)

    #partial switch token.type {
        case .IntKeyword:
            if len(labels) > 0 do parse_error(token, tokens)
            token, tokens = take_first_token(tokens)
            token, tokens = take_first_token(tokens)
            if token.type != .Ident do parse_error(token, tokens)
            var_name := token.text
            token, tokens = take_first_token(tokens)

            if token.type == .Semicolon {
                statement := make_node_1(Decl_Node, var_name)
                return statement, tokens
            }
            else if token.type == .Equal {
                right: ^Ast_Node = ---
                right, tokens = parse_expression(tokens)
                statement := make_node_2(Decl_Assign_Node, var_name, right)
                token, tokens = take_first_token(tokens)
                if token.type != .Semicolon do parse_error(token, tokens)
                return statement, tokens
            }
            else {
                parse_error(token, tokens)
            }

        case:
            return parse_statement(tokens, labels)
    }
    
    panic("Unreachable")
}

parse_statement :: proc(tokens: []Token, labels: [dynamic]string = nil) -> (^Ast_Node, []Token) {
    tokens := tokens
    labels := labels
    if labels == nil {
        labels, tokens = parse_labels(tokens)
    }
    token := peek_first_token(tokens)

    result: ^Ast_Node = ---

    #partial switch token.type {
        case .ReturnKeyword:
            tokens = tokens[1:]
            expr: ^Ast_Node = ---
            expr, tokens = parse_expression(tokens)
            result = make_node_1(Return_Node, expr)
            token, tokens = take_first_token(tokens)
            if token.type != .Semicolon do parse_error(token, tokens)

        case .IfKeyword:
            tokens = tokens[1:]
            token, tokens = take_first_token(tokens)
            if token.type != .LParen do parse_error(token, tokens)
            condition: ^Ast_Node = ---
            condition, tokens = parse_expression(tokens)
            token, tokens = take_first_token(tokens)
            if token.type != .RParen do parse_error(token, tokens)

            if_true: ^Ast_Node = ---
            if_true, tokens = parse_statement(tokens)

            token = peek_first_token(tokens)
            if token.type == .ElseKeyword {
                if_false: ^Ast_Node = ---
                if_false, tokens = parse_statement(tokens[1:])
                result = make_node_3(If_Else_Node, condition, if_true, if_false)
            }
            else {
                result = make_node_2(If_Node, condition, if_true)
            }

        case .GotoKeyword:
            tokens = tokens[1:]
            token, tokens = take_first_token(tokens)
            if token.type != .Ident do parse_error(token, tokens)
            label := token.text
            token, tokens = take_first_token(tokens)
            if token.type != .Semicolon do parse_error(token, tokens)
            result = make_node_1(Goto_Node, label)

        case .Semicolon:
            tokens = tokens[1:]
            result = make_node_0(Null_Statement_Node)

        case .LBrace:
            statements: [dynamic]^Ast_Node = ---
            statements, tokens = parse_block_statement_list(tokens[1:])
            result = make_node_1(Compound_Statement_Node, statements)

        case:
            result, tokens = parse_expression(tokens)
            token, tokens = take_first_token(tokens)
            if token.type != .Semicolon do parse_error(token, tokens)
    }

    result.labels = labels
    return result, tokens
}

parse_block_statement_list :: proc(tokens: []Token) -> ([dynamic]^Ast_Node, []Token) {
    tokens := tokens
    list := make([dynamic]^Ast_Node)
    for token := peek_first_token(tokens); token.type != .RBrace; token = peek_first_token(tokens) {
        // Skip null statements
        if token.type == .Semicolon {
            tokens = tokens[1:]
            continue
        }
        block_statement: ^Ast_Node = ---
        block_statement, tokens = parse_block_statement(tokens)
        append(&list, block_statement)
    }

    token: Token = ---
    token, tokens = take_first_token(tokens)
    if token.type != .RBrace do parse_error(token, tokens)

    return list, tokens
}

parse_function :: proc(tokens: []Token) -> (^Ast_Node, []Token) {
    tokens := tokens
    token: Token = ---

    token, tokens = take_first_token(tokens)
    if token.type != .IntKeyword do parse_error(token, tokens)

    token, tokens = take_first_token(tokens)
    if token.type != .Ident do parse_error(token, tokens)
    name := token.text

    token, tokens = take_first_token(tokens)
    if token.type != .LParen do parse_error(token, tokens)
    token, tokens = take_first_token(tokens)
    if token.type != .Ident || token.text != "void" do parse_error(token, tokens)
    token, tokens = take_first_token(tokens)
    if token.type != .RParen do parse_error(token, tokens)

    token, tokens = take_first_token(tokens)
    if token.type != .LBrace do parse_error(token, tokens)

    body: [dynamic]^Ast_Node = ---
    body, tokens = parse_block_statement_list(tokens)

    // @HACK: This will need to change when we parse multiple functions
    if len(tokens) > 0 do parse_error(token, tokens)

    return make_node_2(Function_Node, name, body), tokens
}

parse :: proc(tokens: []Token) -> Program {
    tokens := tokens

    children := make([dynamic]^Ast_Node)

    for len(tokens) > 0 {
        function: ^Ast_Node = ---
        function, tokens = parse_function(tokens)
        append(&children, function)
    }

    return Program{children}
}

contains :: proc(elem: $E, list: $L/[]E) -> bool {
    for e in list {
        if e == elem do return true
    }
    return false
}

semantic_error :: proc(location := #caller_location) {
    fmt.printfln("Semantic error in %v", location)
    os.exit(4)
}

validate_and_gather_block_statement_labels :: proc(block_statement: ^Ast_Node, labels: ^[dynamic]string) {
    for label in block_statement.labels {
        if contains(label, labels[:]) do semantic_error()
        append(labels, label)
    }
}

validate_and_gather_function_labels :: proc(function: Function_Node) -> [dynamic]string {
    labels := make([dynamic]string)

    for block_statement in function.body {
        validate_and_gather_block_statement_labels(block_statement, &labels)

        #partial switch stmt in block_statement.variant {
            case If_Node:
                validate_and_gather_block_statement_labels(stmt.if_true, &labels)

            case If_Else_Node:
                validate_and_gather_block_statement_labels(stmt.if_true, &labels)
                validate_and_gather_block_statement_labels(stmt.if_false, &labels)

            case Compound_Statement_Node:
                for block_statement in stmt.statements {
                    validate_and_gather_block_statement_labels(block_statement, &labels)
                }
        }
    }

    return labels
}

/*
validate_and_gather_variables :: proc(program: Program, labels: map[string][dynamic]string) -> ^Scoped_Variables {
    scoped_vars := new(Scoped_Variables)

    for node in program.children {
        function := node.variant.(Function_Node)
        vars := make_scoped_variables(scoped_vars, node) 
        validate_function(function, vars, &labels[function.name])
    }

    return scoped_vars
}

validate_function :: proc(function: Function_Node, vars: ^Scoped_Variables, labels: ^[dynamic]string) {
    for block_statement in function.body {
        validate_block_statement(block_statement, vars, labels)
    }
}

validate_block_statement :: proc(block_statement: ^Ast_Node, vars: ^Scoped_Variables, labels: ^[dynamic]string) {
    #partial switch stmt in block_statement.variant {
        case Decl_Node:
            if stmt.var_name in vars.var_offsets do semantic_error()
            vars.var_offsets[stmt.var_name] = 0

        case Decl_Assign_Node:
            if stmt.var_name in vars.var_offsets do semantic_error()
            vars.var_offsets[stmt.var_name] = 0

        case:
            validate_statement(block_statement, vars, labels)
    }
}

validate_statement :: proc(statement: ^Ast_Node, vars: ^Scoped_Variables, labels: ^[dynamic]string) {
    #partial switch stmt in statement.variant {
        case Return_Node:
            validate_expr(stmt.expr, vars)

        case If_Node:
            validate_expr(stmt.condition, vars)
            validate_statement(stmt.if_true, vars, labels)

        case If_Else_Node:
            validate_expr(stmt.condition, vars)
            validate_statement(stmt.if_true, vars, labels)
            validate_statement(stmt.if_false, vars, labels)

        case Goto_Node:
            if !contains(stmt.label, labels[:]) do semantic_error()

        case Compound_Statement_Node:
            inner_vars := make_scoped_variables(vars, statement)
            for block_statement in stmt.statements {
                validate_block_statement(block_statement, inner_vars, labels)
            }

        case:
            validate_expr(statement, vars)
    }
}

validate_expr :: proc(expr: ^Ast_Node, vars: ^Scoped_Variables) {
    #partial switch e in expr.variant {
        case Ident_Node:
            if !is_defined(vars, e.var_name) do semantic_error()

        case Negate_Node: validate_expr(e.expr, vars)
        case Bit_Negate_Node: validate_expr(e.expr, vars)
        case Boolean_Negate_Node: validate_expr(e.expr, vars)
        case Pre_Decrement_Node:
            if _, is_ident := e.expr.variant.(Ident_Node); !is_ident do semantic_error()
            validate_expr(e.expr, vars)
        case Pre_Increment_Node:
            if _, is_ident := e.expr.variant.(Ident_Node); !is_ident do semantic_error()
            validate_expr(e.expr, vars)
        case Post_Decrement_Node:
            if _, is_ident := e.expr.variant.(Ident_Node); !is_ident do semantic_error()
            validate_expr(e.expr, vars)
        case Post_Increment_Node:
            if _, is_ident := e.expr.variant.(Ident_Node); !is_ident do semantic_error()
            validate_expr(e.expr, vars)

        case Add_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Subtract_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Multiply_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Modulo_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Divide_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Boolean_And_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Boolean_Or_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Boolean_Equal_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Boolean_Not_Equal_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Less_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Less_Equal_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case More_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case More_Equal_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Bit_And_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Bit_Or_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Bit_Xor_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Shift_Left_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
        case Shift_Right_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)

        case Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Plus_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Minus_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Times_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Divide_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Modulo_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Xor_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Or_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case And_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Shift_Left_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)
        case Shift_Right_Equal_Node:
            ident, is_ident := e.left.variant.(Ident_Node)
            if !is_ident do semantic_error()
            if !is_defined(vars, ident.var_name) do semantic_error()
            validate_expr(e.right, vars)

        case Ternary_Node:
            validate_expr(e.condition, vars)
            validate_expr(e.if_true, vars)
            validate_expr(e.if_false, vars)
    }
}
*/

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

current_label := 1
current_offset := 4

emit_label :: proc(builder: ^strings.Builder, label := -1) {
    if label == -1 {
        fmt.sbprintfln(builder, "L%v:", current_label)
        current_label += 1
    }
    else {
        fmt.sbprintfln(builder, "L%v:", label)
    }
}

emit_unary_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, offsets: ^Scoped_Variable_Offsets) {
    #partial switch o in op.variant {
        case Negate_Node:
            emit_expr(builder, o.expr, offsets)
            fmt.sbprintln(builder, "  neg %eax")

        case Bit_Negate_Node:
            emit_expr(builder, o.expr, offsets)
            fmt.sbprintln(builder, "  not %eax")

        case Boolean_Negate_Node:
            emit_expr(builder, o.expr, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")

        case Pre_Decrement_Node:
            fmt.sbprintfln(builder, "  decl -%v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Pre_Increment_Node:
            fmt.sbprintfln(builder, "  incl -%v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Decrement_Node:
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  decl -%v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case Post_Increment_Node:
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))
            fmt.sbprintfln(builder, "  incl -%v(%%rbp)", get_offset(offsets, o.expr.variant.(Ident_Node).var_name))

        case:
            fmt.println(op)
            panic("Not a valid unary operator!")
    }
}

emit_binary_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, vars: ^Scoped_Variable_Offsets) {
    #partial switch o in op.variant {
        case Add_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  add %ebx, %eax")
        
        case Subtract_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  sub %eax, %ebx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")

        case Multiply_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  imul %ebx")

        case Modulo_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  idiv %ecx")
            fmt.sbprintln(builder, "  mov %edx, %eax")

        case Divide_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  idiv %ecx")

        case Boolean_And_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 1
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            fmt.sbprintln(builder, "  mov $1, %eax")
            emit_label(builder, label)

        case Boolean_Or_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 2 
            fmt.sbprintfln(builder, "  jne L%v", label)
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 1)
            emit_label(builder, label)
            fmt.sbprintln(builder, "    mov $1, %eax")
            emit_label(builder, label + 1)

        case Boolean_Equal_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")

        case Boolean_Not_Equal_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setne %al")

        case Less_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnge %al")

        case Less_Equal_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setle %al")

        case More_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnle %al")

        case More_Equal_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setge %al")

        case Bit_And_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  and %ebx, %eax")

        case Bit_Or_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  or %ebx, %eax")

        case Bit_Xor_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %ebx, %eax")

        // @TODO: This will need some semantics passes, but we are skipping them for now until we have type checking since a lot of the semantics depends on this
        case Shift_Left_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  shl %cl, %eax")

        case Shift_Right_Node:
            emit_expr(builder, o.left, vars)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, o.right, vars)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            // @TODO: Whether this is a logical or arithmetic shift depends on the type of the left expression. Since we assume everything is a signed int for now,
            // we do an arithmetic shift right.
            fmt.sbprintln(builder, "  sar %cl, %eax")

        case:
            fmt.println(op)
            panic("Not a valid binary operator!")
    }
}

emit_assign_op :: proc(builder: ^strings.Builder, op: ^Ast_Node, offsets: ^Scoped_Variable_Offsets) {
    fmt.println("\n\nEmitting assignment operator:")
    pretty_print_node(op^)
    #partial switch o in op.variant {
        case Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Plus_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  add %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            
        case Minus_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  sub %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Times_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  imul %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Divide_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Modulo_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%edx, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  mov %edx, %eax")

        case Xor_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  xor %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Or_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  or %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case And_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  and %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Left_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  shl %cl, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case Shift_Right_Equal_Node:
            emit_expr(builder, o.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(offsets, o.left.variant.(Ident_Node).var_name))
            fmt.sbprintln(builder, "  shr %cl, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, o.left.variant.(Ident_Node).var_name))

        case:
            fmt.println(op)
            panic("Not a valid assignment operator!")
    }
}

emit_expr :: proc(builder: ^strings.Builder, expr: ^Ast_Node, vars: ^Scoped_Variable_Offsets) {
    fmt.println("\n\nEmitting expression:")
    pretty_print_node(expr^)
    #partial switch e in expr.variant {
        case Int_Constant_Node:
            fmt.sbprintfln(builder, "  mov $%v, %%eax", e.value)

        case Ident_Node:
            if !is_defined(vars, e.var_name) do semantic_error()
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", get_offset(vars, e.var_name))

        case Negate_Node: emit_unary_op(builder, expr, vars)
        case Bit_Negate_Node: emit_unary_op(builder, expr, vars)
        case Boolean_Negate_Node: emit_unary_op(builder, expr, vars)
        case Pre_Decrement_Node: emit_unary_op(builder, expr, vars)
        case Pre_Increment_Node: emit_unary_op(builder, expr, vars)
        case Post_Decrement_Node: emit_unary_op(builder, expr, vars)
        case Post_Increment_Node: emit_unary_op(builder, expr, vars)
            

        case Add_Node: emit_binary_op(builder, expr, vars)
        case Subtract_Node: emit_binary_op(builder, expr, vars)
        case Multiply_Node: emit_binary_op(builder, expr, vars)
        case Modulo_Node: emit_binary_op(builder, expr, vars)
        case Divide_Node: emit_binary_op(builder, expr, vars)
        case Boolean_And_Node: emit_binary_op(builder, expr, vars)
        case Boolean_Or_Node: emit_binary_op(builder, expr, vars)
        case Boolean_Equal_Node: emit_binary_op(builder, expr, vars)
        case Boolean_Not_Equal_Node: emit_binary_op(builder, expr, vars)
        case Less_Node: emit_binary_op(builder, expr, vars)
        case Less_Equal_Node: emit_binary_op(builder, expr, vars)
        case More_Node: emit_binary_op(builder, expr, vars)
        case More_Equal_Node: emit_binary_op(builder, expr, vars)
        case Bit_And_Node: emit_binary_op(builder, expr, vars)
        case Bit_Or_Node: emit_binary_op(builder, expr, vars)
        case Bit_Xor_Node: emit_binary_op(builder, expr, vars)
        case Shift_Left_Node: emit_binary_op(builder, expr, vars)
        case Shift_Right_Node: emit_binary_op(builder, expr, vars)

        case Equal_Node: emit_assign_op(builder, expr, vars)
        case Plus_Equal_Node: emit_assign_op(builder, expr, vars)
        case Minus_Equal_Node: emit_assign_op(builder, expr, vars)
        case Times_Equal_Node: emit_assign_op(builder, expr, vars)
        case Divide_Equal_Node: emit_assign_op(builder, expr, vars)
        case Modulo_Equal_Node: emit_assign_op(builder, expr, vars)
        case Xor_Equal_Node: emit_assign_op(builder, expr, vars)
        case Or_Equal_Node: emit_assign_op(builder, expr, vars)
        case And_Equal_Node: emit_assign_op(builder, expr, vars)
        case Shift_Left_Equal_Node: emit_assign_op(builder, expr, vars)
        case Shift_Right_Equal_Node: emit_assign_op(builder, expr, vars)

        case Ternary_Node:
            label := current_label
            current_label += 2
            emit_expr(builder, e.condition, vars)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_expr(builder, e.if_true, vars)
            fmt.sbprintfln(builder, "  jmp L%v", label + 1)
            emit_label(builder, label)
            emit_expr(builder, e.if_false, vars)
            emit_label(builder, label + 1)

        case:
            fmt.println(expr)
            panic("Not a valid expression!")
    }
}

emit_block_statement :: proc(builder: ^strings.Builder, block_statement: ^Ast_Node, offsets: ^Scoped_Variable_Offsets, function_name: string) {
    fmt.println("\n\nEmitting block statement:")
    pretty_print_node(block_statement^)
    #partial switch stmt in block_statement.variant {
        case Decl_Assign_Node:
            if is_defined(offsets, stmt.var_name) do semantic_error()
            offsets.var_offsets[stmt.var_name] = current_offset
            current_offset += 4
            emit_expr(builder, stmt.right, offsets)
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", get_offset(offsets, stmt.var_name))

        case Decl_Node: // Space on the stack is already allocated by emit_function
            if is_defined(offsets, stmt.var_name) do semantic_error()
            offsets.var_offsets[stmt.var_name] = current_offset
            current_offset += 4

        case:
            emit_statement(builder, block_statement, offsets, function_name)
    }

}

emit_statement :: proc(builder: ^strings.Builder, statement: ^Ast_Node, parent_offsets: ^Scoped_Variable_Offsets, function_name: string) {
    fmt.println("\n\nEmitting statement:")
    pretty_print_node(statement^)
    for label in statement.labels {
        fmt.sbprintfln(builder, "_%v:", label)
    }

    #partial switch stmt in statement.variant {
        case Null_Statement_Node: // Do nothing

        case Return_Node:
            emit_expr(builder, stmt.expr, parent_offsets)
            fmt.sbprintfln(builder, "  jmp %v_done", function_name)

        case If_Node:
            label := current_label
            current_label += 1
            emit_expr(builder, stmt.condition, parent_offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_statement(builder, stmt.if_true, parent_offsets, function_name)
            emit_label(builder, label)

        case If_Else_Node:
            label := current_label
            current_label += 2
            emit_expr(builder, stmt.condition, parent_offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_statement(builder, stmt.if_true, parent_offsets, function_name)
            fmt.sbprintfln(builder, "  jmp L%v", label + 1)
            emit_label(builder, label)
            emit_statement(builder, stmt.if_false, parent_offsets, function_name)
            emit_label(builder, label + 1)

        case Goto_Node:
            fmt.sbprintfln(builder, "  jmp _%v", stmt.label)

        case Compound_Statement_Node:
            offsets := make_scoped_variable_offsets(parent_offsets)
            for block_statement in stmt.statements {
                emit_block_statement(builder, block_statement, offsets, function_name)
            }

        case:
            emit_expr(builder, statement, parent_offsets)
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

print_scoped_variable_offsets :: proc(vars: ^Scoped_Variable_Offsets, indent := 0) {
    print_indent(indent)
    fmt.print("vars=(")
    if len(vars.var_offsets) != 0 {
        fmt.println()
        for var in vars.var_offsets {
            print_indent(indent + 1)
            fmt.println(var)
        }
        print_indent(indent)
    }
    fmt.println(")")
}

count_function_variable_declarations :: proc(function: Function_Node) -> int {
    declarations := 0

    for block_statement in function.body {
        #partial switch stmt in block_statement.variant {
            case Decl_Node, Decl_Assign_Node:
                declarations += 1

            case Compound_Statement_Node:
                declarations += count_compound_statement_variable_declarations(stmt)
        }
    }

    return declarations
}

count_compound_statement_variable_declarations :: proc(compound_statement: Compound_Statement_Node) -> int {
    declarations := 0

    for block_statement in compound_statement.statements {
        #partial switch stmt in block_statement.variant {
            case Decl_Node, Decl_Assign_Node:
                declarations += 1

            case Compound_Statement_Node:
                declarations += count_compound_statement_variable_declarations(stmt)
        }
    }

    return declarations
}

emit_function :: proc(builder: ^strings.Builder, function: Function_Node, parent_offsets: ^Scoped_Variable_Offsets) {
    fmt.println("Emitting function ", function.name)
    labels := validate_and_gather_function_labels(function)

    fmt.sbprintfln(builder, ".globl %v", function.name)
    fmt.sbprintfln(builder, "%v:", function.name)
    fmt.sbprintln(builder, "  push %rbp")
    fmt.sbprintln(builder, "  mov %rsp, %rbp")

    rsp_decrement := count_function_variable_declarations(function) * 4
    if rsp_decrement > 0 {
        fmt.sbprintfln(builder, "  sub $%v, %%rsp", rsp_decrement)
    }

    offsets := make_scoped_variable_offsets(parent_offsets)
    for statement in function.body {
        emit_block_statement(builder, statement, offsets, function.name)
    }

    if function.name == "main" {
        fmt.sbprintln(builder, "  xor %eax, %eax")
    }

    fmt.sbprintfln(builder, "%v_done:", function.name)
    if rsp_decrement > 0 {
        fmt.sbprintfln(builder, "  add $%v, %%rsp", rsp_decrement)
    }
    fmt.sbprintln(builder, "  pop %rbp")
    fmt.sbprintln(builder, "  ret")
}

emit :: proc(program: Program) -> string {
    builder: strings.Builder
    offsets := make_scoped_variable_offsets(nil) // Global scope has no parent

    for node in program.children {
        function := node.variant.(Function_Node)
        emit_function(&builder, function, offsets)
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

    tokens := lex(string(code[:]))
    program := parse(tokens[:])
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
