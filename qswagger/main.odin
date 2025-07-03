// odin run qswagger -- <...urls>
package main
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

OUT_DIR :: "fetch/"
GlobalArgs :: struct {
	gen_dates:   bool,
	date_type:   string,
	date_import: string,
	date_fmt:    string,
}
global_args := GlobalArgs {
	gen_dates   = false,
	date_type   = "Date",
	date_import = "",
	date_fmt    = "%v.toISOString()",
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
					new_import_line := args[i + 1]
					if len(global_args.date_import) != 0 {
						global_args.date_import = strings.join(
							{global_args.date_import, new_import_line},
							"\n",
						)
					} else {
						global_args.date_import = new_import_line
					}
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_import?: string")
				}
			case "-date_fmt":
				if i + 1 < len(args) {
					global_args.date_fmt = args[i + 1]
					i += 1
				} else {
					mark_invalid_arg(&args_are_invalid, "Missing value for -date_fmt?: string")
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
		fmt.println("  -date_fmt?: string")
		fmt.println("Version: v2.4")
		os.exit(1)
	}
	fmt.printfln("global_args, %v", global_args)
	remove_directory_recursive(OUT_DIR)
	os.make_directory(OUT_DIR)
	// index.ts
	swagger_index := print_swagger_index()
	os.write_entire_file(strings.join({OUT_DIR, "index.ts"}, ""), transmute([]u8)swagger_index)
	// runtime.ts
	swagger_runtime := print_swagger_runtime()
	os.write_entire_file(strings.join({OUT_DIR, "runtime.ts"}, ""), transmute([]u8)swagger_runtime)
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
			file_path := strings.join({OUT_DIR, "models/", name, ".ts"}, "")
			fmt.printfln("- %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
		for name in sort_keys(models^) {
			line_to_write := strings.join({"export * from './", name, "';\n"}, "")
			os.write(model_index_file, transmute([]u8)line_to_write)
		}
		for group, api in apis {
			file_to_write := print_typescript_api(group, api)
			//fmt.printfln("-- %v", name)
			//fmt.printfln("%v", file_to_write)
			file_path := strings.join({OUT_DIR, "apis/", group, "Api", ".ts"}, "")
			fmt.printfln("- %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
		for group in sort_keys(apis^) {
			line_to_write := strings.join({"export * from './", group, "Api';\n"}, "")
			os.write(apis_index_file, transmute([]u8)line_to_write)
		}
	}
}
remove_directory_recursive :: proc(file_path: string) {
	callback :: proc(
		info: os.File_Info,
		in_err: os.Error,
		user_data: rawptr,
	) -> (
		err: os.Error,
		skip_dir: bool,
	) {
		if !info.is_dir {return os.remove(info.fullpath), false}
		return nil, false
	}
	filepath.walk(file_path, callback, nil)
	os.remove_directory(file_path)
}
open_index_file_for_writing :: proc(file_path: string) -> os.Handle {
	file, file_error := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0)
	fmt.assertf(file_error == nil, "Couldn't open %v file: %v", file_path, file_error)
	os.write(file, transmute([]u8)AUTOGEN_HEADER)
	return file
}
