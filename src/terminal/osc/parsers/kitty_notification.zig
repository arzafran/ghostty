//! Fork: turns kitty desktop notifications (OSC 99), which upstream parses
//! into `kitty_desktop_notification` but does not act on, into the same
//! `show_desktop_notification` that OSC 9 and OSC 777 produce. Chunks of one
//! notification (`d=0`) can arrive in separate sequences, so the title and
//! body accumulate in `Pending`, which lives on the OSC parser and outlives
//! its per-sequence reset.

const std = @import("std");

const KittyDesktopNotification = @import("kitty_desktop_notification.zig").OSC;

const log = std.log.scoped(.osc_kitty_notification);

const MAX_TEXT = 2048;

pub const Notification = struct {
    title: []const u8,
    body: []const u8,
};

pub const Pending = struct {
    active: bool = false,
    id_len: usize = 0,
    title_len: usize = 0,
    body_len: usize = 0,
    id: [64]u8 = undefined,
    title: [MAX_TEXT]u8 = undefined,
    body: [MAX_TEXT]u8 = undefined,

    pub fn reset(self: *Pending) void {
        self.active = false;
        self.id_len = 0;
        self.title_len = 0;
        self.body_len = 0;
    }

    fn idSlice(self: *const Pending) []const u8 {
        return self.id[0..self.id_len];
    }
};

const PayloadKind = enum { title, body, ignore };

/// Feeds one parsed OSC 99 sequence into `pending`. Returns the finished
/// notification once its last chunk arrives; the returned slices point into
/// `pending` and stay valid until the next call.
pub fn assemble(pending: *Pending, cmd: KittyDesktopNotification) ?Notification {
    var payload_kind: PayloadKind = .title;
    var done = true;
    var base64 = false;
    var id: ?[]const u8 = null;

    var it = std.mem.splitScalar(u8, cmd.metadata, ':');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (eq == 0) continue;
        const value = part[eq + 1 ..];
        switch (part[0]) {
            'p' => payload_kind = parsePayloadKind(value),
            'd' => done = parseBool(value, true),
            'e' => base64 = parseBool(value, false),
            'i' => if (isValidId(value)) {
                id = value;
            },
            else => {},
        }
    }

    if (payload_kind == .ignore) return null;

    if (id) |value| {
        if (!pending.active or !std.mem.eql(u8, pending.idSlice(), value)) {
            pending.reset();
            pending.active = true;
            pending.id_len = @min(value.len, pending.id.len);
            @memcpy(pending.id[0..pending.id_len], value[0..pending.id_len]);
        }
    } else {
        pending.reset();
        pending.active = true;
    }

    const ok = switch (payload_kind) {
        .title => append(&pending.title, &pending.title_len, cmd.payload, base64),
        .body => append(&pending.body, &pending.body_len, cmd.payload, base64),
        .ignore => unreachable,
    };
    if (!ok) {
        pending.reset();
        return null;
    }

    if (!done) return null;

    defer pending.reset();
    if (pending.title_len == 0 and pending.body_len == 0) return null;

    const title = pending.title[0..pending.title_len];
    const body = pending.body[0..pending.body_len];
    if (title.len == 0) return .{ .title = body, .body = "" };
    return .{ .title = title, .body = body };
}

fn parsePayloadKind(value: []const u8) PayloadKind {
    if (std.mem.eql(u8, value, "title")) return .title;
    if (std.mem.eql(u8, value, "body")) return .body;
    return .ignore;
}

fn parseBool(value: []const u8, default: bool) bool {
    if (value.len == 0) return default;
    return switch (value[0]) {
        '0' => false,
        '1' => true,
        else => default,
    };
}

fn isValidId(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| {
        if (std.ascii.isAlphanumeric(c)) continue;
        switch (c) {
            '-', '_', '+', '.', ':' => continue,
            else => return false,
        }
    }
    return true;
}

fn append(buffer: *[MAX_TEXT]u8, len: *usize, payload: []const u8, base64: bool) bool {
    if (payload.len == 0) return true;
    const dest = buffer[len.*..];
    var n = payload.len;
    if (base64) {
        const decoder = std.base64.standard.Decoder;
        n = decoder.calcSizeForSlice(payload) catch return false;
    }
    if (n >= dest.len) {
        log.warn("kitty notification payload too large (len={d})", .{n});
        return false;
    }
    if (base64) {
        std.base64.standard.Decoder.decode(dest[0..n], payload) catch return false;
        if (!std.unicode.utf8ValidateSlice(dest[0..n])) return false;
    } else {
        @memcpy(dest[0..n], payload);
    }
    len.* += n;
    return true;
}

fn feed(pending: *Pending, metadata: []const u8, payload: []const u8) ?Notification {
    return assemble(pending, .{ .metadata = metadata, .payload = payload, .terminator = .st });
}

test "OSC 99: title only" {
    var pending: Pending = .{};
    const n = feed(&pending, "", "Hello Kitty").?;
    try std.testing.expectEqualStrings("Hello Kitty", n.title);
    try std.testing.expectEqualStrings("", n.body);
}

test "OSC 99: chunked title and body" {
    var pending: Pending = .{};
    try std.testing.expect(feed(&pending, "i=1:d=0", "Kitty Title") == null);
    const n = feed(&pending, "i=1:p=body", "Kitty Body").?;
    try std.testing.expectEqualStrings("Kitty Title", n.title);
    try std.testing.expectEqualStrings("Kitty Body", n.body);
}

test "OSC 99: base64 payload" {
    var pending: Pending = .{};
    const n = feed(&pending, "e=1", "SGVsbG8=").?;
    try std.testing.expectEqualStrings("Hello", n.title);
}

test "OSC 99: body only becomes title" {
    var pending: Pending = .{};
    const n = feed(&pending, "p=body", "Only body").?;
    try std.testing.expectEqualStrings("Only body", n.title);
    try std.testing.expectEqualStrings("", n.body);
}

test "OSC 99: close and alive are ignored" {
    var pending: Pending = .{};
    try std.testing.expect(feed(&pending, "p=close", "") == null);
    try std.testing.expect(feed(&pending, "p=alive", "") == null);
}
