// Copyright (c) 2023 Cyber (See LICENSE)

/// Fibers.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const stdx = @import("stdx");
const t = stdx.testing;
const cy = @import("cyber.zig");
const vmc = @import("vm_c.zig");
const rt = cy.rt;
const log = cy.log.scoped(.fiber);
const Value = cy.Value;
const bt = cy.types.BuiltinTypes;

pub const PanicPayload = u64;

pub const PanicType = enum(u8) {
    uncaughtError = vmc.PANIC_UNCAUGHT_ERROR,
    staticMsg = vmc.PANIC_STATIC_MSG,
    msg = vmc.PANIC_MSG,
    nativeThrow = vmc.PANIC_NATIVE_THROW,
    inflightOom = vmc.PANIC_INFLIGHT_OOM,
    none = vmc.PANIC_NONE,
};

test "fiber internals." {
    if (cy.is32Bit) {
        try t.eq(@sizeOf(vmc.Fiber), 72);
        try t.eq(@sizeOf(vmc.TryFrame), 12);
    } else {
        try t.eq(@sizeOf(vmc.Fiber), 88);
        try t.eq(@sizeOf(vmc.TryFrame), 12);
    }
}

pub fn allocFiber(vm: *cy.VM, pc: usize, args: []const cy.Value, argDst: u8, initialStackSize: u32) linksection(cy.HotSection) !cy.Value {
    // Args are copied over to the new stack.
    var stack = try vm.alloc.alloc(Value, initialStackSize);
    // Assumes initial stack size generated by compiler is enough to hold captured args.
    std.mem.copy(Value, stack[argDst..argDst+args.len], args);

    const obj: *vmc.Fiber = @ptrCast(try cy.heap.allocExternalObject(vm, @sizeOf(vmc.Fiber), true));
    const parentDstLocal = cy.NullU8;
    obj.* = .{
        .typeId = bt.Fiber | vmc.CYC_TYPE_MASK,
        .rc = 1,
        .stackPtr = @ptrCast(stack.ptr),
        .stackLen = @intCast(stack.len),
        .pcOffset = @intCast(pc),
        .argStart = argDst,
        .numArgs = @intCast(args.len),
        .stackOffset = 0,
        .parentDstLocal = parentDstLocal,
        .tryStackCap = 0,
        .tryStackPtr = undefined,
        .tryStackLen = 0,
        .throwTracePtr = undefined,
        .throwTraceCap = 0,
        .throwTraceLen = 0,
        .initialPcOffset = @intCast(pc),
        .panicPayload = undefined,
        .panicType = vmc.PANIC_NONE,
        .prevFiber = undefined,
    };

    return Value.initCycPtr(obj);
}

/// Since this is called from a coresume expression, the fiber should already be retained.
pub fn pushFiber(vm: *cy.VM, curFiberEndPc: usize, curFramePtr: [*]Value, fiber: *cy.Fiber, parentDstLocal: u8) PcSp {
    // Save current fiber.
    vm.curFiber.stackPtr = @ptrCast(vm.stack.ptr);
    vm.curFiber.stackLen = @intCast(vm.stack.len);
    vm.curFiber.pcOffset = @intCast(curFiberEndPc);
    vm.curFiber.stackOffset = @intCast(getStackOffset(vm.stack.ptr, curFramePtr));

    // Push new fiber.
    fiber.prevFiber = vm.curFiber;
    fiber.parentDstLocal = parentDstLocal;
    vm.curFiber = fiber;
    vm.stack = @as([*]Value, @ptrCast(fiber.stackPtr))[0..fiber.stackLen];
    vm.stackEndPtr = vm.stack.ptr + fiber.stackLen;
    // Check if fiber was previously yielded.
    if (vm.ops[fiber.pcOffset].opcode() == .coyield) {
        log.debug("fiber set to {} {*}", .{fiber.pcOffset + 3, vm.framePtr});
        return .{
            .pc = toVmPc(vm, fiber.pcOffset + 3),
            .sp = @ptrCast(fiber.stackPtr + fiber.stackOffset),
        };
    } else {
        log.debug("fiber set to {} {*}", .{fiber.pcOffset, vm.framePtr});
        return .{
            .pc = toVmPc(vm, fiber.pcOffset),
            .sp = @ptrCast(fiber.stackPtr + fiber.stackOffset),
        };
    }
}

pub fn popFiber(vm: *cy.VM, cur: PcSpOff, retValue: Value) PcSpOff {
    vm.curFiber.stackPtr = @ptrCast(vm.stack.ptr);
    vm.curFiber.stackLen = @intCast(vm.stack.len);
    vm.curFiber.pcOffset = cur.pc;
    vm.curFiber.stackOffset = cur.sp;
    const dstLocal = vm.curFiber.parentDstLocal;

    // Release current fiber.
    const nextFiber = vm.curFiber.prevFiber.?;
    cy.arc.releaseObject(vm, cy.ptrAlignCast(*cy.HeapObject, vm.curFiber));

    // Set to next fiber.
    vm.curFiber = nextFiber;

    // Copy return value to parent local.
    if (dstLocal != cy.NullU8) {
        vm.curFiber.stackPtr[vm.curFiber.stackOffset + dstLocal] = @bitCast(retValue);
    } else {
        cy.arc.release(vm, retValue);
    }

    vm.stack = @as([*]Value, @ptrCast(vm.curFiber.stackPtr))[0..vm.curFiber.stackLen];
    vm.stackEndPtr = vm.stack.ptr + vm.curFiber.stackLen;
    log.debug("fiber set to {} {*}", .{vm.curFiber.pcOffset, vm.framePtr});
    return PcSpOff{
        .pc = vm.curFiber.pcOffset,
        .sp = vm.curFiber.stackOffset,
    };
}

/// Unwinds the stack and releases the locals.
/// This also releases the initial captured vars since it's on the stack.
pub fn releaseFiberStack(vm: *cy.VM, fiber: *cy.Fiber) !void {
    log.tracev("release fiber stack, start", .{});
    defer log.tracev("release fiber stack, end", .{});
    var stack = @as([*]Value, @ptrCast(fiber.stackPtr))[0..fiber.stackLen];
    var framePtr = fiber.stackOffset;
    var pc = fiber.pcOffset;

    if (pc != cy.NullId) {
        // Check if fiber was previously on a yield op.
        if (vm.ops[pc].opcode() == .coyield) {
            // The yield statement contains the alive locals.
            const localsStart = vm.ops[pc+1].val;
            const localsEnd = vm.ops[pc+2].val;
            log.debug("release on frame {} {} localsEnd: {}", .{framePtr, pc, localsEnd});
            for (stack[framePtr+localsStart..framePtr+localsEnd]) |val| {
                cy.arc.release(vm, val);
            }

            // Prev frame.
            pc = @intCast(getInstOffset(vm.ops.ptr, stack[framePtr + 2].retPcPtr) - stack[framePtr + 1].retInfoCallInstOffset());
            framePtr = @intCast(getStackOffset(stack.ptr, stack[framePtr + 3].retFramePtr));

            // Unwind stack and release all locals.
            while (framePtr > 0) {
                const symIdx = cy.debug.indexOfDebugSym(vm, pc) orelse return error.NoDebugSym;
                const sym = cy.debug.getDebugSymByIndex(vm, symIdx);
                const tempIdx = cy.debug.getDebugTempIndex(vm, symIdx);

                const locals = sym.getLocals();
                log.debug("release on frame {} {}, locals: {}-{}", .{framePtr, pc, locals.start, locals.end});

                if (tempIdx != cy.NullId) {
                    cy.arc.runTempReleaseOps(vm, stack.ptr + framePtr, tempIdx);
                }
                if (locals.len() > 0) {
                    cy.arc.releaseLocals(vm, vm.stack, framePtr, locals);
                }

                // Prev frame.
                pc = @intCast(getInstOffset(vm.ops.ptr, stack[framePtr + 2].retPcPtr) - stack[framePtr + 1].retInfoCallInstOffset());
                framePtr = @intCast(getStackOffset(stack.ptr, stack[framePtr + 3].retFramePtr));
            }
        }

        // Cleanup on main fiber block.
        if (vm.ops[pc].opcode() != .coreturn) {
            const symIdx = cy.debug.indexOfDebugSym(vm, pc) orelse return error.NoDebugSym;
            const tempIdx = cy.debug.getDebugTempIndex(vm, symIdx);
            if (tempIdx != cy.NullId) {
                cy.arc.runTempReleaseOps(vm, stack.ptr + framePtr, tempIdx);
            }

            // No end locals for main fiber block yet.
            // const endLocalsPc = cy.debug.debugSymToEndLocalsPc(vm, sym);
            // if (endLocalsPc != cy.NullId) {
            //     cy.arc.runBlockEndReleaseOps(vm, stack, framePtr, endLocalsPc);
            // }
        }
    }

    // Release any binded args.
    if (fiber.numArgs > 0) {
        for (stack[fiber.argStart..fiber.argStart+fiber.numArgs]) |arg| {
            log.tracev("release fiber arg", .{});
            cy.arc.release(vm, arg);
        }
    }

    // Finally free stack.
    vm.alloc.free(stack);
}

// Determine whether it's a vm or host frame.
pub fn isVmFrame(_: *cy.VM, stack: []const Value, fpOff: u32) bool {
    return stack[fpOff+1].retInfoCallInstOffset() > 0;
}

/// Unwind from `ctx` and release each frame.
/// TODO: See if releaseFiberStack can resuse the same code.
pub fn unwindStack(vm: *cy.VM, stack: []const Value, ctx: PcSpOff) !PcSpOff {
    log.tracev("panic unwind {*}", .{stack.ptr + ctx.sp});
    var pc = ctx.pc;
    var fp = ctx.sp;

    vm.compactTrace.clearRetainingCapacity();

    while (true) {
        try vm.compactTrace.append(vm.alloc, .{
            .pcOffset = pc,
            .fpOffset = fp,
        });
        if (fp == 0 or isVmFrame(vm, stack, fp)) {
            try releaseFrame(vm, fp, pc);
            if (fp == 0) {
                // Done, at main block.
                return PcSpOff{ .pc = pc, .sp = fp };
            } else {
                const prev = getPrevCallFrame(vm, stack, fp);
                pc = prev.pc;
                fp = prev.sp;
            }
        } else {
            log.tracev("Skip host frame.", .{});
            fp = getPrevFp(vm, stack, fp);
        }
    }
}

/// Walks the stack and records each frame.
pub fn recordCurFrames(vm: *cy.VM) !void {
    @setCold(true);
    log.tracev("recordCompactFrames", .{});

    var fp = cy.fiber.getStackOffset(vm.stack.ptr, vm.framePtr);
    var pc = cy.fiber.getInstOffset(vm.ops.ptr, vm.pc);
    while (true) {
        log.tracev("pc: {}, fp: {}", .{pc, fp});

        try vm.compactTrace.append(vm.alloc, .{
            .pcOffset = pc,
            .fpOffset = fp,
        });
        if (fp == 0 or cy.fiber.isVmFrame(vm, vm.stack, fp)) {
            if (fp == 0) {
                // Main.
                break;
            } else {
                const prev = getPrevCallFrame(vm, vm.stack, fp);
                fp = prev.sp;
                pc = prev.pc;
            }
        } else {
            fp = getPrevFp(vm, vm.stack, fp);
        }
    }
}

fn releaseFrame(vm: *cy.VM, fp: u32, pc: u32) !void {
    const symIdx = cy.debug.indexOfDebugSym(vm, pc) orelse return error.NoDebugSym;
    const sym = cy.debug.getDebugSymByIndex(vm, symIdx);
    const tempIdx = cy.debug.getDebugTempIndex(vm, symIdx);
    const locals = sym.getLocals();
    log.tracev("release frame: {} {}, tempIdx: {}, locals: {}-{}", .{pc, vm.ops[pc].opcode(), tempIdx, locals.start, locals.end});

    // Release temps.
    if (tempIdx != cy.NullId) {
        cy.arc.runTempReleaseOps(vm, vm.stack.ptr + fp, tempIdx);
    }

    // Release locals.
    if (locals.len() > 0) {
        cy.arc.releaseLocals(vm, vm.stack, fp, locals);
    }
}

fn releaseFrameTemps(vm: *cy.VM, fp: u32, pc: u32) !void {
    const symIdx = cy.debug.indexOfDebugSym(vm, pc) orelse return error.NoDebugSym;
    const tempIdx = cy.debug.getDebugTempIndex(vm, symIdx);
    log.tracev("release frame temps: {} {}, tempIdx: {}", .{pc, vm.ops[pc].opcode(), tempIdx});

    // Release temps.
    cy.arc.runTempReleaseOps(vm, vm.stack.ptr + fp, tempIdx);
}

fn getPrevFp(_: *cy.VM, stack: []const Value, fp: u32) u32 {
    return cy.fiber.getStackOffset(stack.ptr, stack[fp + 3].retFramePtr);
}

fn getPrevCallFrame(vm: *cy.VM, stack: []const Value, fp: u32) PcSpOff {
    const prevPc = getInstOffset(vm.ops.ptr, stack[fp + 2].retPcPtr) - stack[fp + 1].retInfoCallInstOffset();
    const prevFp = getStackOffset(stack.ptr, stack[fp + 3].retFramePtr);
    return PcSpOff{ .pc = prevPc, .sp = prevFp };
}

// Returns a continuation if there is a parent fiber otherwise null.
pub fn fiberEnd(vm: *cy.VM, ctx: PcSpOff) ?PcSpOff {
    if (vm.curFiber != &vm.mainFiber) {
        if (cy.Trace) {
            // Print fiber panic.
            cy.debug.printLastUserPanicError(vm) catch cy.fatal();
        }
        return cy.fiber.popFiber(vm, ctx, Value.None);
    } else return null;
}

/// Throws an error value by unwinding until the either the first matching catch block
/// is reached or `endFp` is reached.
/// If the main rootFp is reached without a catch block, the error is elevated to an uncaught panic error.
/// Records frames in `compactTrace`.
pub fn throw(vm: *cy.VM, endFp: u32, ctx: PcSpOff, err: Value) !PcSpOff {
    log.tracev("throw", .{});
    var tframe: vmc.TryFrame = undefined;
    var hasTryFrame = false;

    if (vm.tryStack.len > 0) {
        tframe = vm.tryStack.buf[vm.tryStack.len-1];
        if (tframe.fp >= endFp) {
            // Only consider a tframe if it exists at or after `endFp`.
            vm.tryStack.len -= 1;
            hasTryFrame = true;
        }
    }

    vm.compactTrace.clearRetainingCapacity();
    var fp = ctx.sp;
    var pc = ctx.pc;

    while (true) {
        try vm.compactTrace.append(vm.alloc, .{
            .pcOffset = pc,
            .fpOffset = fp,
        });
        if (hasTryFrame) {
            if (fp > tframe.fp) {
                // Haven't reached target try block. Unwind frame.
                try releaseFrame(vm, fp, pc);
                const prev = getPrevCallFrame(vm, vm.stack, fp);
                fp = prev.sp;
                pc = prev.pc;
            } else {
                if (cy.Trace and fp != tframe.fp) {
                    log.tracev("{} {}", .{fp, tframe.fp});
                    return error.Unexpected;
                }

                // Reached target try block.
                try releaseFrameTemps(vm, fp, pc);

                // Copy error to catch dst.
                if (tframe.catchErrDst != cy.NullU8) {
                    if (tframe.releaseDst) {
                        cy.arc.release(vm, vm.stack[fp + tframe.catchErrDst]);
                    }
                    vm.stack[tframe.fp + tframe.catchErrDst] = @bitCast(err);
                }
                // Goto catch block in the current frame.
                return PcSpOff{
                    .pc = tframe.catchPc,
                    .sp = fp,
                };
            }
        } else {
            // Unwind frame.
            try releaseFrame(vm, fp, pc);
            if (fp > endFp) {
                const prev = getPrevCallFrame(vm, vm.stack, fp);
                fp = prev.sp;
                pc = prev.pc;
            } else {
                if (cy.Trace and fp != endFp) {
                    log.tracev("{} {}", .{fp, endFp});
                    return error.Unexpected;
                }
                
                // Reached end.

                if (fp == 0) {
                    // Main root. Convert to uncaught panic.
                    vm.curFiber.panicType = vmc.PANIC_UNCAUGHT_ERROR;

                    // Build stack trace.
                    const frames = try cy.debug.allocStackTrace(vm, vm.stack, vm.compactTrace.items());
                    vm.stackTrace.deinit(vm.alloc);
                    vm.stackTrace.frames = frames;

                    return fiberEnd(vm, .{ .pc = pc, .sp = fp }) orelse {
                        return error.Panic;
                    };
                } else {
                    // Gives host dispatch a chance to catch the error.
                    vm.curFiber.panicType = vmc.PANIC_UNCAUGHT_ERROR;
                    return error.Panic;
                }
            }
        }
    }
}

pub fn freeFiberPanic(vm: *const cy.VM, fiber: *vmc.Fiber) void {
    const panicT: PanicType = @enumFromInt(fiber.panicType);
    if (panicT == .msg) {
        const ptr: usize = @intCast(fiber.panicPayload & ((1 << 48) - 1));
        const len: usize = @intCast(fiber.panicPayload >> 48);
        vm.alloc.free(@as([*]const u8, @ptrFromInt(ptr))[0..len]);
    }
}

pub inline fn getInstOffset(from: [*]const cy.Inst, to: [*]const cy.Inst) u32 {
    return @intCast(@intFromPtr(to) - @intFromPtr(from));
}

pub inline fn getStackOffset(from: [*]const Value, to: [*]const Value) u32 {
    // Divide by eight.
    return @intCast((@intFromPtr(to) - @intFromPtr(from)) >> 3);
}

pub inline fn stackEnsureUnusedCapacity(self: *cy.VM, unused: u32) !void {
    if (@intFromPtr(self.framePtr) + 8 * unused >= @intFromPtr(self.stack.ptr + self.stack.len)) {
        try self.stackGrowTotalCapacity((@intFromPtr(self.framePtr) + 8 * unused) / 8);
    }
}

pub inline fn stackEnsureTotalCapacity(self: *cy.VM, newCap: usize) !void {
    if (newCap > self.stack.len) {
        try stackGrowTotalCapacity(self, newCap);
    }
}

pub fn stackEnsureTotalCapacityPrecise(self: *cy.VM, newCap: usize) !void {
    if (newCap > self.stack.len) {
        try stackGrowTotalCapacityPrecise(self, newCap);
    }
}

pub fn stackGrowTotalCapacity(self: *cy.VM, newCap: usize) !void {
    var betterCap = self.stack.len;
    while (true) {
        betterCap +|= betterCap / 2 + 8;
        if (betterCap >= newCap) {
            break;
        }
    }
    try stackGrowTotalCapacityPrecise(self, betterCap);
}

pub fn stackGrowTotalCapacityPrecise(self: *cy.VM, newCap: usize) !void {
    if (self.alloc.resize(self.stack, newCap)) {
        self.stack.len = newCap;
        self.stackEndPtr = self.stack.ptr + newCap;
    } else {
        self.stack = try self.alloc.realloc(self.stack, newCap);
        self.stackEndPtr = self.stack.ptr + newCap;

        if (builtin.is_test or cy.Trace) {
            // Fill the stack with null heap objects to surface undefined access better.
            @memset(self.stack, Value.initCycPtr(&DummyHeapObject));
        }
    }
}

var DummyHeapObject = cy.HeapObject{
    .head = .{
        .typeId = cy.NullId,
        .rc = 0,
    },
};

pub inline fn toVmPc(self: *const cy.VM, offset: usize) [*]cy.Inst {
    return self.ops.ptr + offset;
}

// Performs stackGrowTotalCapacityPrecise in addition to patching the frame pointers.
pub fn growStackAuto(vm: *cy.VM) !void {
    @setCold(true);
    // Grow by 50% with minimum of 16.
    var growSize = vm.stack.len / 2;
    if (growSize < 16) {
        growSize = 16;
    }
    try growStackPrecise(vm, vm.stack.len + growSize);
}

pub fn ensureTotalStackCapacity(vm: *cy.VM, newCap: usize) !void {
    if (newCap > vm.stack.len) {
        var betterCap = vm.stack.len;
        while (true) {
            betterCap +|= betterCap / 2 + 8;
            if (betterCap >= newCap) {
                break;
            }
        }
        try growStackPrecise(vm, betterCap);
    }
}

fn growStackPrecise(vm: *cy.VM, newCap: usize) !void {
    if (vm.alloc.resize(vm.stack, newCap)) {
        vm.stack.len = newCap;
        vm.stackEndPtr = vm.stack.ptr + newCap;
    } else {
        const newStack = try vm.alloc.alloc(Value, newCap);

        // Copy to new stack.
        std.mem.copy(Value, newStack[0..vm.stack.len], vm.stack);

        // Patch frame ptrs. 
        var curFpOffset = getStackOffset(vm.stack.ptr, vm.framePtr);
        while (curFpOffset != 0) {
            const prevFpOffset = getStackOffset(vm.stack.ptr, newStack[curFpOffset + 3].retFramePtr);
            newStack[curFpOffset + 3].retFramePtr = newStack.ptr + prevFpOffset;
            curFpOffset = prevFpOffset;
        }

        // Free old stack.
        vm.alloc.free(vm.stack);

        // Update to new frame ptr.
        vm.framePtr = newStack.ptr + getStackOffset(vm.stack.ptr, vm.framePtr);
        vm.stack = newStack;
        vm.stackEndPtr = vm.stack.ptr + newCap;
    }
}

pub const PcSpOff = struct {
    pc: u32,
    sp: u32,
};

pub const PcSp = struct {
    pc: [*]cy.Inst,
    sp: [*]Value,
};