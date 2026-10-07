
package magic

import lex "Godlex"

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"
import "core:flags"

import win32 "core:sys/windows"

main :: proc() {

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    when ODIN_OS == .Windows {
        win32.SetConsoleOutputCP(.UTF8)
    }

    Options :: struct {
        file: ^os.File `args:"pos=0,required,file=r" usage:"Input File."`,
        one_at_a_time: bool `usage:"Enabling accessibility by NOT forcing programmers to buy a vertical monitor in order to read all the ****ing error messages"`,
    }
    opts: Options
    flags.parse_or_exit(&opts, os.args, .Odin)
 
    info, stat_err := os.fstat(opts.file, context.temp_allocator)
    if stat_err != nil {
        fmt.println("bad file?")
        return
    }
    data, succ := os.read_entire_file(opts.file, context.temp_allocator)

    g,_ := lex.make_character_grouper(info.name, cast(string) data, context.temp_allocator)
    defer lex.delete_character_grouper(g)
    root := parse_top_level(g)
    if lex.has_error(g) {
        return
    }

    c: Checker
    init_checker(&c, g)
    seed(&c, root) 
    if c.error_count > 0 {
        lex.flush_messages(g)
        fmt.printf("[MAGIC] failed to seed!\n")
        return
    }

    result := check_node(&c, root)

    when ODIN_DEBUG {
        b := strings.builder_make()
        sbprint(root, &b)
        debug := strings.to_string(b)
        fmt.println(debug)
        delete(debug)
    }

    fmt.printf("[MAGIC] finished in %d inference passes!!\n", c.passes)
    if c.error_count > 0 {
        fmt.println()
        lex.flush_messages(g)
        return
    }

    fmt.println("generating feedback...")
    fmt.println()

    mark_invalid_types(&c, root)
    if c.error_count > 0 {
        lex.flush_messages(g)
        return
    }
    fmt.println("[MAGIC] we good, fam")
}
