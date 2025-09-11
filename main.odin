package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

/*
   TODO:
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

    line_chars : [dynamic]Character_Info
    defer delete(line_chars)

    append(&editor_lines, Line{
        x = 0,
        y = 0,
        chars = line_chars,
    })

    editor := Editor{
        renderer = renderer,
        font = font,
        lines = editor_lines,
        glyph_atlas = &atlas,
        cursor = Cursor{
            line_index = 0,
            col_index = 0,
            x = EDITOR_OFFSET_X,
            y = 0
        },
        line_height = atlas.font_line_skip
    }

    assert(len(editor.lines) > 0, "Editor lines should have at least one line on startup")

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
            case .TEXTINPUT:
                input := int(event.text.text[0])
                editor_on_text_input(&editor, input)
                break
            case .KEYDOWN:
                keycode := event.key.keysym.sym
                if keycode == .TAB {
                    editor_on_tab(&editor)
                    break
                }
                if keycode == .RETURN {
                    editor_on_return(&editor)
                    break
                }
                if keycode == .BACKSPACE {
                    editor_on_backspace(&editor)
                    break
                }

                if keycode == .UP {
                    editor_move_cursor_up(&editor)
                    break
                }

                if keycode == .DOWN {
                    editor_move_cursor_down(&editor)
                    break
                }

                if keycode == .LEFT {
                    editor_move_cursor_left(&editor)
                    break
                }

                if keycode == .RIGHT {
                    editor_move_cursor_right(&editor)
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
        sdl.SetRenderDrawColor(renderer, 6, 69, 38, 0)

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        editor_draw_text(&editor)

        if cursor_visible {
            editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {editor.cursor.x, editor.cursor.y + 6}, 5, 30)
        }

        sdl.RenderPresent(renderer)
    }
}


