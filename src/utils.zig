pub fn Required(comptime t: type) type {
    const info = @typeInfo(t);
    return switch (info) {
        .Optional => |o| o.child,
        else => @compileError("Optional type expected"),
    };
}
