// ice run <...urls>
package main
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

OUT_DIR :: "fetch/"
GlobalArgs :: struct {
	gen_dates:            bool,
	date_type:            string,
	date_import:          string,
	date_in_fmt:          string,
	date_in_import:       string,
	date_out_fmt:         string,
	date_out_import:      string,
	array_item_null_type: string,
}
global_args := GlobalArgs {
	gen_dates            = false,
	date_type            = "Date",
	date_import          = "",
	date_in_fmt          = "%v.toISOString()",
	date_in_import       = "",
	date_out_fmt         = "{0} == null ? {0} : new Date({0})",
	date_out_import      = "",
	array_item_null_type = "null",
}

// TODO: throw error in typescript if required parameters are missing?
mark_invalid_arg :: proc(args_are_invalid: ^bool, format: string, args: ..any) {
	fmt.printfln(format, ..args)
	args_are_invalid^ = true
}
main :: proc() {
	args := os.args
	args_are_invalid := len(args) < 2
	urls: [dynamic]string
	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		if strings.starts_with(arg, "-") {
			switch arg {
			case "-gen_dates":
				global_args.gen_dates = true
			case "-date_type":
				if i + 1 < len(args) {
					global_args.date_type = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_type?: string")
				}
			case "-date_import":
				if i + 1 < len(args) {
					global_args.date_import = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_import?: string")
				}
			case "-date_in_fmt":
				if i + 1 < len(args) {
					global_args.date_in_fmt = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_in_fmt?: string")
				}
			case "-date_in_import":
				if i + 1 < len(args) {
					global_args.date_in_import = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(
						&args_are_invalid,
						"Missing value for -date_in_import?: string",
					)
				}
			case "-date_out_fmt":
				if i + 1 < len(args) {
					global_args.date_out_fmt = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_out_fmt?: string")
				}
			case "-date_out_import":
				if i + 1 < len(args) {
					global_args.date_out_import = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(
						&args_are_invalid,
						"Missing value for -date_out_import?: string",
					)
				}
			case "-array_item_null_type":
				if i + 1 < len(args) {
					global_args.array_item_null_type = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(
						&args_are_invalid,
						"Missing value for -array_item_null_type?: string",
					)
				}
			case:
				mark_invalid_arg(&args_are_invalid, "Unknown argument: %v", arg)
			}
		} else {
			append(&urls, arg)
		}
	}
	if args_are_invalid {
		fmt.println("Usage: qswagger <...urlsOrFiles>")
		fmt.println("  -gen_dates?")
		fmt.println("  -date_type?: string")
		fmt.println("  -date_import?: string")
		fmt.println("  -date_in_fmt?: string")
		fmt.println("  -date_in_import?: string")
		fmt.println("  -date_out_fmt?: string")
		fmt.println("  -date_out_import?: string")
		fmt.println("  -array_item_null_type?: string")
		fmt.println("Version: v2.5.6")
		os.exit(1)
	}
	fmt.printfln("global_args, %v", global_args)
	remove_directory_recursive(OUT_DIR)
	os.make_directory(OUT_DIR)
	// index.ts
	swagger_index := print_swagger_index()
	error := os.write_entire_file(
		strings.join({OUT_DIR, "index.ts"}, ""),
		transmute([]u8)swagger_index,
	)
	fmt.assertf(error == os.General_Error.None, "error: %v", error)
	// runtime.ts
	swagger_runtime := print_swagger_runtime()
	error = os.write_entire_file(
		strings.join({OUT_DIR, "runtime.ts"}, ""),
		transmute([]u8)swagger_runtime,
	)
	fmt.assertf(error == os.General_Error.None, "error: %v", error)
	// model, api
	os.make_directory(strings.join({OUT_DIR, "models"}, ""))
	os.make_directory(strings.join({OUT_DIR, "apis"}, ""))
	model_index_file := open_index_file_for_writing(strings.join({OUT_DIR, "models/index.ts"}, ""))
	apis_index_file := open_index_file_for_writing(strings.join({OUT_DIR, "apis/index.ts"}, ""))
	for url in urls {
		// fetch
		fmt.printfln("url: %v", url)
		data: json.Object
		if strings.starts_with(url, "http://") || strings.starts_with(url, "https://") {
			data = fetch_json(url)
		} else {
			data = read_file_json(url)
		}
		fmt.printfln("info: %v", data["info"])
		// title
		module := get_swagger_title(data)
		if len(urls) == 1 {module = ""}
		fmt.printfln("module: %v", module)
		models := parse_models(data, module)
		//fmt.printfln("models: %v", models)
		apis := parse_apis(data, module)
		//fmt.printfln("acc_apis: %v", acc_apis)
		for name, model in models {
			file_to_write := print_typescript_model(name, model)
			//fmt.printfln("-- %v", name)
			//fmt.println(file_to_write)
			file_path := fmt.tprintf("%vmodels/%v.ts", OUT_DIR, name)
			fmt.printfln("- %v", file_path)
			model_file_error := os.write_entire_file(file_path, transmute([]u8)file_to_write)
			fmt.assertf(model_file_error == os.General_Error.None, "error: %v", model_file_error)
		}
		for name in sort_keys(models^) {
			/* NOTE: javascript bundlers are bad and don't understand export by name for types... */
			line_to_write := fmt.tprintfln("export * from './{0}';", name)
			os.write(model_index_file, transmute([]u8)line_to_write)
		}
		for group, api in apis {
			file_to_write := print_typescript_api(group, api)
			//fmt.printfln("-- %v", group)
			//fmt.printfln("%v", file_to_write)
			file_path := strings.join({OUT_DIR, "apis/", group, "Api", ".ts"}, "")
			fmt.printfln("- %v", file_path)
			api_file_error := os.write_entire_file(file_path, transmute([]u8)file_to_write)
			fmt.assertf(api_file_error == os.General_Error.None, "error: %v", api_file_error)
		}
		for group in sort_keys(apis^) {
			line_to_write := strings.join({"export * from './", group, "Api';\n"}, "")
			os.write(apis_index_file, transmute([]u8)line_to_write)
		}
	}
}
remove_directory_recursive :: proc(dir_path: string) {
	assert(len(dir_path) > 4) /* NOTE: don't delete the whole system */
	/* walker := os.walker_create(dir_path)
	defer os.walker_destroy(&walker)
	for info in os.walker_walk(&walker) {
		if info.type != .Directory {
			_ = os.remove(info.fullpath)
		}
	}
	_ = os.remove(dir_path) */
	os.remove_all(dir_path)
}
open_index_file_for_writing :: proc(file_path: string) -> ^os.File {
	file, error := os.open(file_path, {.Create, .Trunc, .Write})
	fmt.assertf(error == nil, "Couldn't open %v file: %v", file_path, error)
	os.write(file, transmute([]u8)AUTOGEN_HEADER)
	return file
}
