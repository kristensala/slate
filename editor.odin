package main

import sdl "vendor:sdl2"

@(private) EDITOR_FONT_SIZE :: 30

Editor :: struct {
    lines: [dynamic]Line,
    cursor: Cursor,
    rect: sdl.Rect
}

Line :: struct {
    data: string,
    rect: sdl.Rect
}

Cursor :: struct {
    pos: [2]int, // row and "col"
    rect: sdl.Rect
}

// read file line by line
read_file :: proc() {
} 

