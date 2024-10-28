package occm

import "core:fmt"
import "core:reflect"
import "base:runtime"

Program :: struct {
    children: [dynamic]^Ast_Node,
}

Default_Label :: struct{}

Label :: union {
    string,
    int, // For case labels
    Default_Label,
}

Ast_Node :: struct {
    labels: [dynamic]Label,

    // Common stuff would go here
    variant: union {
        Function_Node,
        Int_Constant_Node,
        Ident_Node,
        Negate_Node,
        Bit_Negate_Node,
        Boolean_Negate_Node,
        Pre_Decrement_Node,
        Pre_Increment_Node,
        Post_Decrement_Node,
        Post_Increment_Node,
        Add_Node,
        Subtract_Node,
        Multiply_Node,
        Modulo_Node,
        Divide_Node,
        Boolean_And_Node,
        Boolean_Or_Node,
        Boolean_Equal_Node,
        Boolean_Not_Equal_Node,
        Less_Node,
        Less_Equal_Node,
        More_Node,
        More_Equal_Node,
        Bit_And_Node,
        Bit_Or_Node,
        Bit_Xor_Node,
        Shift_Left_Node,
        Shift_Right_Node,
        Equal_Node,
        Plus_Equal_Node,
        Minus_Equal_Node,
        Times_Equal_Node,
        Divide_Equal_Node,
        Modulo_Equal_Node,
        Xor_Equal_Node,
        Or_Equal_Node,
        And_Equal_Node,
        Shift_Left_Equal_Node,
        Shift_Right_Equal_Node,
        Null_Statement_Node,
        Return_Node,
        Goto_Node,
        Decl_Assign_Node,
        Decl_Node,
        Compound_Statement_Node,
        Ternary_Node,
        If_Node,
        If_Else_Node,
        While_Node,
        Do_While_Node,
        For_Node,
        Continue_Node,
        Break_Node,
        Switch_Node,
    },
}

Function_Node :: struct {
    name: string,
    args: [dynamic]string,
    body: [dynamic]^Ast_Node,
}

Int_Constant_Node :: struct {
    value: int,
}

Ident_Node :: struct {
    var_name: string,
}

Negate_Node :: struct {
    expr: ^Ast_Node,
}

Bit_Negate_Node :: distinct Negate_Node
Boolean_Negate_Node :: distinct Negate_Node
Pre_Decrement_Node :: distinct Negate_Node
Pre_Increment_Node :: distinct Negate_Node
Post_Decrement_Node :: distinct Negate_Node
Post_Increment_Node :: distinct Negate_Node

Add_Node :: struct {
    left: ^Ast_Node,
    right: ^Ast_Node,
}

Subtract_Node :: distinct Add_Node
Multiply_Node :: distinct Add_Node
Modulo_Node :: distinct Add_Node
Divide_Node :: distinct Add_Node
Boolean_And_Node :: distinct Add_Node
Boolean_Or_Node :: distinct Add_Node
Boolean_Equal_Node :: distinct Add_Node
Boolean_Not_Equal_Node :: distinct Add_Node
Less_Node :: distinct Add_Node
Less_Equal_Node :: distinct Add_Node
More_Node :: distinct Add_Node
More_Equal_Node :: distinct Add_Node
Bit_And_Node :: distinct Add_Node
Bit_Or_Node :: distinct Add_Node
Bit_Xor_Node :: distinct Add_Node
Shift_Left_Node :: distinct Add_Node
Shift_Right_Node :: distinct Add_Node

Equal_Node :: struct {
    left: ^Ast_Node,
    right: ^Ast_Node,
}

Plus_Equal_Node :: distinct Equal_Node
Minus_Equal_Node :: distinct Equal_Node
Times_Equal_Node :: distinct Equal_Node
Divide_Equal_Node :: distinct Equal_Node
Modulo_Equal_Node :: distinct Equal_Node
Xor_Equal_Node :: distinct Equal_Node
Or_Equal_Node :: distinct Equal_Node
And_Equal_Node :: distinct Equal_Node
Shift_Left_Equal_Node :: distinct Equal_Node
Shift_Right_Equal_Node :: distinct Equal_Node

Null_Statement_Node :: struct {}

Return_Node :: struct {
    expr: ^Ast_Node,
}

Goto_Node :: struct {
    label: string
}

Decl_Assign_Node :: struct {
    var_name: string,
    right: ^Ast_Node,
}

Decl_Node :: struct {
    var_name: string 
}

Compound_Statement_Node :: struct {
    statements: [dynamic]^Ast_Node,
}

Ternary_Node :: struct {
    condition: ^Ast_Node,
    if_true: ^Ast_Node,
    if_false: ^Ast_Node,
}

If_Node :: struct {
    condition: ^Ast_Node,
    if_true: ^Ast_Node,
}

If_Else_Node :: distinct Ternary_Node
While_Node :: distinct If_Node
Do_While_Node :: distinct If_Node

For_Node :: struct {
    pre_condition: ^Ast_Node,
    condition: ^Ast_Node,
    post_condition: ^Ast_Node,
    if_true: ^Ast_Node,
}

Continue_Node :: distinct Null_Statement_Node
Break_Node :: distinct Null_Statement_Node

Switch_Node :: struct {
    expr: ^Ast_Node,
    block: ^Ast_Node,
}

make_node_0 :: proc($T: typeid) -> ^Ast_Node {
    node := new(Ast_Node)
    node.variant = T{}
    return node
}

make_node_1 :: proc($T: typeid, inner: $I) -> ^Ast_Node {
    node := new(Ast_Node)
    node.variant = T{inner}
    return node
}

make_node_2 :: proc($T: typeid, first: $F, second: $S) -> ^Ast_Node {
    node := new(Ast_Node)
    node.variant = T{first, second}
    return node
}

make_node_3 :: proc($T: typeid, first: $F, second: $S, third: $H) -> ^Ast_Node {
    node := new(Ast_Node)
    node.variant = T{first, second, third}
    return node
}

make_node_4 :: proc($T: typeid, first: $F, second: $S, third: $H, fourth: $O) -> ^Ast_Node {
    node := new(Ast_Node)
    node.variant = T{first, second, third, fourth}
    return node
}

// Printing functions for debugging

print_indent :: proc(indent: int) {
    for i in 0..<indent {
        fmt.print("  ")
    }
}

pretty_print_node :: proc(node: Ast_Node, indent := 0) {
    print_indent(indent)

    for label in node.labels {
        switch l in label {
            case string:
                fmt.printf("%v: ", l)
            case int:
                fmt.printf("case %v: ", l)
            case Default_Label:
                fmt.print("default: ")
        }
    }

    node_struct_id := reflect.union_variant_typeid(node.variant)
    node_struct_info := type_info_of(node_struct_id).variant.(runtime.Type_Info_Named)
    fmt.printf("%v(", node_struct_info.name)

    node_variant := reflect.get_union_variant(node.variant)
    for field_name, i in reflect.struct_field_names(node_struct_id) {
        if i > 0 do fmt.print(", ")
        fmt.printf("%v=", field_name)
        switch v in reflect.struct_field_value_by_name(node_variant, field_name) {
            case ^Ast_Node:
                fmt.println("(")
                pretty_print_node(v^, indent + 1)
                fmt.println()
                print_indent(indent)
                fmt.print(")")

            case [dynamic]^Ast_Node:
                fmt.println("(")
                for node, i in v {
                    if i > 0 do fmt.println(",")
                    pretty_print_node(node^, indent + 1)
                }
                fmt.println()
                print_indent(indent)
                fmt.print(")")

            case:
                fmt.printf("%v", v)
        }
    }
    fmt.print(")")
}

pretty_print_program :: proc(program: Program) {
    if len(program.children) == 0 {
        fmt.print("program()")
    }
    else {
        fmt.println("program(")
        for child in program.children {
            pretty_print_node(child^, 1)
        }
        fmt.println(")")
    }
}

