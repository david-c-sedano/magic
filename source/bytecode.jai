
Instruction_Kind :: enum u8 {
    INVALID;
    LABEL;
    RETURN;
    CALL;
    BRANCH;
    SET_ON_CONDITION;
    COPY;
    LOAD_ADDRESS;

    CAST;
    INCREMENT;
    DECREMENT;
    NEGATE;
    BIT_NOT;
    ADD;
    SUB;
    MUL;
    DIV;
    MOD;
    BIT_OR;
    BIT_AND;
    SHIFT_LEFT;
    SHIFT_RIGHT;
}

Condition :: enum u8 {
    NEVER;
    ALWAYS;
    EQUALS;
    NOT_EQUALS;
    LESS;
    LESS_OR_EQUAL;
    GREATER;
    GREATER_OR_EQUAL;
}

Addressing_Mode :: enum u8 {
    INVALID;
    IMMEDIATE;
    REGISTER;
    DIRECT;
    INDIRECT;
}

Instruction :: struct {
    offset: int;
    kind: Instruction_Kind;
    operands: [..]Operand;

    cond_kind: Condition;
    jump_destination: int;

    call_info: *Type_Hint;

    start, end: Source_Loc;
    file_path: string;
}

Operand :: struct {
    mode: Addressing_Mode;

    register_index: int;
    type: Type_Hint;
    using value: Value;
}

Register :: struct {
    type: Type_Hint;
    using data: Value;
}

Value :: union {
    as_s8:  s8;
    as_s16: s16;
    as_s32: s32;
    as_s64: s64;
    as_u8:  u8;
    as_u16: u16;
    as_u32: u32;
    as_u64: u64;
    as_float32: float32;
    as_float64: float64;

    reference: *void;
}

Bytecode_Program :: struct {
    registers: [..]Register;
    instructions: [..]Instruction;

    workspace: *Compiler_Workspace;
}

add_register :: (program: *Bytecode_Program, type: Type_Hint) -> int {
    r: Register;  
    r.type = type;
    array_add(*program.registers, r);
    return program.registers.count-1;
}

emit_instruction :: (program: *Bytecode_Program, kind: Instruction_Kind) -> *Instruction {
    inst: Instruction;
    inst.kind = kind;
    inst.operands.allocator = program.workspace.execution_allocator;
    array_add(*program.instructions, inst);
    return program.instructions.data + (program.instructions.count-1);
}

immediate_operand :: (using bp: *Bytecode_Program, literal: *AST_Node(Literal)) -> Operand {
    operand: Operand;
    operand.mode = .IMMEDIATE;
    operand.register_index = -1;

    if literal.hint.kind == {
    case .SIGNED;
        value: int; succ: bool;
        if slice(literal.text, 0, 2) == "0x" {
            value, succ = string_to_int(slice(literal.text,2,literal.text.count-2), base = 16);
        } else {
            value, succ = string_to_int(literal.text);
        }
        assert(succ);
        if literal.hint.size == {
        case 8;  operand.type = literal.hint; operand.as_s8  = cast(s8) value;
        case 16; operand.type = literal.hint; operand.as_s16 = cast(s16) value;
        case 32; operand.type = literal.hint; operand.as_s32 = cast(s32) value;
        case 64; operand.type = literal.hint; operand.as_s64 = cast(s64) value;
        }

    case .UNSIGNED;
        value: int; succ: bool;
        if slice(literal.text, 0, 2) == "0x" {
            value, succ = string_to_int(slice(literal.text,2,literal.text.count-2), base = 16);
        } else {
            value, succ = string_to_int(literal.text);
        }
        assert(succ);
        if literal.hint.size == {
        case 8;  operand.type = literal.hint; operand.as_u8  = cast(u8) value;
        case 16; operand.type = literal.hint; operand.as_u16 = cast(u16) value;
        case 32; operand.type = literal.hint; operand.as_u32 = cast(u32) value;
        case 64; operand.type = literal.hint; operand.as_u64 = cast(u64) value;
        }

    case .FLOAT;
        value, succ := string_to_float(literal.text);
        assert(succ);
        if literal.hint.size == {
        case 32; operand.type = literal.hint; operand.as_float32 = cast(float32) value;
        case 64; operand.type = literal.hint; operand.as_float64 = cast(float64) value;
        }
    }

    return operand;
}

emit_arithmetic :: (using bp: *Bytecode_Program, expr: *AST_Node(Expr)) -> Operand {
    index := add_register(bp, expr.hint);
    reg := Operand.{ mode = .REGISTER, register_index = index, type = expr.hint };

    arithmetic_unary_case :: (inst_kind: Instruction_Kind) #expand {
        inst := emit_instruction(bp, inst_kind);
        array_add(*inst.operands, reg);
        array_add(*inst.operands, lhs);
        `return reg;
    }

    lhs := emit_expr(bp, expr.left);
    if expr.right == null {
        if expr.op.kind == {
        case .MINUS; arithmetic_unary_case(.NEGATE);
        }

        // should be unreachable
        print("[DUMP] undefined UNARY operator `%`??\n", expr.op.kind);
        assert(false);
        return .{ mode = .INVALID };
    }

    rhs := emit_expr(bp, expr.right);

    arithmetic_case :: (inst_kind: Instruction_Kind) #expand {
        inst := emit_instruction(bp, inst_kind);
        array_add(*inst.operands, reg);
        array_add(*inst.operands, lhs);
        array_add(*inst.operands, rhs);
        `return reg;
    }

    if expr.op.kind == {
    case .PLUS;   arithmetic_case(.ADD);
    case .MINUS;  arithmetic_case(.SUB);
    case .MUL;    arithmetic_case(.MUL);
    case .DIV;    arithmetic_case(.DIV);
    case .MODULO; arithmetic_case(.MOD);
    }

    // should be unreachable
    print("[DUMP] undefined operator `%`??\n", expr.op.kind);
    assert(false);
    return .{ mode = .INVALID };
}

emit_expr :: (using bp: *Bytecode_Program, node: *AST_Node(void)) -> Operand {
    literal := node_cast(node, Literal);
    if literal != null {
        return immediate_operand(bp, literal);
    }

    expr := node_cast(node, Expr);
    if expr != null {
        return emit_arithmetic(bp, expr);
    }

    print("[DUMP] `%`\n", node.kind);
    assert(false);
    return .{ mode = .INVALID };
}

pprint_bytecode_program :: (using bp: *Bytecode_Program) -> string {
    b: String_Builder;

    pprint_operand :: (operand: Operand) -> string {
        if operand.mode == .REGISTER {
            return sprint("r%", operand.register_index);
        }
        if operand.mode == .IMMEDIATE {
            if operand.type.kind == {
            case .SIGNED;   return sprint("%", operand.as_s64);
            case .UNSIGNED; return sprint("%", operand.as_u64);
            case .FLOAT;    return sprint("%", operand.as_float64);
            }
        }
        return "INVALID";
    }
   
    for inst: instructions {
        print_to_builder(*b, "% ", inst.kind);
        for operand: inst.operands {
            if it_index != inst.operands.count-1 {
                print_to_builder(*b, "%, ", pprint_operand(operand));
            } else {
                print_to_builder(*b, "%\n", pprint_operand(operand));
            }
        }
    }

    return builder_to_string(*b);
}

