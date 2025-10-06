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
    case ':':
        if e.active_viewport == .EDITOR {
            e.active_viewport = .COMMAND_LINE
            //@todo: add ':' to cmd_line input e.cmd_line.input
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
        chars : [dynamic]Character_Info
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
        chars : [dynamic]Character_Info
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
