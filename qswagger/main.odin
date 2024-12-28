// odin run qswagger -- <...urls>
package main
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

OUT_DIR :: "fetch/"

open_index_file_for_writing :: proc(file_path: string) -> os.Handle {
	file, file_error := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0)
	fmt.assertf(file_error == nil, "Couldn't open %v file: %v", file_path, file_error)
	os.write(file, transmute([]u8)AUTOGEN_HEADER)
	return file
}
main :: proc() {
	if len(os.args) < 2 {
		fmt.println("Usage: qswagger <...urls>")
		os.exit(1)
	}
	urls := os.args[1:]
	os.make_directory(OUT_DIR)
	// index.ts
	swagger_index := print_swagger_index()
	os.write_entire_file(strings.join({OUT_DIR, "index.ts"}, ""), transmute([]u8)swagger_index)
	// runtime.ts
	swagger_runtime := print_swagger_runtime()
	os.write_entire_file(strings.join({OUT_DIR, "runtime.ts"}, ""), transmute([]u8)swagger_runtime)
	// model, api
	os.make_directory(strings.join({OUT_DIR, "model"}, ""))
	os.make_directory(strings.join({OUT_DIR, "api"}, ""))
	model_index_file := open_index_file_for_writing(strings.join({OUT_DIR, "model/index.ts"}, ""))
	apis_index_file := open_index_file_for_writing(strings.join({OUT_DIR, "api/index.ts"}, ""))
	for url in urls {
		// fetch
		fmt.printfln("url: %v", url)
		data := get_json(url)
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
			file_path := strings.join({OUT_DIR, "model/", name, ".ts"}, "")
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
			file_path := strings.join({OUT_DIR, "api/", group, "Api", ".ts"}, "")
			fmt.printfln("- %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
		for group in sort_keys(apis^) {
			line_to_write := strings.join({"export * from './", group, "Api';\n"}, "")
			os.write(apis_index_file, transmute([]u8)line_to_write)
		}
	}
}
