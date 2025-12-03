// ============================================================================
// granville-llama: llama.cpp driver for Granville
// ============================================================================
//
// This is a Granville driver that wraps llama.cpp for GGUF model inference.
// It exports the standard Granville driver interface (C ABI) so it can be
// dynamically loaded by the Granville kernel.
//
// Build: zig build -Doptimize=ReleaseFast
// Output: libgranville_llama.dylib (macOS) / .so (Linux) / .dll (Windows)
// ============================================================================

const std = @import("std");
const c = @cImport({
    @cInclude("llama.h");
});

const VERSION = "0.1.0";
const NAME = "granville-llama";

// ============================================================================
// Driver Context
// ============================================================================

const DriverContext = struct {
    allocator: std.mem.Allocator,
    n_threads: i32,
    n_gpu_layers: i32,
    n_ctx: u32,

    fn init() DriverContext {
        // Read config from environment
        const threads = blk: {
            if (std.posix.getenv("GRANVILLE_LLAMA_THREADS")) |t| {
                break :blk std.fmt.parseInt(i32, t, 10) catch 4;
            }
            break :blk @as(i32, @intCast(std.Thread.getCpuCount() catch 4));
        };

        const gpu_layers = blk: {
            if (std.posix.getenv("GRANVILLE_LLAMA_GPU_LAYERS")) |g| {
                break :blk std.fmt.parseInt(i32, g, 10) catch 0;
            }
            break :blk @as(i32, 0);
        };

        const ctx_size = blk: {
            if (std.posix.getenv("GRANVILLE_LLAMA_CONTEXT")) |ctx| {
                break :blk std.fmt.parseInt(u32, ctx, 10) catch 2048;
            }
            break :blk @as(u32, 2048);
        };

        return DriverContext{
            .allocator = std.heap.c_allocator,
            .n_threads = threads,
            .n_gpu_layers = gpu_layers,
            .n_ctx = ctx_size,
        };
    }
};

// ============================================================================
// Model Handle
// ============================================================================

const ModelHandle = struct {
    model: *c.llama_model,
    ctx: *c.llama_context,
    vocab: *const c.llama_vocab,
    n_ctx: u32,
};

// ============================================================================
// Exported Driver Interface (C ABI)
// ============================================================================

/// Initialize the driver
export fn granville_driver_init() ?*anyopaque {
    // Initialize llama.cpp backend
    c.llama_backend_init();

    const ctx = DriverContext.init();
    const ctx_ptr = std.heap.c_allocator.create(DriverContext) catch return null;
    ctx_ptr.* = ctx;

    std.debug.print("[granville-llama] Driver initialized (threads={d}, gpu_layers={d}, ctx={d})\n", .{
        ctx.n_threads,
        ctx.n_gpu_layers,
        ctx.n_ctx,
    });

    return @ptrCast(ctx_ptr);
}

/// Cleanup driver resources
export fn granville_driver_deinit(ctx_ptr: ?*anyopaque) void {
    if (ctx_ptr) |ptr| {
        const ctx: *DriverContext = @ptrCast(@alignCast(ptr));
        std.heap.c_allocator.destroy(ctx);
    }
    c.llama_backend_free();
    std.debug.print("[granville-llama] Driver deinitialized\n", .{});
}

/// Load a model from path
export fn granville_driver_load_model(ctx_ptr: ?*anyopaque, path: [*:0]const u8) ?*anyopaque {
    const driver_ctx: *DriverContext = if (ctx_ptr) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        return null;

    std.debug.print("[granville-llama] Loading model: {s}\n", .{path});

    // Set up model parameters
    var model_params = c.llama_model_default_params();
    model_params.n_gpu_layers = driver_ctx.n_gpu_layers;

    // Load the model
    const model = c.llama_model_load_from_file(path, model_params) orelse {
        std.debug.print("[granville-llama] Failed to load model\n", .{});
        return null;
    };

    // Get vocabulary
    const vocab = c.llama_model_get_vocab(model) orelse {
        std.debug.print("[granville-llama] Failed to get vocabulary\\n", .{});
        c.llama_model_free(model);
        return null;
    };

    // Set up context parameters
    var ctx_params = c.llama_context_default_params();
    ctx_params.n_ctx = driver_ctx.n_ctx;
    ctx_params.n_threads = driver_ctx.n_threads;
    ctx_params.n_threads_batch = driver_ctx.n_threads;

    // Create context
    const llama_ctx = c.llama_init_from_model(model, ctx_params) orelse {
        std.debug.print("[granville-llama] Failed to create context\n", .{});
        c.llama_model_free(model);
        return null;
    };

    // Create handle
    const handle = std.heap.c_allocator.create(ModelHandle) catch {
        c.llama_free(llama_ctx);
        c.llama_model_free(model);
        return null;
    };

    handle.* = ModelHandle{
        .model = model,
        .ctx = llama_ctx,
        .vocab = vocab,
        .n_ctx = driver_ctx.n_ctx,
    };

    std.debug.print("[granville-llama] Model loaded successfully\n", .{});
    return @ptrCast(handle);
}

/// Unload a model
export fn granville_driver_unload_model(ctx_ptr: ?*anyopaque, model_ptr: ?*anyopaque) void {
    _ = ctx_ptr;

    if (model_ptr) |ptr| {
        const handle: *ModelHandle = @ptrCast(@alignCast(ptr));
        c.llama_free(handle.ctx);
        c.llama_model_free(handle.model);
        std.heap.c_allocator.destroy(handle);
        std.debug.print("[granville-llama] Model unloaded\n", .{});
    }
}

/// Generate text from prompt
export fn granville_driver_generate(
    ctx_ptr: ?*anyopaque,
    model_ptr: ?*anyopaque,
    prompt: [*:0]const u8,
    max_tokens: u32,
) [*:0]const u8 {
    _ = ctx_ptr;

    const handle: *ModelHandle = if (model_ptr) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        return allocErrorString("model not loaded");

    const prompt_slice = std.mem.span(prompt);

    // Tokenize the prompt
    var tokens: [4096]c.llama_token = undefined;
    const n_prompt_tokens = c.llama_tokenize(
        handle.vocab,
        prompt_slice.ptr,
        @intCast(prompt_slice.len),
        &tokens,
        @intCast(tokens.len),
        true, // add_special
        true, // parse_special
    );

    if (n_prompt_tokens < 0) {
        return allocErrorString("tokenization failed");
    }

    std.debug.print("[granville-llama] Prompt tokens: {d}\n", .{n_prompt_tokens});

    // Create batch
    var batch = c.llama_batch_init(@intCast(handle.n_ctx), 0, 1);
    defer c.llama_batch_free(batch);

    // Add prompt tokens to batch
    var i: usize = 0;
    while (i < @as(usize, @intCast(n_prompt_tokens))) : (i += 1) {
        batch.token[i] = tokens[i];
        batch.pos[i] = @intCast(i);
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = 0;
    }
    batch.n_tokens = n_prompt_tokens;
    batch.logits[@intCast(n_prompt_tokens - 1)] = 1; // Request logits for last token

    // Decode prompt
    if (c.llama_decode(handle.ctx, batch) != 0) {
        return allocErrorString("decode failed");
    }

    // Set up sampler
    const sampler_params = c.llama_sampler_chain_default_params();
    const sampler = c.llama_sampler_chain_init(sampler_params);
    defer c.llama_sampler_free(sampler);

    // Add temperature and greedy sampling
    c.llama_sampler_chain_add(sampler, c.llama_sampler_init_temp(0.7));
    c.llama_sampler_chain_add(sampler, c.llama_sampler_init_greedy());

    // Generate tokens
    var output_tokens: std.ArrayListUnmanaged(c.llama_token) = .empty;
    defer output_tokens.deinit(std.heap.c_allocator);

    var n_cur: i32 = n_prompt_tokens;
    const n_max = @min(n_prompt_tokens + @as(i32, @intCast(max_tokens)), @as(i32, @intCast(handle.n_ctx)));

    var generated_count: usize = 0;
    while (n_cur < n_max) {
        // Sample next token
        const new_token = c.llama_sampler_sample(sampler, handle.ctx, -1);

        // Check for end of generation (but generate at least a few tokens)
        if (generated_count > 5 and c.llama_vocab_is_eog(handle.vocab, new_token)) {
            break;
        }

        output_tokens.append(std.heap.c_allocator, new_token) catch break;
        generated_count += 1;

        // Prepare batch for next token
        batch.n_tokens = 1;
        batch.token[0] = new_token;
        batch.pos[0] = n_cur;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = 1;

        if (c.llama_decode(handle.ctx, batch) != 0) {
            break;
        }

        n_cur += 1;
    }

    std.debug.print("[granville-llama] Generated {d} tokens\n", .{output_tokens.items.len});

    // Detokenize output
    return detokenize(handle.vocab, output_tokens.items);
}

/// Free a string returned by generate
export fn granville_driver_free_string(str: [*:0]const u8) void {
    const slice = std.mem.span(str);
    std.heap.c_allocator.free(slice[0 .. slice.len + 1]);
}

/// Get driver name
export fn granville_driver_get_name() [*:0]const u8 {
    return NAME;
}

/// Get driver version
export fn granville_driver_get_version() [*:0]const u8 {
    return VERSION;
}

// ============================================================================
// VTable Export (for dynamic loading)
// ============================================================================

pub const DriverVTable = extern struct {
    init: *const fn () callconv(.c) ?*anyopaque,
    deinit: *const fn (?*anyopaque) callconv(.c) void,
    load_model: *const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque,
    unload_model: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    generate: *const fn (?*anyopaque, ?*anyopaque, [*:0]const u8, u32) callconv(.c) [*:0]const u8,
    free_string: *const fn ([*:0]const u8) callconv(.c) void,
    get_name: *const fn () callconv(.c) [*:0]const u8,
    get_version: *const fn () callconv(.c) [*:0]const u8,
};

export const granville_driver_vtable: DriverVTable = .{
    .init = granville_driver_init,
    .deinit = granville_driver_deinit,
    .load_model = granville_driver_load_model,
    .unload_model = granville_driver_unload_model,
    .generate = granville_driver_generate,
    .free_string = granville_driver_free_string,
    .get_name = granville_driver_get_name,
    .get_version = granville_driver_get_version,
};

// ============================================================================
// Helper Functions
// ============================================================================

fn allocErrorString(msg: []const u8) [*:0]const u8 {
    const buf = std.heap.c_allocator.allocSentinel(u8, msg.len, 0) catch {
        return "allocation failed";
    };
    @memcpy(buf, msg);
    return buf.ptr;
}

fn detokenize(vocab: *const c.llama_vocab, tokens: []const c.llama_token) [*:0]const u8 {
    if (tokens.len == 0) {
        return allocErrorString("");
    }

    // Estimate buffer size (8 chars per token is usually enough)
    const buf_size: usize = tokens.len * 8 + 1;
    const buf = std.heap.c_allocator.allocSentinel(u8, buf_size, 0) catch {
        return allocErrorString("allocation failed");
    };

    var offset: usize = 0;
    for (tokens) |token| {
        const remaining = buf_size - offset;
        if (remaining <= 1) break;

        const n = c.llama_token_to_piece(
            vocab,
            token,
            buf.ptr + offset,
            @intCast(remaining - 1),
            0,
            true,
        );

        if (n > 0) {
            offset += @intCast(n);
        }
    }

    buf[offset] = 0;
    return buf.ptr;
}

// ============================================================================
// Tests
// ============================================================================

test "driver name and version" {
    const name = std.mem.span(granville_driver_get_name());
    const version = std.mem.span(granville_driver_get_version());

    try std.testing.expectEqualStrings("granville-llama", name);
    try std.testing.expectEqualStrings("0.1.0", version);
}
