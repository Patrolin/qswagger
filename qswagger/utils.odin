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
kebab_case_to_camel_case :: proc(s: string, start_upper_case: bool) -> string {
	builder := strings.builder_make_none()
	was_dash := start_upper_case
	for c in s {
		if c == '-' {
			was_dash = true
			continue
		} else {
			if was_dash {fmt.sbprint(&builder, unicode.to_upper(c))}
			else {fmt.sbprint(&builder, c)}
		}
		was_dash = false
	}
	return strings.to_string(builder)
}
kebab_case_to_snake_case :: proc(s: string) -> string {
	builder := strings.builder_make_none()
	for c in s {
		if c == '-' {
			fmt.sbprint(&builder, '_')
		} else {
			fmt.sbprint(&builder, c)
		}
	}
	return strings.to_string(builder)
}
