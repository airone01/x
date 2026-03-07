const std = @import("std");
const vk = @import("vulkan");
const VulkanContext = @import("vk_context.zig").VulkanContext;
const vk_helpers = @import("vk_helpers.zig");
const SievePipeline = @import("pipeline.zig").SievePipeline;
const Condition = @import("types.zig").Condition;
const FoundSeed = @import("types.zig").FoundSeed;
const Estimator = @import("estimator.zig").Estimator;
const SanityChecker = @import("sanity.zig").SanityChecker;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ctx = try VulkanContext.init(allocator, "SeedFinder");
    defer ctx.deinit();
    const d = ctx.dev_d;

    // --- Setup data (search conditions)
    var conditions = std.ArrayList(Condition).initCapacity(allocator, 9) catch |err| {
        std.debug.print("Alloc failed: {}\n", .{err});
        return;
    };
    defer conditions.deinit(allocator);

    // const full_checker = false;
    // var x_i: i32 = 0;
    // while (x_i <= 6) : (x_i += 1) {
    //     var z_i: i32 = 0;
    //     while (z_i <= 3) : (z_i += 1) {
    //         if (full_checker) {
    //             if (@mod(x_i, 2) == @mod(z_i, 2)) {
    //                 try conditions.append(allocator, .{ .kind = 0, .x = x_i, .z = z_i, .param = 0 });
    //             }
    //         } else {
    //             if (@mod(x_i, 2) == 0 and @mod(z_i, 2) == 0)
    //                 try conditions.append(allocator, .{ .kind = 0, .x = x_i, .z = z_i, .param = 0 });
    //         }
    //     }
    // }
    try conditions.append(allocator, .{
        .kind = 2, // end portal eyes search
        .x = 0, // ignored
        .z = 0, // ignored
        .param = 12,
    });
    std.debug.print("Initializing search for {} chunks...\n", .{conditions.items.len});

    const estimator = Estimator.init(conditions.items.len);
    std.debug.print("Target: {} chunks. Expect 1 match in every {d:.0} seeds.\n", .{ conditions.items.len, estimator.expected_seeds });

    // --- Setup GPU resources
    const pipeline_obj = try SievePipeline.init(&ctx);

    // Check if input config is even possible
    const checker = try SanityChecker.init(&ctx, &pipeline_obj);
    _ = checker;
    // try checker.validate(conditions.items);

    // Buffer 0: results
    const res_buf_size = 16 + (1024 * @sizeOf(FoundSeed));
    const res_buf = try vk_helpers.createBuffer(&ctx, res_buf_size, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });

    // Buffer 1: filter config (16 byte header + array)
    const filter_size = @as(u64, 16) + (conditions.items.len * @sizeOf(Condition));
    const filter_buf = try vk_helpers.createBuffer(&ctx, filter_size, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });

    // Upload filter data
    {
        const ptr = try d.mapMemory(ctx.dev, filter_buf.memory, 0, vk.WHOLE_SIZE, .{});
        const byte_ptr: [*]u8 = @ptrCast(@alignCast(ptr));

        const count_ptr: *u32 = @ptrCast(@alignCast(byte_ptr));
        count_ptr.* = @intCast(conditions.items.len); // write count
        @memset(byte_ptr[4..16], 0); // write padding

        const struct_ptr: [*]Condition = @ptrCast(@alignCast(byte_ptr + 16));
        @memcpy(struct_ptr[0..conditions.items.len], conditions.items); // write array

        d.unmapMemory(ctx.dev, filter_buf.memory);
    }

    // Connect buffers to pipeline
    const writes = [_]vk.WriteDescriptorSet{
        .{
            .s_type = .write_descriptor_set,
            .dst_set = pipeline_obj.descriptor_set,
            .dst_binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_buffer_info = @ptrCast(&vk.DescriptorBufferInfo{ .buffer = res_buf.buffer, .offset = 0, .range = vk.WHOLE_SIZE }),
            .p_next = null,
            .dst_array_element = 0,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        },
        .{
            .s_type = .write_descriptor_set,
            .dst_set = pipeline_obj.descriptor_set,
            .dst_binding = 1,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_buffer_info = @ptrCast(&vk.DescriptorBufferInfo{ .buffer = filter_buf.buffer, .offset = 0, .range = vk.WHOLE_SIZE }),
            .p_next = null,
            .dst_array_element = 0,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    };
    d.updateDescriptorSets(ctx.dev, writes.len, &writes, 0, null);

    // --- Execution loop
    const map_ptr = try d.mapMemory(ctx.dev, res_buf.memory, 0, vk.WHOLE_SIZE, .{});
    const result_data: [*]u32 = @ptrCast(@alignCast(map_ptr));

    var base_seed: i64 = 0;
    const batch_size: u64 = 10_000_000;

    var timer = try std.time.Timer.start();
    var seeds_since_update: u64 = 0;
    var current_speed_str: []u8 = try allocator.dupe(u8, "Calculating...");
    var total_hit_count: u64 = 0;
    const max_hit_count = 5;

    std.debug.print("Growing seeds...\n", .{});
    while (true) {
        result_data[0] = 0; // reset counter

        const cmd_pool = try d.createCommandPool(ctx.dev, &.{ .queue_family_index = ctx.q_fam }, null);
        var cmd: vk.CommandBuffer = undefined;
        try d.allocateCommandBuffers(ctx.dev, &.{ .command_pool = cmd_pool, .level = .primary, .command_buffer_count = 1 }, @ptrCast(&cmd));

        try d.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } });
        d.cmdBindPipeline(cmd, .compute, pipeline_obj.pipeline);
        d.cmdBindDescriptorSets(cmd, .compute, pipeline_obj.layout, 0, 1, @ptrCast(&pipeline_obj.descriptor_set), 0, null);
        d.cmdPushConstants(cmd, pipeline_obj.layout, .{ .compute_bit = true }, 0, 8, @ptrCast(&base_seed));
        d.cmdDispatch(cmd, @intCast((batch_size / 256) + 1), 1, 1);
        try d.endCommandBuffer(cmd);

        const submit = vk.SubmitInfo{ .command_buffer_count = 1, .p_command_buffers = @ptrCast(&cmd) };
        try d.queueSubmit(ctx.queue, 1, @ptrCast(&submit), .null_handle);
        try d.queueWaitIdle(ctx.queue);

        const count = result_data[0];
        // status bar
        if (count > 0) {
            std.debug.print("\x1b[2K\r", .{});
            const base_ptr: [*]u8 = @ptrCast(result_data);
            const array_offset = base_ptr + 16;
            const found_ptr: [*]FoundSeed = @ptrCast(@alignCast(array_offset));
            const readable_count = @min(count, 1024);
            var i: u32 = 0;
            while (i < readable_count) : (i += 1) {
                const res = found_ptr[i];
                if (res.seed == 0 or (res.x == 0 and res.z == 0 and i > 0)) continue;
                total_hit_count += 1;
                std.debug.print("[+] HIT: {} | Chunk: {}, {} (Block: {}, {})\n", .{ res.seed, res.x, res.z, res.x * 16, res.z * 16 });
            }
        }
        d.destroyCommandPool(ctx.dev, cmd_pool, null);
        seeds_since_update += batch_size;

        if (timer.read() >= 500 * std.time.ns_per_ms) {
            const elapsed_ns = timer.lap();
            const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
            const seeds_per_sec = @as(f64, @floatFromInt(seeds_since_update)) / elapsed_s;
            if (current_speed_str.len > 0) allocator.free(current_speed_str);
            current_speed_str = try estimator.estimateTime(allocator, seeds_per_sec);
            const m_seeds = seeds_per_sec / 1_000_000.0;
            std.debug.print("\x1b[2K\rSpeed: {d:.1} M/s | ETA: {s} | Base: {}", .{ m_seeds, current_speed_str, base_seed });
            seeds_since_update = 0;
        }

        if (total_hit_count > max_hit_count)
            break;

        base_seed +%= @intCast(batch_size);
    }
}
