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

    // Link against llama.cpp libraries
    // These are built separately via CMake
    const llama_lib_path = "vendor/llama.cpp/build/bin";
    lib.addLibraryPath(b.path(llama_lib_path));
    lib.addRPath(b.path(llama_lib_path));

    // Link the required libraries
    lib.linkSystemLibrary("llama");
    lib.linkSystemLibrary("ggml");
    lib.linkSystemLibrary("ggml-base");
    lib.linkSystemLibrary("ggml-cpu");

    // On macOS, link Metal
    if (target.result.os.tag == .macos) {
        lib.linkSystemLibrary("ggml-metal");
        lib.linkFramework("Foundation");
        lib.linkFramework("Metal");
        lib.linkFramework("MetalKit");
        lib.linkFramework("Accelerate");
    }

    // Link C++ runtime
    lib.linkLibCpp();

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
