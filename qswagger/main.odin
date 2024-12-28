// odin run qswagger -- <...urls>
package main
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

OUT_DIR :: "fetch/"
main :: proc() {
	if len(os.args) < 2 {
		fmt.println("Usage: qswagger <...urls>")
		os.exit(1)
	}
	urls := os.args[1:]
	for url in urls {
		// fetch
		fmt.printfln("url: %v", url)
		data := get_json(url)
		fmt.printfln("info: %v", data["info"])
		// title
		module := get_swagger_title(data)
		//if len(urls) == 1 {module = ""} // TODO: uncomment
		fmt.printfln("module: %v", module)
		models := parse_models(data, module)
		//fmt.printfln("models: %v", models)
		apis := parse_apis(data, module)
		//fmt.printfln("acc_apis: %v", acc_apis)
		os.make_directory(OUT_DIR)
		os.make_directory(strings.join({OUT_DIR, "model"}, ""))
		os.make_directory(strings.join({OUT_DIR, "api"}, ""))
		for name, model in models {
			file_to_write := print_typescript_model(name, model)
			//fmt.printfln("-- %v", name)
			//fmt.println(file_to_write)
			file_path := strings.join({OUT_DIR, "model/", name, ".ts"}, "")
			fmt.printfln("- %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
		for group, api in apis {
			file_to_write := print_typescript_api(group, api)
			//fmt.printfln("-- %v", name)
			//fmt.printfln("%v", file_to_write)
			file_path := strings.join({OUT_DIR, "api/", group, "Api", ".ts"}, "")
			fmt.printfln("- %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
	}
}
