
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

    while true {
        msg := compiler_wait_for_message();
        if msg.kind == {
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

just_run_it: bool;
FILE_FOR_EZ_TESTING :: "./tests/some_types.magic";

#import "Basic";
#import "Compiler";
#import "Process";
