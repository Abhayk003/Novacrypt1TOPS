`timescale 1ns/1ps

module tb_m_exten_corner;

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

// Instruction memory
logic [31:0] imem [0:255];

// Data memory
logic [31:0] dmem [0:255];

// AXI4 Instruction memory model
logic [31:0] ibus_pending_addr;
logic        ibus_burst_active;
logic [2:0]  ibus_beat;
logic [1:0]  ibus_delay;

assign ARREADY_I = !reset;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_I          <= 0;
        RLAST_I           <= 0;
        RDATA_I           <= 0;
        ibus_burst_active <= 0;
        ibus_beat         <= 0;
        ibus_delay        <= 0;
        ibus_pending_addr <= 0;
    end
    else begin
        RVALID_I <= 0;
        RLAST_I  <= 0;

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
                RLAST_I           <= 1;
                ibus_burst_active <= 0;
                ibus_beat         <= 0;
            end
            else
                ibus_beat <= ibus_beat + 1;
        end
    end
end

// AXI4 Data memory model
logic        dbus_read_pending;
logic [31:0] dbus_read_addr;

assign ARREADY_D = 1'b1;
assign AWREADY_D = 1'b1;
assign WREADY_D  = 1'b1;

always_ff @(posedge clk) begin
    if (reset) begin
        RVALID_D          <= 0;
        RDATA_D           <= 0;
        BVALID_D          <= 0;
        dbus_read_pending <= 0;
        dbus_read_addr    <= 0;
    end
    else begin
        RVALID_D <= 0;
        BVALID_D <= 0;

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
            BVALID_D <= 1;
            BRESP_D  <= 2'b00;
        end
    end
end

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
            $display("PASS  %s  (x%0d = 0x%08h)", test_name, reg_idx, expected);
            return;
        end
    end
    $display("FAIL  %s  (x%0d got 0x%08h, expected 0x%08h)",
             test_name, reg_idx, dut.regfile.regs[reg_idx], expected);
endtask

initial begin
    clk   = 0;
    reset = 1;

    for (int i = 0; i < 256; i++) begin
        imem[i] = 32'h00000013; // NOP
        dmem[i] = 32'h00000000;
    end

    // ------------------------------------------------------------------
    // Instruction layout - NO NOPs between instructions.
    // Setup registers:
    //   x1 = 10, x2 = 20, x3 = -3 (0xFFFFFFFD),
    //   x4 = INT32_MIN (0x80000000), x5 = -1 (0xFFFFFFFF), x0 = 0
    //
    // Results:
    //   MUL     → x6..x10
    //   MULH    → x11..x15
    //   MULHU   → x16..x19
    //   MULHSU  → x20..x23
    //   DIV     → x24..x29
    //   DIVU    → x30..x31
    //   REM     → x6..x10  (reused after MUL checks)
    //   REMU    → x11..x14 (reused after MULH checks)
    //
    // Corner cases tested:
    //   MUL:    (-1)*(-1), INT32_MIN^2
    //   MULH:   (-1)*(-1) hi
    //   MULHU:  0xFFFFFFFF^2 hi
    //   MULHSU: s(-1)*u(20) hi
    //   DIV:    INT32_MIN/-1 (overflow), div-by-zero
    //   REM:    INT32_MIN rem -1, rem-by-zero
    //   REMU:   0xFFFFFFFF%20, remu-by-zero
    // ------------------------------------------------------------------

    // ── Setup (no NOPs) ──────────────────────────────────────────────────────
    imem[ 0] = 32'h00A00093; // ADDI x1, x0, 10
    imem[ 1] = 32'h01400113; // ADDI x2, x0, 20
    imem[ 2] = 32'hFFD00193; // ADDI x3, x0, -3   (0xFFFFFFFD)
    imem[ 3] = 32'h80000237; // LUI  x4, 0x80000  (0x80000000 = INT32_MIN)
    imem[ 4] = 32'hFFF00293; // ADDI x5, x0, -1   (0xFFFFFFFF)

    // ── MUL (lower 32 bits, signed × signed) ────────────────────────────────
    imem[ 5] = 32'h02208333; // MUL  x6,  x1, x2  = 10*20          = 0x000000C8
    imem[ 6] = 32'h023083B3; // MUL  x7,  x1, x3  = 10*(-3)        = 0xFFFFFFE2
    imem[ 7] = 32'h02318433; // MUL  x8,  x3, x3  = (-3)*(-3)      = 0x00000009
    imem[ 8] = 32'h024204B3; // MUL  x9,  x4, x4  = INT32_MIN^2 lo = 0x00000000
    imem[ 9] = 32'h02528533; // MUL  x10, x5, x5  = (-1)*(-1) lo   = 0x00000001  [corner]

    // ── MULH (upper 32 bits, signed × signed) ───────────────────────────────
    imem[10] = 32'h022095B3; // MULH x11, x1, x2  = 10*20 hi       = 0x00000000
    imem[11] = 32'h02309633; // MULH x12, x1, x3  = 10*(-3) hi     = 0xFFFFFFFF
    imem[12] = 32'h023196B3; // MULH x13, x3, x3  = (-3)*(-3) hi   = 0x00000000
    imem[13] = 32'h02421733; // MULH x14, x4, x4  = INT32_MIN^2 hi = 0x40000000
    imem[14] = 32'h025297B3; // MULH x15, x5, x5  = (-1)*(-1) hi   = 0x00000000  [corner]

    // ── MULHU (upper 32 bits, unsigned × unsigned) ───────────────────────────
    imem[15] = 32'h0220B833; // MULHU x16, x1, x2 = 10*20 hi       = 0x00000000
    imem[16] = 32'h024238B3; // MULHU x17, x4, x4 = 0x80000000^2 hi= 0x40000000
    imem[17] = 32'h0231B933; // MULHU x18, x3, x3 = 0xFFFFFFFD^2 hi= 0xFFFFFFFA
    imem[18] = 32'h0252B9B3; // MULHU x19, x5, x5 = 0xFFFFFFFF^2 hi= 0xFFFFFFFE  [corner]

    // ── MULHSU (upper 32 bits, signed rs1 × unsigned rs2) ───────────────────
    imem[19] = 32'h0220AA33; // MULHSU x20, x1, x2 = s(10)*u(20) hi    = 0x00000000
    imem[20] = 32'h0231AAB3; // MULHSU x21, x3, x3 = s(-3)*u(0xFFFFFFFD) hi = 0xFFFFFFFD
    imem[21] = 32'h02422B33; // MULHSU x22, x4, x4 = INT32_MIN*u(0x80000000) hi = 0xC0000000
    imem[22] = 32'h0222ABB3; // MULHSU x23, x5, x2 = s(-1)*u(20) hi    = 0xFFFFFFFF  [corner]

    // ── DIV (signed, truncate toward zero) ───────────────────────────────────
    imem[23] = 32'h0220CC33; // DIV  x24, x1, x2  = 10/20          = 0x00000000
    imem[24] = 32'h02114CB3; // DIV  x25, x2, x1  = 20/10          = 0x00000002
    imem[25] = 32'h0221CD33; // DIV  x26, x3, x2  = -3/20(trunc)   = 0x00000000
    imem[26] = 32'h02324DB3; // DIV  x27, x4, x3  = INT32_MIN/-3   = 0x2AAAAAAA
    imem[27] = 32'h02524E33; // DIV  x28, x4, x5  = INT32_MIN/-1   = 0x80000000  [corner: overflow]
    imem[28] = 32'h0200CEB3; // DIV  x29, x1, x0  = 10/0           = 0xFFFFFFFF  [corner: div/0]

    // ── DIVU (unsigned) ──────────────────────────────────────────────────────
    imem[29] = 32'h0220DF33; // DIVU x30, x1, x2  = 10/20          = 0x00000000
    imem[30] = 32'h02125FB3; // DIVU x31, x4, x1  = 0x80000000/10  = 0x0CCCCCCC

    // ── REM (signed, sign follows dividend) ──────────────────────────────────
    // Reuse x6..x10; these are checked before reaching this point
    imem[31] = 32'h0220E333; // REM  x6,  x1, x2  = 10 rem 20      = 0x0000000A
    imem[32] = 32'h023263B3; // REM  x7,  x4, x3  = INT32_MIN rem -3= 0xFFFFFFFE
    imem[33] = 32'h0221E433; // REM  x8,  x3, x2  = -3 rem 20      = 0xFFFFFFFD
    imem[34] = 32'h025264B3; // REM  x9,  x4, x5  = INT32_MIN rem -1= 0x00000000  [corner: overflow rem]
    imem[35] = 32'h0200E533; // REM  x10, x1, x0  = 10 rem 0       = 0x0000000A  [corner: rem/0]

    // ── REMU (unsigned remainder) ─────────────────────────────────────────────
    // Reuse x11..x14
    imem[36] = 32'h022275B3; // REMU x11, x4, x2  = 0x80000000%20  = 0x00000008
    imem[37] = 32'h0211F633; // REMU x12, x3, x1  = 0xFFFFFFFD%10  = 0x00000003
    imem[38] = 32'h0222F6B3; // REMU x13, x5, x2  = 0xFFFFFFFF%20  = 0x0000000F  [corner]
    imem[39] = 32'h0200F733; // REMU x14, x1, x0  = 10 remu 0      = 0x0000000A  [corner: remu/0]

    // Release reset
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n==== RV32M EXTENSION TEST ====\n");

    // ── MUL ──────────────────────────────────────────────────────────────────
    wait_reg( 6, 32'h000000C8, "MUL   10*20=200",                    120);
    wait_reg( 7, 32'hFFFFFFE2, "MUL   10*(-3)=-30",                  120);
    wait_reg( 8, 32'h00000009, "MUL   (-3)*(-3)=9",                  120);
    wait_reg( 9, 32'h00000000, "MUL   INT32_MIN^2 lo=0",             120);
    wait_reg(10, 32'h00000001, "MUL   (-1)*(-1) lo=1      [corner]", 120);

    // ── MULH ─────────────────────────────────────────────────────────────────
    wait_reg(11, 32'h00000000, "MULH  10*20 hi=0",                   120);
    wait_reg(12, 32'hFFFFFFFF, "MULH  10*(-3) hi=-1",                120);
    wait_reg(13, 32'h00000000, "MULH  (-3)*(-3) hi=0",               120);
    wait_reg(14, 32'h40000000, "MULH  INT32_MIN^2 hi=0x40000000",    120);
    wait_reg(15, 32'h00000000, "MULH  (-1)*(-1) hi=0     [corner]",  120);

    // ── MULHU ────────────────────────────────────────────────────────────────
    wait_reg(16, 32'h00000000, "MULHU 10*20 hi=0",                   120);
    wait_reg(17, 32'h40000000, "MULHU 0x80000000^2 hi=0x40000000",   120);
    wait_reg(18, 32'hFFFFFFFA, "MULHU 0xFFFFFFFD^2 hi=0xFFFFFFFA",   120);
    wait_reg(19, 32'hFFFFFFFE, "MULHU 0xFFFFFFFF^2 hi=0xFFFFFFFE [corner]", 120);

    // ── MULHSU ───────────────────────────────────────────────────────────────
    wait_reg(20, 32'h00000000, "MULHSU s(10)*u(20) hi=0",            120);
    wait_reg(21, 32'hFFFFFFFD, "MULHSU s(-3)*u(0xFFFFFFFD) hi",      120);
    wait_reg(22, 32'hC0000000, "MULHSU INT32_MIN*0x80000000 hi",      120);
    wait_reg(23, 32'hFFFFFFFF, "MULHSU s(-1)*u(20) hi=-1  [corner]", 120);

    // ── DIV ──────────────────────────────────────────────────────────────────
    wait_reg(24, 32'h00000000, "DIV   10/20=0",                      200);
    wait_reg(25, 32'h00000002, "DIV   20/10=2",                      200);
    wait_reg(26, 32'h00000000, "DIV   -3/20=0 (trunc toward 0)",     200);
    wait_reg(27, 32'h2AAAAAAA, "DIV   INT32_MIN/-3=715827882",        200);
    wait_reg(28, 32'h80000000, "DIV   INT32_MIN/-1=INT32_MIN [corner: overflow]", 200);
    wait_reg(29, 32'hFFFFFFFF, "DIV   10/0=0xFFFFFFFF      [corner: div/0]",     200);

    // ── DIVU ─────────────────────────────────────────────────────────────────
    wait_reg(30, 32'h00000000, "DIVU  10/20=0",                      200);
    wait_reg(31, 32'h0CCCCCCC, "DIVU  0x80000000/10=0x0CCCCCCC",     200);

    // ── REM ──────────────────────────────────────────────────────────────────
    wait_reg( 6, 32'h0000000A, "REM   10 rem 20=10",                 200);
    wait_reg( 7, 32'hFFFFFFFE, "REM   INT32_MIN rem -3=-2",          200);
    wait_reg( 8, 32'hFFFFFFFD, "REM   -3 rem 20=-3",                 200);
    wait_reg( 9, 32'h00000000, "REM   INT32_MIN rem -1=0  [corner: overflow rem]", 200);
    wait_reg(10, 32'h0000000A, "REM   10 rem 0=10         [corner: rem/0]",        200);

    // ── REMU ─────────────────────────────────────────────────────────────────
    wait_reg(11, 32'h00000008, "REMU  0x80000000%20=8",              200);
    wait_reg(12, 32'h00000003, "REMU  0xFFFFFFFD%10=3",              200);
    wait_reg(13, 32'h0000000F, "REMU  0xFFFFFFFF%20=15   [corner]",  200);
    wait_reg(14, 32'h0000000A, "REMU  10 remu 0=10        [corner: remu/0]", 200);

    // ── x0 hardwired zero ────────────────────────────────────────────────────
    wait_reg( 0, 32'h00000000, "x0 hardwired zero",                   10);

    $display("\n==== TEST COMPLETE ====\n");
    $finish;
end

endmodule