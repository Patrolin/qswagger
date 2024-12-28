package main
import "core:encoding/json"
import "core:fmt"
import "core:strings"
// title
get_swagger_title :: proc(data: json.Object) -> string {
	info := data["info"].(json.Object)
	title := info["title"].(json.String)
	if strings.ends_with(title, " Module") || strings.ends_with(title, " module") {
		title = title[:len(title) - 7]
	}
	return title
}
// model
SwaggerModel :: union {
	SwaggerModelEnum,
	SwaggerModelStruct,
}
SwaggerModelEnum :: struct {
	type:   string,
	values: json.Array,
}
SwaggerModelStruct :: map[string]SwaggerModelProperty
SwaggerModelProperty :: union {
	SwaggerModelPropertyPrimitive,
	SwaggerModelPropertyReference,
	SwaggerModelPropertyDynamicArray,
}
SwaggerModelPropertyPrimitive :: struct {
	type:     string,
	format:   string,
	nullable: bool,
}
SwaggerModelPropertyReference :: struct {
	name: string,
}
SwaggerModelPropertyDynamicArray :: struct {
	value: ^SwaggerModelProperty,
}
get_swagger_property :: proc(property: json.Object) -> SwaggerModelProperty {
	ref_key, is_ref := property["$ref"].(json.String)
	if is_ref {
		last_slash := strings.last_index(ref_key, "/")
		return SwaggerModelPropertyReference{ref_key[last_slash + 1:]}
	}
	type := property["type"].(json.String)
	if type == "array" {
		array_value := new(SwaggerModelProperty)
		array_value^ = get_swagger_property(property["items"].(json.Object))
		return SwaggerModelPropertyDynamicArray{array_value}
	} else {
		return SwaggerModelPropertyPrimitive {
			format = json_get_string(property, "format"),
			type = json_get_string(property, "type"),
			nullable = json_get_boolean(property, "nullable"),
		}
	}
}
parse_models :: proc(data: json.Object) -> ^map[string]SwaggerModel {
	acc_models := new(map[string]SwaggerModel)
	components := data["components"].(json.Object)
	for name, _value in components["schemas"].(json.Object) {
		value := _value.(json.Object)
		type := value["type"].(json.String)
		if enum_values, is_enum := value["enum"].(json.Array); is_enum {
			acc_models[name] = SwaggerModelEnum{type, enum_values}
			//fmt.printfln("enum %v, %v", name, enum_values)
		} else {
			type = value["type"].(json.String)
			fmt.assertf(type == "object", "Uknown model type: %v %v", type, name)
			swagger_model: SwaggerModelStruct
			for key, _property in value["properties"].(json.Object) {
				property := _property.(json.Object)
				swagger_model[key] = get_swagger_property(property)
			}
			acc_models[name] = swagger_model
			//fmt.printfln("object %v", name)
		}
	}
	return acc_models
}
print_typescript_model :: proc(name: string, model: SwaggerModel) -> string {
	builder := strings.builder_make_none()
	switch m in model {
	case SwaggerModelEnum:
		// export enum
		fmt.sbprintfln(&builder, "export enum %v {{", name)
		for value in m.values {
			if m.type == "string" {
				fmt.sbprintfln(&builder, "    %v = \"%v\",", value, value)
			} else {
				fmt.sbprintfln(&builder, "    %v", value)
			}
		}
		fmt.sbprintfln(&builder, "}")
	case SwaggerModelStruct:
		// imports
		acc_imports: map[string]bool
		sorted_keys := sort_keys(m)
		for key in sorted_keys {
			property := m[key]
			reference, is_reference := property.(SwaggerModelPropertyReference)
			if is_reference && !(reference.name in acc_imports) {
				acc_imports[reference.name] = true
			}
		}
		for import_name in sort_keys(acc_imports) {
			fmt.sbprintfln(&builder, "import {{%v}} from \"./%v\"", import_name, import_name)
		}
		if len(acc_imports) > 0 {fmt.sbprintln(&builder)}
		// export type
		fmt.sbprintfln(&builder, "export type %v = {{", name)
		for key in sorted_keys {
			property := m[key]
			type, format, nullable, is_array := get_typescript_type(property)
			fmt.sbprintf(&builder, "    %v", key)
			has_question_mark_colon := nullable && !is_array
			fmt.sbprintf(&builder, has_question_mark_colon ? "?: " : ": ")
			has_or_undefined := nullable && is_array
			if has_or_undefined {fmt.sbprint(&builder, "(")}
			fmt.sbprint(&builder, type)
			if has_or_undefined {fmt.sbprint(&builder, "| undefined)")}
			if is_array {fmt.sbprint(&builder, "[]")}
			fmt.sbprintln(&builder, ";")
		}
		fmt.sbprintln(&builder, "};")
	}
	return strings.to_string(builder)
}
get_typescript_type :: proc(
	struct_model: SwaggerModelProperty,
) -> (
	type, format: string,
	nullable, is_array: bool,
) {
	switch m in struct_model {
	case SwaggerModelPropertyPrimitive:
		switch m.type {
		case "boolean":
			type = "boolean"
		case "integer", "number":
			type = "number"
		case "string":
			type = "string"
		case:
			fmt.assertf(false, "TODO: handle primitive types: %v", m)
		}
		format = m.format
		nullable = m.nullable
	case SwaggerModelPropertyReference:
		type = m.name
	case SwaggerModelPropertyDynamicArray:
		type, format, nullable, is_array = get_typescript_type(m.value^)
		is_array = true
	}
	return
}
