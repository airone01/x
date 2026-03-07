const std = @import("std");

pub const COND_SLIME_CHUNK: u32 = 0;
pub const COND_END_PORTAL: u32 = 1;

// Matches GLSL struct exactly
pub const Condition = extern struct {
    kind: u32,
    x: i32,
    z: i32,
    param: i32,
};

// Simple wrapper for a GPU buffer
pub const BufferObject = struct {
    buffer: @import("vulkan").Buffer,
    memory: @import("vulkan").DeviceMemory,
    size: u64,
};

pub const FoundSeed = extern struct {
    seed: i64, // 8 bytes
    x: i32, // 4 bytes
    z: i32, // 4 bytes
}; // Total 16 bytes
