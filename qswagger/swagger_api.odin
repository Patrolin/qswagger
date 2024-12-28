package main
import "core:encoding/json"
import "core:fmt"

// api
SwaggerApi :: [dynamic]SwaggerApiItem
SwaggerApiItem :: struct {
	path: string,
	type: SwaggerRequestType,
}
SwaggerRequestType :: enum {
	Get,
	Post,
	Delete,
	Patch,
}
add_api_item :: proc(
	acc_apis: ^map[string]SwaggerApi,
	type: SwaggerRequestType,
	path: string,
	value: json.Object,
) {
	groups := value["tags"].(json.Array)
	group := groups[0].(json.String)
	if !(group in acc_apis) {
		acc_apis[group] = new([dynamic]SwaggerApiItem)^
	}
	append(&acc_apis[group], SwaggerApiItem{path, type})
	//fmt.printfln("add_api_item: %v, %v", type, path)
}
parse_apis :: proc(data: json.Object) -> ^map[string]SwaggerApi {
	acc_apis := new(map[string]SwaggerApi)
	for path, _value in data["paths"].(json.Object) {
		value := _value.(json.Object)
		if "get" in value {
			add_api_item(acc_apis, SwaggerRequestType.Get, path, value["get"].(json.Object))
		}
		if "post" in value {
			add_api_item(acc_apis, SwaggerRequestType.Post, path, value["post"].(json.Object))
		}
		if "delete" in value {
			add_api_item(acc_apis, SwaggerRequestType.Delete, path, value["delete"].(json.Object))
		}
		if "patch" in value {
			add_api_item(acc_apis, SwaggerRequestType.Patch, path, value["patch"].(json.Object))
		}
	}
	return acc_apis
}
