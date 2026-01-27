# MoonBit Sandbox - Task Runner

# Default recipe
default:
    @just --list

# Build all targets
build:
    moon build --target wasm-gc
    moon build --target wasm
    moon build --target native

# Build specific target
build-wasm-gc:
    moon build --target wasm-gc

build-wasm:
    moon build --target wasm

build-native:
    moon build --target native

# Run type check
check:
    moon check --target wasm-gc
    moon check --target native

# Run tests
test:
    moon test --target wasm-gc

test-native:
    moon test --target native

# Run demo (wasm-gc)
demo: build-wasm-gc
    moonrun ./_build/wasm-gc/release/build/cli/cli.wasm

# Run interactive shell with wasmtime (WASI)
shell: build-wasm
    wasmtime ./_build/wasm/release/build/cli/cli.wasm

# Run native shell
shell-native: build-native
    ./_build/native/release/build/cli/cli

# Run agent demo (wasm-gc)
agent: build-wasm-gc
    moonrun ./_build/wasm-gc/release/build/agent-cli/agent-cli.wasm

# Clean build artifacts
clean:
    rm -rf _build

# Format code
fmt:
    moon fmt

# Update dependencies
update:
    moon update

# Generate documentation
doc:
    moon doc --serve

# Run benchmarks
bench:
    moon bench --target wasm-gc
