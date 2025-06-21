package main
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// api
SwaggerApi :: [dynamic]SwaggerRequest
SwaggerRequest :: struct {
	path:              string,
	type:              SwaggerRequestType,
	query_params:      [dynamic]SwaggerRequestParam,
	path_params:       [dynamic]SwaggerRequestParam,
	request_body_type: SwaggerRequestBody,
	response_type:     SwaggerResponseBody,
}
SwaggerRequestType :: enum {
	Delete,
	Get,
	Patch,
	Post,
}
SwaggerRequestParam :: struct {
	name:     string,
	property: SwaggerModelProperty,
}
SwaggerRequestParamType :: enum {
	Path,
	Query,
}
SwaggerRequestBody :: union {
	SwaggerRequestNoBody,
	SwaggerRequestJsonBody,
	SwaggerRequestMultipartBody,
}
SwaggerResponseBody :: union {
	SwaggerRequestNoBody,
	SwaggerRequestJsonBody,
}
SwaggerRequestNoBody :: struct {
}
SwaggerRequestJsonBody :: struct {
	property: SwaggerModelProperty,
}
SwaggerRequestMultipartBody :: struct {
	model: SwaggerModelStruct,
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
	acc_query_params: [dynamic]SwaggerRequestParam
	acc_path_params: [dynamic]SwaggerRequestParam
	params_data, params_data_ok := value["parameters"].(json.Array)
	if params_data_ok {
		for param in params_data {
			param := param.(json.Object)
			param_name := param["name"].(json.String)
			property := get_swagger_property(param["schema"].(json.Object), module_prefix, {})
			param_type: SwaggerRequestParamType
			param_type_data := param["in"].(json.String)
			switch param_type_data {
			case "query":
				append(&acc_query_params, SwaggerRequestParam{param_name, property})
			case "path":
				append(&acc_path_params, SwaggerRequestParam{param_name, property})
			case:
				fmt.assertf(false, "Unknown parameter type: %v", param_type_data)
			}
		}
	}
	// request body
	request_body_type: SwaggerRequestBody = SwaggerRequestNoBody{}
	request_body_json_data, request_body_is_json := json_get_object(
		value,
		"requestBody",
		"content",
		"application/json",
		"schema",
	)
	if request_body_is_json {
		request_body_type = SwaggerRequestJsonBody {
			get_swagger_property(request_body_json_data, module_prefix, {"<json_request_type>"}),
		}
	}
	request_body_multipart_data, request_body_is_multipart := json_get_object(
		value,
		"requestBody",
		"content",
		"multipart/form-data",
		"schema",
	)
	if request_body_is_multipart {
		model: SwaggerModelStruct
		for key, _property in request_body_multipart_data["properties"].(json.Object) {
			property := _property.(json.Object)
			model[key] = get_swagger_property(
				property,
				module_prefix,
				{"<multipart_request_type>"},
			)
		}
		request_body_type = SwaggerRequestMultipartBody{model}
	}
	// response type
	response_data, response_data_ok := json_get_object(
		value,
		"responses",
		"200",
		"content",
		"application/json",
		"schema",
	)
	response_type: SwaggerResponseBody = SwaggerRequestNoBody{}
	if response_data_ok {
		response_type = SwaggerRequestJsonBody {
			get_swagger_property(response_data, module_prefix, {"<json_response_type>"}),
		}
	}
	// append
	append(
		&acc_apis[group],
		SwaggerRequest {
			path,
			type,
			acc_query_params,
			acc_path_params,
			request_body_type,
			response_type,
		},
	)
}
parse_apis :: proc(data: json.Object, module_prefix: string) -> ^map[string]SwaggerApi {
	acc_apis := new(map[string]SwaggerApi)
	paths := data["paths"].(json.Object)
	paths_v := (map[string]json.Value)(paths)
	for path in sort_keys(paths_v) {
		value := paths_v[path].(json.Object)
		if "delete" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Delete,
				path,
				value["delete"].(json.Object),
				module_prefix,
			)
		}
		if "get" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Get,
				path,
				value["get"].(json.Object),
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
		if "post" in value {
			add_api_item(
				acc_apis,
				SwaggerRequestType.Post,
				path,
				value["post"].(json.Object),
				module_prefix,
			)
		}
	}
	return acc_apis
}
get_request_type_name :: proc(request_type: SwaggerRequestType) -> string {
	switch request_type {
	case .Delete:
		return "DELETE"
	case .Get:
		return "GET"
	case .Patch:
		return "PATCH"
	case .Post:
		return "POST"
	}
	return "GET"
}
get_request_type_name_capitalized :: proc(request_type: SwaggerRequestType) -> string {
	switch request_type {
	case .Delete:
		return "Delete"
	case .Get:
		return "Get"
	case .Patch:
		return "Patch"
	case .Post:
		return "Post"
	}
	return "Get"
}
get_request_name :: proc(request: SwaggerRequest) -> string {
	path := request.path
	start := strings.index(path[1:], "/") + 1
	start += strings.index(path[start:], "/") + 1
	request_name, was_allocation := path[start:], false
	request_name, was_allocation = strings.replace_all(request_name, "/{", "_")
	request_name, was_allocation = strings.replace_all(request_name, "/", "")
	request_name, was_allocation = strings.replace_all(request_name, "}", "_")
	request_name = strings.join(
		{request_name, get_request_type_name_capitalized(request.type)},
		"_",
	)
	request_name, was_allocation = strings.replace_all(request_name, "__", "_")
	return strings.trim_suffix(request_name, "_")
}
get_request_body_type :: proc(request: SwaggerRequest, request_name: string) -> string {
	switch v in request.request_body_type {
	case SwaggerRequestNoBody:
		return ""
	case SwaggerRequestJsonBody:
		return print_typescript_type(v.property)
	case SwaggerRequestMultipartBody:
		return strings.join({request_name, "_MultipartBody"}, "")
	}
	return ""
}
print_typescript_api :: proc(group: string, api: SwaggerApi) -> string {
	builder := strings.builder_make_none()
	// print header
	fmt.sbprint(&builder, AUTOGEN_HEADER)
	// add imports
	acc_imports: map[string]void
	for request in api {
		request_body_json, request_body_is_json := request.request_body_type.(SwaggerRequestJsonBody)
		if request_body_is_json {
			add_imports(&acc_imports, request_body_json.property)
		}
		response_body_json, response_body_is_json := request.response_type.(SwaggerRequestJsonBody)
		if response_body_is_json {
			add_imports(&acc_imports, response_body_json.property)
		}
	}
	// print imports
	for key in sort_keys(acc_imports) {
		fmt.sbprintfln(&builder, "import {{%v}} from '../models/%v'", key, key)
	}
	fmt.sbprintln(&builder, "import * as runtime from '../runtime'")
	// print date import
	need_date_import := false
	for request in api {
		for param in request.path_params {
			if need_date_fmt(param) {need_date_import = true}
		}
		for param in request.query_params {
			if need_date_fmt(param) {need_date_import = true}
		}
	}
	if need_date_import && len(global_args.date_import) > 0 {
		fmt.sbprintln(&builder, global_args.date_import)
	}
	fmt.sbprintln(&builder)
	// print apis
	for request in api {
		request_name := get_request_name(request)
		if len(request.path_params) > 0 {
			type_name := strings.join({request_name, "_PathParams"}, "")
			fmt.sbprintfln(&builder, "export type %v = {{", type_name)
			for param in request.path_params {
				type_def := print_typescript_key_type(param.name, param.property)
				fmt.sbprintfln(&builder, "    %v;", type_def)
			}
			fmt.sbprintln(&builder, "};")
		}
		if len(request.query_params) > 0 {
			type_name := strings.join({request_name, "_QueryParams"}, "")
			fmt.sbprintfln(&builder, "export type %v = {{", type_name)
			for param in request.query_params {
				type_def := print_typescript_key_type(param.name, param.property)
				fmt.sbprintfln(&builder, "    %v;", type_def)
			}
			fmt.sbprintln(&builder, "};")
		}
		if v, body_is_multipart := request.request_body_type.(SwaggerRequestMultipartBody);
		   body_is_multipart {
			type_name := get_request_body_type(request, request_name)
			m := v.model
			fmt.sbprintfln(&builder, "export type %v = {{", type_name)
			for key in sort_keys(m) {
				property := m[key]
				type_def := print_typescript_key_type(key, property)
				fmt.sbprintfln(&builder, "    %v;", type_def)
			}
			fmt.sbprintln(&builder, "};")
		}
	}
	fmt.sbprintfln(&builder, "export class %vApi extends runtime.BaseAPI {{", group)
	slice.sort_by(api[:], proc(a, b: SwaggerRequest) -> bool {
		name_1 := get_request_name(a)
		name_2 := get_request_name(b)
		return name_1 < name_2
	})
	for request in api {
		request_name := get_request_name(request)
		args: [dynamic]string
		arg_names: [dynamic]string
		if len(request.path_params) > 0 {
			params_type := strings.join({request_name, "_PathParams"}, "")
			append(&args, strings.join({"path_params: ", params_type}, ""))
			append(&arg_names, "path_params")
		}
		if len(request.query_params) > 0 {
			params_type := strings.join({request_name, "_QueryParams"}, "")
			append(&args, strings.join({"query: ", params_type}, ""))
			append(&arg_names, "query")
		}
		request_body_type := get_request_body_type(request, request_name)
		if len(request_body_type) > 0 {
			append(&args, strings.join({"body: ", request_body_type}, ""))
			append(&arg_names, "body")
		}
		append(&args, "overrides: RequestInit = {}")
		append(&arg_names, "overrides")
		args_string := strings.join(args[:], ", ")
		response_type_string := "void"
		response_type_json, response_type_is_json := request.response_type.(SwaggerRequestJsonBody)
		if response_type_is_json {
			response_type_string = print_typescript_type(response_type_json.property)
		}
		// raw request
		fmt.sbprintfln(
			&builder,
			"    async %v_Raw(%v): Promise<Response> {{",
			request_name,
			args_string,
		)
		fmt.sbprintfln(&builder, "        let path = '%v';", request.path)
		for param in request.path_params {
			formatted_param := format_typescript_param(param, "path_params.")
			fmt.sbprintfln(
				&builder,
				"        path = path.replace('{{%v}}', encodeURIComponent(%v));",
				param.name,
				formatted_param,
			)
		}
		fmt.sbprint(&builder, AUTH_PREAMBLE)
		_, request_body_type_is_json := request.request_body_type.(SwaggerRequestJsonBody)
		if request_body_type_is_json {
			fmt.sbprintln(&builder, "        headers['Content-Type'] = 'application/json';")
		}
		if v, body_is_multipart := request.request_body_type.(SwaggerRequestMultipartBody);
		   body_is_multipart {
			fmt.sbprintln(&builder, "        const formData = new FormData();")
			for k in v.model {
				fmt.sbprintfln(&builder, "        formData.append('%v', body.%v);", k, k)
			}
		}
		fmt.sbprintln(&builder, "        return await this.request({")
		fmt.sbprintfln(&builder, "            method: '%v',", get_request_type_name(request.type))
		fmt.sbprintln(&builder, "            path,")
		fmt.sbprintln(&builder, "            headers,")
		switch v in request.request_body_type {
		case SwaggerRequestNoBody:
			{}
		case SwaggerRequestJsonBody:
			fmt.sbprintln(&builder, "            body,")
		case SwaggerRequestMultipartBody:
			fmt.sbprintln(&builder, "            body: formData,")
		}
		if len(request.query_params) > 0 {
			fmt.sbprintln(&builder, "            query,")
		}
		fmt.sbprintln(&builder, "        }, overrides);")
		fmt.sbprintln(&builder, "    }")
		// typed request
		fmt.sbprintfln(
			&builder,
			"    async %v(%v): Promise<%v> {{",
			request_name,
			args_string,
			response_type_string,
		)
		fmt.sbprintfln(
			&builder,
			"        const response = await this.%v_Raw(%v);",
			request_name,
			strings.join(arg_names[:], ", "),
		)
		if response_type_string != "void" {
			fmt.sbprintfln(
				&builder,
				"        return await new runtime.JSONApiResponse(response, v => v as %v).value();",
				response_type_string,
			)
		} else {
			fmt.sbprintfln(
				&builder,
				"        return await new runtime.VoidApiResponse(response).value();",
			)
		}
		fmt.sbprintln(&builder, "    }")
	}
	fmt.sbprintln(&builder, "}")
	return strings.to_string(builder)
}
need_date_fmt :: proc(param: SwaggerRequestParam) -> bool {
	primitive, is_primitive := param.property.(SwaggerModelPropertyPrimitive)
	return global_args.gen_dates && is_primitive && primitive.format == "date-time"
}
format_typescript_param :: proc(param: SwaggerRequestParam, prefix: string) -> string {
	sb := strings.builder_make_none()
	prefixed_param := strings.join({prefix, param.name}, "")
	if need_date_fmt(param) {
		fmt.sbprintf(&sb, global_args.date_fmt, prefixed_param)
	} else {
		fmt.sbprintf(&sb, "String(%v)", prefixed_param)
	}
	return strings.to_string(sb)
}
