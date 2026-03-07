const std = @import("std");

pub const Estimator = struct {
    expected_seeds: f64,

    pub fn init(condition_count: usize) Estimator {
        // Probability of a slime chunk is exactly 1/10.
        // For N chunks, the rarity is 1 in 10^N.
        // We use f64 because 20+ chunks will overflow a u64 integer.
        const rarity = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(condition_count)));
        return Estimator{ .expected_seeds = rarity };
    }

    /// Returns a formatted string like "2h 15m 30s" based on current speed
    pub fn estimateTime(self: Estimator, allocator: std.mem.Allocator, seeds_per_second: f64) ![]u8 {
        if (seeds_per_second <= 0) return allocator.dupe(u8, "Calculating...");

        const seconds_left = self.expected_seeds / seeds_per_second;

        // Cap at extremely high numbers to avoid formatting weirdness
        if (seconds_left > 3153600000.0) return allocator.dupe(u8, "> 100 years!");

        const s = @as(u64, @intFromFloat(seconds_left));
        const days = s / 86400;
        const hours = (s % 86400) / 3600;
        const minutes = (s % 3600) / 60;
        const sec = s % 60;

        if (days > 0) {
            return std.fmt.allocPrint(allocator, "{d}d {d}h {d}m", .{ days, hours, minutes });
        } else if (hours > 0) {
            return std.fmt.allocPrint(allocator, "{d}h {d}m {d}s", .{ hours, minutes, sec });
        } else {
            return std.fmt.allocPrint(allocator, "{d}m {d}s", .{ minutes, sec });
        }
    }
};
