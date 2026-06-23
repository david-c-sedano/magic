
Arguments :: struct {
    file: string; @"?the file with which the text that constitutes your program which you desire to have be compiled";
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetConsoleOutputCP(CP_UTF8);
    }
    ok, args, is_set := parse_arguments(Arguments);
    if !ok {
        return;
    }

    if is_set.file {
        root: Compiler_Workspace;
        root_parser: Parser;
        root.current_file_being_worked_on = args.file;
        ok = init_parser_from_current_file(*root, *root_parser);
        if !ok {
            return;
        }

        while root_parser.curr.kind != .EOF {
            node := parse_node(*root_parser);
            if root_parser.has_error {
                flush_messages(*root);
                return;
            }

            print("%\n", pprint_node(node));
            reset_ast_rendering();
        }
    
    } else {
        print(meme1);
    }
}

meme1 :: #string MEME
———————————No file?———————————
⠀⣞⢽⢪⢣⢣⢣⢫⡺⡵⣝⡮⣗⢷⢽⢽⢽⣮⡷⡽⣜⣜⢮⢺⣜⢷⢽⢝⡽⣝
⠸⡸⠜⠕⠕⠁⢁⢇⢏⢽⢺⣪⡳⡝⣎⣏⢯⢞⡿⣟⣷⣳⢯⡷⣽⢽⢯⣳⣫⠇
⠀⠀⢀⢀⢄⢬⢪⡪⡎⣆⡈⠚⠜⠕⠇⠗⠝⢕⢯⢫⣞⣯⣿⣻⡽⣏⢗⣗⠏⠀
⠀⠪⡪⡪⣪⢪⢺⢸⢢⢓⢆⢤⢀⠀⠀⠀⠀⠈⢊⢞⡾⣿⡯⣏⢮⠷⠁⠀⠀
⠀⠀⠀⠈⠊⠆⡃⠕⢕⢇⢇⢇⢇⢇⢏⢎⢎⢆⢄⠀⢑⣽⣿⢝⠲⠉⠀⠀⠀⠀
⠀⠀⠀⠀⠀⡿⠂⠠⠀⡇⢇⠕⢈⣀⠀⠁⠡⠣⡣⡫⣂⣿⠯⢪⠰⠂⠀⠀⠀⠀
⠀⠀⠀⠀⡦⡙⡂⢀⢤⢣⠣⡈⣾⡃⠠⠄⠀⡄⢱⣌⣶⢏⢊⠂⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢝⡲⣜⡮⡏⢎⢌⢂⠙⠢⠐⢀⢘⢵⣽⣿⡿⠁⠁⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠨⣺⡺⡕⡕⡱⡑⡆⡕⡅⡕⡜⡼⢽⡻⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⣼⣳⣫⣾⣵⣗⡵⡱⡡⢣⢑⢕⢜⢕⡝⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⣴⣿⣾⣿⣿⣿⡿⡽⡑⢌⠪⡢⡣⣣⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⡟⡾⣿⢿⢿⢵⣽⣾⣼⣘⢸⢸⣞⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠁⠇⠡⠩⡫⢿⣝⡻⡮⣒⢽⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
——————————————————————————————
MEME

#load "workspace.jai";
#load "tokenizer.jai";
#load "parser.jai";
#load "code_printer.jai";

#if OS == .WINDOWS {
    console_input :: () -> string {
        temp: [MAX_BYTES_TO_READ]u8;
        result: string = ---;
        bytes_read: s32;
        
        if !ReadConsoleA(GetStdHandle(STD_INPUT_HANDLE), temp.data, xx temp.count, *bytes_read) {
            return "";
        }

        result.data = alloc(bytes_read);
        result.count = bytes_read;
        memcpy(result.data, temp.data, bytes_read);
        return result;
    }

    ReadConsoleA :: (
        hConsoleHandle: HANDLE, 
        buff: *u8, 
        chars_to_read: s32,  
        chars_read: *s32, 
        lpInputControl := *void 
    ) -> bool #foreign kernel32;

    kernel32 :: #library,system "kernel32";
    #import "Windows";

    MAX_BYTES_TO_READ :: 4000;
}

#import "Basic";
#import "Command_Line";
#import "Unicode";
#import "String";
#import "File";
#import "Flat_Pool";
#import "Hash_Table";
