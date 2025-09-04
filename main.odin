package main

import "core:fmt"
import sdl "vendor:sdl2"
//import ttf "vendor:sdl2/ttf"


Editor :: struct {
    lines: [dynamic]Line
}

Line :: struct {
    data: string
}

main :: proc() {
    window := sdl.CreateWindow(
        "slate_editor",
        sdl.WINDOWPOS_UNDEFINED,
        sdl.WINDOWPOS_UNDEFINED,
        500,
        500,
        {},
    )

    if window == nil {
        fmt.eprintln("Failed to create the window")
        return
    }

    defer sdl.DestroyWindow(window)

    // We must call SDL_CreateRenderer in order for draw calls to affect this window.
    renderer := sdl.CreateRenderer(window, -1, {.SOFTWARE});
    sdl.SetRenderDrawColor(renderer, 255, 0, 0, 255) // red

    // Clear the entire screen to our selected color.
    sdl.RenderClear(renderer)

    // Up until now everything was drawn behind the scenes.
    // This will show the new, red contents of the window.
    sdl.RenderPresent(renderer)

    // Load a font
    /*font := ttf.OpenFont("", 12)
    defer ttf.CloseFont(font)*/


    loop: for {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                sdl.Quit()
                //ttf.Quit()
                break loop
            }
        }
    }
}
