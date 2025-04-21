const std = @import("std");
const testing = std.testing;

const DELTA = 0.0001;
const EPSILON = 0.00001;
// const W = @divFloor(std.math.e + 1, EPSILON);
const W = 371828;
// const D = @ceil(std.math.ln10(@divFloor(1, DELTA)));
const D = 4;

pub const CountMinSketch = struct {
    table: []u32,
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator) !CountMinSketch {
        const total = try allocator.alloc(u32, D * W);
        @memset(total, 0);
        return CountMinSketch{
            .table = total,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CountMinSketch) void {
        self.allocator.free(self.table);
    }

    pub fn insert(self: *CountMinSketch, key: []const u8) void {
        for (0..D) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const index = hash % W;
            self.table[i * W + index] += 1;
        }
    }

    pub fn query(self: *const CountMinSketch, key: []const u8) u32 {
        var min = @as(u32, std.math.maxInt(u32));
        for (0..D) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const index = hash % W;
            min = if (self.table[i * W + index] < min) self.table[i * W + index] else min;
        }
        return min;
    }
};

test "CountMinSketch" {
    var allocator = std.testing.allocator;
    var cms = try CountMinSketch.init(&allocator);
    defer cms.deinit();

    const key1 = "apple";
    const key2 = "banana";

    cms.insert(key1);
    cms.insert(key1);
    cms.insert(key2);

    try testing.expectEqual(2, cms.query(key1));
    try testing.expectEqual(1, cms.query(key2));
    try testing.expectEqual(0, cms.query("orange"));
}
