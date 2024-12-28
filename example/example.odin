package example
import "core:fmt"
import "core:strings"

main :: proc() {
	builder := strings.builder_make_len(200)
	name := "UserRole"
	fmt.sbprintfln(&builder, "type %v = {{", name)
	str := strings.to_string(builder)
	fmt.println(str)
}
