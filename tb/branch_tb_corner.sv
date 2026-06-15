`timescale 1ns/1ps

module branch_tb_corner;

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
            dmem[AWADDR_D[31:2]] <= WDATA_D;
            BVALID_D             <= 1;
            BRESP_D              <= 2'b00;
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

    // Zero out memories
    for (int i = 0; i < 256; i++) begin
        imem[i] = 32'h00000013; // NOP
        dmem[i] = 32'h00000000;
    end

    // ------------------------------------------------------------------
    // Instruction layout - NO NOPs between instructions.
    // Branches skip +8 bytes (one word) over a poison ADDI into a pass ADDI.
    // ADDI x18/x19 immediately before BLTU/BGEU tests forwarding.
    //
    // Setup registers:
    //   x1 = 10, x2 = 10, x3 = 5
    //
    // Test map:
    //   [0]  ADDI x1,  x0, 10
    //   [1]  ADDI x2,  x0, 10
    //   [2]  ADDI x3,  x0, 5
    //
    //   [3]  BEQ  x1,x2, +8   (taken:  x1==x2)
    //   [4]  ADDI x5,  x0, 99  <- poison (skipped)
    //   [5]  ADDI x4,  x0, 1   -> x4 = 1
    //
    //   [6]  BNE  x1,x3, +8   (taken:  x1!=x3)
    //   [7]  ADDI x7,  x0, 99  <- poison (skipped)
    //   [8]  ADDI x6,  x0, 2   -> x6 = 2
    //
    //   [9]  BNE  x1,x2, +8   (not taken: x1==x2, falls through)
    //   [10] ADDI x8,  x0, 3   -> x8 = 3
    //   [11] ADDI x9,  x0, 4   -> x9 = 4
    //
    //   [12] BLT  x3,x1, +8   (taken:  5 < 10 signed)
    //   [13] ADDI x11, x0, 99  <- poison (skipped)
    //   [14] ADDI x10, x0, 5   -> x10 = 5
    //
    //   [15] BLT  x1,x3, +8   (not taken: 10 < 5 false)
    //   [16] ADDI x12, x0, 6   -> x12 = 6
    //   [17] ADDI x13, x0, 7   -> x13 = 7
    //
    //   [18] BGE  x1,x3, +8   (taken:  10 >= 5 signed)
    //   [19] ADDI x15, x0, 99  <- poison (skipped)
    //   [20] ADDI x14, x0, 8   -> x14 = 8
    //
    //   [21] BGE  x3,x1, +8   (not taken: 5 >= 10 false)
    //   [22] ADDI x16, x0, 9   -> x16 = 9
    //   [23] ADDI x17, x0, 10  -> x17 = 10
    //
    //   -- No NOPs here: forwarding must carry x18/x19 into BLTU/BGEU --
    //   [24] ADDI x18, x0, 1
    //   [25] ADDI x19, x0, -1   (0xFFFFFFFF)
    //
    //   [26] BLTU x18,x19, +8  (taken:  1 < 0xFFFFFFFF unsigned)
    //   [27] ADDI x21, x0, 99  <- poison (skipped)
    //   [28] ADDI x20, x0, 11  -> x20 = 11
    //
    //   [29] BGEU x19,x18, +8  (taken:  0xFFFFFFFF >= 1 unsigned)
    //   [30] ADDI x23, x0, 99  <- poison (skipped)
    //   [31] ADDI x22, x0, 12  -> x22 = 12
    // ------------------------------------------------------------------

    imem[ 0] = 32'h00A00093; // ADDI x1,  x0, 10
    imem[ 1] = 32'h00A00113; // ADDI x2,  x0, 10
    imem[ 2] = 32'h00500193; // ADDI x3,  x0, 5

    imem[ 3] = 32'h00208463; // BEQ  x1,x2, +8
    imem[ 4] = 32'h06300293; // ADDI x5,  x0, 99  (poison)
    imem[ 5] = 32'h00100213; // ADDI x4,  x0, 1

    imem[ 6] = 32'h00309463; // BNE  x1,x3, +8
    imem[ 7] = 32'h06300393; // ADDI x7,  x0, 99  (poison)
    imem[ 8] = 32'h00200313; // ADDI x6,  x0, 2

    imem[ 9] = 32'h00209463; // BNE  x1,x2, +8   (not taken)
    imem[10] = 32'h00300413; // ADDI x8,  x0, 3
    imem[11] = 32'h00400493; // ADDI x9,  x0, 4

    imem[12] = 32'h0011C463; // BLT  x3,x1, +8
    imem[13] = 32'h06300593; // ADDI x11, x0, 99  (poison)
    imem[14] = 32'h00500513; // ADDI x10, x0, 5

    imem[15] = 32'h0030C463; // BLT  x1,x3, +8   (not taken)
    imem[16] = 32'h00600613; // ADDI x12, x0, 6
    imem[17] = 32'h00700693; // ADDI x13, x0, 7

    imem[18] = 32'h0030D463; // BGE  x1,x3, +8
    imem[19] = 32'h06300793; // ADDI x15, x0, 99  (poison)
    imem[20] = 32'h00800713; // ADDI x14, x0, 8

    imem[21] = 32'h0011D463; // BGE  x3,x1, +8   (not taken)
    imem[22] = 32'h00900813; // ADDI x16, x0, 9
    imem[23] = 32'h00A00893; // ADDI x17, x0, 10

    imem[24] = 32'h00100913; // ADDI x18, x0, 1
    imem[25] = 32'hFFF00993; // ADDI x19, x0, -1  (0xFFFFFFFF)

    imem[26] = 32'h01396463; // BLTU x18,x19, +8
    imem[27] = 32'h06300A93; // ADDI x21, x0, 99  (poison)
    imem[28] = 32'h00B00A13; // ADDI x20, x0, 11

    imem[29] = 32'h0129F463; // BGEU x19,x18, +8
    imem[30] = 32'h06300B93; // ADDI x23, x0, 99  (poison)
    imem[31] = 32'h00C00B13; // ADDI x22, x0, 12

    // Release reset
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n==== RV32I BRANCH + FORWARDING TEST ====\n");

    // BEQ taken: x4=1, x5 stays 0 (poison skipped)
    wait_reg( 4, 32'd1,  "BEQ  taken  : x4=1",            60);
    wait_reg( 5, 32'd0,  "BEQ  taken  : x5=0 (no poison)", 10);

    // BNE taken: x6=2, x7 stays 0
    wait_reg( 6, 32'd2,  "BNE  taken  : x6=2",            60);
    wait_reg( 7, 32'd0,  "BNE  taken  : x7=0 (no poison)", 10);

    // BNE not taken: x8=3, x9=4
    wait_reg( 8, 32'd3,  "BNE  !taken : x8=3",            60);
    wait_reg( 9, 32'd4,  "BNE  !taken : x9=4",            60);

    // BLT taken: x10=5, x11 stays 0
    wait_reg(10, 32'd5,  "BLT  taken  : x10=5",           60);
    wait_reg(11, 32'd0,  "BLT  taken  : x11=0 (no poison)",10);

    // BLT not taken: x12=6, x13=7
    wait_reg(12, 32'd6,  "BLT  !taken : x12=6",           60);
    wait_reg(13, 32'd7,  "BLT  !taken : x13=7",           60);

    // BGE taken: x14=8, x15 stays 0
    wait_reg(14, 32'd8,  "BGE  taken  : x14=8",           60);
    wait_reg(15, 32'd0,  "BGE  taken  : x15=0 (no poison)",10);

    // BGE not taken: x16=9, x17=10
    wait_reg(16, 32'd9,  "BGE  !taken : x16=9",           60);
    wait_reg(17, 32'd10, "BGE  !taken : x17=10",          60);

    // BLTU taken (forwarding): x20=11, x21 stays 0
    wait_reg(20, 32'd11, "BLTU taken  : x20=11 [fwd]",    60);
    wait_reg(21, 32'd0,  "BLTU taken  : x21=0 (no poison)",10);

    // BGEU taken (forwarding): x22=12, x23 stays 0
    wait_reg(22, 32'd12, "BGEU taken  : x22=12 [fwd]",    60);
    wait_reg(23, 32'd0,  "BGEU taken  : x23=0 (no poison)",10);

    // x0 hardwired zero
    wait_reg( 0, 32'd0,  "x0 hardwired zero",             10);

    $display("\n==== TEST COMPLETE ====\n");
    $finish;
end

endmodule