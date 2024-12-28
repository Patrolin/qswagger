package main
import "core:fmt"
import "core:strings"

SWAGGER_RUNTIME :: #load("swagger_runtime.ts", string)

print_swagger_runtime :: proc() -> string {
    builder := strings.builder_make_none()
    sbprint_header(&builder)
    fmt.sbprint(&builder, SWAGGER_RUNTIME)
    return strings.to_string(builder)
}
