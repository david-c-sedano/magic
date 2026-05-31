
/*  so, the messager is basically a logger
    but its fancier because it doesn't really do "logging"
    it keeps track of indices within the source code input and associated messages
    when it does an error message, it will put together a view of the text
    then it prints it with highlighting all nice

    because it's similar to a logger, it pairs well with Jai's context system
    whenever you are parsing/evaluating a different source string from a file
    just override the context fields and everything magically works 
*/

Source_Loc :: struct {
    offset: int;
    line: int;
    column: int;
}

Message :: struct {
    is_error: bool;
    text: string;
    source: string;
    file_name: string;
    start: Source_Loc;
    end: Source_Loc;
}

#add_context messages: [..]Message;
#add_context source: string;
#add_context file_name: string;

push_message :: (msg_text: string, fmt: ..Any) {
    msg: Message;
    msg.text = sprint(msg_text, ..fmt);
    array_add(*context.messages, msg);
}

push_location :: (start: Source_Loc, end: Source_Loc, msg_text: string, fmt: ..Any) {
    msg: Message;
    msg.is_error = true;
    msg.text = sprint(msg_text, ..fmt);
    msg.source = context.source;
    msg.file_name = context.file_name;
    msg.start = start;
    msg.end = end;
    array_add(*context.messages, msg);
}

flush_messages :: () {
    for msg: context.messages {
        if !msg.is_error {
            print("[INFO] %\n", msg.text);
            continue;
        }

        print("[ERROR] %\n", msg.text);
        print("  --> here from (%:%) to (%:%) in `%`\n", 
            msg.start.line, msg.start.column, msg.end.line, msg.end.column,
            msg.file_name 
        );

        if msg.start.line == msg.end.line {
            print("\n\t%\n", get_line_text(msg.source, msg.start.line));
            print("\t%\n", caret_line(msg.start, msg.end));
        } else {
            b: String_Builder;
            init_string_builder(*b);

            // offset from the `msg.start.line` 
            for line_offset: msg.start.line .. msg.end.line {
                line := get_line_text(msg.source, line_offset);
                append(*b, "\n\t");
                for 0..line.count-1 {
                    if line_offset == msg.start.line && it == msg.start.column-1 {
                        append(*b, "\x1b[31m");
                    }
                    append(*b, line[it]);
                    // is last line in source view
                    if line_offset == msg.end.line && it == msg.end.column-1 {
                        append(*b, "\x1b[0m");
                    }
                }
            }
            append(*b, "\n");
            source_view := builder_to_string(*b);

            print(source_view);
        }
    }
    array_reset(*context.messages);
}

get_line_text :: (source: string, line: int) -> string {
    start := 0;
    curr_line := 1;

    for c, i: source {
        if curr_line == line {
            end := i;
            for j: i..source.count {
                if j >= source.count || source[j] == #char "\n" {
                    end = j;
                    break j;
                }
            }
            return slice(source, start, end - start);
        }

        if c == #char "\n" {
            curr_line += 1;
            start = i + 1;
        }
    }

    return "";
}

caret_line :: (start: Source_Loc, end: Source_Loc) -> string {
    b: String_Builder;
    init_string_builder(*b);
    append(*b, "\x1b[31m");
    for 1..end.column { 
        if it >= start.column {
            print_to_builder(*b, "^");
        } else {
            print_to_builder(*b, " ");
        }
    }
    append(*b, "\x1b[0m");
    return builder_to_string(*b);
}

suppress_messages :: () {
    array_reset(*context.messages);
}

