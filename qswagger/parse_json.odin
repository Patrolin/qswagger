package main
import "core:encoding/json"
import "core:fmt"
import "core:strings"

json_get_boolean :: proc(data: json.Object, key: string) -> bool {
	value := data[key]
	#partial switch v in value {
	case json.Boolean:
		{return v}
	case:
		{return false}
	}
}
json_get_string :: proc(data: json.Object, key: string) -> string {
	value := data[key]
	#partial switch v in value {
	case json.String:
		{return v}
	case:
		{return ""}
	}
}
json_get_object :: proc(data: json.Object, keys: ..string) -> (result: json.Object, ok: bool) {
	result = data
	for key in keys {
		result, ok = result[key].(json.Object)
		if !ok {return}
	}
	return
}
// to string
json_to_string_array :: proc(data: json.Object, key: string) -> []string {
	acc: [dynamic]string
	array, ok := data[key].(json.Array)
	if ok {
		for value in array {
			builder := strings.builder_make_none()
			#partial switch v in value {
			case json.String:
				{fmt.sbprintf(&builder, "'%v'", v)}
			case json.Integer:
				{fmt.sbprintf(&builder, "%v", v)}
			case json.Null:
				{fmt.sbprintf(&builder, "null")}
			case:
				fmt.assertf(false, "Unsupported enum value: %v", v)
			}
			append(&acc, strings.to_string(builder))
		}
	}
	return acc[:]
}
