const std = @import("std");
const vk = @import("vulkan");
const VulkanContext = @import("vk_context.zig").VulkanContext;
const BufferObject = @import("types.zig").BufferObject;

pub fn createBuffer(ctx: *VulkanContext, size: u64, usage: vk.BufferUsageFlags, props: vk.MemoryPropertyFlags) !BufferObject {
    const d = ctx.dev_d;

    const buffer = try d.createBuffer(ctx.dev, &.{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null);

    // allocate memory
    const mem_reqs = d.getBufferMemoryRequirements(ctx.dev, buffer);
    const mem_type = findMemoryType(ctx.mem_props, mem_reqs.memory_type_bits, props);
    const memory = try d.allocateMemory(ctx.dev, &.{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type,
    }, null);

    // bind
    try d.bindBufferMemory(ctx.dev, buffer, memory, 0);

    return BufferObject{ .buffer = buffer, .memory = memory, .size = size };
}

fn findMemoryType(props: vk.PhysicalDeviceMemoryProperties, type_filter: u32, flags: vk.MemoryPropertyFlags) u32 {
    for (props.memory_types[0..props.memory_type_count], 0..) |mem_type, i| {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and mem_type.property_flags.contains(flags)) {
            return @intCast(i);
        }
    }
    return 0;
}
