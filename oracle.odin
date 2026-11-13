
package magic

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"
import "core:math/rand"

import vmem "core:mem/virtual"
import lex "Godlex"

TEST_AMOUNT :: 10
TEST_FILE :: "./tests/oracle.magic"
TEST_INCLUDES :: []string { "./easy" }

expectf :: proc(cond: bool, msg: string, args: ..any) -> bool {
    if !cond {
        fmt.printf(msg, ..args)
    }
    return cond
}

oracle :: proc() {
    data, succ := os.read_entire_file(TEST_FILE, context.allocator)
    defer delete(data)
    if ok := expectf(succ == nil, "[MAGIC] `%s` not valid file!\n", TEST_FILE); !ok {
        return
    }

    arena: vmem.Arena 
    _=vmem.arena_init_growing(&arena)
    arena_alloc := vmem.arena_allocator(&arena)
    defer vmem.arena_destroy(&arena)

    g,_ := lex.make_character_grouper(TEST_FILE, cast(string) data, arena_alloc)
    g.include_paths = TEST_INCLUDES
    defer lex.delete_character_grouper(g)

    root := parse_top_level(g)
    ok := expectf(!lex.has_error(g),
        "[MAGIC] Oracle compilation failed with parser errors"
    )
    if !ok {
        lex.flush_messages(g)
        return
    }

    original_root := node_cast(Block, root)
    original_last := original_root.code[len(original_root.code) - 1]
    b := strings.builder_make()
    sbprint(original_last, &b)
    fmt.printf("\x1b[32mORIGINAL AST\x1b[0m\n")
    fmt.printf("%s", strings.to_string(b))
    strings.builder_destroy(&b)

    original, original_ok := oracle_compile(g, root)
    ok = expectf(original_ok, 
        "[MAGIC] Oracle compile failed on original source\n",
    )
    if !ok {
        return
    }
    original_stdout: []u8
    original_stdout, original_ok = oracle_run(original)
    defer delete(original_stdout)
    ok = expectf(original_ok, "[MAGIC] Oracle run failed on original source\n")
    if !ok {
        return
    }
    fmt.printf(
        "\x1b[35moriginal output:\n\x1b[0m%s\n----------------\n", 
        original_stdout
    )

    for i in 0..<TEST_AMOUNT {
        defer free_all(context.temp_allocator)

        fmt.printf("\x1b[31mrunning test %d\x1b[0m\n", i)
        value := rand.uint64()
        case_seed := value ~ u64(i)

        rewritten := copy_node_recursively(root, context.temp_allocator)
        rewritten_root := node_cast(Block, rewritten)
        rewritten_last := rewritten_root.code[len(rewritten_root.code) - 1]
        oracle_rewrite(rewritten_last, case_seed)

        b := strings.builder_make()
        sbprint(rewritten_last, &b)
        fmt.printf("\x1b[32mREWRITE AST\x1b[0m\n")
        fmt.printf("%s", strings.to_string(b))
        strings.builder_destroy(&b)
       
        mutated, mutated_ok := oracle_compile(g, rewritten)
        ok := expectf(mutated_ok, 
            "\n[MAGIC] Oracle compile failed: seed=%v case = %v\n",
            value, i
        )
        if !ok {
            lex.flush_messages(g)
            return
        }

        mutated_stdout: []u8
        mutated_stdout,mutated_ok = oracle_run(mutated)
        defer delete(mutated_stdout)
        ok = expectf(mutated_ok, 
            "[MAGIC] Oracle run failed: seed=%v case = %v\n",
            value, i
        )
        if !ok {
            lex.flush_messages(g)
            return
        }
        fmt.printf("\x1b[35mrewritten output:\n\x1b[0m%s\n\n", mutated_stdout)

        if cast(string) mutated_stdout != cast(string) original_stdout {
            //TODO: oracle_save_failure(original, mutated)
            ok := expectf(false, "[MAGIC] Oracle mismatch: seed=%v case=%v\n",
                value, i
            )
            if !ok {
                return
            }
        }
    }

    fmt.println("\x1b[31mYou have passed the test.\x1b[0m")
}

oracle_compile :: proc(g: ^lex.Godlex, ast: ^Node(Wrapped)) -> (ssa: string, ok: bool) {
    c: Checker
    init_checker(&c, g)
    seed(&c, ast, toplevel=true)
    if c.error_count > 0 {
        return "", false
    }
    check_node(&c, ast)
    if c.error_count > 0 {
        return "", false
    }
    finalize(&c, ast)
    if c.error_count > 0 {
        return "", false
    }

    e: Emitter
    init_emitter(&e, ast, context.temp_allocator)
    ssa = generate(&e, &c, ast)
    return ssa, true
}

oracle_run :: proc(ssa: string) -> (stdout: []u8, ok: bool) {
    defer { 
        delete(ssa)
        // temporaries
        _=os.remove("oracle.ssa")
        _=os.remove("oracle.s")
        _=os.remove("oracle.exe")
    }

    _=os.write_entire_file("oracle.ssa", transmute([]u8) ssa)
    cmd := os.Process_Desc {
        command = { "qbe", "-t", "amd64_win", "-o", "oracle.s", "oracle.ssa" }
    }
    qbe_s,qbe_stdout,qbe_stderr,qbe_err := os.process_exec(cmd, context.temp_allocator)
    ok = qbe_err == nil && qbe_s.exited && qbe_s.exit_code == 0
    if !ok {
        return {}, false
    }

    cmd = os.Process_Desc {
        command = { "gcc", "oracle.s", "-o", "oracle.exe" }
    }
    gcc_s,gcc_stdout,gcc_stderr,gcc_err := os.process_exec(cmd, context.temp_allocator)
    ok = gcc_err == nil && gcc_s.exited && gcc_s.exit_code == 0
    if !ok {
        return {}, false
    }

    s: os.Process_State
    stderr: []u8
    err: os.Error
    s,stdout,stderr,err = os.process_exec(
        {command={"./oracle.exe"}}, context.temp_allocator
    )
    ok = err == nil && s.exited && s.exit_code == 0
    return slice.clone(stdout, context.allocator), ok
}

oracle_rewrite :: proc(ast: ^Node(Wrapped), seed: u64) -> ^Node(Wrapped) {
    value := (seed ~ 0x9e3779b97f4a7c15) | 1

    // random decider
    flip :: proc(value: ^u64) -> bool {
        x := value^
        x = x ~ (x << 13)
        x = x ~ (x >> 7)
        x = x ~ (x << 17)
        value^ = x
        return (x & 1) == 0
    }

    /* REWRITE TYPE 1 EXAMPLE: `1 + 2` -> `do 1 + 2` */
    maybe_wrap_into_blocks :: proc(expr: ^Node(Wrapped), value: ^u64) -> ^Node(Wrapped){
        if expr == nil {
            return nil
        }

        if node_cast(Leaf, expr)       == nil &&
           node_cast(Bin_Expr, expr)   == nil &&
           node_cast(Unary_Expr, expr) == nil {
            return expr
        }
        if !flip(value) {
            return expr
        }

        block := new_node(Block, alloc=context.temp_allocator)
        block.code = make([]^Node(Wrapped), 1, context.temp_allocator)
        block.code[0] = expr
        block.span = expr.span
        return wrap_node(block)
    }

    visit :: proc(node: ^Node(Wrapped), data: rawptr) {
        value := cast(^u64) data

        if decl := node_cast(Decl, node); decl != nil {
            decl.rhs = maybe_wrap_into_blocks(decl.rhs, value)
            return
        }
        if bin_expr := node_cast(Bin_Expr, node); bin_expr != nil {
            bin_expr.left = maybe_wrap_into_blocks(bin_expr.left, value)
            bin_expr.right = maybe_wrap_into_blocks(bin_expr.right, value)
            return
        }
        if unary_expr := node_cast(Unary_Expr, node); unary_expr != nil {
            unary_expr.operand = maybe_wrap_into_blocks(unary_expr.operand, value)
            return
        }
        if block := node_cast(Block, node); block != nil {
            for i in 0..<len(block.code) {
                block.code[i] = maybe_wrap_into_blocks(block.code[i], value)
            }
            return
        }
        if func := node_cast(Function, node); func != nil {
            func.body = maybe_wrap_into_blocks(func.body, value)
            return
        }
    }

    post_order_walk(ast, &value, visit)
    return ast
}
