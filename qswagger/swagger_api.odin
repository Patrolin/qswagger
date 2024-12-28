package main
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// api
SwaggerApi :: [dynamic]SwaggerRequest
SwaggerRequest :: struct {
	path:              string,
	type:              SwaggerRequestType,
	params:            [dynamic]SwaggerRequestParam,
	request_body_type: string,
	response_type:     string,
}
SwaggerRequestType :: enum {
	Get,
	Post,
	Delete,
	Patch,
}
SwaggerRequestParam :: struct {
	name:     string,
	type:     SwaggerRequestParamType,
	property: SwaggerModelProperty,
}
SwaggerRequestParamType :: enum {
	Path,
	Query,
}
add_api_item :: proc(
	acc_apis: ^map[string]SwaggerApi,
	type: SwaggerRequestType,
	path: string,
	value: json.Object,
	module_prefix: string,
) {
	groups := value["tags"].(json.Array)
	group := strings.join({module_prefix, groups[0].(json.String)}, "")
	if !(group in acc_apis) {
		acc_apis[group] = new([dynamic]SwaggerRequest)^
	}
	// params
	acc_params: [dynamic]SwaggerRequestParam
	params_data, params_data_ok := value["parameters"].(json.Array)
	if params_data_ok {
		for param in params_data {
			param := param.(json.Object)
			param_name := param["name"].(json.String)
			param_type: SwaggerRequestParamType
			param_type_data := param["in"].(json.String)
			switch param_type_data {
			case "path":
				param_type = .Path
			case "query":
				param_type = .Query
			case:
				fmt.assertf(false, "Unknown parameter type: %v", param_type_data)
			}
			property := get_swagger_property(param["schema"].(json.Object), module_prefix)
			append(&acc_params, SwaggerRequestParam{param_name, param_type, property})
		}
	}
	// request body
	request_body_data, request_body_data_ok := json_get_object(
		value,
		"requestBody",
		"content",
		"application/json",
		"schema",
	)
	request_body :=
		request_body_data_ok ? get_swagger_property(request_body_data, module_prefix).(SwaggerModelPropertyReference).name : ""
	// response type
	response_data, response_data_ok := json_get_object(
		value,
		"responses",
		"200",
		"content",
		"application/json",
		"schema",
	)
	response_type :=
		response_data_ok ? get_swagger_property(response_data, module_prefix).(SwaggerModelPropertyReference).name : ""
	// append
	append(&acc_apis[group], SwaggerRequest{path, type, acc_params, request_body, response_type})
}
parse_apis :: proc(data: json.Object, module_prefix: string) -> ^map[string]SwaggerApi {
	acc_apis := new(map[string]SwaggerApi)
	for path, _value in data["paths"].(json.Object) {
		value := _value.(json.Object)
		if "get" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Get,
				path,
				value["get"].(json.Object),
				module_prefix,
			)
		}
		if "post" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Post,
				path,
				value["post"].(json.Object),
				module_prefix,
			)
		}
		if "delete" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Delete,
				path,
				value["delete"].(json.Object),
				module_prefix,
			)
		}
		if "patch" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Patch,
				path,
				value["patch"].(json.Object),
				module_prefix,
			)
		}
	}
	return acc_apis
}
get_request_type_name :: proc(request_type: SwaggerRequestType) -> string {
	switch request_type {
	case .Get:
		return "GET"
	case .Post:
		return "POST"
	case .Delete:
		return "DELETE"
	case .Patch:
		return "PATCH"
	}
	return "GET"
}
get_request_type_name_capitalized :: proc(request_type: SwaggerRequestType) -> string {
	switch request_type {
	case .Get:
		return "Get"
	case .Post:
		return "Post"
	case .Delete:
		return "Delete"
	case .Patch:
		return "Patch"
	}
	return "Get"
}
get_request_name :: proc(group: string, request: SwaggerRequest) -> string {
	path := request.path
	start := strings.index(path[1:], "/") + 1
	start += strings.index(path[start:], "/") + 1
	request_name, was_allocation := path[start:], false
	request_name, was_allocation = strings.replace_all(request_name, "/{", "_")
	request_name, was_allocation = strings.replace_all(request_name, "/", "")
	request_name, was_allocation = strings.replace_all(request_name, "}", "")
	return strings.join({request_name, get_request_type_name_capitalized(request.type)}, "_")
}
print_typescript_api :: proc(group: string, api: SwaggerApi) -> string {
	builder := strings.builder_make_none()
	sbprint_header(&builder)
	acc_imports: map[string]bool
	for request in api {
		if len(request.request_body_type) > 0 {acc_imports[request.request_body_type] = true}
		if len(request.response_type) > 0 {acc_imports[request.response_type] = true}
	}
	for key in sort_keys(acc_imports) {
		fmt.sbprintfln(&builder, "import {{%v}} from '../model/%v'", key, key)
	}
	fmt.sbprintln(&builder, "import {BaseApi} from '../runtime'")
	fmt.sbprintln(&builder)
	for request in api {
		request_name := get_request_name(group, request)
		if len(request.params) > 0 {
			params_type := strings.join({request_name, "_Params"}, "")
			fmt.sbprintfln(&builder, "export type %v = {{", params_type)
			for param in request.params {
				type_def := print_typescript_type_def(param.name, param.property)
				fmt.sbprintfln(&builder, "    %v;", type_def)
			}
			fmt.sbprintln(&builder, "};")
		}
	}
	fmt.sbprintfln(&builder, "export class %vApi extends BaseApi {{", group)
	for request in api {
		request_name := get_request_name(group, request)
		args: [dynamic]string
		if len(request.params) > 0 {
			params_type := strings.join({request_name, "_Params"}, "")
			append(&args, strings.join({"params: ", params_type}, ""))
		}
		if len(request.request_body_type) > 0 {
			append(&args, strings.join({"body: ", request.request_body_type}, ""))
		}
		append(&args, "overrides: RequestInit")
		args_string := strings.join(args[:], ", ")
		response_type_string := ""
		if len(request.response_type) > 0 {
			response_type_string = strings.join({": Promise<", request.response_type, ">"}, "")
		}
		fmt.sbprintfln(
			&builder,
			"    async %v_Raw(%v)%v {{",
			request_name,
			args_string,
			response_type_string,
		)
		fmt.sbprintfln(&builder, "        let path = '%v';", request.path)
		for param in request.params {
			if param.type == .Path {
				fmt.sbprintfln(
					&builder,
					"        path = path.replace('{{%v}}', encodeURIComponent(String(params.%v)));",
					param.name,
					param.name,
				)
			}
		}
		fmt.sbprintln(&builder, "        return await this.request({")
		fmt.sbprintfln(&builder, "            method: '%v',", get_request_type_name(request.type))
		fmt.sbprintln(&builder, "            path,")
		fmt.sbprintln(&builder, "            overrides,")
		fmt.sbprintln(&builder, "        })")
		fmt.sbprintln(&builder, "    }")
	}
	fmt.sbprintln(&builder, "}")
	return strings.to_string(builder)
}
