package main
import "core:slice"

sort_keys :: proc(items: map[$K]$V) -> []K {
	keys, _ := slice.map_keys(items)
	slice.sort(keys)
	return keys
}
