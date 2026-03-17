package main
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:unicode"

sort_keys :: proc(items: map[$K]$V) -> []K {
	keys, _ := slice.map_keys(items)
	slice.sort(keys)
	return keys
}
kebab_case_to_upper_camel_case :: proc(s: string) -> string {
	builder := strings.builder_make_none()
	next_is_uppercase := true
	for c in s {
		if c == '-' {
			next_is_uppercase = true
		} else {
			if next_is_uppercase {
				fmt.sbprint(&builder, unicode.to_upper(c))
			} else {
				fmt.sbprint(&builder, c)
			}
			next_is_uppercase = false
		}
	}
	return strings.to_string(builder)
}
