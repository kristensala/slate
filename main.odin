package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

main :: proc() {
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
    defer sdl.DestroyRenderer(renderer)

    if ttf.Init() != 0 {
        fmt.eprintln("Faild to initialize ttf library", ttf.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", EDITOR_FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", ttf.GetError())
        return
    }

    defer ttf.CloseFont(font)

    atlas: Atlas
    build_atlas(renderer, font, &atlas)

    // render example text
    text_color: sdl.Color = {255, 255, 255, 255}
    surface := ttf.RenderUTF8_Blended(font, "slate_editor", text_color)
    if surface == nil {
        fmt.eprintln("Failed to create a surface: ", ttf.GetError())
        return
    }
    defer sdl.FreeSurface(surface)

    texture := sdl.CreateTextureFromSurface(renderer, surface)
    defer sdl.DestroyTexture(texture)

    if texture == nil {
        fmt.eprintln("Failed to create a texture: ", sdl.GetError())
        return
    }

    text_width, text_height : i32 = 100, 100
    sdl.QueryTexture(texture, nil, nil, &text_width, &text_height)
    text_destination : sdl.Rect = {10, 10, text_width, text_height}

    // Main "game" loop
    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
                //free(atlas)
                break loop
            case .KEYDOWN:
                fmt.print(event.key.keysym.sym)
                break
            }
        }

        // Set background color of the window
        sdl.SetRenderDrawColor(renderer, 105, 105, 105, 0) // gray

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        sdl.RenderCopy(renderer, texture, nil, &text_destination)

        sdl.RenderPresent(renderer)
    }
}

