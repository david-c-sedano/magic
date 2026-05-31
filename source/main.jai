
Arguments :: struct {
    repl: bool; @"?go into repl";
    file: string; @"?read from file";
}

main :: () {
    #if OS == .WINDOWS SetConsoleOutputCP(CP_UTF8);
    ok, args, is_set := parse_arguments(Arguments);
    if !ok {
        return;
    }

    if is_set.repl {
        while repl := 1 {
            print("magic> ");
            input := trim_right(console_input());
            if input == "quit" || input == "q" {
                return;
            }

            context.source = input;
            context.file_name = "REPL";

            t: Tokenizer;
            init_tokenizer(*t, input);
            curr := get_token(*t);

            while curr.kind != .EOF {
                if curr.kind == .INVALID {
                    flush_messages();
                    continue repl;
                }

                print("%\n", pprint_token(curr));
                free_token(curr);
                curr = get_token(*t);
            }
        }
    } else if is_set.file {
        print("TODO");
    } else {
        print(meme1);
    }
}

meme1 :: #string MEME
———————————No args?———————————
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

#load "tokenizer.jai";
#load "messager.jai";

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
