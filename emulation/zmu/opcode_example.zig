const std = @import("std");

//
// ===== CPU STATE (pure data) =====
//

const Register = enum(u2) { A, B, C, D };

const CPU = struct {
    regs: [4]u8 = .{ 0, 0, 0, 0 },
    pc: u8 = 0,
};

//
// ===== MEMORY =====
//

var memory: [256]u8 = undefined;

fn memRead(addr: u8) u8 {
    return memory[addr];
}

fn memWrite(addr: u8, value: u8) void {
    memory[addr] = value;
}

//
// ===== INSTRUCTION REPRESENTATION =====
//

const Operand = union(enum) {
    reg: Register,
    imm: u8,
};

const InstrKind = enum {
    Nop,
    Load,
    Add,
};

const Instruction = struct {
    kind: InstrKind,
    dst: ?Operand = null,
    src: ?Operand = null,
};

//
// ===== DECODER =====
//

const DecodeFn = fn (cpu: *CPU) Instruction;
var decode_table: [256]DecodeFn = undefined;

fn fetch(cpu: *CPU) u8 {
    const v = memRead(cpu.pc);
    cpu.pc +%= 1;
    return v;
}

// --- Generic decoders ---

fn decodeNop(_: *CPU) Instruction {
    return Instruction{ .kind = .Nop };
}

fn decodeLdImm(cpu: *CPU) Instruction {
    const opcode = memRead(cpu.pc - 1);
    const reg_index: u2 = @intCast(opcode & 0b11);

    return Instruction{
        .kind = .Load,
        .dst = .{ .reg = @enumFromInt(reg_index) },
        .src = .{ .imm = fetch(cpu) },
    };
}

fn decodeAddImm(cpu: *CPU) Instruction {
    const opcode = memRead(cpu.pc - 1);
    const reg_index: u2 = @intCast(opcode & 0b11);

    return Instruction{
        .kind = .Add,
        .dst = .{ .reg = @enumFromInt(reg_index) },
        .src = .{ .imm = fetch(cpu) },
    };
}

fn initDecodeTable() void {
    // default: illegal → NOP
    for (decode_table) |*d| d.* = decodeNop;

    decode_table[0x00] = decodeNop;

    for (0x10..0x14) |op| decode_table[op] = decodeLdImm;
    for (0x20..0x24) |op| decode_table[op] = decodeAddImm;
}

//
// ===== EXECUTION =====
//

fn execute(cpu: *CPU, instr: Instruction) void {
    switch (instr.kind) {
        .Nop => {},

        .Load => {
            const r = instr.dst.?.reg;
            const v = instr.src.?.imm;
            cpu.regs[@intFromEnum(r)] = v;
        },

        .Add => {
            const r = instr.dst.?.reg;
            const v = instr.src.?.imm;
            cpu.regs[@intFromEnum(r)] +%= v;
        },
    }
}

//
// ===== MAIN LOOP =====
//

fn step(cpu: *CPU) void {
    const opcode = fetch(cpu);
    const instr = decode_table[opcode](cpu);
    execute(cpu, instr);
}

pub fn main() !void {
    initDecodeTable();

    // Program:
    // LD A, 3
    // ADD A, 5
    // NOP
    memory = .{
        0x10, 3,
        0x20, 5,
        0x00,
    } ++ [_]u8{0} ** 251;

    var cpu = CPU{};

    step(&cpu);
    step(&cpu);
    step(&cpu);

    std.debug.print("A = {}\n", .{cpu.regs[0]}); // should print 8
}
