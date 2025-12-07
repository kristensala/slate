package main

import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

DEFAULT_EDITOR_FONT_SIZE :: 25
EDITOR_GUTTER_WIDTH :: 70
EDITOR_RIGHT_SIDE_CUTOFF :: 10
EDITOR_BOTTOM_PADDING :: 60
//EDITOR_CURSOR_OFFSET :: 8 // 8 lines

COMMAND_LINE_HEIGHT :: 25
SPACE_ASCII_CODE :: 32

SHOW_BUFFER :: true

Viewport :: enum {
    EDITOR,
    COMMAND_LINE
}

/*
   Gap buffer:
   What if I read the data into multiple buffers
   based on how many lines fit to the screen.
   Each of these buffers will have a 15 char empty buffer at the end!
   Like splitting them into paragraphs.
   I don't think this will work. I can show half of the paragraph and this gets overly complicated

   ...
   I do know the index on the cursor inside of the buffer. I can take a substring starting anywhere close to the cursor
 */

@(rodata)
lexer := []string{
    "package", "for", "proc", "if", "else", "import",
    "func", "function", "fn", "return", "int", "i32",
    "def", "bool", "string", "defer", "switch", "in",
    "case", "struct", "enum", "class", "public", "private",
    "dynamic", "rune", "break"
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
    
    // testing gap buffer
    lines2: ^[dynamic]Gap_Buffer,

    lines: ^[dynamic]Line,
    lines_start: i32,
    lines_end: i32,
    line_height: i32,

    cursor: Cursor,
    cmd_line: Command_Line,

    vim: Vim,
    theme: Theme
}

Theme :: struct {
    text_color: sdl.Color,
    background_color: sdl.Color,
    keyword_color: sdl.Color,
    string_color: sdl.Color,
    line_nr_color: sdl.Color,
    comment_color: sdl.Color,

    font_size: i32
}

Line :: struct {
    chars: [dynamic]rune,
    x, y: i32,
    is_dirty: bool
}

Cursor :: struct {
    line_index: i32,
    col_index: i32, // current col index
    fat_cursor: i32,
    skinny_cursor: i32,

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

    sdl.SetTextureColorMod(atlas.texture, 0, 0, 0)

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
editor_draw_text_v2 :: proc(editor: ^Editor) {
    sdl.SetTextureColorMod(
        editor.glyph_atlas.texture,
        editor.theme.text_color.r,
        editor.theme.text_color.g,
        editor.theme.text_color.b)

    pen_x := editor.editor_offset_x
    baseline : i32 = 0

    string_count := 0

    for &line, line_idx in editor.lines2 {
        for char, char_idx in line.data {
            if !SHOW_BUFFER {
                if i32(char_idx) >= line.gap_start && i32(char_idx) < line.gap_end {
                    continue
                }
            }

            char_do_draw := char
            if (SHOW_BUFFER) {
                if i32(char_idx) >= line.gap_start && i32(char_idx) < line.gap_end {
                    char_do_draw = '_'
                }

            }

            glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char_do_draw))
            glyph_x := pen_x
            glyph_y := baseline
            destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

            uv : sdl.FRect
            sdl.RectToFRect(glyph.uv, &uv)

            sdl.RenderTexture(editor.renderer, editor.glyph_atlas.texture, &uv, &destination)
            pen_x += glyph.advance
        }
        baseline += editor.glyph_atlas.font_line_skip
        pen_x = editor.editor_offset_x
    }
}

editor_draw_text :: proc(editor: ^Editor) {
    pen_x := editor.editor_offset_x
    baseline : i32 = 0

    sdl.SetTextureColorMod(
        editor.glyph_atlas.texture,
        editor.theme.text_color.r,
        editor.theme.text_color.g,
        editor.theme.text_color.b)

    string_count := 0
    for &line, line_idx in editor.lines[editor.lines_start:editor.lines_end] {
        comment_started : bool = false

        char_idx: int
        quotation_mark_count: i32

        b := strings.builder_make()
        defer strings.builder_destroy(&b)

        for c in line.chars {
            strings.write_rune(&b, c)
        }

        data := strings.to_string(b)
        split_line_data := strings.split(data, " ")

        defer delete(split_line_data)
        free(&data)

        for word, word_idx in split_line_data {
            contains_keyword, start_idx, end_idx := contains_where(lexer, word)
            if !comment_started {
                if quotation_mark_count % 2 == 0 {
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.text_color.r,
                        editor.theme.text_color.g,
                        editor.theme.text_color.b)

                    quotation_mark_count = 0
                }
            }

            for char, idx in word {
                if char == '/' && len(word) > idx + 1 && word[idx + 1] == '/' && !comment_started {
                    comment_started = true
                }
                if contains_keyword && start_idx == idx  {
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.keyword_color.r,
                        editor.theme.keyword_color.g,
                        editor.theme.keyword_color.b)
                }

                if contains_keyword && idx == end_idx {
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.text_color.r,
                        editor.theme.text_color.g,
                        editor.theme.text_color.b)
                }

                if char == '"' {
                    quotation_mark_count += 1
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.string_color.r,
                        editor.theme.string_color.g,
                        editor.theme.string_color.b) 
                }

                if comment_started {
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.string_color.r,
                        editor.theme.string_color.g,
                        editor.theme.string_color.b)
                }
                
                glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char))
                glyph_x := pen_x
                glyph_y := baseline //- glyph.bearing_y
                destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

                uv : sdl.FRect
                sdl.RectToFRect(glyph.uv, &uv)

                sdl.RenderTexture(editor.renderer, editor.glyph_atlas.texture, &uv, &destination)
                pen_x += glyph.advance

                if quotation_mark_count == 2 {
                    quotation_mark_count = 0
                    sdl.SetTextureColorMod(
                        editor.glyph_atlas.texture,
                        editor.theme.text_color.r,
                        editor.theme.text_color.g,
                        editor.theme.text_color.b)
                }

                char_idx += 1
            }

            if word_idx == len(split_line_data) - 1 {
                // end of the line
                continue
            }

            // @note(kristen): finished with the word, add a space
            glyph := get_glyph_from_atlas(editor.glyph_atlas, SPACE_ASCII_CODE)
            glyph_x := pen_x
            glyph_y := baseline
            destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

            uv : sdl.FRect
            sdl.RectToFRect(glyph.uv, &uv)

            sdl.RenderTexture(editor.renderer, editor.glyph_atlas.texture, &uv, &destination)
            pen_x += glyph.advance

            char_idx += 1
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

editor_move_cursor_down :: proc(editor: ^Editor, retain_col: bool = true) {
    if int(editor.cursor.line_index + 1) == len(editor.lines) {
        return
    }

    editor.cursor.line_index += 1
    editor_update_visible_lines(editor, .DOWN)

    cursor_idx_in_view := get_cursor_line_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    if retain_col {
        editor_retain_cursor_column(editor)
    } else {
        reset_cursor_to_first_word(editor)
    }
}

// @todo: move gap buffer
// by updating the gap_start and gap_end
// and move the chars around
// between gap_start and gap_end there can be no characters
editor_move_cursor_left :: proc(editor: ^Editor) {
    if editor.cursor.col_index <= 0 {
        editor.cursor.col_index = 0 // failsafe
        editor.editor_offset_x = EDITOR_GUTTER_WIDTH
        return
    }

    editor.cursor.col_index -= 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor_update_cursor_col_and_offset(editor)

    assert(editor.cursor.x >= EDITOR_GUTTER_WIDTH)
}

editor_move_cursor_right_v2 :: proc(editor: ^Editor) {
    line := &editor.lines2[editor.cursor.line_index]
    char_count := line.len
    if char_count == 0 || char_count == editor.cursor.col_index {
        return
    }

    editor.cursor.col_index += 1
    
    // start shifting the cap
    new_gap_start := editor.cursor.col_index
    new_gap_end := line.gap_end + 1

    new_data := make([]rune, line.cap)

    // @note: build the data by removing the gap
    old_data_before_gap := line.data[0:line.gap_start]
    old_data_after_gap := line.data[line.gap_end:]

    data : [dynamic]rune
    defer delete(data)

    append(&data, ..old_data_before_gap[:])
    append(&data, ..old_data_after_gap[:])

    count := 0
    for char, idx in new_data {
        if i32(idx) >= new_gap_start && i32(idx) < new_gap_end {
            new_data[idx] = '_'
            continue
        }

        new_data[idx] = data[count]
        count += 1
    }

    line.data = new_data
    line.gap_start = new_gap_start
    line.gap_end = new_gap_end


    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor_update_cursor_col_and_offset(editor)

}

editor_move_cursor_right :: proc(editor: ^Editor) {
    line := editor.lines[editor.cursor.line_index]
    char_count := i32(len(line.chars))
    if char_count == 0 || char_count == editor.cursor.col_index {
        return
    }

    editor.cursor.col_index += 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor_update_cursor_col_and_offset(editor)
}

editor_on_backspace :: proc(editor: ^Editor) { 
    if editor.cursor.col_index == 0 {
        if editor.cursor.line_index == 0 {
            return
        }

        line_above_current_line := &editor.lines[editor.cursor.line_index - 1]

        editor.cursor.col_index = i32(len(line_above_current_line.chars))
        editor.cursor.memorized_col_index = editor.cursor.col_index

        for c in line_above_current_line.chars {
            glyph := get_glyph_from_atlas(editor.glyph_atlas, int(c))
            editor.cursor.x += glyph.advance
        }

        current_line := editor.lines[editor.cursor.line_index]
        if len(current_line.chars) > 0 {
            append(&line_above_current_line.chars, ..current_line.chars[:])
        }

        ordered_remove(editor.lines, editor.cursor.line_index)

        current_line.is_dirty = true
        editor_move_cursor_up(editor)
        editor.lines[editor.cursor.line_index].is_dirty = true
        return
    }

    editor_move_cursor_left(editor)
    editor.cursor.memorized_col_index = editor.cursor.col_index
    glyph_to_remove := get_glyph_under_cursor(editor)

    line := &editor.lines[editor.cursor.line_index]
    ordered_remove(&line.chars, editor.cursor.col_index)

    line.is_dirty = true
}

editor_on_return :: proc(editor: ^Editor) { 
    editor.editor_offset_x = EDITOR_GUTTER_WIDTH

    current_line := &editor.lines[editor.cursor.line_index]
    current_line.is_dirty = true

    current_col := editor.cursor.col_index
    chars_to_move: []rune
    defer {
        chars_to_move = nil
    }

    if current_col == 0 {
        chars_to_move = current_line.chars[current_col:]
        clear(&current_line.chars)
    }

    if current_col > 0 {
        data: [dynamic]rune
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

    max_visible_rows := editor.editor_clip.h / editor.line_height
    if editor.cursor.y > max_visible_rows * editor.line_height - editor.line_height {
        editor.cursor.y = max_visible_rows * editor.line_height - editor.line_height
    }

    line_chars : [dynamic]rune
    if len(chars_to_move) > 0 {
        append(&line_chars, ..chars_to_move[:])
    }

    append_line_at(editor.lines, Line{
        x = 0,
        y = editor.cursor.line_index,
        chars = line_chars
    }, editor.cursor.line_index)

    editor.lines[editor.cursor.line_index].is_dirty = true
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


    line := &editor.lines[editor.cursor.line_index]
    append_char_at(&line.chars, rune(char), editor.cursor.col_index)

    editor.cursor.col_index += 1
    editor.cursor.memorized_col_index = editor.cursor.col_index

    line.is_dirty = true
}

editor_draw_rect :: proc(
    renderer: ^sdl.Renderer,
    color: sdl.Color,
    pos: [2]i32,
    w: i32,
    h: i32
) -> sdl.FRect {
    ok := sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    if !ok {
        fmt.eprintln("Could not set the rect color: ", sdl.GetError())
    }
    rect: sdl.FRect = {f32(pos.x), f32(pos.y), f32(w), f32(h)}
    sdl.RenderFillRect(renderer, &rect)
    return rect
}

// @note: gap buffer testing here
editor_on_file_open_v2 :: proc(editor: ^Editor, file_name: string) {
    data, ok := os.read_entire_file_from_filename(file_name)
    if !ok {
        fmt.eprintln("Could not read the file")
        return
    }
    defer delete(data)

    it := string(data)

    buffers: [dynamic]Gap_Buffer
    for line in strings.split_lines_iterator(&it) {
        line_len := len(line)
        cap := line_len + DEFAULT_GAP_BUFFER_SIZE

        start := DEFAULT_GAP_BUFFER_SIZE
        gap_buffer := Gap_Buffer{
            data = make([]rune, cap),

            gap_start = 0,
            gap_end = DEFAULT_GAP_BUFFER_SIZE,

            len = i32(line_len),
            cap = i32(cap)
        }

        for character in line {
            gap_buffer.data[start] = character
            start = start + 1
        }


        append(&buffers, gap_buffer)
    }

    clear(editor.lines2)
    append(editor.lines2, ..buffers[:])
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
    // @todo: get the length of the line and add a buffer size to it
    for line in strings.split_lines_iterator(&it) {
        {
            // new gap buffer data testing
            /*
               line_len := len(line)
               cap := line_len + DEFAULT_GAP_BUFFER_SIZE

               data := make([]rune, cap)
               gap_start := line_len
               gap_end := len(data) - 1
             */
        }

        editor_line := Line{
            chars = make([dynamic]rune)
        }

        for character, idx in line {
            append(&editor_line.chars, character)
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

        // @todo: use glyph atlas
        surface := ttf.RenderText_Blended(editor.font, line_nr_cstring, 0, editor.theme.line_nr_color)
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

// Cursor pos based where the cursor is on the line.
// This value can be bigger than the bounds of the editor/window,
// but the value should not be assigned to the cursor.x, this would
// put the cursor off the screen
@(private = "file")
cursor_pos_x_on_line :: proc(editor: ^Editor) -> i32 {
    current_line := editor.lines2[editor.cursor.line_index]
    pos_x: i32 = EDITOR_GUTTER_WIDTH;
    if current_line.data == nil {
        return pos_x
    }

    for char, i in current_line.data[:editor.cursor.col_index] {
        glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char))
        pos_x += glyph.advance
    }

    return pos_x
}

@(private = "file")
get_glyph_under_cursor :: proc(editor: ^Editor) -> ^Glyph {
    line := editor.lines[editor.cursor.line_index]
    char := line.chars[editor.cursor.col_index]
    glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char))
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

// @note: this handles scrolling but not jumping to the line
editor_update_visible_lines :: proc(
    editor: ^Editor,
    move_dir: Cursor_Move_Direction = .NONE
) {
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
        for char in current_line_data {
            glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char))
            total_glyph_width += glyph.advance
        }
    } else {
        for char in current_line_data[:editor.cursor.memorized_col_index] {
            glyph := get_glyph_from_atlas(editor.glyph_atlas, int(char))
            total_glyph_width += glyph.advance
        }
    }

    current_line_length := len(current_line_data)
    if current_line_length - 1 >= int(editor.cursor.memorized_col_index) {
        editor.cursor.col_index = editor.cursor.memorized_col_index
    } else {
        editor.cursor.col_index = i32(current_line_length)
    }

    editor_update_cursor_col_and_offset(editor)
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

        chars : [dynamic]rune
        append_line_at(editor.lines, Line{
            x = 0,
            y = editor.cursor.line_index,
            chars = chars
        }, editor.cursor.line_index)

        reset_cursor(editor)
    } else if input == int('O') {
        chars : [dynamic]rune
        append_line_at(editor.lines, Line{
            x = 0,
            y = editor.cursor.line_index,
            chars = chars
        }, editor.cursor.line_index)

        reset_cursor(editor)
    } else if input == int('w') { // @fix: if 2 spaces in a row and add symbol support.
        idx_to_move_to := editor.cursor.col_index
        current_line_data := editor.lines[editor.cursor.line_index].chars
        for char, idx in current_line_data {
            if i32(idx) < editor.cursor.col_index {
                continue
            }
            if char == rune(32) {
                idx_to_move_to = i32(idx + 1)
                break
            }
        }
        editor_move_cursor_to(editor, editor.cursor.line_index, idx_to_move_to)
    } else if input == int('b') { // @fix: if 2 spaces in a row
        idx_to_move_to : i32 = 0
        current_line_data := editor.lines[editor.cursor.line_index].chars
        #reverse for char, idx in current_line_data {
            if i32(idx) > editor.cursor.col_index {
                continue
            }
            if char == rune(32) {
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

editor_move_cursor_to :: proc(editor: ^Editor, line_to_move_to: i32, col_to_move_to: i32) {
    if int(line_to_move_to) > len(editor.lines) - 1 || line_to_move_to < 0 {
        return
    }

    editor.cursor.line_index = line_to_move_to
    editor.cursor.col_index = col_to_move_to
    editor.cursor.memorized_col_index = col_to_move_to

    if line_to_move_to < editor.lines_start || line_to_move_to > editor.lines_end {
        // @note: keep a 10 line buffer so that the cursor will be somewhere
        // in the middle of the screen, not bottom or top
        if line_to_move_to > 10 {
            editor.lines_start = line_to_move_to - 10
        } else {
            editor.lines_start = 0
        }
        editor_update_visible_lines(editor)
    }

    cursor_pos_idx_in_view := get_cursor_line_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_pos_idx_in_view * editor.line_height

    editor_update_cursor_col_and_offset(editor)
}

@(private = "file")
editor_update_cursor_col_and_offset :: proc(editor: ^Editor) {
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

    assert(editor.cursor.x >= EDITOR_GUTTER_WIDTH,
        "Cursor pos can not be smaller than the gutter width")

    assert(editor.cursor.x <= editor.cursor_right_side_cutoff_line,
        "Cursor pos can not be bigger than the right side cutoff line")
}

reset_cursor :: proc(editor: ^Editor) {
    editor.cursor.col_index = 0
    editor.cursor.x = EDITOR_GUTTER_WIDTH
    editor.editor_offset_x = EDITOR_GUTTER_WIDTH
}

reset_cursor_to_first_word :: proc(e: ^Editor) {
    current_line_chars := e.lines[e.cursor.line_index].chars
    if len(current_line_chars) == 0 {
        reset_cursor(e)
        return
    }

    // get first char index which is not a space
    for c, i in current_line_chars {
        if c == SPACE_ASCII_CODE {
            continue
        }

        editor_move_cursor_to(e, e.cursor.line_index, i32(i))
        break
    }
}

