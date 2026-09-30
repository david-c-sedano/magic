
package magic

import lex "Godlex"

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"

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
   
    buf := [4000]u8{}
    for {
        total_read, err := os.read(os.stdin, buf[:])
        input := strings.trim_space(cast(string) buf[:total_read])
        if input == "q" {
            break 
        }
        if input == "" {
            continue
        }
        g,_ := lex.make_character_grouper("REPL", input, context.temp_allocator)
        defer lex.delete_character_grouper(g)

        root := parse_top_level(g)
        if lex.has_error(g) {
            continue
        }

        c: Checker
        init_checker(&c, g)
        seed(&c, root)
        if c.error_count > 0 {
            lex.flush_messages(g)
            continue
        }

        when ODIN_DEBUG {
            b := strings.builder_make()
            sbprint(root, &b)
            debug := strings.to_string(b)
            fmt.println(debug)
            delete(debug)

            result := check_node(&c, root)
            fmt.println(result.mode)
            fmt.println(result.constraints)
        }
    }
}
