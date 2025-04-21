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
    row_mutexes: []std.Thread.Mutex,

    pub fn init(allocator: *const std.mem.Allocator) !CountMinSketch {
        const total = try allocator.alloc(u32, D * W);
        @memset(total, 0);

        const mutexes = try allocator.alloc(std.Thread.Mutex, D);
        for (mutexes) |*mutex| {
            mutex.* = std.Thread.Mutex{};
        }

        return CountMinSketch{
            .table = total,
            .allocator = allocator,
            .row_mutexes = mutexes,
        };
    }

    pub fn deinit(self: *CountMinSketch) void {
        self.allocator.free(self.row_mutexes);
        self.allocator.free(self.table);
    }

    pub fn insert(self: *CountMinSketch, key: []const u8) void {
        for (0..D) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const index = hash % W;

            // Lock only the specific row being modified
            self.row_mutexes[i].lock();
            defer self.row_mutexes[i].unlock();

            self.table[i * W + index] += 1;
        }
    }

    pub fn query(self: *const CountMinSketch, key: []const u8) u32 {
        var min = @as(u32, std.math.maxInt(u32));

        for (0..D) |i| {
            const hash = std.hash.Wyhash.hash(i, key);
            const index = hash % W;

            // Lock only the specific row being read
            self.row_mutexes[i].lock();
            defer self.row_mutexes[i].unlock();

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

test "CountMinSketch concurrency" {
    var allocator = std.testing.allocator;
    var cms = try CountMinSketch.init(&allocator);
    defer cms.deinit();

    const thread_count = 10;
    const iterations = 1000;
    var threads: [thread_count]std.Thread = undefined;

    // Create threads that insert the same key multiple times
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, worker, .{ &cms, "concurrent_key", iterations });
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Verify the count is approximately correct
    const expected_count = thread_count * iterations;
    const actual_count = cms.query("concurrent_key");

    // Allow for some error due to hash collisions
    try testing.expect(actual_count >= expected_count * 0.95);
    try testing.expect(actual_count <= expected_count * 1.05);
}

fn worker(cms_ptr: *CountMinSketch, key: []const u8, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        cms_ptr.insert(key);
    }
}
