package main
import client "../odin-http/client"
import "core:encoding/json"
import "core:fmt"

get_json :: proc(url: string) -> json.Object {
	res, err := client.get(url)
	defer client.response_destroy(&res)
	fmt.assertf(err == nil, "Request failed: %s", err)
	body, allocation, body_err := client.response_body(&res)
	fmt.assertf(body_err == nil, "Body error: %s", body_err)
	defer client.body_destroy(body, allocation)
	data, json_err := json.parse(transmute([]u8)body.(client.Body_Plain))
	fmt.assertf(json_err == .None, "Couldn't parse JSON: %s", err)
	return data.(json.Object)
}
