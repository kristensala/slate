package main

import "core:strings"
import "core:fmt"

// @note(kristen): if the incoming word is for example proc() then I want to stop coloring right after c
// The int returned indicates exactly that
contains :: proc(array: []string, word: string) -> (bool, int) {
    for lexer_word in array {
        if strings.starts_with(word, lexer_word) {
            lexer_word_idx := len(lexer_word)
            if len(word) == len(lexer_word) {
                return true, lexer_word_idx
            }
            if len(word) > len(lexer_word) {
                next_rune : u8 = word[len(lexer_word):][0]

                // letters uppercase [65..90] and  lower_case [97..122]
                if (next_rune < 65 || next_rune > 90) && (next_rune < 97 || next_rune > 122) {
                    return true, lexer_word_idx
                }
            }
        }
    }
    return false, 0
}

append_line_at :: proc(editor_lines: ^[dynamic]Line, line: Line, index: i32) {
    result : [dynamic]Line
    first_part := editor_lines[0 : index]
    last_part := editor_lines[index:]

    append(&result, ..first_part[:])
    append(&result, line)
    append(&result, ..last_part[:])

    editor_lines^ = result
}

append_char_at :: proc(chars: ^[dynamic]Character_Info, char: Character_Info, index: i32) {
    result : [dynamic]Character_Info
    if len(chars) == 0 {
        append(&result, char)
        chars^ = result
        return
    }

    first_part := chars[:index]
    last_part := chars[index:]

    append(&result, ..first_part[:])
    append(&result, char)
    append(&result, ..last_part[:])

    chars^ = result
}

