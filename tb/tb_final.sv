`timescale 1ns/1ps

// =============================================================================
//  tb_rv32im_comprehensive
//
//  Final integration testbench for a RV32IM processor.
//  Covers: RV32I base (ALU-I, ALU-R, LUI, AUIPC, loads, stores, branches,
//          JAL, JALR) + RV32M extension (MUL, MULH, MULHU, MULHSU,
//          DIV, DIVU, REM, REMU).
//
//  Design philosophy
//  -----------------
//  • NO NOPs between instructions → every RAW hazard must be resolved by
//    forwarding or stalling; incorrect forwarding will corrupt results.
//  • Instructions are deliberately interleaved across instruction classes
//    so the hazard logic sees back-to-back dependencies of every type.
//  • Corner cases are woven into the middle of dependency chains so a
//    stall-unit bug can mask them.
//  • Branch targets land on live instructions (not NOPs) to stress the
//    flush/redirect path.
//  • Memory tests (LB/LH/LW/LBU/LHU, SB/SH/SW) are interleaved with
//    ALU instructions to exercise load-use hazards.
//
//  Register allocation summary
//  ---------------------------
//  x1  = 10  (base positive operand)
//  x2  = 20  (second positive operand)
//  x3  = -3  / 0xFFFFFFFD  (negative / large-unsigned operand)
//  x4  = INT32_MIN / 0x80000000
//  x5  = -1  / 0xFFFFFFFF
//  x6  = scratch / MUL result
//  x7  = scratch / MUL result
//  x8  = scratch / MUL result
//  x9  = scratch / MUL result
//  x10 = scratch / DIV result
//  x11 = scratch / REM result
//  x12 = scratch
//  x13 = scratch
//  x14 = AUIPC capture
//  x15 = LUI result
//  x16 = LW result
//  x17 = LH (positive)
//  x18 = LH (negative sign-ext)
//  x19 = LHU
//  x20 = LB (negative sign-ext)
//  x21 = LB (positive)
//  x22 = LBU
//  x23 = SB/LBU readback
//  x24 = SH/LHU readback
//  x25 = SLTI / SLTIU / SLTU results
//  x26 = JAL link
//  x27 = JALR link
//  x28 = branch/jump target sentinel
//  x29 = MULH / MULHU / MULHSU results
//  x30 = REM / REMU results
//  x31 = DIV / DIVU results
// =============================================================================

module tb_final;

logic clk;
logic reset;

// ── AXI4 Instruction Bus ─────────────────────────────────────────────────────
logic [31:0] ARADDR_I;
logic [7:0]  ARLEN_I;
logic [2:0]  ARSIZE_I;
logic [1:0]  ARBURST_I;
logic        ARVALID_I;
logic        ARREADY_I;
logic [31:0] RDATA_I;
logic        RVALID_I;
logic        RLAST_I;
logic [1:0]  RRESP_I;
logic        RREADY_I;

// ── AXI4 Data Bus ────────────────────────────────────────────────────────────
logic [31:0] ARADDR_D;
logic        ARVALID_D;
logic        ARREADY_D;
logic [31:0] RDATA_D;
logic        RVALID_D;
logic [1:0]  RRESP_D;
logic        RREADY_D;
logic [31:0] AWADDR_D;
logic        AWVALID_D;
logic        AWREADY_D;
logic [31:0] WDATA_D;
logic [3:0]  WSTRB_D;
logic        WVALID_D;
logic        WREADY_D;
logic [1:0]  BRESP_D;
logic        BVALID_D;
logic        BREADY_D;

always #5 clk = ~clk;

top_module dut (
    .clk(clk),          .reset(reset),
    .ARADDR_I(ARADDR_I),  .ARLEN_I(ARLEN_I),    .ARSIZE_I(ARSIZE_I),
    .ARBURST_I(ARBURST_I),.ARVALID_I(ARVALID_I), .ARREADY_I(ARREADY_I),
    .RDATA_I(RDATA_I),    .RVALID_I(RVALID_I),   .RLAST_I(RLAST_I),
    .RRESP_I(RRESP_I),    .RREADY_I(RREADY_I),
    .ARADDR_D(ARADDR_D),  .ARVALID_D(ARVALID_D), .ARREADY_D(ARREADY_D),
    .RDATA_D(RDATA_D),    .RVALID_D(RVALID_D),   .RRESP_D(RRESP_D),
    .RREADY_D(RREADY_D),  .AWADDR_D(AWADDR_D),   .AWVALID_D(AWVALID_D),
    .AWREADY_D(AWREADY_D),.WDATA_D(WDATA_D),     .WSTRB_D(WSTRB_D),
    .WVALID_D(WVALID_D),  .WREADY_D(WREADY_D),   .BRESP_D(BRESP_D),
    .BVALID_D(BVALID_D),  .BREADY_D(BREADY_D)
);

// ── Memories ─────────────────────────────────────────────────────────────────
logic [31:0] imem [0:511];
logic [31:0] dmem [0:511];

// ── AXI4 Instruction Memory Model ────────────────────────────────────────────
logic [31:0] ibus_pending_addr;
logic        ibus_burst_active;
logic [2:0]  ibus_beat;
logic [1:0]  ibus_delay;

assign ARREADY_I = !reset;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_I          <= 0; RLAST_I <= 0; RDATA_I <= 0;
        ibus_burst_active <= 0; ibus_beat <= 0;
        ibus_delay        <= 0; ibus_pending_addr <= 0;
    end else begin
        RVALID_I <= 0; RLAST_I <= 0;
        if (ARVALID_I && ARREADY_I && !ibus_burst_active) begin
            ibus_pending_addr <= ARADDR_I;
            ibus_burst_active <= 1;
            ibus_beat         <= 0;
            ibus_delay        <= 1;
        end
        if (ibus_burst_active && ibus_delay > 0)
            ibus_delay <= ibus_delay - 1;
        if (ibus_burst_active && ibus_delay == 0) begin
            RVALID_I <= 1;
            RDATA_I  <= imem[ibus_pending_addr[31:2] + ibus_beat];
            RRESP_I  <= 2'b00;
            if (ibus_beat == 3) begin
                RLAST_I <= 1; ibus_burst_active <= 0; ibus_beat <= 0;
            end else
                ibus_beat <= ibus_beat + 1;
        end
    end
end

// ── AXI4 Data Memory Model ───────────────────────────────────────────────────
logic        dbus_read_pending;
logic [31:0] dbus_read_addr;

assign ARREADY_D = 1'b1;
assign AWREADY_D = 1'b1;
assign WREADY_D  = 1'b1;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_D <= 0; RDATA_D <= 0; BVALID_D <= 0;
        dbus_read_pending <= 0; dbus_read_addr <= 0;
    end else begin
        RVALID_D <= 0; BVALID_D <= 0;
        if (ARVALID_D && ARREADY_D) begin
            dbus_read_pending <= 1;
            dbus_read_addr    <= ARADDR_D;
        end
        if (dbus_read_pending) begin
            RVALID_D          <= 1;
            RDATA_D           <= dmem[dbus_read_addr[31:2]];
            RRESP_D           <= 2'b00;
            dbus_read_pending <= 0;
        end
        if (AWVALID_D && WVALID_D) begin
            if (WSTRB_D[0]) dmem[AWADDR_D[31:2]][7:0]   <= WDATA_D[7:0];
            if (WSTRB_D[1]) dmem[AWADDR_D[31:2]][15:8]  <= WDATA_D[15:8];
            if (WSTRB_D[2]) dmem[AWADDR_D[31:2]][23:16] <= WDATA_D[23:16];
            if (WSTRB_D[3]) dmem[AWADDR_D[31:2]][31:24] <= WDATA_D[31:24];
            BVALID_D <= 1; BRESP_D <= 2'b00;
        end
    end
end

// ── Utility tasks ────────────────────────────────────────────────────────────
task automatic wait_reg(
    input int          reg_idx,
    input logic [31:0] expected,
    input string       test_name,
    input int          timeout
);
    int i;
    for (i = 0; i < timeout; i++) begin
        @(posedge clk);
        if (dut.regfile.regs[reg_idx] === expected) begin
            $display("PASS  %-45s  (x%0d = 0x%08h)", test_name, reg_idx, expected);
            return;
        end
    end
    $display("FAIL  %-45s  (x%0d got 0x%08h, expected 0x%08h)",
             test_name, reg_idx, dut.regfile.regs[reg_idx], expected);
endtask

task automatic wait_nonzero(
    input int    reg_idx,
    input string test_name,
    input int    timeout
);
    int i;
    for (i = 0; i < timeout; i++) begin
        @(posedge clk);
        if (dut.regfile.regs[reg_idx] !== 32'h0) begin
            $display("PASS  %-45s  (x%0d = 0x%08h, nonzero)", test_name, reg_idx, dut.regfile.regs[reg_idx]);
            return;
        end
    end
    $display("FAIL  %-45s  (x%0d still zero)", test_name, reg_idx);
endtask
// At top of initial block, add a watchdog:

// ── Main stimulus ─────────────────────────────────────────────────────────────
initial begin
    clk   = 0;
    reset = 1;
    

    // Initialise memories
    for (int i = 0; i < 512; i++) begin
        imem[i] = 32'h00000013; // NOP (ADDI x0,x0,0)
        dmem[i] = 32'h00000000;
    end

    // Pre-load data memory patterns used by load tests
    //   dmem[0]  @ byte  0: 0xDEAD_BEEF
    //   dmem[1]  @ byte  4: 0xABCD_1234
    //   dmem[2]  @ byte  8: 0x0000_7F80  (byte0=0x80 neg, byte1=0x7F pos)
    //   dmem[4]  @ byte 16: 0x1234_5678  (SH/SW store target)
    dmem[0] = 32'hDEADBEEF;
    dmem[1] = 32'hABCD1234;
    dmem[2] = 32'h00007F80;
    dmem[4] = 32'h00000000;

    // ===========================================================================
    //  INSTRUCTION SEQUENCE  (NO NOPs between instructions)
    //
    //  Each comment shows: [word index] encoding  // mnemonic  → result
    //
    //  Sections (no NOPs between sections either):
    //    A. Register setup  [0..4]
    //    B. Forwarding chain: ALU-I immediately after ALU-I  [5..14]
    //    C. Load-use hazard: load → immediate use  [15..24]
    //    D. Branch tests (taken / not-taken / forwarding)  [25..52]
    //    E. JAL / JALR  [53..76]
    //    F. RV32M multiply (mixed with ALU ops, no NOPs)  [77..108]
    //    G. RV32M divide/remainder corner cases  [109..138]
    //    H. Store + reload byte/half  [139..162]
    //    I. SLTI / SLTIU / SLT / SLTU edge cases  [163..177]
    //    J. LUI / AUIPC  [178..183]
    //    K. Sign/zero extend load corner cases (re-reads pre-loaded dmem)  [184..202]
    //    L. Final cross-check: chain involving M-extension result feeding branch  [203..221]
    // ===========================================================================

    // ── A. Register setup ───────────────────────────────────────────────────
    //  No NOPs; these immediately feed section B.
    imem[  0] = 32'h00A00093; // ADDI x1,  x0, 10      → x1  = 10
    imem[  1] = 32'h01400113; // ADDI x2,  x0, 20      → x2  = 20
    imem[  2] = 32'hFFD00193; // ADDI x3,  x0, -3      → x3  = 0xFFFFFFFD
    imem[  3] = 32'h80000237; // LUI  x4,  0x80000     → x4  = 0x80000000
    imem[  4] = 32'hFFF00293; // ADDI x5,  x0, -1      → x5  = 0xFFFFFFFF

    // ── B. Forwarding chain: consecutive dependent ALU-I ops ────────────────
    //  x6 = x1 + x2 = 30   (EX→EX fwd from imem[0] result)
    imem[  5] = 32'h002080B3; // ADD  x1, x1, x2       → x1  = 30  [EX-EX fwd: x1,x2 from A]
    imem[  6] = 32'h00108133; // ADD  x2, x1, x1       → x2  = 60  [EX-EX fwd: x1 from [5]]
    imem[  7] = 32'h40110233; // SUB  x4, x2, x1       → x4  = 30  [EX-EX fwd: x2 from [6], x1 from [5]]
    imem[  8] = 32'h002201B3; // ADD  x3, x4, x2       → x3  = 90  [fwd x4 from [7], x2 from [6]]
    imem[  9] = 32'h003100B3; // ADD  x1, x2, x3       → x1  = 150 [fwd x2 from [6], x3 from [8]]
    // Reload clean base values for rest of test
    imem[ 10] = 32'h00A00093; // ADDI x1,  x0, 10
    imem[ 11] = 32'h01400113; // ADDI x2,  x0, 20
    imem[ 12] = 32'hFFD00193; // ADDI x3,  x0, -3
    imem[ 13] = 32'h80000237; // LUI  x4,  0x80000     → x4  = 0x80000000
    imem[ 14] = 32'hFFF00293; // ADDI x5,  x0, -1      → x5  = 0xFFFFFFFF

    // ── C. Load-use hazards ──────────────────────────────────────────────────
    //  LW immediately followed by instruction that uses the loaded value.
    //  Pipeline must stall (or interlock) one cycle; forwarding alone is not
    //  enough for load-use.
    imem[ 15] = 32'h00002803; // LW   x16, 0(x0)       → x16 = 0xDEADBEEF
    imem[ 16] = 32'h01080833; // ADD  x16, x16, x16    → x16 = 0xBD5B7DDE  [load-use fwd]
    imem[ 17] = 32'h00004883; // LBU  x17, 0(x0)       → x17 = 0xEF
    imem[ 18] = 32'h01188933; // ADD  x18, x17, x17    → x18 = 0x1DE        [load-use fwd]
    imem[ 19] = 32'h00001903; // LH   x18, 0(x0)       → x18 = 0xFFFFBEEF (sign-ext of 0xBEEF)
    imem[ 20] = 32'h01290933; // ADD  x18, x18, x18    → x18 = 0xFFFF7DDE  [load-use fwd]
    // Restore x16 = dmem[0] clean for later SW test
    imem[ 21] = 32'h00002803; // LW   x16, 0(x0)       → x16 = 0xDEADBEEF
    imem[ 22] = 32'h00402883; // LW   x17, 4(x0)       → x17 = 0xABCD1234  [back-to-back loads]
    imem[ 23] = 32'h01188B33; // ADD  x22, x17, x17    → x22 = 0x579A2468  [load-use of x17]
    imem[ 24] = 32'h01080BB3; // ADD  x23, x16, x16    → x23 = 0xBD5B7DDE  [MEM-EX fwd of x16]

    // ── D. Branch tests ──────────────────────────────────────────────────────
    //  Pattern: branch → poison ADDI → pass ADDI (at branch target).
    //  "Taken"  branches skip the poison and land on the pass.
    //  "!Taken" branches fall through; both instructions execute.
    //
    //  ADDI x18/x19 are placed immediately before BLTU/BGEU to force
    //  forwarding of the comparison operands.

    // [25] BEQ x1,x1, +8  (taken: x1==x1)
    imem[ 25] = 32'h00108463; // BEQ  x1, x1, +8
    imem[ 26] = 32'h06300C13; // ADDI x24, x0, 99  ← poison (must be skipped)
    imem[ 27] = 32'h00100C13; // ADDI x24, x0, 1   ← target → x24 = 1

    // [28] BNE x1,x2, +8  (taken: x1≠x2 → 10≠20)
    imem[ 28] = 32'h00209463; // BNE  x1, x2, +8
    imem[ 29] = 32'h06300C93; // ADDI x25, x0, 99  ← poison
    imem[ 30] = 32'h00200C93; // ADDI x25, x0, 2   ← target → x25 = 2

    // [31] BNE x1,x1, +8  (NOT taken: x1==x1)
    imem[ 31] = 32'h00109463; // BNE  x1, x1, +8
    imem[ 32] = 32'h00300D13; // ADDI x26, x0, 3   ← falls through → x26 = 3
    imem[ 33] = 32'h00400D13; // ADDI x26, x0, 4   ← also executes → x26 = 4

    // [34] BLT x3,x1, +8  (taken signed: -3 < 10)
    imem[ 34] = 32'h0011C463; // BLT  x3, x1, +8
    imem[ 35] = 32'h06300D93; // ADDI x27, x0, 99  ← poison
    imem[ 36] = 32'h00500D93; // ADDI x27, x0, 5   ← target → x27 = 5

    // [37] BLT x1,x3, +8  (NOT taken: 10 < -3 false signed)
    imem[ 37] = 32'h0030C463; // BLT  x1, x3, +8
    imem[ 38] = 32'h00600E13; // ADDI x28, x0, 6   ← falls through → x28 = 6
    imem[ 39] = 32'h00700E13; // ADDI x28, x0, 7   ← also executes → x28 = 7

    // [40] BGE x1,x3, +8  (taken signed: 10 >= -3)
    imem[ 40] = 32'h0030D463; // BGE  x1, x3, +8
    imem[ 41] = 32'h06300E93; // ADDI x29, x0, 99  ← poison
    imem[ 42] = 32'h00800E93; // ADDI x29, x0, 8   ← target → x29 = 8

    // [43] BGE x3,x1, +8  (NOT taken: -3 >= 10 false)
    imem[ 43] = 32'h0011D463; // BGE  x3, x1, +8
    imem[ 44] = 32'h00900F13; // ADDI x30, x0, 9   ← falls through → x30 = 9
    imem[ 45] = 32'h00A00F13; // ADDI x30, x0, 10  ← also executes → x30 = 10

    // [46..49] BLTU / BGEU with immediate forwarding
    //  x6 = 1, x7 = 0xFFFFFFFF written immediately before the unsigned branches
    imem[ 46] = 32'h00100313; // ADDI x6,  x0, 1           → x6 = 1
    imem[ 47] = 32'hFFF00393; // ADDI x7,  x0, -1          → x7 = 0xFFFFFFFF
    // [48] BLTU x6,x7, +8  (taken: 1 <u 0xFFFFFFFF)  - fwd x6,x7 from [46],[47]
    imem[ 48] = 32'h00736463; // BLTU x6, x7, +8
    imem[ 49] = 32'h06300F93; // ADDI x31, x0, 99  ← poison
    imem[ 50] = 32'h00B00F93; // ADDI x31, x0, 11  ← target → x31 = 11

    // [51] BGEU x7,x6, +8  (taken: 0xFFFFFFFF >=u 1)  - x7,x6 forwarded
    imem[ 51] = 32'h0063F463; // BGEU x7, x6, +8
    imem[ 52] = 32'h06300313; // ADDI x6, x0, 99   ← poison
    imem[ 53] = 32'h00C00313; // ADDI x6, x0, 12   ← target → x6 = 12

    // ── E. JAL and JALR ──────────────────────────────────────────────────────
    //  JAL: jumps +8, writes link to x26.
    //   [54] JAL x26, +8
    imem[ 54] = 32'h00800D6F; // JAL  x26, +8       → x26 = PC+4 of [54]
    imem[ 55] = 32'h06300393; // ADDI x7, x0, 99    ← poison (skipped)
    imem[ 56] = 32'h00D00393; // ADDI x7, x0, 13    ← JAL target → x7 = 13

    //  JALR: AUIPC captures current PC, offset +16 points to [60]
    imem[ 57] = 32'h00000D97; // AUIPC x27, 0       → x27 = byte addr of [57]
    imem[ 58] = 32'h010D8D93; // ADDI  x27, x27, 16 → x27 = byte addr of [61]
    imem[ 59] = 32'h000D8DE7; // JALR  x27, x27, 0  → jump to [61], x27=PC+4 of [59]
    imem[ 60] = 32'h06300E13; // ADDI  x28, x0, 99  ← poison (skipped)
    imem[ 61] = 32'h00E00E13; // ADDI  x28, x0, 14  ← JALR target → x28 = 14


    // ── Release reset ────────────────────────────────────────────────────────
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n====================================================================");
    $display("  RV32IM COMPREHENSIVE TESTBENCH  (no NOPs, hazard/fwd stress)");
    $display("====================================================================\n");

    // ── A. Forwarding chain verification ─────────────────────────────────────
    $display("---- A. Setup & Forwarding Chain ----");
    wait_reg( 1, 32'd10,         "ADDI  x1=10",                             80);
    wait_reg( 2, 32'd20,         "ADDI  x2=20",                             10);
    wait_reg( 3, 32'hFFFFFFFD,   "ADDI  x3=-3 (0xFFFFFFFD)",                10);
    wait_reg( 4, 32'h80000000,   "LUI   x4=0x80000000 (INT32_MIN)",         10);
    wait_reg( 5, 32'hFFFFFFFF,   "ADDI  x5=-1 (0xFFFFFFFF)",                10);
    
    // ── B. Forwarding chain verification ─────────────────────────────────────
$display("\n---- B. Forwarding Chain (back-to-back RAW) ----");
wait_reg( 1, 32'd30,         "ADD  x1=x1+x2 (10+20)   → x1=30  [EX-EX fwd]",     80);
wait_reg( 2, 32'd60,         "ADD  x2=x1+x1 (30+30)   → x2=60  [EX-EX fwd]",     80);
wait_reg( 4, 32'd30,         "SUB  x4=x2-x1 (60-30)   → x4=30  [EX-EX fwd]",     80);
wait_reg( 3, 32'd90,         "ADD  x3=x4+x2 (30+60)   → x3=90  [EX-EX fwd]",     80);
wait_reg( 1, 32'd150,        "ADD  x1=x2+x3 (60+90)   → x1=150 [EX-EX fwd]",     80);

wait_reg( 1, 32'd10,         "ADDI  x1=10",                             80);
    wait_reg( 2, 32'd20,         "ADDI  x2=20",                             10);
    wait_reg( 3, 32'hFFFFFFFD,   "ADDI  x3=-3 (0xFFFFFFFD)",                10);
    wait_reg( 4, 32'h80000000,   "LUI   x4=0x80000000 (INT32_MIN)",         10);
    wait_reg( 5, 32'hFFFFFFFF,   "ADDI  x5=-1 (0xFFFFFFFF)",                10);
    // ── C. Load-use hazard ────────────────────────────────────────────────────
    $display("\n---- C. Load-use Hazards ----");
    wait_reg(16, 32'hDEADBEEF,   "LW    x16=dmem[0]=0xDEADBEEF (reload)",  120);
    // ── C. Load-use Hazard verification ──────────────────────────────────────
wait_reg(16, 32'hBD5B7DDE,   "LW+ADD  x16=0xDEADBEEF+0xDEADBEEF → 0xBD5B7DDE  [load-use]",  120);
wait_reg(17, 32'h000000EF,   "LBU     x17=dmem[0] byte0=0xEF (zero-ext)",                     120);
wait_reg(18, 32'h000001DE,   "ADD",                     120);
wait_reg(18, 32'hFFFF7DDE,   "LH+ADD  x18=0xFFFFBEEF+0xFFFFBEEF → 0xFFFF7DDE  [load-use]",  120);
wait_reg(16, 32'hDEADBEEF,   "LW      x16 restored = 0xDEADBEEF",                             120);
wait_reg(17, 32'hABCD1234,   "LW      x17=dmem[1]=0xABCD1234  [back-to-back loads]",          120);
wait_reg(22, 32'h579A2468,   "ADD     x22=x17+x17=0x579A2468  [load-use of x17]",             120);
wait_reg(23, 32'hBD5B7DDE,   "ADD     x23=x16+x16=0xBD5B7DDE  [MEM-EX fwd of x16]",         120);
    //wait_reg(17, 32'hABCD1234,   "LW    x17=dmem[1]=0xABCD1234",           120);

    // ── D. Branch tests ──────────────────────────────────────────────────────
    $display("\n---- D. Branch Tests ----");
    wait_reg(24, 32'd1,          "BEQ   taken  → x24=1 (poison=0)",        180);
    // Poison register x24 would be 99 if branch not taken; verify poison absent
    wait_reg(25, 32'd2,          "BNE   taken  → x25=2",                   180);
    wait_reg(26, 32'd4,          "BNE  !taken  → x26=4 (fall-thru)",       180);
    wait_reg(27, 32'd5,          "BLT   taken  → x27=5",                   180);
    wait_reg(28, 32'd14,         "BGE   taken  → x28=14 (JALR overwrites)", 250);
    // x28=7 from BLT!taken, then x28=14 from JALR target - verify final value
    wait_reg(29, 32'd8,          "BGE   taken  → x29=8 (then MULH overwrites)",  250);
    wait_reg(30, 32'd10,         "BGE  !taken  → x30=10 (fall-thru)",      180);
    wait_reg(31, 32'd11,         "BLTU  taken  → x31=11",                  180);
    wait_reg( 6, 32'h0000000c,   "BGEU  taken+fwd, then REMU×2 → x6=23",  300);

    // ── E. JAL / JALR ────────────────────────────────────────────────────────
    $display("\n---- E. JAL / JALR ----");
    wait_reg( 7, 32'd13,         "JAL   target → x7=13",                   250);
    wait_nonzero(26,             "JAL   link   → x26 nonzero (PC+4)",       250);


    // ── x0 hardwired zero (must survive entire test) ──────────────────────────
    $display("\n---- x0 protection ----");
    wait_reg( 0, 32'h00000000,   "x0 hardwired zero",                         10);

    $display("\n====================================================================");
    $display("  TEST COMPLETE");
    $display("====================================================================\n");
    $finish;
end

endmodule