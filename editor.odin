package main

import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

EDITOR_FONT_SIZE :: 25
EDITOR_GUTTER_WIDTH :: 70
EDITOR_RIGHT_SIDE_CUTOFF :: 10
//EDITOR_CURSOR_OFFSET :: 8 // 8 lines

COMMAND_LINE_HEIGHT :: 25
SPACE_ASCII_CODE :: 32

Viewport :: enum {
    EDITOR,
    COMMAND_LINE
}

Editor :: struct {
    editor_gutter_clip: sdl.Rect,
    editor_clip: sdl.Rect,
    editor_offset_x: i32, // to track horizontal scrolling

    // Do not allow for the cursor to go past this line.
    // Once the cursor gets here, decrease the editor offset_x
    cursor_right_side_cutoff_line: i32, 
    command_clip: sdl.Rect,
    active_viewport: Viewport,

    renderer: ^sdl.Renderer,
    font: ^ttf.Font,
    glyph_atlas: ^Atlas,

    lines: ^[dynamic]Line,
    lines_start: i32,
    lines_end: i32,
    line_height: i32,

    cursor: Cursor,

    vim: Vim,
}

Line :: struct {
    data: string,
    chars: [dynamic]Character_Info,
    x, y: i32,
}

Character_Info :: struct {
    char: rune,
    glyph: ^Glyph,

    char_idx: i32
}

Cursor :: struct {
    line_index: i32,
    col_index: i32, // current col index

    // update every time cursor is moved manually left or right
    memorized_col_index: i32,
    x, y: i32, // pixel pos

    visible: bool,
    indent: i32
}

Cursor_Move_Direction :: enum {
    NONE,
    UP,
    DOWN
}

draw_custom_text :: proc(renderer: ^sdl.Renderer, atlas: ^Atlas, text: string, pos: [2]f32) {
    pen_x : i32 = i32(pos.x)

    sdl.SetTextureColorMod(atlas.texture, 155, 0, 0) //red

    for char in text {
        glyph := get_glyph_from_atlas(atlas, int(char))
        if glyph == nil {
            continue
        }
        glyph_x := pen_x
        destination : sdl.FRect = {f32(glyph_x), pos.y, f32(glyph.width), f32(glyph.height)}

        uv : sdl.FRect
        sdl.RectToFRect(glyph.uv, &uv)

        sdl.RenderTexture(renderer, atlas.texture, &uv, &destination)
        pen_x += glyph.advance
    }
}

editor_draw_text :: proc(editor: ^Editor) {
    pen_x := editor.editor_offset_x
    baseline : i32 = 0

    sdl.SetTextureColorMod(editor.glyph_atlas.texture, 255, 255, 255)
    string_count := 0

    for line, i in editor.lines {
        if i32(i) < editor.lines_start || i32(i) > editor.lines_end {
            continue
        }
        // letters uppercase [65..90] and  lower_case [97..122]

        for character_info, i in line.chars {
            glyph := character_info.glyph
            if glyph == nil {
                continue
            }

            /*word, ok := strings.substring(line.data, i, 32)
            fmt.println(word)*/

            // set string color
            if character_info.char == '"' {
                string_count += 1
                sdl.SetTextureColorMod(editor.glyph_atlas.texture, 125, 247, 0) //green
            }

            glyph_x := pen_x
            glyph_y := baseline //- glyph.bearing_y
            destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

            uv : sdl.FRect
            sdl.RectToFRect(glyph.uv, &uv)

            sdl.RenderTexture(editor.renderer, editor.glyph_atlas.texture, &uv, &destination)
            pen_x += glyph.advance

            if string_count >= 2 {
                string_count = 0
                sdl.SetTextureColorMod(editor.glyph_atlas.texture, 255, 255, 255)
            }
        }

        baseline += editor.glyph_atlas.font_line_skip
        pen_x = editor.editor_offset_x
    }
}

editor_move_cursor_up :: proc(editor: ^Editor) {
    if editor.cursor.line_index == 0 {
        return
    }

    editor.cursor.line_index -= 1
    editor_update_visible_lines(editor, .UP)

    cursor_idx_in_view := get_cursor_line_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    editor_retain_cursor_column(editor)
}

editor_move_cursor_down :: proc(editor: ^Editor) {
    if int(editor.cursor.line_index + 1) == len(editor.lines) {
        return
    }

    editor.cursor.line_index += 1
    editor_update_visible_lines(editor, .DOWN)

    cursor_idx_in_view := get_cursor_line_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    editor_retain_cursor_column(editor)
}

editor_move_cursor_left :: proc(editor: ^Editor) {
    if editor.cursor.col_index <= 0 {
        editor.cursor.col_index = 0 // failsafe
        editor.editor_offset_x = EDITOR_GUTTER_WIDTH
        return
    }

    editor.cursor.col_index -= 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor_update_cursor_and_offset(editor)

    assert(editor.cursor.x >= EDITOR_GUTTER_WIDTH)
}

editor_move_cursor_right :: proc(editor: ^Editor) {
    line := editor.lines[editor.cursor.line_index]
    char_count := i32(len(line.chars))
    if char_count == 0 || char_count == editor.cursor.col_index {
        return
    }

    editor.cursor.col_index += 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor_update_cursor_and_offset(editor)
}

editor_on_backspace :: proc(editor: ^Editor) { 
    if editor.cursor.col_index == 0 {
        if editor.cursor.line_index == 0 {
            return
        }

        current_line := editor.lines[editor.cursor.line_index]
        line_above_current_line := &editor.lines[editor.cursor.line_index - 1]

        editor.cursor.col_index = i32(len(line_above_current_line.chars))
        editor.cursor.memorized_col_index = editor.cursor.col_index

        for c in line_above_current_line.chars {
            editor.cursor.x += c.glyph.advance
        }

        if len(current_line.chars) > 0 {
            append(&line_above_current_line.chars, ..current_line.chars[:])
        }

        ordered_remove(editor.lines, editor.cursor.line_index)
        editor_move_cursor_up(editor)
        return
    }

    editor_move_cursor_left(editor)
    editor.cursor.memorized_col_index = editor.cursor.col_index
    glyph_to_remove := get_glyph_under_cursor(editor)

    line := &editor.lines[editor.cursor.line_index]
    ordered_remove(&line.chars, editor.cursor.col_index)
}

editor_on_return :: proc(editor: ^Editor) { 
    editor.editor_offset_x = EDITOR_GUTTER_WIDTH

    current_line := &editor.lines[editor.cursor.line_index]
    current_col := editor.cursor.col_index
    chars_to_move: []Character_Info
    defer {
        chars_to_move = nil
    }

    if current_col == 0 {
        chars_to_move = current_line.chars[current_col:]
        clear(&current_line.chars)
    }

    if current_col > 0 {
        data: [dynamic]Character_Info
        chars_to_move = current_line.chars[current_col:]
        chars_to_keep := current_line.chars[:current_col]
        append(&data, ..chars_to_keep[:])
        current_line.chars = data
    }

    editor.cursor.line_index += 1

    editor.cursor.col_index = 0
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor.cursor.x = editor.editor_offset_x

    cursor_pos_idx_in_view := get_cursor_line_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_pos_idx_in_view * editor.line_height

    line_chars : [dynamic]Character_Info
    if len(chars_to_move) > 0 {
        append(&line_chars, ..chars_to_move[:])
    }

    append_line_at(editor.lines, Line{
        x = 0,
        y = editor.cursor.line_index,
        chars = line_chars
    }, editor.cursor.line_index)

    editor_update_visible_lines(editor, .DOWN)
}

editor_on_tab :: proc(editor: ^Editor) {
    for _ in 0..<4 {
        editor_on_text_input(editor, SPACE_ASCII_CODE)
    }
}

editor_on_text_input :: proc(editor: ^Editor, char: int) {
    glyph := get_glyph_from_atlas(editor.glyph_atlas, char)
    if glyph == nil {
        fmt.eprintln("Glyph not found from atlas: ", char)
        return
    }

    if editor.cursor.x + glyph.advance > editor.cursor_right_side_cutoff_line {
        editor.editor_offset_x -= glyph.advance
    } else {
        editor.cursor.x += glyph.advance
    }

    character_info := Character_Info{
        char = rune(char),
        glyph = glyph
    }

    line := &editor.lines[editor.cursor.line_index]
    append_char_at(&line.chars, character_info, editor.cursor.col_index)

    editor.cursor.col_index += 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
}

editor_draw_rect :: proc(renderer: ^sdl.Renderer, color: sdl.Color, pos: [2]i32, w: i32, h: i32) -> sdl.FRect {
    sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    rect: sdl.FRect = {f32(pos.x), f32(pos.y), f32(w), f32(h)};
    sdl.RenderFillRect(renderer, &rect)
    return rect
}

editor_draw_status_line :: proc(renderer: ^sdl.Renderer) {
    // @todo
}

editor_on_file_open :: proc(editor: ^Editor, file_name: string) {
    data, ok := os.read_entire_file_from_filename(file_name)
    if !ok {
        fmt.eprintln("Could not read the file")
        return
    }
    defer delete(data)

    it := string(data)
    lines: [dynamic]Line
    for line in strings.split_lines_iterator(&it) {
        editor_line := Line{
            chars = make([dynamic]Character_Info)
        }

        for character, idx in line {
            cp := int(character)
            glyph := get_glyph_from_atlas(editor.glyph_atlas, cp)

            character_info := Character_Info{
                char = character,
                glyph = glyph,
                char_idx = i32(idx)
            }
            append(&editor_line.chars, character_info)
        }

        append(&lines, editor_line)
    }

    clear(editor.lines)
    append(editor.lines, ..lines[:])
}

editor_draw_line_nr :: proc(editor: ^Editor) {
    line_skip: i32 = 0
    for i in editor.lines_start..<editor.lines_end {
        line_nr := fmt.tprintf("%v", i + 1)
        line_nr_cstring := strings.clone_to_cstring(line_nr)
        defer delete(line_nr_cstring)

        surface := ttf.RenderText_Blended(editor.font, line_nr_cstring, 0 ,{255, 255, 255, 50})
        if surface == nil {
            fmt.eprintln("RenderText_blended error: ", sdl.GetError())
        }
        defer sdl.DestroySurface(surface)

        tex := sdl.CreateTextureFromSurface(editor.renderer, surface)
        defer sdl.DestroyTexture(tex)

        rect : sdl.FRect = {0, f32(line_skip), f32(surface.w), f32(surface.h)}
        sdl.RenderTexture(editor.renderer, tex, nil, &rect)

        line_skip += editor.glyph_atlas.font_line_skip
    }
}

editor_jump_to_line :: proc(destination_line: i32) {
    // @todo
}

// Cursor pos based where the cursor is on the line.
// This value can be bigger than the bounds of the editor/window,
// but the value should not be assigned to the cursor.x, this would
// put the cursor off the screen
@(private = "file")
cursor_pos_x_on_line :: proc(editor: ^Editor) -> i32 {
    current_line := editor.lines[editor.cursor.line_index]
    pos_x: i32 = EDITOR_GUTTER_WIDTH;
    if current_line.chars == nil {
        return pos_x
    }

    for char_info, i in current_line.chars[:editor.cursor.col_index] {
        pos_x += char_info.glyph.advance
    }

    return pos_x
}

@(private = "file")
get_glyph_under_cursor :: proc(editor: ^Editor) -> ^Glyph {
    line := editor.lines[editor.cursor.line_index]
    glyph := line.chars[editor.cursor.col_index].glyph
    return glyph
}

// @remove: not in use
@(private = "file")
get_normalized_window_height :: proc(window: ^sdl.Window, editor_line_height: i32) -> i32 {
    w, h: i32
    sdl.GetWindowSize(window, &w, &h)

    lines_count := h / editor_line_height
    normalized_height := lines_count * editor_line_height
    return normalized_height
}

@(private = "file")
get_cursor_line_index_in_visible_lines :: proc(editor: Editor) -> i32 {
    cursor_row_nr := editor.cursor.line_index
    cursor_idx_in_visible_lines := cursor_row_nr - editor.lines_start
    return cursor_idx_in_visible_lines
}

editor_update_visible_lines :: proc(editor: ^Editor, move_dir: Cursor_Move_Direction = .NONE) {
    assert(editor.line_height > 0, "Editor line height is not set")

    max_visible_rows := editor.editor_clip.h / editor.line_height
    cursor_idx_in_visible_lines := get_cursor_line_index_in_visible_lines(editor^)

    if cursor_idx_in_visible_lines >= i32(max_visible_rows) && move_dir == .DOWN {
        editor.lines_start = editor.cursor.line_index + 1 - i32(max_visible_rows)
    }

    if editor.cursor.line_index < editor.lines_start {
        editor.lines_start = editor.cursor.line_index
    }

    editor.lines_end = editor.lines_start + i32(max_visible_rows)
    if editor.lines_end > i32(len(editor.lines)) {
        editor.lines_end = i32(len(editor.lines))
    }
}

@(private = "file")
editor_retain_cursor_column :: proc(editor: ^Editor) {
    total_glyph_width : i32 = 0
    current_line_data := editor.lines[editor.cursor.line_index].chars

    if int(editor.cursor.memorized_col_index) >= len(current_line_data) {
        for char_info in current_line_data {
            total_glyph_width += char_info.glyph.advance
        }
    } else {
        for char_info in current_line_data[:editor.cursor.memorized_col_index] {
            total_glyph_width += char_info.glyph.advance
        }
    }

    current_line_length := len(current_line_data)
    if current_line_length - 1 >= int(editor.cursor.memorized_col_index) {
        editor.cursor.col_index = editor.cursor.memorized_col_index
    } else {
        editor.cursor.col_index = i32(current_line_length)
    }

    editor_update_cursor_and_offset(editor)
}

editor_vim_mode_normal_shortcuts :: proc(input: int, editor: ^Editor) {
    //exec_vim_motion(input)
    if input == int('j') {
        editor_move_cursor_down(editor)
    } else if input == int('k') {
        editor_move_cursor_up(editor)
    } else if input == int('h') {
        editor_move_cursor_left(editor)
    } else if input == int('l') {
        editor_move_cursor_right(editor)
    } else if input == int('i') {
        editor.vim.mode = .INSERT
    } else if input == int('o') {
        editor_move_cursor_down(editor)

        chars : [dynamic]Character_Info
        append_line_at(editor.lines, Line{
            x = 0,
            y = editor.cursor.line_index,
            chars = chars
        }, editor.cursor.line_index)

        reset_cursor(editor)
    } else if input == int('O') {
        chars : [dynamic]Character_Info
        append_line_at(editor.lines, Line{
            x = 0,
            y = editor.cursor.line_index,
            chars = chars
        }, editor.cursor.line_index)

        reset_cursor(editor)
    } else if input == int('w') { // @fix: if 2 spaces in a row and add symbol support.
        idx_to_move_to := editor.cursor.col_index
        current_line_data := editor.lines[editor.cursor.line_index].chars
        for data, idx in current_line_data {
            if i32(idx) < editor.cursor.col_index {
                continue
            }
            if data.char == rune(32) {
                idx_to_move_to = i32(idx + 1)
                break
            }
        }
        editor_move_cursor_to(editor, editor.cursor.line_index, idx_to_move_to)
    } else if input == int('b') { // @fix: if 2 spaces in a row
        idx_to_move_to : i32 = 0
        current_line_data := editor.lines[editor.cursor.line_index].chars
        #reverse for data, idx in current_line_data {
            if i32(idx) > editor.cursor.col_index {
                continue
            }
            if data.char == rune(32) {
                if i32(idx) + 1 == editor.cursor.col_index {
                    continue
                }
                idx_to_move_to = i32(idx + 1)
                break
            }
        }
        editor_move_cursor_to(editor, editor.cursor.line_index, idx_to_move_to)
    }
}

@(private = "file")
editor_move_cursor_to :: proc(editor: ^Editor, line_to_move_to: i32, col_to_move_to: i32) {
    editor.cursor.line_index = line_to_move_to
    editor.cursor.col_index = col_to_move_to
    editor.cursor.memorized_col_index = col_to_move_to

    editor_update_cursor_and_offset(editor)
}

@(private = "file")
editor_update_cursor_and_offset :: proc(editor: ^Editor) {
    left_bound := EDITOR_GUTTER_WIDTH
    right_bound := editor.cursor_right_side_cutoff_line

    cursor_x_on_line := cursor_pos_x_on_line(editor)

    // reset offset and then recalculate
    editor.editor_offset_x = EDITOR_GUTTER_WIDTH

    if cursor_x_on_line > right_bound {
        diff := right_bound - cursor_x_on_line
        editor.editor_offset_x = EDITOR_GUTTER_WIDTH - math.abs(diff)
        editor.cursor.x = right_bound
        return
    }

    if cursor_x_on_line < editor.editor_offset_x {
        diff := editor.editor_offset_x - cursor_x_on_line
        editor.editor_offset_x = EDITOR_GUTTER_WIDTH + math.abs(diff)
        editor.cursor.x = EDITOR_GUTTER_WIDTH
        return
    }

    if cursor_x_on_line == EDITOR_GUTTER_WIDTH {
        editor.editor_offset_x = EDITOR_GUTTER_WIDTH
    }

    editor.cursor.x = cursor_x_on_line

    assert(editor.cursor.x >= EDITOR_GUTTER_WIDTH, "Cursor pos can not be smaller than the gutter width")
    assert(editor.cursor.x <= editor.cursor_right_side_cutoff_line, "Cursor pos can not be bigger than the right side cutoff line")
}


reset_cursor :: proc(editor: ^Editor) {
    editor.cursor.col_index = 0
    editor.cursor.x = EDITOR_GUTTER_WIDTH
    editor.editor_offset_x = EDITOR_GUTTER_WIDTH
}

