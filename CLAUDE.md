# granville-llama

The official llama.cpp driver for [Granville](https://github.com/rjpruitt16/granville), providing GGUF model inference.

## Overview

This driver wraps llama.cpp to provide text generation capabilities for Granville. It's distributed as a shared library that Granville loads at runtime.

## Installation

```bash
granville driver install granville-llama
```

Or manual installation:
```bash
# Download for your platform
curl -LO https://github.com/rjpruitt16/granville-llama/releases/latest/download/granville-llama-darwin-arm64.tar.gz
tar -xzf granville-llama-darwin-arm64.tar.gz -C ~/.granville/drivers/
```

## Building from Source

### Prerequisites
- Zig 0.15.2+
- CMake (for llama.cpp)
- C++ compiler (clang++ or g++)

### Build Steps

```bash
# Clone with llama.cpp submodule
git clone --recursive https://github.com/rjpruitt16/granville-llama.git
cd granville-llama

# Build llama.cpp first
cd vendor/llama.cpp
cmake -B build -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
cd ../..

# Build the driver
zig build -Doptimize=ReleaseFast

# Output: zig-out/lib/libgranville_llama.dylib (or .so/.dll)
```

## Project Structure

```
granville-llama/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies
├── CLAUDE.md           # This file
├── src/
│   ├── main.zig        # Driver implementation
│   └── llama.zig       # llama.cpp Zig bindings
└── vendor/
    └── llama.cpp/      # llama.cpp (git submodule)
```

## Driver Interface

This driver exports the Granville driver interface:

```zig
// Exported symbols (C ABI)
export fn granville_driver_init() ?*anyopaque
export fn granville_driver_deinit(ctx: ?*anyopaque) void
export fn granville_driver_load_model(ctx: ?*anyopaque, path: [*:0]const u8) ?*anyopaque
export fn granville_driver_unload_model(ctx: ?*anyopaque, model: ?*anyopaque) void
export fn granville_driver_generate(ctx: ?*anyopaque, model: ?*anyopaque, prompt: [*:0]const u8, max_tokens: u32) [*:0]const u8
export fn granville_driver_free_string(str: [*:0]const u8) void
export fn granville_driver_get_name() [*:0]const u8
export fn granville_driver_get_version() [*:0]const u8

// VTable for dynamic loading
export const granville_driver_vtable: DriverVTable = .{ ... };
```

## Usage with Granville

```bash
# Install the driver
granville driver install granville-llama

# Download a model
granville download https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Start serving
granville serve tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf --driver granville-llama
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| macOS | arm64 (Apple Silicon) | ✅ Supported |
| macOS | x86_64 | ✅ Supported |
| Linux | x86_64 | ✅ Supported |
| Linux | arm64 | ✅ Supported |
| Windows | x86_64 | 🚧 Planned |

## GPU Acceleration

On supported platforms, llama.cpp automatically uses:
- **macOS**: Metal (Apple GPU)
- **Linux/Windows**: CUDA (if available)

## Configuration

The driver uses sensible defaults but can be configured via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GRANVILLE_LLAMA_THREADS` | CPU count | Number of threads for inference |
| `GRANVILLE_LLAMA_GPU_LAYERS` | 0 | Layers to offload to GPU |
| `GRANVILLE_LLAMA_CONTEXT` | 2048 | Context window size |

## Development

### Running Tests
```bash
zig build test
```

### Creating a Release
```bash
# Build for current platform
zig build -Doptimize=ReleaseFast

# Cross-compile for Linux
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-gnu
```

## License

MIT License - same as llama.cpp
