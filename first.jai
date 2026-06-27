
#run do_build();

do_build :: () {
    set_build_options_dc(.{do_output=false});

    w := compiler_create_workspace("magic");
    
    opts := get_build_options(w);
    opts.output_executable_name = "magic";
    args := opts.compile_time_command_line;

    for args {
        if it == {
        case "just_run_it";
            just_run_it = true;
        }
    }

    set_build_options(opts, w);
    compiler_begin_intercept(w);
    add_build_file("./source/main.jai", w);
    message_loop(w);
    compiler_end_intercept(w);
}

message_loop :: (w: Workspace) #expand {
    opts := `opts;
    generated_ast_types := false;

    while true {
        msg := compiler_wait_for_message();
        if msg.kind == {
        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) msg;
            for decl: typechecked.declarations {
                for note: decl.expression.notes {
                    if note.text == "ast" {
                        array_add(*ast_types, copy_string(decl.expression.name));
                    }
                }
            }

        case .PHASE;
            phase := cast(*Message_Phase) msg;
            if generated_ast_types == false
            && phase.phase == .TYPECHECKED_ALL_WE_CAN {
                code := generate_ast_types();
                add_build_string(code, w);
                print("\n\x1b[31mGenerated `AST_TYPES` !!!\x1b[0m\n\n");
                generated_ast_types = true;
            }

        case .COMPLETE;
            complete := cast(*Message_Complete) msg;
            if just_run_it && complete.error_code == 0 {
                print("[JUST RUNNING IT]:\n");
                run_command(opts.output_executable_name, "-file", FILE_FOR_EZ_TESTING);
            }
            break;
        }
    }
}

generate_ast_types :: () -> string #expand {
    b: String_Builder;

append(*b, #string CODE
AST_TYPES :: Type.[
CODE);

    for ast_types {
        print_to_builder(*b, "\t%,\n", it);
    }

append(*b, #string CODE
];
CODE);

    return builder_to_string(*b);
}

ast_types: [..]string;

just_run_it: bool;
FILE_FOR_EZ_TESTING :: "./tests/some_types.magic";

#import "Basic";
#import "Compiler";
#import "Process";
