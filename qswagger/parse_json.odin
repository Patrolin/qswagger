package main
import "core:encoding/json"

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
