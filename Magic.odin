
package magic

import lex "Godlex"

import "core:fmt"
import "core:mem"
import "core:strings"

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
   
    /*
    g,_ := lex.make_character_grouper(
        "test", 
        `
        // count fibonaccis
        #define N 92 // 93 is too big for i64
        decl count = 0
        decl first = 0
        decl second = 1
        decl next
        while count < N do
            next = first + second
            first = second
            second = next
            count+=1
        first
        `, 
        context.temp_allocator
    )
    */
    
    g,_ := lex.make_character_grouper(
        "test", 
        `
        #define NUTS 67
        #define DEEZ 69 + NUTS
            
        do
            decl thing = push int
            1+1
            DEEZ - NUTS
        `, 
        context.temp_allocator
    )
    defer lex.delete_character_grouper(g)

    root := parse_top_level(g)
    if root == nil {
        return
    }
    roote := node_cast(Block, root)
    lex.error(g, roote.code[0].span, "testo")
    lex.flush_messages(g)
    
    when ODIN_DEBUG {
        b := strings.builder_make()
        sbprint(root, &b)
        debug := strings.to_string(b)
        fmt.println(debug)
        delete(debug)
    }
}
