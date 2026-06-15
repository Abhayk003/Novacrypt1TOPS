`timescale 1ns/1ps

module datapath_tb_axi4;

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

    // LUI x5, 0x12345
    load_instr(32'h123452B7);
    load_instr(32'h00000013); // NOP
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // AUIPC x6, 0x10
    load_instr(32'h00010317);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // ADDI x1, x0, 10
    load_instr(32'h00A00093);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SLTI x7, x1, 20
    load_instr(32'h0140A393);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // XORI x8, x1, 0xFF
    load_instr(32'h0FF0C413);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // ORI x9, x1, 0xFF
    load_instr(32'h0FF0E493);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // ANDI x10, x1, 0xFF
    load_instr(32'h0FF0F513);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SLLI x2, x1, 1
    load_instr(32'h00109113);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SRLI x3, x1, 1
    load_instr(32'h0010D193);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SRAI x4, x1, 1
    load_instr(32'h4010D213);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // ADD x11, x1, x1
    load_instr(32'h001085B3);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SUB x12, x1, x1
    load_instr(32'h40108633);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // AND x13, x1, x12 (x12=0 so result=0)
    load_instr(32'h0010F6B3);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // OR x14, x12, x12 (x12=0 so result=0)
    load_instr(32'h0010E733);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // XOR x15, x12, x12 (x12=0 so result=0)
    load_instr(32'h0010C7B3);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // LW x16, 0(x0)
    load_instr(32'h00002803);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);

    // SW x16, 0(x0)
   // load_instr(32'h01002023);
 // SW x16, 12(x0)
    load_instr(32'h01002623);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    load_instr(32'h00000013);
    
    // BEQ x1,x1,+16 - x1=10 so always taken
    // branch skips over 3 instructions to land on ADDI x28,x0,1
    imem[imem_ptr]   = 32'h00808663; // BEQ x1,x1,+16
    imem[imem_ptr+1] = 32'h00000013; // NOP (skipped if branch taken)
    imem[imem_ptr+2] = 32'h00000013; // NOP (skipped)
    imem[imem_ptr+3] = 32'h00000013; // NOP (skipped)
    imem[imem_ptr+4] = 32'h00100e13; // ADDI x28,x0,1 ← branch target
    imem[imem_ptr+5] = 32'h00000013;
    imem[imem_ptr+6] = 32'h00000013;
    imem[imem_ptr+7] = 32'h00000013;
    
    // JAL x29,+8 - jumps forward 8 bytes, x29=pc+4
    imem[imem_ptr+8]  = 32'h0080_0EEF; // JAL x29,+8
    imem[imem_ptr+9]  = 32'h00000013;  // NOP (skipped)
    imem[imem_ptr+10] = 32'h00100F13;  // ADDI x30,x0,1 ← JAL target
    imem[imem_ptr+11] = 32'h00000013;
    imem[imem_ptr+12] = 32'h00000013;
    imem[imem_ptr+13] = 32'h00000013;
    imem[imem_ptr+14] = 32'h00000013;
    imem[imem_ptr+15] = 32'h00000013;
    // imem_ptr+16 = NOP gap (keep separation from JAL block)
    imem[imem_ptr+16] = 32'h00000013;

    // ── JALR1 starts at imem_ptr+17 ───────────────────────────────────────
    // AUIPC x20, 0       → x20 = byte address of this instruction (BASE)
    // ADDI  x20, x20, 8  → x20 = BASE + 8 (byte addr of target at +19+2=imem_ptr+21)
    // Wait - recalculate:
    //   AUIPC at imem_ptr+17 → byte addr = (imem_ptr+17)*4
    //   JALR  at imem_ptr+19 → byte addr = (imem_ptr+17)*4 + 8
    //   target at imem_ptr+21 → byte addr = (imem_ptr+17)*4 + 16
    //   So ADDI immediate = 16
    imem[imem_ptr+17] = 32'h00000A17; // AUIPC x20, 0
    imem[imem_ptr+18] = 32'h010A0A13; // ADDI  x20, x20, 16
    imem[imem_ptr+19] = 32'h000A0AE7; // JALR  x21, x20, 0
    imem[imem_ptr+20] = 32'h00200013; // NOP sentinel-A ← must be SKIPPED
    // target lands here:
    imem[imem_ptr+21] = 32'h00100B13; // ADDI x22, x0, 1 ← JALR1 target
    imem[imem_ptr+22] = 32'h00000013; // NOP
    imem[imem_ptr+23] = 32'h00000013; // NOP
    imem[imem_ptr+24] = 32'h00000013; // NOP

    // ── JALR2 (no-forwarding stress) starts at imem_ptr+25 ────────────────
    // AUIPC x23, 0       → x23 = byte addr of imem_ptr+25
    // 3 NOPs             → x23 fully in regfile, no forwarding
    // ADDI  x23, x23, 48 → x23 = (imem_ptr+25)*4 + 48 = byte addr of imem_ptr+37
    // 3 NOPs             → x23 re-settled after ADDI
    // JALR  x24, x23, 0  → jump to imem_ptr+37, link x24 = JALR_PC + 4
    // imem_ptr+33        → sentinel ADDI x25,x0,2, must be SKIPPED
    // imem_ptr+37        → target ADDI x26,x0,1, must execute
    //
    // Offset math:
    //   AUIPC at +25, target at +37 → distance = 12 words = 48 bytes ✓
    imem[imem_ptr+25] = 32'h00000B97; // AUIPC x23, 0
    imem[imem_ptr+26] = 32'h00000013; // NOP
    imem[imem_ptr+27] = 32'h00000013; // NOP
    imem[imem_ptr+28] = 32'h00000013; // NOP
    imem[imem_ptr+29] = 32'h030B8B93; // ADDI  x23, x23, 48
    imem[imem_ptr+30] = 32'h00000013; // NOP
    imem[imem_ptr+31] = 32'h00000013; // NOP
    imem[imem_ptr+32] = 32'h00000013; // NOP
    imem[imem_ptr+33] = 32'h000B8C67; // JALR  x24, x23, 0
    imem[imem_ptr+34] = 32'h00200C93; // ADDI  x25, x0, 2 ← sentinel, must be SKIPPED
    imem[imem_ptr+35] = 32'h00000013; // NOP
    imem[imem_ptr+36] = 32'h00000013; // NOP
    imem[imem_ptr+37] = 32'h00100D13; // ADDI  x26, x0, 1 ← JALR2 target
    imem[imem_ptr+38] = 32'h00000013; // NOP
    imem[imem_ptr+39] = 32'h00000013; // NOP
    imem[imem_ptr+40] = 32'h00000013; // NOP
    
    
    imem[imem_ptr+41] = 32'h0140BD93;  // SLTIU x27, x1, 20  → expect 1  (10 <u 20)
    imem[imem_ptr+42] = 32'h00000013;  // NOP
    imem[imem_ptr+43] = 32'h00000013;  // NOP
    imem[imem_ptr+44] = 32'h00000013;  // NOP

    imem[imem_ptr+45] = 32'h0050BE13;  // SLTIU x28, x1, 5   → expect 0  (10 <u 5 false)
    imem[imem_ptr+46] = 32'h00000013;
    imem[imem_ptr+47] = 32'h00000013;
    imem[imem_ptr+48] = 32'h00000013;

    imem[imem_ptr+49] = 32'h00A0BE93;  // SLTIU x29, x1, 10  → expect 0  (equal, not less)
    imem[imem_ptr+50] = 32'h00000013;
    imem[imem_ptr+51] = 32'h00000013;
    imem[imem_ptr+52] = 32'h00000013;

    imem[imem_ptr+53] = 32'h00500193;  // ADDI x3, x0, 5     (reload x3=5)
    imem[imem_ptr+54] = 32'h00000013;
    imem[imem_ptr+55] = 32'h00000013;
    imem[imem_ptr+56] = 32'h00000013;

    imem[imem_ptr+57] = 32'h0011BF33;  // SLTU x30, x3, x1   → expect 1  (5 <u 10)
    imem[imem_ptr+58] = 32'h00000013;
    imem[imem_ptr+59] = 32'h00000013;
    imem[imem_ptr+60] = 32'h00000013;

    imem[imem_ptr+61] = 32'h0030BFB3;  // SLTU x31, x1, x3   → expect 0  (10 <u 5 false)
    imem[imem_ptr+62] = 32'h00000013;
    imem[imem_ptr+63] = 32'h00000013;
    imem[imem_ptr+64] = 32'h00000013;
    
    // ── LW (word) ── already tested above with x16, keeping for reference
// ── LH (load halfword signed) ──────────────────────────────────────────
// LH x17, 4(x0)  → reads dmem[1] lower halfword = 0x1234 → sign-extend → 0x00001234
imem[imem_ptr+65] = 32'h00401883;  // LH x17, 4(x0)
imem[imem_ptr+66] = 32'h00000013;
imem[imem_ptr+67] = 32'h00000013;
imem[imem_ptr+68] = 32'h00000013;

// LH x18, 6(x0)  → reads dmem[1] upper halfword = 0xABCD → sign-extend → 0xFFFFABCD
imem[imem_ptr+69] = 32'h00601903;  // LH x18, 6(x0)
imem[imem_ptr+70] = 32'h00000013;
imem[imem_ptr+71] = 32'h00000013;
imem[imem_ptr+72] = 32'h00000013;

// ── LHU (load halfword unsigned) ───────────────────────────────────────
// LHU x19, 6(x0) → reads dmem[1] upper halfword = 0xABCD → zero-extend → 0x0000ABCD
imem[imem_ptr+73] = 32'h00605983;  // LHU x19, 6(x0)
imem[imem_ptr+74] = 32'h00000013;
imem[imem_ptr+75] = 32'h00000013;
imem[imem_ptr+76] = 32'h00000013;

// ── LB (load byte signed) ──────────────────────────────────────────────
// LB x20, 8(x0)  → reads dmem[2] byte0 = 0x80 → sign-extend → 0xFFFFFF80
imem[imem_ptr+77] = 32'h00800A03;  // LB x20, 8(x0)
imem[imem_ptr+78] = 32'h00000013;
imem[imem_ptr+79] = 32'h00000013;
imem[imem_ptr+80] = 32'h00000013;

// LB x21, 9(x0)  → reads dmem[2] byte1 = 0x7F → sign-extend → 0x0000007F
imem[imem_ptr+81] = 32'h00900A83;  // LB x21, 9(x0)
imem[imem_ptr+82] = 32'h00000013;
imem[imem_ptr+83] = 32'h00000013;
imem[imem_ptr+84] = 32'h00000013;

// ── LBU (load byte unsigned) ───────────────────────────────────────────
// LBU x22, 8(x0) → reads dmem[2] byte0 = 0x80 → zero-extend → 0x00000080
imem[imem_ptr+85] = 32'h00804B03;  // LBU x22, 8(x0)
imem[imem_ptr+86] = 32'h00000013;
imem[imem_ptr+87] = 32'h00000013;
imem[imem_ptr+88] = 32'h00000013;

// ── SB ─────────────────────────────────────────────────────────────────
// x1=10(0x0A), x2=20(0x14) from earlier tests

// SB x1, 32(x0)  → write 0x0A to byte addr 32 → dmem[8] byte0
imem[imem_ptr+89]  = 32'h02100023;  // SB x1, 32(x0)
imem[imem_ptr+90]  = 32'h00000013;
imem[imem_ptr+91]  = 32'h00000013;
imem[imem_ptr+92]  = 32'h00000013;

// LBU x23, 32(x0) → expect 0x0000000A
imem[imem_ptr+93]  = 32'h02004B83;  // LBU x23, 32(x0)
imem[imem_ptr+94]  = 32'h00000013;
imem[imem_ptr+95]  = 32'h00000013;
imem[imem_ptr+96]  = 32'h00000013;

// SB x1, 33(x0)  → write 0x0A to byte addr 33 → dmem[8] byte1
imem[imem_ptr+97]  = 32'h021000A3;  // SB x1, 33(x0)
imem[imem_ptr+98]  = 32'h00000013;
imem[imem_ptr+99]  = 32'h00000013;
imem[imem_ptr+100] = 32'h00000013;

// LBU x24, 33(x0) → expect 0x0000000A
imem[imem_ptr+101] = 32'h02104C03;  // LBU x24, 33(x0)
imem[imem_ptr+102] = 32'h00000013;
imem[imem_ptr+103] = 32'h00000013;
imem[imem_ptr+104] = 32'h00000013;

// ── SH ─────────────────────────────────────────────────────────────────

// SH x2, 36(x0)  → write 0x0014 to byte addr 36 → dmem[9] lower half
imem[imem_ptr+105] = 32'h02201223;  // SH x2, 36(x0)
imem[imem_ptr+106] = 32'h00000013;
imem[imem_ptr+107] = 32'h00000013;
imem[imem_ptr+108] = 32'h00000013;

// LHU x25, 36(x0) → expect 0x00000014
imem[imem_ptr+109] = 32'h02405C83;  // LHU x25, 36(x0)
imem[imem_ptr+110] = 32'h00000013;
imem[imem_ptr+111] = 32'h00000013;
imem[imem_ptr+112] = 32'h00000013;

// SH x2, 38(x0)  → write 0x0014 to byte addr 38 → dmem[9] upper half
imem[imem_ptr+113] = 32'h02201323;  // SH x2, 38(x0)
imem[imem_ptr+114] = 32'h00000013;
imem[imem_ptr+115] = 32'h00000013;
imem[imem_ptr+116] = 32'h00000013;

// LHU x26, 38(x0) → expect 0x00000014
imem[imem_ptr+117] = 32'h02605D03;  // LHU x26, 38(x0)
imem[imem_ptr+118] = 32'h00000013;
imem[imem_ptr+119] = 32'h00000013;
imem[imem_ptr+120] = 32'h00000013;


    imem_ptr = imem_ptr + 121;
    
    // Fill rest with NOPs
    while (imem_ptr < 256) begin
        imem[imem_ptr] = 32'h00000013;
        imem_ptr = imem_ptr + 1;
    end

    // Release reset
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n==== RV32I AXI4 DATAPATH TEST ====\n");

    // LUI x5, 0x12345 → expect 0x12345000
    wait_reg(5, 32'h12345000, "LUI", 20);

    // AUIPC x6 → expect nonzero
    wait_nonzero_reg(6, "AUIPC", 40);

    // ADDI x1, x0, 10 → expect 10
    wait_reg(1, 32'd10, "ADDI", 20);

    // SLTI x7, x1, 20 → expect 1
    wait_reg(7, 32'd1, "SLTI", 20);

    // XORI x8 → expect nonzero
    wait_nonzero_reg(8, "XORI", 20);

    // ORI x9 → expect nonzero
    wait_nonzero_reg(9, "ORI", 20);

    // ANDI x10 → expect nonzero
    wait_nonzero_reg(10, "ANDI", 20);

    // SLLI x2, x1, 1 → expect 20
    wait_reg(2, 32'd20, "SLLI", 20);

    // SRLI x3, x1, 1 → expect 5
    wait_reg(3, 32'd5, "SRLI", 20);

    // SRAI x4, x1, 1 → expect 5
    wait_reg(4, 32'd5, "SRAI", 20);

    // ADD x11 → expect 20
    wait_reg(11, 32'd20, "ADD", 20);

    // SUB x12 → expect 0
    wait_reg(12, 32'd0, "SUB", 20);

    // AND x13 → expect 0
    wait_reg(13, 32'd0, "AND", 20);

    // OR x14 → expect 0
    wait_reg(14, 32'd0, "OR", 20);

    // XOR x15 → expect 0
    wait_reg(15, 32'd0, "XOR", 20);

    // LW x16 → expect 0xDEADBEEF
    wait_reg(16, 32'hDEADBEEF, "LW", 40);

    // SW: check dmem[0] was written with 0xDEADBEEF
    repeat(10) @(posedge clk);
    if (dmem[3] === 32'hDEADBEEF)
        $display("SW PASS");
    else
        $display("SW FAIL (dmem[0]=%h)", dmem[0]);
        // BEQ taken - x28 should be 1
    wait_reg(28, 32'd1, "BEQ", 40);
    
    // JAL taken - x30 should be 1
    wait_reg(30, 32'd1, "JAL", 40);
    
    // JAL link - x29 should be pc+4 of JAL instruction, nonzero
    wait_nonzero_reg(29, "JAL LINK", 60);
    
    // JALR1: target executed - x22 must be 1
    wait_reg(22, 32'd1, "JALR", 40);

    // JALR1: link - x21 must be nonzero (= JALR_PC + 4)
    wait_nonzero_reg(21, "JALR LINK", 40);

    // JALR2: target executed - x26 must be 1
    wait_reg(26, 32'd1, "JALR2 TARGET", 40);

    // JALR2: link - x24 must be nonzero
    wait_nonzero_reg(24, "JALR2 LINK", 40);

    // JALR2: sentinel must not have run - x25 must stay 0
    wait_reg(25, 32'd0, "JALR2 SKIP", 10);
    
    wait_reg(27, 32'd1, "SLTIU (true)",  20);  // 10 <u 20 = 1
    wait_reg(28, 32'd0, "SLTIU (false)", 20);  // 10 <u 5  = 0
    wait_reg(29, 32'd0, "SLTIU (equal)", 20);  // 10 <u 10 = 0
    wait_reg(30, 32'd1, "SLTU (true)",   20);  // 5  <u 10 = 1
    wait_reg(31, 32'd0, "SLTU (false)",  20);  // 10 <u 5  = 0
    
    // ── Load variant checks ────────────────────────────────────────────────
// LH: lower halfword 0x1234 - positive, so sign-extension leaves it unchanged
wait_reg(17, 32'h00001234, "LH (positive)", 40);

// LH: upper halfword 0xABCD - MSB set, sign-extension fills upper 16 bits with 1s
wait_reg(18, 32'hFFFFABCD, "LH (negative sign-ext)", 40);

// LHU: upper halfword 0xABCD - zero-extended, upper 16 bits stay 0
wait_reg(19, 32'h0000ABCD, "LHU (zero-ext)", 40);

// LB: byte0 = 0x80 - MSB set, sign-extension fills upper 24 bits with 1s
wait_reg(20, 32'hFFFFFF80, "LB (negative sign-ext)", 40);

// LB: byte1 = 0x7F - positive, sign-extension leaves it unchanged
wait_reg(21, 32'h0000007F, "LB (positive)", 40);

// LBU: byte0 = 0x80 - zero-extended, always positive result
wait_reg(22, 32'h00000080, "LBU (zero-ext)", 40);

// SB readbacks
wait_reg(23, 32'h0000000A, "SB byte0 readback", 40);
wait_reg(24, 32'h0000000A, "SB byte1 readback", 40);

// Direct dmem check - byte0 and byte1 both 0x0A, bytes 2&3 untouched (0x00)
repeat(5) @(posedge clk);
if (dmem[8] === 32'h00000a0a)
    $display("SB dmem isolation PASS");
else
    $display("SB dmem isolation FAIL (got %h, expected 00000A0A)", dmem[8]);

// SH readbacks
wait_reg(25, 32'h00000014, "SH lower-half readback", 40);
wait_reg(26, 32'h00000014, "SH upper-half readback",  40);

// Direct dmem check - lower half=0x0014, upper half=0x0014
repeat(5) @(posedge clk);
if (dmem[9] === 32'h00140014)
    $display("SH dmem isolation PASS");
else
    $display("SH dmem isolation FAIL (got %h, expected 00140014)", dmem[9]);

    // x0 protection
    wait_reg(0, 32'd0, "X0 PROTECTION", 10);

    $display("\n==== TEST COMPLETE ====\n");
    $finish;

end

endmodule