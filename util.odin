package main

import "core:strings"
import "core:fmt"

// @note(kristen): if the incoming word is for example 'proc()' then I want to stop coloring right after c
// The int returned indicates exactly when to change the color back
// @todo: this is kind of a mess, fix
contains_where :: proc(array: []string, word: string) -> (found: bool, start_idx: int, end_idx: int) {
    for lexer_word in array {
        substring_idx := strings.index(word, lexer_word)
        if substring_idx != -1 {
            lexer_word_len := len(lexer_word)
            if len(word) == len(lexer_word) {
                return true, substring_idx, lexer_word_len + substring_idx
            }
            if len(word) > lexer_word_len {
                substring := word[substring_idx:]

                // @note: word ends with the lexer_word
                // so only prev char's are present
                if substring == lexer_word {
                    prev_rune := word[substring_idx - 1]
                    if (prev_rune < 65 || prev_rune > 90) && (prev_rune < 97 || prev_rune > 122) {
                        return true, substring_idx, lexer_word_len + substring_idx
                    }
                    return false, 0, 0
                }

                next_rune := substring[len(lexer_word)]
                if substring_idx > 0 {
                    prev_rune := word[substring_idx - 1]

                    if (prev_rune < 65 || prev_rune > 90) && (prev_rune < 97 || prev_rune > 122) {
                        if (next_rune < 65 || next_rune > 90) && (next_rune < 97 || next_rune > 122) {
                            return true, substring_idx, lexer_word_len + substring_idx
                        }
                    }
                    return false, 0, 0
                }


                // letters uppercase [65..90] and  lower_case [97..122]
                // @note(kristen): if the keyword is followed by a symbol (e.g. #@[]{}..)
                // then it's ok to color the word
                if (next_rune < 65 || next_rune > 90) && (next_rune < 97 || next_rune > 122) {
                    return true, substring_idx, lexer_word_len + substring_idx
                }
            }
        }
    }
    return false, 0, 0
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

append_char_at :: proc(chars: ^[dynamic]rune, char: rune, index: i32) {
    result : [dynamic]rune
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

split_on_multi :: proc(s: string, separators: []string) {
    result : [dynamic]string
    for separator in separators {
        if len(result) == 0 {
            data := strings.split(s, separator)
            append(&result, ..data[:])
            continue
        }

        foo : [dynamic]string
        for item in result {
            res := strings.split(item, separator)
            append(&foo, ..res[:])
        }

        clear(&result)
        append(&result, ..foo[:])
    }

    fmt.println(result)
}

