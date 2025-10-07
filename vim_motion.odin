package main

import "core:fmt"

Vim :: struct {
    enabled: bool,
    mode: Vim_Mode,
    motion_store: [dynamic]rune
}

Vim_Mode :: enum {
    NORMAL,
    VISUAL,
    INSERT,
    PENDING
}

exec_vim_motion_normal_mode :: proc(motion: rune, e: ^Editor) {
    switch motion {
    case 'w':
        current_line_chars := e.lines[e.cursor.line_index].chars
        index_to_jump_to : i32

        // @todo(ksala): seems expensive to loop on every press
        // when at the end of the line, jump to the next line
        for char, i in current_line_chars {
            if i32(i) < e.cursor.col_index {
                continue
            }

            if len(current_line_chars) < i + 1 {
                continue
            }

            if (char == '.' ||
                char == '[' ||
                char == SPACE_ASCII_CODE ||
                char == '(') && current_line_chars[i + 1] != SPACE_ASCII_CODE
            {
                editor_move_cursor_to(e, e.cursor.line_index, i32(i + 1))
                break
            }
        }

        break
    case 'I':
        current_line_chars := e.lines[e.cursor.line_index].chars
        first_non_space_char_idx := 0
        for char, i in current_line_chars {
            if char != SPACE_ASCII_CODE {
                first_non_space_char_idx = i
                break
            }
        }

        editor_move_cursor_to(e, e.cursor.line_index, i32(first_non_space_char_idx))
        e.vim.mode = .INSERT
        break
    case 'A':
        current_line := e.lines[e.cursor.line_index]
        end_of_the_line := len(current_line.chars)
        editor_move_cursor_to(e, e.cursor.line_index, i32(end_of_the_line))
        e.vim.mode = .INSERT
        break
    case 'a':
        editor_move_cursor_right(e)
        e.vim.mode = .INSERT
        break
    case ':':
        if e.active_viewport == .EDITOR {
            e.active_viewport = .COMMAND_LINE
            editor_command_line_on_text_input(e, int(motion))
        }
        break
    case 'j':
        editor_move_cursor_down(e)
        break
    case 'k':
        editor_move_cursor_up(e)
        break
    case 'l':
        editor_move_cursor_right(e)
        break
    case 'h':
        editor_move_cursor_left(e)
        break
    case 'i':
        if len(e.vim.motion_store) > 0 && e.vim.motion_store[0] == 'd' {
            //e.vim_motion_store[1] = motion
            break;
        }

        e.vim.mode = .INSERT
        break
    case 'o':
        chars : [dynamic]rune
        append_line_at(e.lines, Line{
            x = 0,
            y = e.cursor.line_index + 1,
            chars = chars
        }, e.cursor.line_index + 1)

        editor_move_cursor_down(e)

        reset_cursor(e)
        e.vim.mode = .INSERT
        break
    case 'O':
        chars : [dynamic]rune
        append_line_at(e.lines, Line{
            x = 0,
            y = e.cursor.line_index,
            chars = chars
        }, e.cursor.line_index)

        editor_update_visible_lines(e)
        reset_cursor(e)
        e.vim.mode = .INSERT
        break
    case 'd':
        /*fmt.println("delete: ", e.vim)
        if len(e.vim.motion_store) > 0 && e.vim.mode == .PENDING {
            first_key := e.vim.motion_store[0]
            if first_key == 'd' {
                // @todo: delete the line
                ordered_remove(e.lines, e.cursor.line_index)
                reset_cursor(e)

                clear_vim_motion_store(e)
                e.vim.mode = .NORMAL
            }

            break
        }

        append(&e.vim.motion_store, motion)
        e.vim.mode = .PENDING*/
        break
    }
}

clear_vim_motion_store :: proc(e: ^Editor) {
    clear(&e.vim.motion_store)
}

get_vim_mode_text :: proc(vim_mode: Vim_Mode) -> string {
    #partial switch vim_mode {
    case .NORMAL:
        return "NORMAL"
    case .VISUAL:
        return "VISUAL"
    case .INSERT:
        return "INSERT"
    }
    return "NORMAL"
}
