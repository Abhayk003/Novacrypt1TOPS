`timescale 1ns/1ps

module tb_m_extension;

logic clk;
logic reset;

// AXI4 Instruction Bus
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

// AXI4 Data Bus
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
    .clk(clk),
    .reset(reset),
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

// Instruction memory - word addressed
logic [31:0] imem [0:255];
logic [31:0] instr_to_serve;

// Data memory
logic [31:0] dmem [0:255];

// Instruction to load next burst from
logic [31:0] next_instr;
int          imem_ptr;

task load_instr(input logic [31:0] instr);
    imem[imem_ptr] = instr;
    imem_ptr = imem_ptr + 1;
endtask

// AXI4 Instruction memory model
// ARREADY fixed at 1, burst of 4, 1 cycle latency
logic [31:0] ibus_pending_addr;
logic        ibus_burst_active;
logic [2:0]  ibus_beat;
logic [1:0]  ibus_delay;


assign ARREADY_I = 1'b1;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_I        <= 0;
        RLAST_I         <= 0;
        RDATA_I         <= 0;
        ibus_burst_active <= 0;
        ibus_beat       <= 0;
        ibus_delay      <= 0;
        ibus_pending_addr <= 0;
    end
    else begin
        RVALID_I <= 0;
        RLAST_I  <= 0;

        if (ARVALID_I && ARREADY_I && !ibus_burst_active && !reset) begin
            ibus_pending_addr <= ARADDR_I;
            ibus_burst_active <= 1;
            ibus_beat         <= 0;
            ibus_delay        <= 1; // 1 cycle latency
        end

        if (ibus_burst_active && ibus_delay > 0) begin
            ibus_delay <= ibus_delay - 1;
        end

        if (ibus_burst_active && ibus_delay == 0) begin
            RVALID_I <= 1;
            RDATA_I  <= imem[ibus_pending_addr[31:2] + ibus_beat];
            RRESP_I  <= 2'b00;

            if (ibus_beat == 3) begin
                RLAST_I           <= 1;
                ibus_burst_active <= 0;
                ibus_beat         <= 0;
            end
            else begin
                ibus_beat         <= ibus_beat + 1;
            end
        end
    end
end
assign ARREADY_I = !reset;
// AXI4 Data memory model - 1 cycle read latency
logic        dbus_read_pending;
logic [31:0] dbus_read_addr;

assign ARREADY_D = 1'b1;
assign AWREADY_D = 1'b1;
assign WREADY_D  = 1'b1;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_D       <= 0;
        RDATA_D        <= 0;
        BVALID_D       <= 0;
        dbus_read_pending <= 0;
        dbus_read_addr <= 0;
    end
    else begin
        RVALID_D <= 0;
        BVALID_D <= 0;

        // Read
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

        // Write
//        if (AWVALID_D && WVALID_D) begin
//            dmem[AWADDR_D[31:2]] <= WDATA_D;
//            BVALID_D             <= 1;
//            BRESP_D              <= 2'b00;
//      end
           if (AWVALID_D && WVALID_D)
            begin
            if (WSTRB_D[0]) dmem[AWADDR_D[31:2]][7:0]   <= WDATA_D[7:0];
            if (WSTRB_D[1]) dmem[AWADDR_D[31:2]][15:8]  <= WDATA_D[15:8];
            if (WSTRB_D[2]) dmem[AWADDR_D[31:2]][23:16] <= WDATA_D[23:16];
            if (WSTRB_D[3]) dmem[AWADDR_D[31:2]][31:24] <= WDATA_D[31:24];
        BVALID_D <= 1;
        BRESP_D  <= 2'b00;
end
        end
    end

//always_ff @(posedge clk) begin
//    if (!reset)
//        $display("TIME=%0t | ARVALID_I=%b RVALID_I=%b RDATA_I=%h | pc=%h | fifo_count=%0d | instr_in=%h | instr_valid=%b",
//                 $time,
//                 ARVALID_I,
//                 RVALID_I,
//                 RDATA_I,
//                 dut.pc,
//                 dut.fifo_count,
//                 dut.fetch_instr,
//                 dut.fetch_valid);
//                 $display("TIME=%0t | state=%0d | fifo_free=%0d | ARVALID_I=%b",
//                 $time, dut.fetch_unit.state, dut.fifo_count, ARVALID_I);
//                 $display("TIME=%0t | pc=%h | opcode=%b | ex_result=%h | reg_we=%b | reg_waddr=%0d | reg_wdata=%h",
//                 $time,
//                 dut.ifid_ex_r.pc,
//                 dut.ifid_ex_r.opcode,
//                 dut.ex_result,
//                 dut.reg_we,
//                 dut.reg_waddr,
//                 dut.reg_wdata);
//end
// Wait until register has expected value, timeout after N cycles
task automatic wait_reg(
    input int   reg_idx,
    input logic [31:0] expected,
    input string test_name,
    input int   timeout
);
    int i;
    for (i = 0; i < timeout; i++) begin
        @(posedge clk);
        if (dut.regfile.regs[reg_idx] === expected) begin
            $display("%s PASS", test_name);
            return;
        end
    end
    $display("%s FAIL (got %h expected %h)", test_name,
             dut.regfile.regs[reg_idx], expected);
endtask

task automatic wait_nonzero_reg(
    input int   reg_idx,
    input string test_name,
    input int   timeout
);
    int i;
    for (i = 0; i < timeout; i++) begin
        @(posedge clk);
        if (dut.regfile.regs[reg_idx] !== 0) begin
            $display("%s PASS", test_name);
            return;
        end
    end
    $display("%s FAIL (still zero)", test_name);
endtask

initial begin

    clk      = 0;
    reset    = 1;
    imem_ptr = 0;

    // zero out memories
    for (int i = 0; i < 256; i++) begin
        imem[i] = 32'h00000013; // NOP
        dmem[i] = 32'h00000000;
    end

    // Pre-load data memory for load test
    dmem[0] = 32'hDEADBEEF;    
    dmem[1] = 32'hABCD_1234;
    dmem[2] = 32'h0000_7F80;
    dmem[3] = 32'h00000000;

    // Load instruction sequence into imem
    // Each instruction needs to be followed by 3 NOPs minimum
    // to clear the pipeline before checking result
    // (pipeline is 3 stages: IF→EX→WB)

    imem_ptr = 0;
    
     // ── Register pre-loads ───────────────────────────────────────────────────
    // x1 = 10  (0x0000000A)
    imem[imem_ptr+0] = 32'h00A00C93;  // ADDI x25, x0, 10
    imem[imem_ptr+1] = 32'h00000013;
    imem[imem_ptr+2] = 32'h00000013;
    imem[imem_ptr+3] = 32'h00000013;

    // x2 = 20  (0x00000014)
    imem[imem_ptr+4] = 32'h01400113;  // ADDI x2, x0, 20
    imem[imem_ptr+5] = 32'h00000013;
    imem[imem_ptr+6] = 32'h00000013;
    imem[imem_ptr+7] = 32'h00000013;

    // x3 = -3  (0xFFFFFFFD)
    imem[imem_ptr+8]  = 32'hFFD00193;  // ADDI x3, x0, -3
    imem[imem_ptr+9]  = 32'h00000013;
    imem[imem_ptr+10] = 32'h00000013;
    imem[imem_ptr+11] = 32'h00000013;

    // x4 = 0x80000000  (INT32_MIN / largest unsigned MSB)
    imem[imem_ptr+12] = 32'h80000237;  // LUI x4, 0x80000
    imem[imem_ptr+13] = 32'h00000013;
    imem[imem_ptr+14] = 32'h00000013;
    imem[imem_ptr+15] = 32'h00000013;

    // ── MUL (lower 32 bits, signed × signed) ────────────────────────────────
    // x5 = MUL x1, x2  →  10 * 20          = 200        = 0x000000C8
    imem[imem_ptr+16] = 32'h022C82B3;  // MUL x5, x25, x2
    //imem[imem_ptr+16] = 32'h039142B3;
    imem[imem_ptr+17] = 32'h00000013;
    imem[imem_ptr+18] = 32'h00000013;
    imem[imem_ptr+19] = 32'h00000013;

    // x6 = MUL x1, x3  →  10 * (-3)        = -30        = 0xFFFFFFE2
    imem[imem_ptr+20] = 32'h023C8333;  // MUL x6, x25, x3
    imem[imem_ptr+21] = 32'h00000013;
    imem[imem_ptr+22] = 32'h00000013;
    imem[imem_ptr+23] = 32'h00000013;

    // x7 = MUL x3, x3  →  (-3) * (-3)      = 9          = 0x00000009
    imem[imem_ptr+24] = 32'h023183B3;  // MUL x7, x3, x3
    imem[imem_ptr+25] = 32'h00000013;
    imem[imem_ptr+26] = 32'h00000013;
    imem[imem_ptr+27] = 32'h00000013;

    // x8 = MUL x4, x4  →  INT32_MIN^2 low  = 0          = 0x00000000
    imem[imem_ptr+28] = 32'h02420433;  // MUL x8, x4, x4
    imem[imem_ptr+29] = 32'h00000013;
    imem[imem_ptr+30] = 32'h00000013;
    imem[imem_ptr+31] = 32'h00000013;

    // ── MULH (upper 32 bits, signed × signed) ───────────────────────────────
    // x9  = MULH x1, x2  →  10 * 20   hi   = 0          = 0x00000000
    imem[imem_ptr+32] = 32'h022C94B3;  // MULH x9, x25, x2
    imem[imem_ptr+33] = 32'h00000013;
    imem[imem_ptr+34] = 32'h00000013;
    imem[imem_ptr+35] = 32'h00000013;

    // x10 = MULH x1, x3  →  10 * (-3) hi   = -1         = 0xFFFFFFFF
    imem[imem_ptr+36] = 32'h023C9533;  // MULH x10, x25, x3
    imem[imem_ptr+37] = 32'h00000013;
    imem[imem_ptr+38] = 32'h00000013;
    imem[imem_ptr+39] = 32'h00000013;

    // x11 = MULH x3, x3  →  (-3)*(-3) hi   = 0          = 0x00000000
    imem[imem_ptr+40] = 32'h023195B3;  // MULH x11, x3, x3
    imem[imem_ptr+41] = 32'h00000013;
    imem[imem_ptr+42] = 32'h00000013;
    imem[imem_ptr+43] = 32'h00000013;

    // x12 = MULH x4, x4  →  INT32_MIN^2 hi = 0x40000000
    imem[imem_ptr+44] = 32'h02421633;  // MULH x12, x4, x4
    imem[imem_ptr+45] = 32'h00000013;
    imem[imem_ptr+46] = 32'h00000013;
    imem[imem_ptr+47] = 32'h00000013;

    // ── MULHU (upper 32 bits, unsigned × unsigned) ───────────────────────────
    // x13 = MULHU x1, x2  →  10 * 20   hi   = 0         = 0x00000000
    imem[imem_ptr+48] = 32'h022CB6B3;  // MULHU x13, x25, x2
    imem[imem_ptr+49] = 32'h00000013;
    imem[imem_ptr+50] = 32'h00000013;
    imem[imem_ptr+51] = 32'h00000013;

    // x14 = MULHU x4, x4  →  0x80000000^2 hi = 0x40000000
    imem[imem_ptr+52] = 32'h02423733;  // MULHU x14, x4, x4
    imem[imem_ptr+53] = 32'h00000013;
    imem[imem_ptr+54] = 32'h00000013;
    imem[imem_ptr+55] = 32'h00000013;

    // x15 = MULHU x3, x3  →  0xFFFFFFFD^2 hi = 0xFFFFFFE4
    // (unsigned(-3) = 0xFFFFFFFD; 0xFFFFFFFD^2 = 0xFFFFFFE4_00000009)
    imem[imem_ptr+56] = 32'h0231B7B3;  // MULHU x15, x3, x3
    imem[imem_ptr+57] = 32'h00000013;
    imem[imem_ptr+58] = 32'h00000013;
    imem[imem_ptr+59] = 32'h00000013;

    // ── MULHSU (upper 32 bits, signed rs1 × unsigned rs2) ───────────────────
    // x16 = MULHSU x1, x2  →  signed(10) * unsigned(20) hi = 0
    imem[imem_ptr+60] = 32'h022CA833;  // MULHSU x16, x25, x2
    imem[imem_ptr+61] = 32'h00000013;
    imem[imem_ptr+62] = 32'h00000013;
    imem[imem_ptr+63] = 32'h00000013;

    // x17 = MULHSU x3, x3  →  signed(-3) * unsigned(0xFFFFFFFD) hi
    // = -3 * 4294967293 = -12884901879 = 0xFFFFFFFC_FFFFFFFD >> wait...
    // -3 * 0xFFFFFFFD = -3 * (2^32 - 3) = -3*2^32 + 9
    // as 64-bit: 0xFFFFFFFF_FFFFFFF9 + (-3*2^32 + 3*2^32) ... let's be precise:
    // signed(-3) = 0xFFFFFFFFFFFFFFFD in 64-bit
    // unsigned(0xFFFFFFFD) = 4294967293
    // product = -3 * 4294967293 = -12884901879 = 0xFFFFFFFC_FFFFFFFD (wrong sign)
    // correct: -3 * 4294967293:
    //   = -(3 * 4294967293) = -12884901879
    //   0xFFFFFFFFFFFFFFFF - 12884901878 = 0xFFFFFFFD_00000009
    // → upper 32b = 0xFFFFFFFD
    imem[imem_ptr+64] = 32'h0231A8B3;  // MULHSU x17, x3, x3
    imem[imem_ptr+65] = 32'h00000013;
    imem[imem_ptr+66] = 32'h00000013;
    imem[imem_ptr+67] = 32'h00000013;

    // x18 = MULHSU x4, x4  →  signed(INT32_MIN) * unsigned(0x80000000) hi
    // = -2147483648 * 2147483648 = -4611686018427387904 = 0xC000000000000000
    // → upper 32b = 0xC0000000
    imem[imem_ptr+68] = 32'h02422933;  // MULHSU x18, x4, x4
    imem[imem_ptr+69] = 32'h00000013;
    imem[imem_ptr+70] = 32'h00000013;
    imem[imem_ptr+71] = 32'h00000013;

    // ── DIV (signed, truncate toward zero) ───────────────────────────────────
    // x19 = DIV x25, x2   →  10 / 20          = 0          = 0x00000000
    imem[imem_ptr+72]  = 32'h022CC9B3;  // DIV x19, x25, x2
    imem[imem_ptr+73]  = 32'h00000013;
    imem[imem_ptr+74]  = 32'h00000013;
    imem[imem_ptr+75]  = 32'h00000013;

    // x20 = DIV x2, x25   →  20 / 10          = 2          = 0x00000002
    imem[imem_ptr+76]  = 32'h03914A33;  // DIV x20, x2, x25
    imem[imem_ptr+77]  = 32'h00000013;
    imem[imem_ptr+78]  = 32'h00000013;
    imem[imem_ptr+79]  = 32'h00000013;

    // x21 = DIV x3, x2    →  -3 / 20          = 0 (trunc)  = 0x00000000
    imem[imem_ptr+80]  = 32'h0221CAB3;  // DIV x21, x3, x2
    imem[imem_ptr+81]  = 32'h00000013;
    imem[imem_ptr+82]  = 32'h00000013;
    imem[imem_ptr+83]  = 32'h00000013;

    // x22 = DIV x4, x3    →  INT32_MIN / -3   = 715827882  = 0x2AAAAAAA
    imem[imem_ptr+84]  = 32'h02324B33;  // DIV x22, x4, x3
    imem[imem_ptr+85]  = 32'h00000013;
    imem[imem_ptr+86]  = 32'h00000013;
    imem[imem_ptr+87]  = 32'h00000013;

    // ── DIVU (unsigned) ──────────────────────────────────────────────────────
    // x23 = DIVU x25, x2  →  10 / 20          = 0          = 0x00000000
    imem[imem_ptr+88]  = 32'h022CDBB3;  // DIVU x23, x25, x2
    imem[imem_ptr+89]  = 32'h00000013;
    imem[imem_ptr+90]  = 32'h00000013;
    imem[imem_ptr+91]  = 32'h00000013;

    // x24 = DIVU x4, x25  →  0x80000000 / 10  = 0x0CCCCCCC
    imem[imem_ptr+92]  = 32'h03925C33;  // DIVU x24, x4, x25
    imem[imem_ptr+93]  = 32'h00000013;
    imem[imem_ptr+94]  = 32'h00000013;
    imem[imem_ptr+95]  = 32'h00000013;

    // ── REM (signed, sign follows dividend) ──────────────────────────────────
    // x26 = REM x25, x2   →  10 rem 20        = 10         = 0x0000000A
    imem[imem_ptr+96]  = 32'h022CED33;  // REM x26, x25, x2
    imem[imem_ptr+97]  = 32'h00000013;
    imem[imem_ptr+98]  = 32'h00000013;
    imem[imem_ptr+99]  = 32'h00000013;

    // x27 = REM x4, x3    →  INT32_MIN rem -3 = -2         = 0xFFFFFFFE
    imem[imem_ptr+100] = 32'h02326DB3;  // REM x27, x4, x3
    imem[imem_ptr+101] = 32'h00000013;
    imem[imem_ptr+102] = 32'h00000013;
    imem[imem_ptr+103] = 32'h00000013;

    // x28 = REM x3, x2    →  -3 rem 20        = -3         = 0xFFFFFFFD
    imem[imem_ptr+104] = 32'h0221EE33;  // REM x28, x3, x2
    imem[imem_ptr+105] = 32'h00000013;
    imem[imem_ptr+106] = 32'h00000013;
    imem[imem_ptr+107] = 32'h00000013;

    // ── REMU (unsigned remainder) ─────────────────────────────────────────────
    // x29 = REMU x4, x2   →  0x80000000 % 20  = 8          = 0x00000008
    imem[imem_ptr+108] = 32'h02227EB3;  // REMU x29, x4, x2
    imem[imem_ptr+109] = 32'h00000013;
    imem[imem_ptr+110] = 32'h00000013;
    imem[imem_ptr+111] = 32'h00000013;

    // x30 = REMU x3, x25  →  0xFFFFFFFD % 10  = 3          = 0x00000003
    imem[imem_ptr+112] = 32'h0391FF33;  // REMU x30, x3, x25
    imem[imem_ptr+113] = 32'h00000013;
    imem[imem_ptr+114] = 32'h00000013;
    imem[imem_ptr+115] = 32'h00000013;

    imem_ptr = imem_ptr + 116;

    // Fill rest with NOPs
    while (imem_ptr < 256) begin
        imem[imem_ptr] = 32'h00000013;
        imem_ptr = imem_ptr + 1;
    end

    // Release reset
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n==== RV32I AXI4 DATAPATH TEST ====\n");
    // ── MUL ──────────────────────────────────────────────────────────────────
    wait_reg( 5, 32'h000000C8, "MUL  10*20=200",        120);
    wait_reg( 6, 32'hFFFFFFE2, "MUL  10*(-3)=-30",      30);
    wait_reg( 7, 32'h00000009, "MUL  (-3)*(-3)=9",      30);
    wait_reg( 8, 32'h00000000, "MUL  INT32_MIN^2 low",  30);

    // ── MULH ─────────────────────────────────────────────────────────────────
    wait_reg( 9, 32'h00000000, "MULH  10*20 hi=0",           30);
    wait_reg(10, 32'hFFFFFFFF, "MULH  10*(-3) hi=-1",        30);
    wait_reg(11, 32'h00000000, "MULH  (-3)*(-3) hi=0",       30);
    wait_reg(12, 32'h40000000, "MULH  INT32_MIN^2 hi",       30);

    // ── MULHU ────────────────────────────────────────────────────────────────
    wait_reg(13, 32'h00000000, "MULHU 10*20 hi=0",           30);
    wait_reg(14, 32'h40000000, "MULHU 0x80000000^2 hi",      30);
    wait_reg(15, 32'hFFFFFFFA, "MULHU 0xFFFFFFFD^2 hi",      30);

    // ── MULHSU ───────────────────────────────────────────────────────────────
    wait_reg(16, 32'h00000000, "MULHSU s(10)*u(20) hi=0",    30);
    wait_reg(17, 32'hFFFFFFFD, "MULHSU s(-3)*u(0xFFFFFFFD)", 30);
    wait_reg(18, 32'hC0000000, "MULHSU INT32_MIN*0x80000000",30);

 // ── DIV ──────────────────────────────────────────────────────────────────
    wait_reg(19, 32'h00000000, "DIV  10/20=0",             100);
    wait_reg(20, 32'h00000002, "DIV  20/10=2",             100);
    wait_reg(21, 32'h00000000, "DIV  -3/20=0 (trunc)",     100);
    wait_reg(22, 32'h2AAAAAAA, "DIV  INT32_MIN/-3",        100);

    // ── DIVU ─────────────────────────────────────────────────────────────────
    wait_reg(23, 32'h00000000, "DIVU 10/20=0",             100);
    wait_reg(24, 32'h0CCCCCCC, "DIVU 0x80000000/10",       100);

    // ── REM ──────────────────────────────────────────────────────────────────
    wait_reg(26, 32'h0000000A, "REM  10 rem 20=10",        100);
    wait_reg(27, 32'hFFFFFFFE, "REM  INT32_MIN rem -3=-2", 100);
    wait_reg(28, 32'hFFFFFFFD, "REM  -3 rem 20=-3",        100);

    // ── REMU ─────────────────────────────────────────────────────────────────
    wait_reg(29, 32'h00000008, "REMU 0x80000000%20=8",     100);
    wait_reg(30, 32'h00000003, "REMU 0xFFFFFFFD%10=3",     100);

    wait_reg(0, 32'd0, "X0 PROTECTION", 10);

    $display("\n==== TEST COMPLETE ====\n");
    $finish;
    
end

endmodule