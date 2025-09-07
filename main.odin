package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

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
    line_chars : [dynamic]rune
    append(&editor_lines, Line{
        x = 0,
        y = 0,
        chars = line_chars
    })

    editor := Editor{
        renderer = renderer,
        lines = editor_lines,
        glyph_atlas = &atlas
    }

    // current active line
    current_line : i32

    assert(len(editor_lines) > 0, "Editor lines should have at least one line on startup")

    // Main "game" loop
    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
                clear(&editor_lines)
                break loop
            case .TEXTINPUT:
                character := rune(event.text.text[0])
                append(&editor_lines[current_line].chars, character)
                break
            case .KEYDOWN:
                keycode := event.key.keysym.sym
                if keycode == .RETURN {
                    current_line += 1

                    line_chars : [dynamic]rune
                    append_line_at(&editor_lines, Line{
                        x = 0,
                        y = current_line,
                        chars = line_chars
                    }, current_line)
                    break
                }
                if keycode == .BACKSPACE {
                    // @todo: delete char
                }

                if keycode == .UP {
                    if current_line == 0 {
                        break
                    }
                    current_line -= 1
                }

                if keycode == .DOWN {
                    if int(current_line + 1) == len(editor_lines) {
                        break
                    }
                    current_line += 1
                }
                break

            }
        }

        // Set background color of the window
        sdl.SetRenderDrawColor(renderer, 105, 105, 105, 0) // gray

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        draw_text(renderer, &atlas, editor_lines)

        sdl.RenderPresent(renderer)
    }
}

