package main
import client "../odin-http/client"
import "core:encoding/json"
import "core:fmt"
import "core:os"

_parse_json :: proc(bytes: []u8) -> json.Object {
	data, json_err := json.parse(bytes)
	fmt.assertf(json_err == .None, "Couldn't parse JSON: %s", json_err)
	return data.(json.Object)
}
read_file_json :: proc(path: string) -> json.Object {
	file_data, ok := os.read_entire_file_from_filename(path)
	fmt.assertf(ok, "Couldn't read file '%v'", path)
	data := _parse_json(file_data)
	free(raw_data(file_data))
	return data
}
fetch_json :: proc(url: string) -> json.Object {
	res, err := client.get(url)
	defer client.response_destroy(&res)
	if (!(err == nil && res.status == .OK)) {
		if (err == nil) {
			fmt.printf("Request failed: %v %s", int(res.status), res.status)
		} else {
			fmt.printf("Request failed: %v %s", int(res.status), err)
		}
		os.exit(1)
	}
	body, allocation, body_err := client.response_body(&res)
	fmt.assertf(body_err == nil, "Body error: %s", body_err)
	defer client.body_destroy(body, allocation)
	data := _parse_json(transmute([]u8)body.(client.Body_Plain))
	return data
}
