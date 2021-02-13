load("//rust:rust_proto_compile.bzl", "rust_proto_compile")
load("//rust:rust_proto_lib.bzl", "rust_proto_lib")
load("@rules_rust//rust:rust.bzl", "rust_library")

def rust_proto_library(**kwargs):
    # Compile protos
    name_pb = kwargs.get("name") + "_pb"
    name_lib = kwargs.get("name") + "_lib"
    rust_proto_compile(
        name = name_pb,
        **{k: v for (k, v) in kwargs.items() if k in ("protos" if "protos" in kwargs else "deps", "verbose")}  # Forward args
    )

    # Create lib file
    rust_proto_lib(
        name = name_lib,
        compilation = name_pb,
        grpc = False,
    )

    # Create rust library
    rust_library(
        name = kwargs.get("name"),
        srcs = [name_pb, name_lib],
        deps = PROTO_DEPS + (kwargs.get("deps", []) if "protos" in kwargs else []),
        visibility = kwargs.get("visibility"),
        tags = kwargs.get("tags"),
    )

PROTO_DEPS = [
    Label("//rust/raze:protobuf"),
]
