
Type_Hint :: struct {
    size: u8; // 8, 16, 32, 64
    kind: Type_Kind;
    key: string;
}

Type_Kind :: enum u8 {
    UNKNOWN;
    NONE;
    SIGNED;
    UNSIGNED;
    FLOAT;
}

get_hint_from_key :: (key: string) -> Type_Hint {
    if key == {
        case "s64";     return Type_Hint.{ size = 64, kind = .SIGNED,   key = key };
        case "s32";     return Type_Hint.{ size = 32, kind = .SIGNED,   key = key };
        case "s16";     return Type_Hint.{ size = 16, kind = .SIGNED,   key = key };
        case "s8";      return Type_Hint.{ size = 8,  kind = .SIGNED,   key = key };
        case "u64";     return Type_Hint.{ size = 64, kind = .UNSIGNED, key = key };
        case "u32";     return Type_Hint.{ size = 32, kind = .UNSIGNED, key = key };
        case "u16";     return Type_Hint.{ size = 16, kind = .UNSIGNED, key = key };
        case "u8";      return Type_Hint.{ size = 8,  kind = .UNSIGNED, key = key };
        case "bool";    return Type_Hint.{ size = 8,  kind = .UNSIGNED, key = key };
        case "float32"; return Type_Hint.{ size = 32, kind = .FLOAT,    key = key };
        case "float64"; return Type_Hint.{ size = 64, kind = .FLOAT,    key = key };
    }
    return .{ size = 0, kind = .UNKNOWN, key = key };
}

infer_literal :: (literal: *AST_Node(Literal), hint := Type_Hint.{ kind = .UNKNOWN }) {
    if literal.kind == .PLACEHOLDER && hint.kind != .UNKNOWN {
        literal.hint = hint;
        return;
    }
    
    if literal.kind == .PLACEHOLDER && literal.hint.key != "" {
        literal.hint = get_hint_from_key(literal.hint.key);
    }

    if literal.kind == {
        case .NONE;    literal.hint = .{ kind = .UNSIGNED, size = 0,  key = "none" };
        case .CHAR;    literal.hint = .{ kind = .UNSIGNED, size = 8,  key = "u8" };
        case .BOOL;    literal.hint = .{ kind = .UNSIGNED, size = 8,  key = "bool" };
        case .INTEGER; literal.hint = .{ kind = .SIGNED,   size = 64, key = "s64" };
        case .REAL;    literal.hint = .{ kind = .FLOAT,    size = 32, key = "float32" };
    }
}

infer_arithmetic :: (workspace: *Compiler_Workspace, expr: *AST_Node(Expr)) -> bool {
    if expr.hint.kind != .UNKNOWN {
        return true;
    }

    maybe_type_for_entire_expr := expr.left.hint;
    op_is_defined_for :: (kinds: ..Type_Kind) #expand {
        if !array_find(kinds, maybe_type_for_entire_expr.kind) {
            mark_node(workspace, expr, "operator `%` is not defined for type `%`",
               expr.op.text, maybe_type_for_entire_expr.kind 
            );
            `return false;
        }
        expr.hint = maybe_type_for_entire_expr;
        `return true;
    }

    if expr.right == null {
        if expr.left.hint.kind == .UNKNOWN {
            return true;
        }

        if expr.op.kind == {
        case .MINUS;       op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
        case .BIT_NOT;     op_is_defined_for(.SIGNED, .UNSIGNED);
        case .LOGICAL_NOT; op_is_defined_for(.SIGNED, .UNSIGNED);
        }

        print("[DUMP] undefined UNARY operator `%`??\n", expr.op.kind);
        assert(false);
        return false;
    }

    if expr.left.hint.kind == .UNKNOWN || expr.right.hint.kind == .UNKNOWN {
        return true;
    } else {
        if expr.left.hint.kind != expr.right.hint.kind {
            mark_node(workspace, expr, "mismatching types in binary expression `%` and `%`",
                expr.left.hint.kind, expr.right.hint.kind
            );
            return false;
        }

        if expr.left.hint.size != expr.right.hint.size {
            mark_node(workspace, expr, "mismatching sizes in binary expression `%bit` vs `%bit`",
                expr.left.hint.size, expr.right.hint.size
            );
            return false;
        }
    }
    
    if expr.op.kind == {
        case .PLUS;   op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
        case .MINUS;  op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
        case .MUL;    op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
        case .DIV;    op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
        case .MODULO; op_is_defined_for(.SIGNED, .UNSIGNED, .FLOAT);
    }

    print("[DUMP] undefined operator `%`??\n", expr.op.kind);
    assert(false);
    return false;
}

infer_types :: (workspace: *Compiler_Workspace, ast: *AST_Node(void)) {

    visit :: (node: *AST_Node(void), workspace: *Compiler_Workspace) {
        literal := node_cast(node, Literal);
        if literal != null {
            infer_literal(literal);
            return;
        }

        expr := node_cast(node, Expr);
        if expr != null {
            ok := infer_arithmetic(workspace, expr);
            if !ok {
                workspace.type_related_errors += 1;
            }
            return;
        }
    }

    // NOTE: we might wanna do this with `pre_order_walk` actually
    post_order_walk(ast, workspace, visit);
}

check_for_unknown_types :: (workspace: *Compiler_Workspace, node: *AST_Node(void)) {
    if workspace.unknown_nodes.allocator.proc != workspace.allocator.proc {
        workspace.unknown_nodes.allocator = workspace.allocator;
    }

    visit :: (node: *AST_Node(void), workspace: *Compiler_Workspace) {
        if node.hint.kind == .UNKNOWN {
            array_add(*workspace.unknown_nodes, node);
        }
    }

    pre_order_walk(node, workspace, visit);
}
