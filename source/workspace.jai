
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

Compiler_Workspace :: struct {
    // key=path, value=actual source code
    sources: Table(string, string); 
    current_file_being_worked_on: string;
    messages: [..]Message;

    type_related_errors: int;
    unknown_nodes: [..]*AST_Node(void);

    allocator: Allocator;
    execution_allocator: Allocator;
}

// NOTE: i dont think the allocators are set for `messages` and `sources`
get_current_file_source :: (using w: *Compiler_Workspace) -> string, bool {
    assert(current_file_being_worked_on != "");
    source, ok := table_find(*sources, current_file_being_worked_on);
    if !ok {
        source, ok = read_entire_file(current_file_being_worked_on, log_errors = false);
        if !ok {
            print("The wizards of great magic cannot find `%`!!\n", 
                current_file_being_worked_on
            );
            return "", false;
        }
        if source == "" {
            print("File is empty??\n");
            print(meme1);
            return "", false;
        }
        table_add(*sources, current_file_being_worked_on, source);
    }
    return source, true;
}

push_message :: (using w: *Compiler_Workspace, msg_text: string, fmt: ..Any) {
    msg: Message;
    msg.text = sprint(msg_text, ..fmt);
    array_add(*messages, msg);
}

push_location :: (using w: *Compiler_Workspace, start: Source_Loc, end: Source_Loc, msg_text: string, fmt: ..Any) {
    msg: Message;
    msg.is_error = true;
    msg.text = sprint(msg_text, ..fmt);
    msg.source = get_current_file_source(w);
    msg.file_name = current_file_being_worked_on;
    msg.start = start;
    msg.end = end;
    array_add(*messages, msg);
}

mark_node :: (using w: *Compiler_Workspace, node: *AST_Node($T), msg_text: string, fmt: ..Any) {
    msg: Message;
    msg.is_error = true;
    msg.text = sprint(msg_text, ..fmt);
    msg.source = get_current_file_source(w);
    msg.file_name = current_file_being_worked_on;
    msg.start = node.pos;
    msg.end = node.end;
    array_add(*messages, msg);
}

flush_messages :: (using w: *Compiler_Workspace) {
    for msg: messages {
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
    array_reset(*messages);
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

suppress_messages :: (using w: *Compiler_Workspace) {
    array_reset(*messages);
}

