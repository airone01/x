const std = @import("std");

/// Validates generic type RegType
fn typeCheckRegType(comptime RegType: type) void {
    const reg_info = @typeInfo(RegType);
    if (reg_info != .@"enum") {
        @compileError("Register type must be an enum, but found " ++ @typeName(RegType));
    }
    const enum_info = reg_info.@"enum";
    const tag_info = @typeInfo(enum_info.tag_type);
    if (tag_info != .int or tag_info.int.signedness != .unsigned) {
        @compileError("Register enum must be backed by an unsigned integer, but found " ++ @typeName(enum_info.tag_type));
    }
}

pub fn GenericCpu(comptime RegType: type) type {
    typeCheckRegType(RegType);
    const reg_count = @typeInfo(RegType).@"enum".fields.len;

    return struct {
        regs: [reg_count]u8 = [_]u8{0} ** reg_count,
        pc: u8 = 0,
    };
}

pub fn GenericOperand(comptime RegType: type) type {
    typeCheckRegType(RegType);

    // we cannot set default values, because it's a union, and Zig cannot know
    // at compile time which value of the union will be used first.
    // hence we set data when creating an instance
    return union(enum) {
        reg: RegType,
        imm: u8,
    };
}

pub fn GenericInstruction(comptime OperandType: type, comptime InstrKind: type) type {
    // TODO typecheck

    return struct {
        kind: InstrKind,
        src: ?OperandType = null,
        dst: ?OperandType = null,
    };
}

pub fn GenericDecodeFn(comptime CpuType: type, comptime InstructionType: type) type {
    // TODO typecheck

    return fn (cpu: *CpuType) InstructionType;
}

test "CPU generic validation" {
    const test_regs = enum(u8) { A, B };

    // `GenericCpu(test_regs)` is like TS's `A<"foo">`
    // we could pass data into `{}` below, or let the compiler do it for us
    // like here
    const test_cpu = GenericCpu(test_regs){};
    _ = test_cpu;

    const test_operand = GenericOperand(test_regs){ .imm = 0 };
    _ = test_operand;
}
