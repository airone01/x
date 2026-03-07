const std = @import("std");
const vk = @import("vulkan");
const VulkanContext = @import("vk_context.zig").VulkanContext;
const SievePipeline = @import("pipeline.zig").SievePipeline;
const vk_helpers = @import("vk_helpers.zig");
const Condition = @import("types.zig").Condition;

pub const SanityChecker = struct {
    ctx: *VulkanContext,
    pipeline: *const SievePipeline,

    // We reuse one big buffer for the ladder test
    filter_buf: @import("types.zig").BufferObject,
    res_buf: @import("types.zig").BufferObject,

    pub fn init(ctx: *VulkanContext, pipeline: *const SievePipeline) !SanityChecker {
        // Prepare buffers large enough for the full config
        // Filter: Allow up to 128 conditions
        const f_size = 16 + (128 * @sizeOf(Condition));
        const r_size = 4 + 4 + (1024 * 8);

        return SanityChecker{
            .ctx = ctx,
            .pipeline = pipeline,
            .filter_buf = try vk_helpers.createBuffer(ctx, f_size, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }),
            .res_buf = try vk_helpers.createBuffer(ctx, r_size, .{ .storage_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }),
        };
    }

    /// Uploads a specific subset of conditions to the GPU
    fn uploadFilter(self: *SanityChecker, subset: []const Condition) !void {
        const d = self.ctx.dev_d;
        const ptr = try d.mapMemory(self.ctx.dev, self.filter_buf.memory, 0, vk.WHOLE_SIZE, .{});
        const byte_ptr: [*]u8 = @ptrCast(@alignCast(ptr));

        const count_ptr: *u32 = @ptrCast(@alignCast(byte_ptr));
        count_ptr.* = @intCast(subset.len);
        @memset(byte_ptr[4..16], 0);

        const struct_ptr: [*]Condition = @ptrCast(@alignCast(byte_ptr + 16));
        @memcpy(struct_ptr[0..subset.len], subset);
        d.unmapMemory(self.ctx.dev, self.filter_buf.memory);
    }

    /// Runs the GPU for a set number of batches or until a match is found.
    fn bruteForceCheck(self: *SanityChecker, subset_len: usize, max_batches: usize) !u32 {
        const d = self.ctx.dev_d;
        const batch_size: u64 = 10_000_000;

        // 1. Update Descriptor (Point to Sanity Buffers)
        const writes = [_]vk.WriteDescriptorSet{
            .{
                .s_type = .write_descriptor_set,
                .dst_set = self.pipeline.descriptor_set,
                .dst_binding = 0,
                .descriptor_count = 1,
                .descriptor_type = .storage_buffer,
                .p_buffer_info = @ptrCast(&vk.DescriptorBufferInfo{ .buffer = self.res_buf.buffer, .offset = 0, .range = vk.WHOLE_SIZE }),
                .p_next = null,
                .dst_array_element = 0,
                .p_image_info = undefined,
                .p_texel_buffer_view = undefined,
            },
            .{
                .s_type = .write_descriptor_set,
                .dst_set = self.pipeline.descriptor_set,
                .dst_binding = 1,
                .descriptor_count = 1,
                .descriptor_type = .storage_buffer,
                .p_buffer_info = @ptrCast(&vk.DescriptorBufferInfo{ .buffer = self.filter_buf.buffer, .offset = 0, .range = vk.WHOLE_SIZE }),
                .p_next = null,
                .dst_array_element = 0,
                .p_image_info = undefined,
                .p_texel_buffer_view = undefined,
            },
        };
        d.updateDescriptorSets(self.ctx.dev, writes.len, &writes, 0, null);

        // 2. Clear Counter
        {
            const map_ptr = try d.mapMemory(self.ctx.dev, self.res_buf.memory, 0, vk.WHOLE_SIZE, .{});
            const res_data: [*]u32 = @ptrCast(@alignCast(map_ptr));
            res_data[0] = 0;
            d.unmapMemory(self.ctx.dev, self.res_buf.memory);
        }

        // 3. Execution Loop
        const cmd_pool = try d.createCommandPool(self.ctx.dev, &.{ .queue_family_index = self.ctx.q_fam }, null);
        defer d.destroyCommandPool(self.ctx.dev, cmd_pool, null);

        var base_seed: i64 = 0;
        // Start from a random-ish place each time to avoid testing the same 0-100 seeds repeatedly
        // if we call this function multiple times.
        base_seed = @intCast(subset_len * 999999);

        var batch: usize = 0;
        while (batch < max_batches) : (batch += 1) {
            var cmd: vk.CommandBuffer = undefined;
            try d.allocateCommandBuffers(self.ctx.dev, &.{ .command_pool = cmd_pool, .level = .primary, .command_buffer_count = 1 }, @ptrCast(&cmd));

            try d.beginCommandBuffer(cmd, &.{ .flags = .{ .one_time_submit_bit = true } });
            d.cmdBindPipeline(cmd, .compute, self.pipeline.pipeline);
            d.cmdBindDescriptorSets(cmd, .compute, self.pipeline.layout, 0, 1, @ptrCast(&self.pipeline.descriptor_set), 0, null);
            d.cmdPushConstants(cmd, self.pipeline.layout, .{ .compute_bit = true }, 0, 8, @ptrCast(&base_seed));
            d.cmdDispatch(cmd, @intCast((batch_size / 256) + 1), 1, 1);
            try d.endCommandBuffer(cmd);

            const submit = vk.SubmitInfo{ .command_buffer_count = 1, .p_command_buffers = @ptrCast(&cmd) };
            try d.queueSubmit(self.ctx.queue, 1, @ptrCast(&submit), .null_handle);
            try d.queueWaitIdle(self.ctx.queue);
            // Free buffer implicitly by resetting pool or re-allocating (simplified here)

            // Check results
            const res_ptr = try d.mapMemory(self.ctx.dev, self.res_buf.memory, 0, vk.WHOLE_SIZE, .{});
            const count = (@as([*]u32, @ptrCast(@alignCast(res_ptr))))[0];
            d.unmapMemory(self.ctx.dev, self.res_buf.memory);

            if (count > 0) return count;

            base_seed +%= @intCast(batch_size);
        }

        return 0;
    }

    pub fn validate(self: *SanityChecker, conditions: []const Condition) !void {
        std.debug.print("\n--- LADDER VALIDATION ---\n", .{});
        std.debug.print("Testing stability of the configuration chain...\n", .{});

        // We progressively check 1 chunk, then 1+2, then 1+2+3...
        // We increase the search depth (batches) as probability drops.

        var i: usize = 0;
        while (i < conditions.len) : (i += 1) {
            const subset_len = i + 1;

            // Calculate how hard we need to search.
            // P = 10^(-subset_len).
            // Expected seeds to find 1 match = 10^subset_len.
            // We want to check at least 5x that amount for confidence.
            const prob_exponent: f64 = @floatFromInt(subset_len);
            const expected_seeds = std.math.pow(f64, 10.0, prob_exponent);

            // Limit: Don't search more than 2 Billion seeds (0.2 seconds) for sanity
            // unless it's the final steps.
            var seeds_to_check: u64 = @intFromFloat(expected_seeds * 2.0);
            if (seeds_to_check < 10_000_000) seeds_to_check = 10_000_000;

            // Cap at ~1 second of runtime (10B seeds) per step
            if (seeds_to_check > 15_000_000_000) seeds_to_check = 15_000_000_000;

            const batches = (seeds_to_check / 10_000_000) + 1;

            std.debug.print("[Level {}] Checking first {} chunks (Target: {d:.1}M seeds)... ", .{ subset_len, subset_len, @as(f64, @floatFromInt(seeds_to_check)) / 1e6 });

            // Upload the subset [0..i]
            try self.uploadFilter(conditions[0..subset_len]);

            // Run
            const matches = try self.bruteForceCheck(subset_len, batches);

            if (matches > 0) {
                std.debug.print("OK (Found matches)\n", .{});
            } else {
                std.debug.print("\n\n[!] IMPOSSIBLE CONFIGURATION [!]\n", .{});
                std.debug.print("The chain broke at Chunk #{}.\n", .{subset_len});
                std.debug.print("Specifically, adding chunk ({}, {}) to the previous set yielded 0 matches in {d:.1}B seeds.\n", .{ conditions[i].x, conditions[i].z, @as(f64, @floatFromInt(seeds_to_check)) / 1e9 });
                std.debug.print("This suggests a high-order RNG conflict. Remove this chunk.\n", .{});
                return error.ImpossibleConfiguration;
            }
        }

        std.debug.print("Ladder Check Passed. Configuration is statistically possible.\n", .{});
    }
};
