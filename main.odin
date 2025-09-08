package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

/*
   TODO:
   - show line numbers
   - if pressing enter in the middle of the row, move text right from the cursor to the next line
   - when moving with arrows and reach either the end or the beginning of the line, move to the next/previous line
   - ability to open files
   - scroll (and render only the visible lines)
   - text selection(highlighting)
 */
main :: proc() {
    /*
       @note: sdl.CreateWindow already calls sdl.Init if it
       is not called, but it is still a good practice
       to call sdl.Init beforehand
     */
    if sdl.Init({.VIDEO}) != 0 {
        fmt.eprintln("sdl.Init failed: ", sdl.GetError())
        return
    }
    defer sdl.Quit()

    window := sdl.CreateWindow(
        "slate_editor",
        sdl.WINDOWPOS_UNDEFINED,
        sdl.WINDOWPOS_UNDEFINED,
        1000,
        1000,
        {},
    )

    if window == nil {
        fmt.eprintln("Failed to create the window")
        return
    }

    defer sdl.DestroyWindow(window)

    renderer := sdl.CreateRenderer(window, -1, {.SOFTWARE})
    if renderer == nil {
        fmt.eprintln("Could not create a renderer: ", sdl.GetError())
        return
    }
    defer sdl.DestroyRenderer(renderer)

    if ttf.Init() != 0 {
        fmt.eprintln("Failed to initialize ttf library", ttf.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", EDITOR_FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", ttf.GetError())
        return
    }

    defer ttf.CloseFont(font)

    atlas := Atlas{}
    build_atlas(renderer, font, &atlas)

    editor_lines : [dynamic]Line
    defer delete(editor_lines)

    line_chars : [dynamic]rune
    defer delete(line_chars)

    append(&editor_lines, Line{
        x = 0,
        y = 0,
        chars = line_chars,
    })

    editor := Editor{
        renderer = renderer,
        lines = editor_lines,
        glyph_atlas = &atlas
    }

    current_line_idx : i32 // current active line
    current_col_idx : i32 // current active column

    // where the cursor is positioned on the screen
    cursor_x: i32
    cursor_y: i32

    assert(len(editor.lines) > 0, "Editor lines should have at least one line on startup")

    line_height := editor.glyph_atlas.font_line_skip

    cursor_visible := true
    blink_interval : i32 = 400
    next_blink := sdl.GetTicks() + u32(blink_interval)

    // Main "game" loop
    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
                break loop
            case .TEXTINPUT: // @todo: add 4 spaces if tab is pressed
                glyph := get_glyph_from_atlas(editor.glyph_atlas, int(event.text.text[0]))
                cursor_x += glyph.advance

                character := rune(event.text.text[0])
                line := &editor.lines[current_line_idx]
                append_char_at(&line.chars, character, current_col_idx)
                current_col_idx += 1
                break
            case .KEYDOWN:
                keycode := event.key.keysym.sym
                if keycode == .RETURN {
                    current_line_idx += 1
                    cursor_y += line_height

                    // @todo: cursor col needs to stay the same if possible,
                    // otherwise should be at the end of the line
                    current_col_idx = 0
                    cursor_x = 0


                    line_chars : [dynamic]rune
                    append_line_at(&editor.lines, Line{
                        x = 0,
                        y = current_line_idx,
                        chars = line_chars
                    }, current_line_idx)
                    break
                }
                if keycode == .BACKSPACE {
                    if current_col_idx == 0 {
                        if current_line_idx == 0 {
                            break
                        }

                        // @todo: move to the previous line
                        break
                    }

                    current_col_idx -= 1
                    glyph_to_remove := get_glyph_by_cursor_pos(editor, current_line_idx, current_col_idx)

                    line := &editor.lines[current_line_idx]
                    ordered_remove(&line.chars, current_col_idx)
                    cursor_x -= glyph_to_remove.advance
                    break
                }

                if keycode == .UP {
                    if current_line_idx == 0 {
                        break
                    }
                    current_line_idx -= 1
                    current_col_idx = 0

                    cursor_y -= line_height
                    cursor_x = 0
                    break
                }

                if keycode == .DOWN {
                    if int(current_line_idx + 1) == len(editor.lines) {
                        break
                    }
                    current_line_idx += 1
                    current_col_idx = 0
                    cursor_y += line_height
                    cursor_x = 0
                    break
                }

                if keycode == .LEFT {
                    if current_col_idx == 0 {
                        break
                    }

                    current_col_idx -= 1
                    glyph := get_glyph_by_cursor_pos(editor, current_line_idx, current_col_idx)
                    cursor_x -= glyph.advance
                    break
                }

                if keycode == .RIGHT {
                    line := editor.lines[current_line_idx]
                    char_count := i32(len(line.chars))

                    if current_col_idx >= char_count {
                        break
                    }

                    glyph := get_glyph_from_atlas(editor.glyph_atlas, int(line.chars[current_col_idx]))
                    cursor_x += glyph.advance
                    current_col_idx += 1
                    break
                }
                break

            }
        }

        current_tick := sdl.GetTicks()
        if current_tick >= next_blink {
            cursor_visible = !cursor_visible
            next_blink += u32(blink_interval)
        }

        // Set background color of the window
        sdl.SetRenderDrawColor(renderer, 105, 105, 105, 0) // gray

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        draw_text(&editor)

        if cursor_visible {
            draw_rect(renderer, sdl.Color{0, 0, 255, 255}, {cursor_x, cursor_y + 6}, 5, 30)
        }

        sdl.RenderPresent(renderer)
    }
}

