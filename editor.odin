package main

Editor :: struct {
    lines: [dynamic]Line,
    cursor: Cursor
}

Line :: struct {
    data: string
}

Cursor :: struct {
    pos: [2]int // row and "col"
}

// read file line by line
read_file :: proc() {
} 

