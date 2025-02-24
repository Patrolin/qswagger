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
	SwaggerModelPropertyAllOf,
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
	value:    ^SwaggerModelProperty,
	nullable: bool,
}
SwaggerModelPropertyAllOf :: struct {
	items:    []SwaggerModelProperty,
	nullable: bool, // NOTE: SwaggerModelPropertyReference doesn't have nullable, so this is often used as a workaround
}
get_swagger_property :: proc(
	property: json.Object,
	module_prefix: string,
	_debug_name: []string,
	loc := #caller_location,
) -> SwaggerModelProperty {
	ref_key, has_ref := property["$ref"].(json.String)
	if has_ref {
		last_slash := strings.last_index(ref_key, "/")
		ref_name := strings.join({module_prefix, ref_key[last_slash + 1:]}, "")
		return SwaggerModelPropertyReference{ref_name}
	}
	all_of, has_all_of := property["allOf"].(json.Array)
	if has_all_of {
		items: [dynamic]SwaggerModelProperty
		for item in all_of {
			append(
				&items,
				get_swagger_property(item.(json.Object), module_prefix, _debug_name, loc = loc),
			)
		}
		nullable := json_get_boolean(property, "nullable")
		return SwaggerModelPropertyAllOf{items[:], nullable}
	}
	type, has_type := property["type"].(json.String)
	if has_type {
		if type == "array" {
			array_value := new(SwaggerModelProperty)
			array_value^ = get_swagger_property(
				property["items"].(json.Object),
				module_prefix,
				_debug_name,
				loc = loc,
			)
			nullable := json_get_boolean(property, "nullable")
			return SwaggerModelPropertyDynamicArray{array_value, nullable}
		} else {
			return SwaggerModelPropertyPrimitive {
				enum_ = json_to_string_array(property, "enum"),
				format = json_get_string(property, "format"),
				type = json_get_string(property, "type"),
				nullable = json_get_boolean(property, "nullable"),
			}
		}
	} else {
		fmt.printfln("property: %v", property)
		return SwaggerModelPropertyPrimitive {
			format = json_get_string(property, "format"),
			type = "any",
			nullable = json_get_boolean(property, "nullable"),
		}
	}
	sb := strings.builder_make_none()
	fmt.sbprint(&sb, "Unsupported type definition, key: '")
	for key, i in _debug_name {
		if i > 0 {fmt.sbprint(&sb, ".")}
		fmt.sbprint(&sb, key)
	}
	fmt.sbprintf(&sb, "', property: %v", property)
	assert(false, strings.to_string(sb), loc = loc)
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
				swagger_model[key] = get_swagger_property(property, module_prefix, {name, key})
			}
			acc_models[name] = swagger_model
			//fmt.printfln("object %v", name)
		}
	}
	return acc_models
}

// print model
print_typescript_model :: proc(name: string, model: SwaggerModel) -> string {
	sb := strings.builder_make_none()
	fmt.sbprint(&sb, AUTOGEN_HEADER)
	switch m in model {
	case SwaggerModelEnum:
		// export enum
		fmt.sbprintfln(&sb, "export enum %v {{", name)
		for value in m.values {
			if m.type == "string" {
				fmt.sbprintfln(&sb, "    %v = \"%v\",", value, value)
			} else {
				fmt.sbprintfln(&sb, "    %v", value)
			}
		}
		fmt.sbprintfln(&sb, "};")
	case SwaggerModelStruct:
		// imports
		acc_imports: map[string]void
		for key, property in m {
			add_imports(&acc_imports, property)
		}
		for import_name in sort_keys(acc_imports) {
			fmt.sbprintfln(&sb, "import {{%v}} from './%v'", import_name, import_name)
		}
		if len(acc_imports) > 0 {fmt.sbprintln(&sb)}
		// export type
		fmt.sbprintfln(&sb, "export type %v = {{", name)
		for key in sort_keys(m) {
			property := m[key]
			type_def := print_typescript_key_type(key, property)
			fmt.sbprintfln(&sb, "    %v;", type_def)
		}
		fmt.sbprintln(&sb, "};")
	}
	return strings.to_string(sb)
}
void :: struct {}
add_imports :: proc(acc: ^map[string]void, model: SwaggerModelProperty) {
	switch m in model {
	case SwaggerModelPropertyPrimitive:
	case SwaggerModelPropertyAllOf:
		for v in m.items {
			add_imports(acc, v)
		}
	case SwaggerModelPropertyDynamicArray:
		add_imports(acc, m.value^)
	case SwaggerModelPropertyReference:
		acc[m.name] = {}
	}
}

// print type
print_typescript_key_type :: proc(key: string, property: SwaggerModelProperty) -> string {
	sb := strings.builder_make_none()
	type, format, needs_brackets, nullable, is_array, is_array_nullable := get_typescript_type(
		property,
	)
	fmt.sbprintf(&sb, "%v", key)
	has_question_mark_colon := nullable && !is_array
	fmt.sbprintf(&sb, has_question_mark_colon ? "?: " : ": ")
	if needs_brackets && is_array {fmt.sbprint(&sb, "(")}
	fmt.sbprint(&sb, type)
	if is_array && nullable {fmt.sbprint(&sb, " | undefined")}
	if needs_brackets && is_array {fmt.sbprint(&sb, ")")}
	if is_array {fmt.sbprint(&sb, "[]")}
	if is_array_nullable {fmt.sbprint(&sb, " | undefined")}
	return strings.to_string(sb)
}
print_typescript_type :: proc(property: SwaggerModelProperty) -> string {
	sb := strings.builder_make_none()
	type, format, needs_brackets, nullable, is_array, is_array_nullable := get_typescript_type(
		property,
	)
	if needs_brackets && is_array {fmt.sbprint(&sb, "(")}
	fmt.sbprint(&sb, type)
	if is_array && nullable {fmt.sbprint(&sb, " | undefined")}
	if needs_brackets && is_array {fmt.sbprint(&sb, ")")}
	if is_array {fmt.sbprint(&sb, "[]")}
	if is_array_nullable || (!is_array && nullable) {fmt.sbprint(&sb, " | undefined")}
	return strings.to_string(sb)
}
get_typescript_type :: proc(
	struct_model: SwaggerModelProperty,
) -> (
	type, format: string,
	needs_brackets: bool,
	nullable, is_array, is_array_nullable: bool,
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
			case "any":
				{
					nullOrEmpty := m.nullable ? " | null" : ""
					type = strings.join(
						{"string | number | boolean | any[] | Record<string, any>", nullOrEmpty},
						"",
					)
				}
			case:
				fmt.assertf(false, "TODO: handle primitive types: %v", m)
			}
		}
		format = m.format
		nullable = m.nullable
	case SwaggerModelPropertyReference:
		type = m.name
	case SwaggerModelPropertyDynamicArray:
		type, format, needs_brackets, nullable, is_array, is_array_nullable = get_typescript_type(
			m.value^,
		)
		is_array = true
		is_array_nullable = m.nullable
	case SwaggerModelPropertyAllOf:
		item_strings: [dynamic]string
		for item in m.items {
			item_type, _, _, _, _, _ := get_typescript_type(item)
			append(&item_strings, item_type)
		}
		type = strings.join(item_strings[:], " | ")
		nullable = m.nullable
	}
	if nullable {needs_brackets = true}
	return
}
