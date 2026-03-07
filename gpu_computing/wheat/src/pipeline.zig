const std = @import("std");
const vk = @import("vulkan");
const VulkanContext = @import("vk_context.zig").VulkanContext;
// We access the shader binary via the build system's generated module
const sieve_module = @import("sieve_shader");

pub const SievePipeline = struct {
    pipeline: vk.Pipeline,
    layout: vk.PipelineLayout,
    descriptor_set: vk.DescriptorSet,
    descriptor_pool: vk.DescriptorPool,
    descriptor_layout: vk.DescriptorSetLayout,

    pub fn init(ctx: *VulkanContext) !SievePipeline {
        const d = ctx.dev_d;

        // 1. Descriptor Layout (2 Storage Buffers)
        const bindings = [_]vk.DescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptor_type = .storage_buffer,
                .descriptor_count = 1,
                .stage_flags = .{ .compute_bit = true },
            },
            .{
                .binding = 1,
                .descriptor_type = .storage_buffer,
                .descriptor_count = 1,
                .stage_flags = .{ .compute_bit = true },
            },
        };
        const ds_layout = try d.createDescriptorSetLayout(ctx.dev, &.{
            .binding_count = bindings.len,
            .p_bindings = &bindings,
        }, null);

        // 2. Pipeline Layout (Push Constants + Descriptor Set)
        const push_range = vk.PushConstantRange{
            .stage_flags = .{ .compute_bit = true },
            .offset = 0,
            .size = 8,
        };
        const pipe_layout = try d.createPipelineLayout(ctx.dev, &.{
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&ds_layout),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&push_range),
        }, null);

        // 3. Shader Module
        const shader_code = &sieve_module.data;
        const module = try d.createShaderModule(ctx.dev, &.{
            .code_size = shader_code.len,
            .p_code = @ptrCast(shader_code),
        }, null);
        defer d.destroyShaderModule(ctx.dev, module, null);

        // 4. Compute Pipeline
        // RESTORED BOILERPLATE: Explicitly initializing all fields required by vulkan-zig
        const pipe_info = vk.ComputePipelineCreateInfo{
            .flags = .{}, // Zero flags
            .stage = .{
                .stage = .{ .compute_bit = true },
                .module = module,
                .p_name = "main",
            },
            .layout = pipe_layout,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = 0, // This was the specific missing field in your error
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try d.createComputePipelines(ctx.dev, .null_handle, 1, @ptrCast(&pipe_info), null, @ptrCast(&pipeline));

        // 5. Allocate Descriptor Set
        const pool_size = vk.DescriptorPoolSize{ .type = .storage_buffer, .descriptor_count = 2 };
        const pool = try d.createDescriptorPool(ctx.dev, &.{
            .max_sets = 1,
            .pool_size_count = 1,
            .p_pool_sizes = @ptrCast(&pool_size),
        }, null);

        var set: vk.DescriptorSet = undefined;
        try d.allocateDescriptorSets(ctx.dev, &.{
            .descriptor_pool = pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&ds_layout),
        }, @ptrCast(&set));

        return SievePipeline{
            .pipeline = pipeline,
            .layout = pipe_layout,
            .descriptor_set = set,
            .descriptor_pool = pool,
            .descriptor_layout = ds_layout,
        };
    }
};
