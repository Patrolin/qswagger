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
	for url in os.args[1:] {
		// fetch
		fmt.printfln("url: %v", url)
		data := get_json(url)
		fmt.printfln("info: %v", data["info"])
		// title
		title := get_swagger_title(data)
		fmt.printfln("title: %v", title)
		/*
		models := parse_models(data)
		//fmt.printfln("models: %v", models)
		apis := parse_apis(data)
		//fmt.printfln("acc_apis: %v", acc_apis)
		os.make_directory(OUT_DIR)
		os.make_directory(strings.join({OUT_DIR, "model"}, ""))
		os.make_directory(strings.join({OUT_DIR, "api"}, ""))
		for name, model in models {
			file_to_write := print_typescript_model(name, model)
			fmt.printfln("-- %v", name)
			fmt.println(file_to_write)
			file_path := strings.join({OUT_DIR, "model/", name, ".ts"}, "")
			fmt.printfln("file_path: %v", file_path)
			os.write_entire_file(file_path, transmute([]u8)file_to_write)
		}
		*/

	}
}
