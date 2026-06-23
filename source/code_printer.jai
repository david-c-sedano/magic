
#add_context code_printer_arena: Flat_Pool; // how lazy!

get_builder_for_ast_rendering :: () -> String_Builder #expand {
    b: String_Builder;
    prev_allocator := context.allocator;
    `defer context.allocator = prev_allocator;
    a: Allocator;
    a.proc = flat_pool_allocator_proc;
    a.data = *context.code_printer_arena;
    context.allocator = a;
    init_string_builder(*b);
    return b;
}

reset_ast_rendering :: () {
    reset(*context.code_printer_arena, overwrite_memory = true);
}

pprint_binding :: (binding: *Parse_Node(Binding), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    print_to_builder(*b, 
        ifx binding.forward then
            "FORWARD %\n"
        else
            "DECL %\n",
        binding.name.text
    );

    append(*b, join(prefix, "└───"));
    append(*b, pprint_expr(binding.rhs, join(prefix, "    ")));
    return builder_to_string(*b);
}

pprint_return :: (return_stmnt: *Parse_Node(Return), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    append(*b, "RETURN\n");
    append(*b, join(prefix, "└───"));
    append(*b, pprint_expr(return_stmnt.result, join(prefix, "    ")));

    return builder_to_string(*b);
}

pprint_node :: (node: *Parse_Node(void), prefix := "") -> string {
    /* STATEMENTS */
    binding := node_cast(node, Binding);
    if binding != null {
        return pprint_binding(binding, prefix);
    }

    return_stmnt := node_cast(node, Return);
    if return_stmnt != null {
        return pprint_return(return_stmnt, prefix);
    }

    break_stmnt := node_cast(node, Break);
    if break_stmnt != null {
        return "BREAK\n"; // easy
    }

    cont_stmnt := node_cast(node, Continue);
    if cont_stmnt != null {
        return "CONTINUE\n"; // ez
    }

    /* DEFAULT TO EXPR CAUSE WE GOT EVERYTHING IN EXPR LEVEL!!! */
    return pprint_expr(node, prefix);
}

pprint_expr :: (node: *Parse_Node(void), prefix := "", mark_block := true, cont := false) -> string {

    recurse :: (
        node: *Parse_Node(void), 
        b: *String_Builder, 
        prefix: string, 
        mark_block := false, 
        cont := false
    ) {
        ident := node_cast(node, Identifier);
        if ident != null {
            print_to_builder(b, "[%]", ident.text);
            append(b, "\n");
            return;
        }

        literal := node_cast(node, Literal);
        if literal != null {
            print_to_builder(b, "[% %]", literal.text, literal.kind);
            append(b, "\n");
            return;
        }

        expr := node_cast(node, Expr);
        if expr != null {
            append(b, pprint_token(*expr.op));
            append(b, "\n");

            if expr.right == null {
                append(b, join(prefix, "└───"));
                recurse(expr.left, b, join(prefix, "    "), mark_block = true);
                return;
            }

            append(b, join(prefix, "├───"));
            recurse(expr.left, b, join(prefix, "│   "), mark_block = true);

            append(b, join(prefix, "└───"));
            recurse(expr.right, b, join(prefix, "    "), mark_block = true);
            return;
        }

        block := node_cast(node, Block);
        if block != null {
            append(b, pprint_block(block, prefix, mark_block, cont = cont));
            return;
        }

        if_else := node_cast(node, If_Else);
        if if_else != null {
            append(b, pprint_if_else(if_else, prefix));
            return;
        }

        while_loop := node_cast(node, While_Loop);
        if while_loop != null {
            append(b, pprint_while(while_loop, prefix));
            return;
        }

        call := node_cast(node, Call);
        if call != null {
            append(b, pprint_call(call, prefix));
            return;
        }

        func := node_cast(node, Function);
        if func != null {
            append(b, pprint_function(func, prefix));
            return;
        }

        list := node_cast(node, List);
        if list != null {
            append(b, pprint_list(list, prefix));
            return;
        }

        map := node_cast(node, Map);
        if map != null {
            append(b, pprint_map(map, prefix));
            return;
        }

        subscript := node_cast(node, Subscript);
        if subscript != null {
            append(b, pprint_subscript(subscript, prefix));
            return;
        }

        print("[DUMP] %\n", node.kind);
        assert(false, "pprint_expr got a weird node kind");
    }

    b := get_builder_for_ast_rendering(); 
    recurse(node, *b, prefix, mark_block, cont);
    return builder_to_string(*b);
}

pprint_call :: (call: *Parse_Node(Call), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    print_to_builder(*b, "CALL\n%├───", prefix);
    append(*b, pprint_expr(call.callee, join(prefix, "│   ")));

    print_to_builder(*b, "%ARGS\n", prefix);
    for call.args {
        is_last := it_index == call.args.count - 1;
        branch := ifx is_last then "└───" else "├───";
        append(*b, join(prefix, branch));

        ext := ifx is_last then "    " else "│   ";
        if it == null {
            append(*b, "DEFAULT\n");
            continue;
        }
        append(*b, pprint_expr(it, join(prefix, ext)));
    }

    return builder_to_string(*b);
}

pprint_subscript :: (subscript: *Parse_Node(Subscript), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    print_to_builder(*b, "SUBSCRIPT\n%├───", prefix);
    append(*b, pprint_expr(subscript.container, join(prefix, "│   ")));
    append(*b, join(prefix, "└───"));
    append(*b, pprint_expr(subscript.index, join(prefix, "    ")));

    return builder_to_string(*b);
}

pprint_block :: (
    block: *Parse_Node(Block), 
    prefix := "", 
    mark_it := false, 
    cont := false
) -> string {

    recurse :: (
        block: *Parse_Node(Block), 
        b: *String_Builder, 
        prefix: string, 
        mark_it: bool,
        cont: bool
    ) {
        if block == null return;
        
        if mark_it append(b, "BLOCK\n");
        for block.code {
            is_last := it_index == block.code.count - 1;
            // you can probably do this in one line
            branch: string;
            if is_last {
                if cont {
                    branch = "├───";
                } else {
                    branch = "└───";
                }
            } else {
                branch = "├───";
            }
            append(b, join(prefix, branch));

            // but I chose to write in Jai, not Haskell 
            ext: string;
            if is_last {
                if cont {
                    ext = "│   ";
                } else {
                    ext = "    ";
                }
            } else {
                ext = "│   ";
            }

            append(b, pprint_node(it, join(prefix, ext)));
        }
    }

    b := get_builder_for_ast_rendering(); 
    recurse(block, *b, prefix, mark_it, cont);
    return builder_to_string(*b);
}

pprint_if_else :: (if_else: *Parse_Node(If_Else), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 
    has_else := if_else.else_body != null;

    print_to_builder(*b, "IF\n%├───", prefix);
    append(*b, pprint_expr(if_else.cond, join(prefix, "│   ")));
    print_to_builder(*b, "%THEN\n", prefix);
    append(*b, pprint_expr(if_else.if_body, prefix, mark_block = false, cont = has_else));
    if has_else {
        print_to_builder(*b, "%ELSE\n", prefix);
        append(*b, pprint_expr(if_else.else_body, prefix, mark_block = false));
    }

    return builder_to_string(*b);
}

pprint_while :: (while_loop: *Parse_Node(While_Loop), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    print_to_builder(*b, "WHILE\n%├───", prefix);
    append(*b, pprint_expr(while_loop.cond, join(prefix, "│   ")));
    print_to_builder(*b, "%DO\n", prefix);
    append(*b, pprint_expr(while_loop.body, prefix, mark_block = false));
    return builder_to_string(*b);
}

pprint_function :: (func: *Parse_Node(Function), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    append(*b, "FUNCTION\n");

    for func.params {
        is_last := it_index == func.params.count - 1;
        append(*b, join(prefix, "├───"));
        append(*b, pprint_expr(it, join(prefix, "│   ")));
    }

    print_to_builder(*b, "%BODY\n", prefix);
    append(*b, join(prefix, "└───"));
    append(*b, pprint_expr(func.body, join(prefix, "    ")));
    return builder_to_string(*b);
}

pprint_list :: (list: *Parse_Node(List), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    append(*b, "LIST\n");
    for list.items {
        is_last := it_index == list.items.count - 1;
        branch := ifx is_last then "└───" else "├───";
        append(*b, join(prefix, branch));

        ext := ifx is_last then "    " else "│   ";
        append(*b, pprint_expr(it, join(prefix, ext)));
    }

    return builder_to_string(*b);
}

pprint_map :: (map: *Parse_Node(Map), prefix := "") -> string {
    b := get_builder_for_ast_rendering(); 

    /* this is killing me bro
       representing maps in this manner is goofy as sheeeeeeet anyways 
    */
    append(*b, "MAP\n");
    for 0 .. map.keys.count-1 {
        is_last := it == map.keys.count - 1;
        ext := ifx is_last then "    " else "│   ";
        append(*b, join(prefix, ifx is_last then "└───KEY\n" else "├───KEY\n"));
        append(*b, join(prefix, ext, "├───"));
        append(*b, pprint_expr(map.keys[it], join(prefix, ext, "│   ")));

        append(*b, join(prefix, ext, "VALUE\n"));
        append(*b, join(prefix, ext, "└───"));
        append(*b, pprint_expr(map.values[it], join(prefix, ext, "    ")));
    }

    return builder_to_string(*b);
}

