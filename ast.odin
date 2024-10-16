package occm

import "core:fmt"
import "core:reflect"
import "base:runtime"

Program :: struct {
    children: [dynamic]^Ast_Node,
}

Ast_Node :: struct {
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
        Return_Node,
        Decl_Assign_Node,
        Decl_Node,
    },
}

Function_Node :: struct {
    name: string,
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

Return_Node :: struct {
    expr: ^Ast_Node,
}

Decl_Assign_Node :: struct {
    var_name: string,
    right: ^Ast_Node,
}

Decl_Node :: struct {
    var_name: string 
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

// Printing functions for debugging

print_indent :: proc(indent: int) {
    for i in 0..<indent {
        fmt.print("  ")
    }
}

pretty_print_node :: proc(node: Ast_Node, indent := 0) {
    print_indent(indent)

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

