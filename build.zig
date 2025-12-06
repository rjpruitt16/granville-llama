const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module for the library
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build as a shared library (driver)
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "granville_llama",
        .root_module = root_module,
    });

    // Link against llama.cpp static libraries
    // These are built separately via CMake with -DBUILD_SHARED_LIBS=OFF
    // Static libs are spread across several directories depending on platform
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/src"));
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/src/Release")); // Windows MSVC
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src"));
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src/Release")); // Windows MSVC
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src/ggml-metal")); // macOS Metal backend
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src/ggml-blas")); // macOS BLAS backend
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src/ggml-cpu")); // CPU backend
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/ggml/src/ggml-cpu/Release")); // Windows CPU
    // Also check bin directories (Windows)
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/bin"));
    lib.addLibraryPath(b.path("vendor/llama.cpp/build/bin/Release"));

    // Link the required libraries (static)
    // Order matters - dependent libs must come after their dependencies
    lib.linkSystemLibrary("llama");
    lib.linkSystemLibrary("ggml");
    lib.linkSystemLibrary("ggml-base");
    lib.linkSystemLibrary("ggml-cpu");

    // On macOS, link Metal and BLAS backends
    if (target.result.os.tag == .macos) {
        lib.linkSystemLibrary("ggml-metal");
        lib.linkSystemLibrary("ggml-blas");
        lib.linkFramework("Foundation");
        lib.linkFramework("Metal");
        lib.linkFramework("MetalKit");
        lib.linkFramework("Accelerate");
    }

    // Link C++ runtime
    // We need both: libc++ (from Zig's clang) and libstdc++ (used by llama.cpp built with g++)
    lib.linkLibCpp();
    // Also link libstdc++ since llama.cpp was built with g++ and uses its ABI
    if (target.result.os.tag == .linux) {
        lib.linkSystemLibrary("stdc++");
    }

    // Add include paths for llama.cpp headers
    lib.addIncludePath(b.path("vendor/llama.cpp/include"));
    lib.addIncludePath(b.path("vendor/llama.cpp/ggml/include"));

    b.installArtifact(lib);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
