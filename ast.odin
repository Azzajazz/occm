package occm

import "core:fmt"

Program :: struct {
    children: [dynamic]^Function_Node,
}

Node_Base :: struct {
}

Function_Node :: struct {
    using base: Node_Base,
    name: string,
    body: [dynamic]Statement_Node,
}

Expr_Node :: union {
    ^Int_Constant_Node,
    ^Unary_Op_Node,
    ^Binary_Op_Node,
}

Unary_Op_Type :: enum {
    Negate,
    BinaryNegate,
    BoolNegate,
}

Unary_Op_Node :: struct {
    using base: Node_Base,
    type: Unary_Op_Type,
    expr: Expr_Node,
}

Binary_Op_Type :: enum {
    Add,
    Subtract,
    Multiply,
    Modulo,
    Divide,
    BoolAnd,
    BoolOr,
    BoolEqual,
    BoolNotEqual,
    BoolLess,
    BoolLessEqual,
    BoolMore,
    BoolMoreEqual,
}

Binary_Op_Node :: struct {
    using base: Node_Base,
    type: Binary_Op_Type,
    left: Expr_Node,
    right: Expr_Node,
}

Int_Constant_Node :: struct {
    using base: Node_Base,
    value: int,
}

/*
Negate_Node :: struct {
    using base: Node_Base,
    expr: Expr_Node,
}

Bool_Negate_Node :: struct {
    using base: Node_Base,
    expr: Expr_Node,
}

Binary_Negate_Node :: struct {
    using base: Node_Base,
    expr: Expr_Node,
}
*/

Statement_Node :: union {
    ^Return_Node,
}

Return_Node :: struct {
    using base: Node_Base,
    expr: Expr_Node,
}

// Printing functions for debugging

print_indent :: proc(indent: int) {
    for i in 0..<indent {
        fmt.print("  ")
    }
}

pretty_print_unary_op_node :: proc(op: Unary_Op_Node, indent := 0) {
    print_indent(indent)

    switch op.type {
        case .Negate:
            fmt.printfln("negate(")
            pretty_print_expr_node(op.expr, indent + 1)
            print_indent(indent)
            fmt.println(")")

        case .BoolNegate:
            fmt.printfln("bool_negate(")
            pretty_print_expr_node(op.expr, indent + 1)
            print_indent(indent)
            fmt.println(")")

        case .BinaryNegate:
            fmt.printfln("binary_negate(")
            pretty_print_expr_node(op.expr, indent + 1)
            print_indent(indent)
            fmt.println(")")
    }
}

pretty_print_binary_op_node :: proc(op: Binary_Op_Node, indent := 0) {
    print_indent(indent)

    switch op.type {
        case .Add:
            fmt.println("add(left=(")

        case .Subtract:
            fmt.println("subtract(")

        case .Multiply:
            fmt.println("multiply(")

        case .Modulo:
            fmt.println("modulo(")

        case .Divide:
            fmt.println("divide(")

        case .BoolAnd:
            fmt.println("bool_and(")

        case .BoolOr:
            fmt.println("bool_or(")

        case .BoolEqual:
            fmt.println("bool_equal(")

        case .BoolNotEqual:
            fmt.println("bool_not_equal(")

        case .BoolLess:
            fmt.println("bool_less(")

        case .BoolLessEqual:
            fmt.println("bool_less_equal(")

        case .BoolMore:
            fmt.println("bool_more(")

        case .BoolMoreEqual:
            fmt.println("bool_more_equal(")
    }

    pretty_print_expr_node(op.left, indent + 1)
    print_indent(indent)
    fmt.println("), right=(")
    pretty_print_expr_node(op.right, indent + 1)
    print_indent(indent)
    fmt.println(")")
}

pretty_print_expr_node :: proc(expr: Expr_Node, indent := 0) {

    switch e in expr {
        case ^Int_Constant_Node:
            print_indent(indent)
            fmt.printfln("int_constant(value=%v)", e.value)

        case ^Unary_Op_Node:
            pretty_print_unary_op_node(e^, indent)

        case ^Binary_Op_Node:
            pretty_print_binary_op_node(e^, indent)
    }
}

pretty_print_statement_node :: proc(statement: Statement_Node, indent := 0) {
    print_indent(indent)

    switch stmt in statement {
        case ^Return_Node:
            fmt.print("return(")
            if stmt.expr == nil {
                fmt.println(")")
            }
            else {
                fmt.println("expr=")
                pretty_print_expr_node(stmt.expr, indent + 1)
                print_indent(indent)
                fmt.println(")")
            }
    }
}

pretty_print_function_node :: proc(function: Function_Node, indent := 0) {
    print_indent(indent)
    fmt.printf("function(name=%v", function.name)

    if len(function.body) == 0 {
        fmt.println(")")
    }
    else {
        fmt.println(", body=(")
        for statement in function.body {
            pretty_print_statement_node(statement, indent + 1)
        }
        print_indent(indent)
        fmt.println(")")
    }
}

pretty_print_program :: proc(program: Program) {
    if len(program.children) == 0 {
        fmt.print("program()")
    }
    else {
        fmt.println("program(")
        for child in program.children {
            pretty_print_function_node(child^, 1)
        }
        fmt.println(")")
    }
}

