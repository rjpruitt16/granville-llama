# granville-llama

The official llama.cpp driver for [Granville](https://github.com/rjpruitt16/granville), providing GGUF model inference.

## Installation

```bash
granville driver install granville-llama
```

## Usage

```bash
# Download a model
granville download https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# Start serving
granville serve tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| macOS | arm64 (Apple Silicon) | Supported |
| macOS | x86_64 | Supported |
| Linux | x86_64 | Supported |
| Linux | arm64 | Supported |
| Windows | x86_64 | Supported |

## Building from Source

### Prerequisites
- Zig 0.15.2+
- CMake
- C++ compiler

### Build Steps

```bash
# Clone with llama.cpp submodule
git clone --recursive https://github.com/rjpruitt16/granville-llama.git
cd granville-llama

# Build llama.cpp first
cd vendor/llama.cpp
cmake -B build -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build -j8
cd ../..

# Build the driver
zig build -Doptimize=ReleaseFast

# Output: zig-out/lib/libgranville_llama.dylib (or .so/.dll)
```

## GPU Acceleration

On supported platforms, llama.cpp automatically uses:
- **macOS**: Metal (Apple GPU)
- **Linux/Windows**: CUDA (if available)

## License

MIT
