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
	builder := strings.builder_make_none()
	fmt.sbprint(&builder, "Unsupported type definition, key: '")
	for key, i in _debug_name {
		if i > 0 {fmt.sbprint(&builder, ".")}
		fmt.sbprint(&builder, key)
	}
	fmt.sbprintf(&builder, "', property: %v", property)
	assert(false, strings.to_string(builder), loc = loc)
	return SwaggerModelPropertyPrimitive{} // make compiler happy
}
parse_models :: proc(data: json.Object, module_prefix: string) -> ^map[string]SwaggerModel {
	acc_models := new(map[string]SwaggerModel)
	components := data["components"].(json.Object)
	for name_key, _value in components["schemas"].(json.Object) {
		name := strings.join({module_prefix, name_key}, "")
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
	builder := strings.builder_make_none()
	// print header
	fmt.sbprint(&builder, AUTOGEN_HEADER)
	// print model
	need_date_import := false
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
		// export date mapping
		if global_args.gen_dates {
			fmt.sbprintfln(&builder, "export function map_{0}(json: any): {0} {{", name)
			fmt.sbprintln(&builder, "  return json;")
			fmt.sbprintln(&builder, "}")
		}
	case SwaggerModelStruct:
		// add imports
		acc_imports: map[string]ImportType
		for _, property in m {
			add_imports(&acc_imports, property, .Request, &need_date_import)
		}
		delete_key(&acc_imports, name)
		// print imports
		for import_name in sort_keys(acc_imports) {
			if global_args.gen_dates {
				fmt.sbprintfln(&builder, "import {{{0}, map_{0}}} from './{0}';", import_name)
			} else {
				fmt.sbprintfln(&builder, "import {{{0}}} from './{0}';", import_name)
			}
		}
		if need_date_import {
			if len(global_args.date_import) > 0 {fmt.sbprintln(&builder, global_args.date_import)}
			if len(global_args.date_out_import) > 0 {
				fmt.sbprintln(&builder, global_args.date_out_import)
			}
		}
		if len(acc_imports) > 0 || need_date_import {fmt.sbprintln(&builder)}
		// export type
		fmt.sbprintfln(&builder, "export type %v = {{", name)
		sorted_keys := sort_keys(m)
		for key in sorted_keys {
			property := m[key]
			type_def := print_typescript_key_type(key, property)
			fmt.sbprintfln(&builder, "    %v;", type_def)
		}
		fmt.sbprintln(&builder, "};")
		// export date mapping
		if global_args.gen_dates {
			fmt.sbprintfln(&builder, "export function map_{0}(json: any): {0} {{", name)
			if !need_date_import {
				fmt.sbprintln(&builder, "  return json;")
			} else {
				fmt.sbprintln(&builder, "  return {")
				fmt.sbprintln(&builder, "    ...json,")
				for key in sorted_keys {
					value := fmt.tprintf("json.%v", key)
					property := m[key]
					mapped_value, needs_mapping := print_mapped_type(value, property, "any")
					if needs_mapping {
						fmt.sbprintfln(&builder, "    %v: %v,", key, mapped_value)
					}
				}
				fmt.sbprintln(&builder, "  };")
			}
			fmt.sbprintln(&builder, "}")
		}
	}
	return strings.to_string(builder)
}

// imports
ImportType :: enum {
	Request  = 0,
	Response = 1,
}
add_imports :: proc(
	acc: ^map[string]ImportType,
	property: SwaggerModelProperty,
	import_type: ImportType,
	need_date_import: ^bool,
) {
	switch p in property {
	case SwaggerModelPropertyPrimitive:
		if p.format == DATE_TIME_FORMAT {
			if need_date_import != nil {
				need_date_import^ = true
			}
		}
	case SwaggerModelPropertyAllOf:
		for v in p.items {
			add_imports(acc, v, import_type, nil)
		}
	case SwaggerModelPropertyDynamicArray:
		add_imports(acc, p.value^, import_type, nil)
	case SwaggerModelPropertyReference:
		prev_value, ok := acc[p.name]
		acc[p.name] = max(ok ? prev_value : import_type, import_type)
	}
}

// print type
print_mapped_type :: proc(
	value: string,
	property: SwaggerModelProperty,
	type_string: string,
) -> (
	mapped_value: string,
	needs_mapping: bool,
) {
	if global_args.gen_dates {
		switch p in property {
		case SwaggerModelPropertyAllOf:
		case SwaggerModelPropertyDynamicArray:
			builder := strings.builder_make_none()
			// print first array
			depth := 1
			fmt.sbprintf(&builder, "%v?.map(", value)
			// print nested arrays
			_, is_array := p.value.(SwaggerModelPropertyDynamicArray)
			value := value
			for is_array {
				value = fmt.tprint("v%v", depth - 1)
				fmt.sbprintf(&builder, "%v => %v?.map(", value)
			}
			// print item and closing brackets
			reference, is_reference := p.value.(SwaggerModelPropertyReference)
			if is_reference {
				fmt.sbprintf(&builder, "map_%v", reference.name)
				for _ in 0 ..< depth {fmt.sbprint(&builder, ")")}
				return strings.to_string(builder), true
			}
		case SwaggerModelPropertyReference:
			return fmt.tprintf("map_{1}({0})", value, p.name), true
		case SwaggerModelPropertyPrimitive:
			if p.format == DATE_TIME_FORMAT {
				return fmt.tprintf(global_args.date_out_fmt, value), true
			}
		}
	}
	return fmt.tprintf("%v as %v", value, type_string), false
}
print_typescript_key_type :: proc(key: string, property: SwaggerModelProperty) -> string {
	builder := strings.builder_make_none()
	type, _, needs_brackets, nullable, is_array, is_array_nullable := get_typescript_type(property)
	fmt.sbprintf(&builder, "%v", key)
	has_question_mark_colon := nullable && !is_array
	fmt.sbprintf(&builder, has_question_mark_colon ? "?: " : ": ")
	if needs_brackets && is_array {fmt.sbprint(&builder, "(")}
	fmt.sbprint(&builder, type)
	if is_array && nullable {fmt.sbprint(&builder, " | undefined")}
	if needs_brackets && is_array {fmt.sbprint(&builder, ")")}
	if is_array {fmt.sbprint(&builder, "[]")}
	if is_array_nullable {fmt.sbprint(&builder, " | undefined")}
	return strings.to_string(builder)
}
print_typescript_type :: proc(property: SwaggerModelProperty) -> string {
	builder := strings.builder_make_none()
	type, _, needs_brackets, nullable, is_array, is_array_nullable := get_typescript_type(property)
	if needs_brackets && is_array {fmt.sbprint(&builder, "(")}
	fmt.sbprint(&builder, type)
	if is_array && nullable {fmt.sbprint(&builder, " | undefined")}
	if needs_brackets && is_array {fmt.sbprint(&builder, ")")}
	if is_array {fmt.sbprint(&builder, "[]")}
	if is_array_nullable || (!is_array && nullable) {fmt.sbprint(&builder, " | undefined")}
	return strings.to_string(builder)
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
				{
					switch m.format {
					case "binary":
						type = "Blob"
					case DATE_TIME_FORMAT:
						if global_args.gen_dates {
							type = global_args.date_type
						} else {
							type = "string"
						}
					case:
						type = "string"
					}
				}
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
