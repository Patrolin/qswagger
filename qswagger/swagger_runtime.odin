package main
import "core:fmt"
import "core:strings"

AUTOGEN_HEADER :: #load("autogen_header.txt", string)
SWAGGER_RUNTIME :: #load("swagger_runtime.ts", string)

print_swagger_index :: proc() -> string {
    builder := strings.builder_make_none()
    fmt.sbprint(&builder, AUTOGEN_HEADER)
    fmt.sbprintln(&builder, "export * from './runtime';")
    fmt.sbprintln(&builder, "export * from './apis/index';")
    fmt.sbprintln(&builder, "export * from './models/index';")
    return strings.to_string(builder)
}
print_swagger_runtime :: proc() -> string {
    builder := strings.builder_make_none()
    fmt.sbprint(&builder, AUTOGEN_HEADER)
    fmt.sbprint(&builder, SWAGGER_RUNTIME)
    return strings.to_string(builder)
}
