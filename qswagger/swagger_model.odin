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
	return strings.join({title, "_"}, "")
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
	enum_:    []string,
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
get_swagger_property :: proc(
	property: json.Object,
	module_prefix: string,
) -> SwaggerModelProperty {
	type, has_type := property["type"].(json.String)
	if has_type {
		if type == "array" {
			array_value := new(SwaggerModelProperty)
			array_value^ = get_swagger_property(property["items"].(json.Object), module_prefix)
			return SwaggerModelPropertyDynamicArray{array_value}
		} else {
			return SwaggerModelPropertyPrimitive {
				enum_ = json_to_string_array(property, "enum"),
				format = json_get_string(property, "format"),
				type = json_get_string(property, "type"),
				nullable = json_get_boolean(property, "nullable"),
			}
		}
	}
	ref_key, has_ref := property["$ref"].(json.String)
	if has_ref {
		last_slash := strings.last_index(ref_key, "/")
		ref_name := strings.join({module_prefix, ref_key[last_slash + 1:]}, "")
		return SwaggerModelPropertyReference{ref_name}
	}
	all_of, has_all_of := property["allOf"].(json.Array)
	if has_all_of && len(all_of) == 1 {
		return get_swagger_property(all_of[0].(json.Object), module_prefix)
	}
	fmt.assertf(false, "Unsupported type definition: %v", property)
	return SwaggerModelPropertyPrimitive{} // make compiler happy
}
parse_models :: proc(data: json.Object, module_prefix: string) -> ^map[string]SwaggerModel {
	acc_models := new(map[string]SwaggerModel)
	components := data["components"].(json.Object)
	for name, _value in components["schemas"].(json.Object) {
		name := strings.join({module_prefix, name}, "")
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
				swagger_model[key] = get_swagger_property(property, module_prefix)
			}
			acc_models[name] = swagger_model
			//fmt.printfln("object %v", name)
		}
	}
	return acc_models
}
print_typescript_model :: proc(name: string, model: SwaggerModel) -> string {
	builder := strings.builder_make_none()
	fmt.sbprint(&builder, AUTOGEN_HEADER)
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
		fmt.sbprintfln(&builder, "};")
	case SwaggerModelStruct:
		// imports
		acc_imports: map[string]bool
		for key, property in m {
			property := property
			for array, is_array := property.(SwaggerModelPropertyDynamicArray); is_array; {
				property = array.value^
				array, is_array = property.(SwaggerModelPropertyDynamicArray)
			}
			reference, is_reference := property.(SwaggerModelPropertyReference)
			if is_reference && !(reference.name in acc_imports) {
				acc_imports[reference.name] = true
			}
		}
		for import_name in sort_keys(acc_imports) {
			fmt.sbprintfln(&builder, "import {{%v}} from './%v'", import_name, import_name)
		}
		if len(acc_imports) > 0 {fmt.sbprintln(&builder)}
		// export type
		fmt.sbprintfln(&builder, "export type %v = {{", name)
		for key in sort_keys(m) {
			property := m[key]
			type_def := print_typescript_type_def(key, property)
			fmt.sbprintfln(&builder, "    %v;", type_def)
		}
		fmt.sbprintln(&builder, "};")
	}
	return strings.to_string(builder)
}
print_typescript_type_def :: proc(key: string, property: SwaggerModelProperty) -> string {
	builder := strings.builder_make_none()
	type, format, needs_brackets, nullable, is_array := get_typescript_type(property)
	fmt.sbprintf(&builder, "%v", key)
	has_question_mark_colon := nullable && !is_array
	fmt.sbprintf(&builder, has_question_mark_colon ? "?: " : ": ")
	if needs_brackets && is_array {fmt.sbprint(&builder, "(")}
	fmt.sbprint(&builder, type)
	if nullable && is_array {fmt.sbprint(&builder, "| undefined")}
	if needs_brackets && is_array {fmt.sbprint(&builder, ")")}
	if is_array {fmt.sbprint(&builder, "[]")}
	return strings.to_string(builder)
}
get_typescript_type :: proc(
	struct_model: SwaggerModelProperty,
) -> (
	type, format: string,
	needs_brackets: bool,
	nullable, is_array: bool,
) {
	switch m in struct_model {
	case SwaggerModelPropertyPrimitive:
		if len(m.enum_) > 0 {
			type = strings.join(m.enum_, " | ")
			needs_brackets = true
		} else {
			switch m.type {
			case "boolean":
				type = "boolean"
			case "integer", "number":
				type = "number"
			case "string":
				type = m.format == "binary" ? "Blob" : "string"
			case:
				fmt.assertf(false, "TODO: handle primitive types: %v", m)
			}
		}
		format = m.format
		nullable = m.nullable
	case SwaggerModelPropertyReference:
		type = m.name
	case SwaggerModelPropertyDynamicArray:
		type, format, needs_brackets, nullable, is_array = get_typescript_type(m.value^)
		is_array = true
	}
	if nullable {needs_brackets = true}
	return
}
