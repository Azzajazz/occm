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
    assert(is_ascii_alpha_byte(input[0]))
    byte_index := 1

    for byte_index < len(input) && is_ident_tail_byte(input[byte_index]) {
        byte_index += 1
    }

    text := input[:byte_index]
    if text == "return" do return Token{.ReturnKeyword, text, {}}, input[byte_index:]
    else if text == "int" do return Token{.IntKeyword, text, {}}, input[byte_index:]
    else do return Token{.Ident, text, {}}, input[byte_index:]
}

is_ascii_digit_byte :: proc(c: u8) -> bool {
    return '0' <= c && c <= '9'
}

is_ascii_alpha_byte :: proc(c: u8) -> bool {
    return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
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
        else if is_ascii_alpha_byte(code[0]) {
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

parse_error :: proc(current: Token, rest: []Token, location := #caller_location) {
    fmt.printfln("Unsuccessful parse in %v:%v", location.procedure, location.line)
    fmt.printfln("Current token: %v", current)
    fmt.printfln("The rest: %v", rest)
    os.exit(3)
}

parse_expression_leaf :: proc(tokens: []Token) -> (Expr_Node, []Token) {
    tokens := tokens
    token: Token = ---

    token, tokens = take_first_token(tokens)
    #partial switch token.type {
        case .IntConstant:
            expr := new(Int_Constant_Node)
            expr.value = token.data.(int)
            return expr, tokens

        case .Ident:
            expr := new(Ident_Node)
            expr.var_name = token.text
            return expr, tokens

        case .Minus:
            expr := new(Unary_Op_Node)
            expr.type = .Negate
            expr.expr, tokens = parse_expression_leaf(tokens)
            return expr, tokens

        case .Bang:
            expr := new(Unary_Op_Node)
            expr.type = .BoolNegate
            expr.expr, tokens = parse_expression_leaf(tokens)
            return expr, tokens

        case .Tilde:
            expr := new(Unary_Op_Node)
            expr.type = .BinaryNegate
            expr.expr, tokens = parse_expression_leaf(tokens)
            return expr, tokens

        case .LParen:
            expr: Expr_Node = ---
            expr, tokens = parse_expression(tokens)
            if tokens[0].type != .RParen do parse_error(token, tokens)
            return expr, tokens[1:] // Remove the )

        case:
            parse_error(token, tokens)
    }

    panic("Unreachable")
}

op_precs := map[Token_Type]int {
    .Equal = 8,
    .PlusEqual = 8,
    .MinusEqual = 8,
    .StarEqual = 8,
    .SlashEqual = 8,
    .PercentEqual = 8,
    .CaratEqual = 8,
    .PipeEqual = 8,
    .AndEqual = 8,
    .LessLessEqual = 8,
    .MoreMoreEqual = 8,
    // @TODO: Add all other compound operators
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

make_binary_op_node :: proc(type: Token_Type) -> ^Binary_Op_Node {
    expr := new(Binary_Op_Node)
    #partial switch type {
        case .Minus:
            expr.type = .Subtract

        case .Plus:
            expr.type = .Add

        case .Star:
            expr.type = .Multiply

        case .Percent:
            expr.type = .Modulo

        case .ForwardSlash:
            expr.type = .Divide

        case .DoubleAnd:
            expr.type = .BoolAnd

        case .DoublePipe:
            expr.type = .BoolOr

        case .DoubleEqual:
            expr.type = .BoolEqual

        case .BangEqual:
            expr.type = .BoolNotEqual

        case .LessEqual:
            expr.type = .BoolLessEqual

        case .Less:
            expr.type = .BoolLess

        case .MoreEqual:
            expr.type = .BoolMoreEqual

        case .More:
            expr.type = .BoolMore

        case .And:
            expr.type = .BitAnd

        case .Pipe:
            expr.type = .BitOr

        case .Carat:
            expr.type = .BitXor

        case .LessLess:
            expr.type = .ShiftLeft

        case .MoreMore:
            expr.type = .ShiftRight

        case:
            fmt.eprintln(type)
            panic("Not a valid binary operator")
    }

    return expr 
}

make_assign_op_node :: proc(type: Token_Type) -> ^Assign_Op_Node {
    node := new(Assign_Op_Node)

    #partial switch type {
        case .Equal:
            node.type = .Equal

        case .PlusEqual:
            node.type = .PlusEqual

        case .MinusEqual:
            node.type = .MinusEqual
        
        case .StarEqual:
            node.type = .TimesEqual

        case .SlashEqual:
            node.type = .DivideEqual

        case .PercentEqual:
            node.type = .ModEqual

        case .CaratEqual:
            node.type = .XorEqual

        case .PipeEqual:
            node.type = .OrEqual

        case .AndEqual:
            node.type = .AndEqual

        case .LessLessEqual:
            node.type = .ShiftLeftEqual

        case .MoreMoreEqual:
            node.type = .ShiftRightEqual

        case:
            fmt.eprintln(type)
            panic("Not a valid compound operator!")
    }

    return node
}

parse_expression :: proc(tokens: []Token, min_prec := 0) -> (Expr_Node, []Token) {
    leaf, tokens := parse_expression_leaf(tokens)

    for ((tokens[0].type in assign_ops) || (tokens[0].type in bin_ops)) && op_precs[tokens[0].type] >= min_prec {
        if (tokens[0].type in assign_ops) {
            ident, is_ident := leaf.(^Ident_Node)
            // @REVISIT: This would be better separated into the semantic pass, but this requires an Assign_Op_Node
            // with a left that can be something other than an Ident_Node
            if !is_ident do semantic_error()

            prec := op_precs[tokens[0].type]
            op := make_assign_op_node(tokens[0].type)
            op.left = ident 
            op.right, tokens = parse_expression(tokens[1:], prec)
            leaf = op
        }
        else {
            prec := op_precs[tokens[0].type]
            op := make_binary_op_node(tokens[0].type)
            // @TODO: Handle associativity here (see https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing)
            op.right, tokens = parse_expression(tokens[1:], prec + 1)
            op.left = leaf
            leaf = op
        }
    }

    return leaf, tokens
}

parse_statement :: proc(tokens: []Token) -> (Statement_Node, []Token) {
    tokens := tokens
    token: Token = ---

    #partial switch tokens[0].type {
        case .ReturnKeyword:
            token, tokens = take_first_token(tokens)
            statement := new(Return_Node) 
            expr: Expr_Node = ---
            expr, tokens = parse_expression(tokens)
            statement.expr = expr
            token, tokens = take_first_token(tokens)
            if token.type != .Semicolon do parse_error(token, tokens)
            return statement, tokens

        case .IntKeyword:
            token, tokens = take_first_token(tokens)
            token, tokens = take_first_token(tokens)
            if token.type != .Ident do parse_error(token, tokens)
            var_name := token.text
            token, tokens = take_first_token(tokens)

            if token.type == .Semicolon {
                statement := new(Decl_Node)
                statement.var_name = var_name
                return statement, tokens
            }
            else if token.type == .Equal {
                statement := new(Decl_Assign_Node)
                statement.var_name = var_name
                statement.right, tokens = parse_expression(tokens)
                token, tokens = take_first_token(tokens)
                if token.type != .Semicolon do parse_error(token, tokens)
                return statement, tokens
            }
            else {
                parse_error(token, tokens)
            }

        case:
            statement, tokens := parse_expression(tokens)
            token, tokens = take_first_token(tokens)
            if token.type != .Semicolon do parse_error(token, tokens)
            return statement, tokens
    }

    panic("Unreachable")
}

parse_function :: proc(tokens: []Token) -> (^Function_Node, []Token) {
    tokens := tokens
    token: Token = ---

    function := new(Function_Node)

    token, tokens = take_first_token(tokens)
    if token.type != .IntKeyword do parse_error(token, tokens)

    token, tokens = take_first_token(tokens)
    if token.type != .Ident do parse_error(token, tokens)
    function.name = token.text

    token, tokens = take_first_token(tokens)
    if token.type != .LParen do parse_error(token, tokens)
    token, tokens = take_first_token(tokens)
    if token.type != .Ident || token.text != "void" do parse_error(token, tokens)
    token, tokens = take_first_token(tokens)
    if token.type != .RParen do parse_error(token, tokens)

    token, tokens = take_first_token(tokens)
    if token.type != .LBrace do parse_error(token, tokens)

    function.body = make([dynamic]Statement_Node)
    for tokens[0].type != .RBrace {
        // Skip null statements
        if tokens[0].type == .Semicolon {
            tokens = tokens[1:]
            continue
        }
        statement: Statement_Node = ---
        statement, tokens = parse_statement(tokens)
        append(&function.body, statement)
    }

    token, tokens = take_first_token(tokens)
    if token.type != .RBrace do parse_error(token, tokens)

    // @HACK: This will need to change when we parse multiple functions
    if len(tokens) > 0 do parse_error(token, tokens)

    return function, tokens
}

parse :: proc(tokens: []Token) -> Program {
    tokens := tokens

    children := make([dynamic]^Function_Node)

    for len(tokens) > 0 {
        function: ^Function_Node = ---
        function, tokens = parse_function(tokens)
        append(&children, function)
    }

    return Program{children}
}

contains_variable :: proc(var: string, vars: ^[dynamic]string) -> bool {
    for v in vars {
        if v == var do return true
    }
    return false
}

semantic_error :: proc() {
    os.exit(4)
}

check_and_gather_variables :: proc(program: Program) -> map[string][dynamic]string {
    result := make(map[string][dynamic]string)

    for function in program.children {
        result[function.name] = make([dynamic]string)
        check_and_gather_function_variables(function, &result[function.name])
    }

    return result
}

check_and_gather_function_variables :: proc(function: ^Function_Node, vars: ^[dynamic]string) {
    for statement in function.body {
        #partial switch stmt in statement {
            case Expr_Node:
                validate_expr(stmt, vars)

            case ^Return_Node:
                validate_expr(stmt.expr, vars)

            case ^Decl_Node:
                if contains_variable(stmt.var_name, vars) do semantic_error()
                append(vars, stmt.var_name)

            case ^Decl_Assign_Node:
                if contains_variable(stmt.var_name, vars) do semantic_error()
                append(vars, stmt.var_name)
        }
    }
}

validate_expr :: proc(expr: Expr_Node, vars: ^[dynamic]string) {
    #partial switch e in expr {
        case ^Ident_Node:
            if !contains_variable(e.var_name, vars) do semantic_error()

        case ^Unary_Op_Node:
            validate_expr(e.expr, vars)

        case ^Binary_Op_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)

        case ^Assign_Op_Node:
            validate_expr(e.left, vars)
            validate_expr(e.right, vars)
    }
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

emit_unary_op :: proc(builder: ^strings.Builder, op: Unary_Op_Node, offsets: ^map[string]int) {
    switch op.type {
        case .Negate:
            emit_expr(builder, op.expr, offsets)
            fmt.sbprintln(builder, "  neg %eax")

        case .BinaryNegate:
            emit_expr(builder, op.expr, offsets)
            fmt.sbprintln(builder, "  not %eax")

        case .BoolNegate:
            emit_expr(builder, op.expr, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")
    }
}

emit_binary_op :: proc(builder: ^strings.Builder, op: Binary_Op_Node, offsets: ^map[string]int) {
    switch op.type {
        case .Add:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  add %ebx, %eax")
        
        case .Subtract:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  sub %eax, %ebx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")

        case .Multiply:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  imul %ebx")

        case .Modulo:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
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

        case .Divide:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  idiv %ecx")

        case .BoolAnd:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 1
            fmt.sbprintfln(builder, "  je L%v", label)
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label)
            fmt.sbprintln(builder, "  mov $1, %eax")
            emit_label(builder, label)

        case .BoolOr:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            label := current_label
            current_label += 2 
            fmt.sbprintfln(builder, "  jne L%v", label)
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  cmp $0, %eax")
            fmt.sbprintfln(builder, "  je L%v", label + 1)
            emit_label(builder, label)
            fmt.sbprintln(builder, "    mov $1, %eax")
            emit_label(builder, label + 1)

        case .BoolEqual:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  sete %al")

        case .BoolNotEqual:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setne %al")

        case .BoolLess:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnge %al")

        case .BoolLessEqual:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setle %al")

        case .BoolMore:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setnle %al")

        case .BoolMoreEqual:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  cmp %eax, %ebx")
            fmt.sbprintln(builder, "  mov $0, %eax")
            fmt.sbprintln(builder, "  setge %al")

        case .BitAnd:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  and %ebx, %eax")

        case .BitOr:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  or %ebx, %eax")

        case .BitXor:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  xor %ebx, %eax")

        // @TODO: This will need some semantics passes, but we are skipping them for now until we have type checking since a lot of the semantics depends on this
        case .ShiftLeft:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            fmt.sbprintln(builder, "  shl %cl, %eax")

        case .ShiftRight:
            emit_expr(builder, op.left, offsets)
            fmt.sbprintln(builder, "  push %rax")
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  pop %rbx")
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintln(builder, "  mov %ebx, %eax")
            // @TODO: Whether this is a logical or arithmetic shift depends on the type of the left expression. Since we assume everything is a signed int for now,
            // we do an arithmetic shift right.
            fmt.sbprintln(builder, "  sar %cl, %eax")
    }
}

emit_assign_op :: proc(builder: ^strings.Builder, op: Assign_Op_Node, offsets: ^map[string]int) {
    switch op.type {
        case .Equal:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .PlusEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  add %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])
            
        case .MinusEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  sub %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .TimesEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  imul %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .DivideEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .ModEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ebx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  xor %edx, %edx")
            fmt.sbprintln(builder, "  cmp $0, %ebx")
            fmt.sbprintfln(builder, "  jge L%v", current_label)
            fmt.sbprintln(builder, "  dec %edx")
            emit_label(builder)
            fmt.sbprintln(builder, "  idiv %ebx")
            fmt.sbprintfln(builder, "  mov %%edx, -%v(%%rbp)", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  mov %edx, %eax")

        case .XorEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  xor %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .OrEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  or %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .AndEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%ebx", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  and %ebx, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .ShiftLeftEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  shl %cl, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])

        case .ShiftRightEqual:
            emit_expr(builder, op.right, offsets)
            fmt.sbprintln(builder, "  mov %eax, %ecx")
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[op.left.var_name])
            fmt.sbprintln(builder, "  shr %cl, %eax")
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[op.left.var_name])
    }
}

emit_expr :: proc(builder: ^strings.Builder, expr: Expr_Node, offsets: ^map[string]int) {
    switch e in expr {
        case ^Int_Constant_Node:
            fmt.sbprintfln(builder, "  mov $%v, %%eax", e.value)

        case ^Ident_Node:
            fmt.sbprintfln(builder, "  mov -%v(%%rbp), %%eax", offsets[e.var_name])

        case ^Unary_Op_Node:
            emit_unary_op(builder, e^, offsets)

        case ^Binary_Op_Node:
            emit_binary_op(builder, e^, offsets)

        case ^Assign_Op_Node:
            emit_assign_op(builder, e^, offsets)
    }
}

emit_statement :: proc(builder: ^strings.Builder, statement: Statement_Node, offsets: ^map[string]int, function_name: string) {
    switch stmt in statement {
        case ^Return_Node:
            emit_expr(builder, stmt.expr, offsets)
            fmt.sbprintfln(builder, "  jmp %v_done", function_name)

        case ^Decl_Assign_Node:
            emit_expr(builder, stmt.right, offsets)
            fmt.sbprintfln(builder, "  mov %%eax, -%v(%%rbp)", offsets[stmt.var_name])

        case ^Decl_Node: // Space on the stack is already allocated by emit_function

        case Expr_Node:
            emit_expr(builder, stmt, offsets)
    }
}

emit_function :: proc(builder: ^strings.Builder, function: ^Function_Node, vars: ^[dynamic]string) {
    fmt.sbprintfln(builder, ".globl %v", function.name)
    fmt.sbprintfln(builder, "%v:", function.name)
    fmt.sbprintln(builder, "  push %rbp")
    fmt.sbprintln(builder, "  mov %rsp, %rbp")

    // Calculate how much we need to decrement rsp by
    rsp_decrement := len(vars) * 4
    if rsp_decrement > 0 {
        fmt.sbprintfln(builder, "  sub $%v, %%rsp", rsp_decrement)
    }

    // Build up a map of the variable offsets from rbp
    offsets := make(map[string]int)
    defer delete(offsets)
    for v, i in vars {
        offsets[v] = 4 * (i + 1)
    }

    for statement in function.body {
        emit_statement(builder, statement, &offsets, function.name)
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

emit :: proc(program: Program, var_map: ^map[string][dynamic]string) -> string {
    builder: strings.Builder

    for function in program.children {
        emit_function(&builder, function, &var_map[function.name])
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

    var_map := check_and_gather_variables(program)
    when LOG {
        fmt.println("\n\n------ VARIABLE MAP ------")
        fmt.println(var_map)
    }

    assembly := emit(program, &var_map)
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
