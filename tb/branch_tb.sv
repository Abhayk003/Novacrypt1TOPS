`timescale 1ns/1ps
// Tests branch instructions one by one
module branch_tb;

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
        if (AWVALID_D && WVALID_D) begin
            dmem[AWADDR_D[31:2]] <= WDATA_D;
            BVALID_D             <= 1;
            BRESP_D              <= 2'b00;
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
//                     $display("branch_taken=%b opcode=%b pc=%h",
//         dut.execute_stage.branch_taken,
//         dut.ifid_ex_r.opcode,
//         dut.ifid_ex_r.pc);
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

    // Load instruction sequence into imem
    // Each instruction needs to be followed by 3 NOPs minimum
    // to clear the pipeline before checking result
    // (pipeline is 3 stages: IF→EX→WB)

imem_ptr = 0;

//// x1 = 10
//load_instr(32'h00A00093); // ADDI x1,x0,10
//load_instr(32'h00000013);
//load_instr(32'h00000013);
//load_instr(32'h00000013);

//// x2 = 10
//load_instr(32'h00A00113); // ADDI x2,x0,10
//load_instr(32'h00000013);
//load_instr(32'h00000013);
//load_instr(32'h00000013);

//// x3 = 5
//load_instr(32'h00500193); // ADDI x3,x0,5
//load_instr(32'h00000013);
//load_instr(32'h00000013);
//load_instr(32'h00000013);

//// BEQ x1,x2,+8 (taken)
//imem[imem_ptr]   = 32'h00208463;
////imem[imem_ptr] = 32'h00308463; // BEQ x1,x3,+8
////imem[imem_ptr+1] = 32'h00000013; // skipped
//imem[imem_ptr+1] = 32'h00200293; // ADDI x5,x0,2
//imem[imem_ptr+2] = 32'h00100213; // ADDI x4,x0,1
//imem[imem_ptr+3] = 32'h00000013;

//imem_ptr += 4;

// --------------------------------------------------
// BRANCH TESTS
// --------------------------------------------------

// x1 = 10
load_instr(32'h00A00093); // ADDI x1,x0,10
load_instr(32'h00000013);
load_instr(32'h00000013);
load_instr(32'h00000013);

// x2 = 10
load_instr(32'h00A00113); // ADDI x2,x0,10
load_instr(32'h00000013);
load_instr(32'h00000013);
load_instr(32'h00000013);

// x3 = 5
load_instr(32'h00500193); // ADDI x3,x0,5
load_instr(32'h00000013);
load_instr(32'h00000013);
load_instr(32'h00000013);

// ==================================================
// BEQ  (taken)
// ==================================================
//imem[imem_ptr]   = 32'h00208463; // BEQ x1,x2,+8
//imem[imem_ptr+1] = 32'h00200293; // ADDI x5,x0,2 (skipped)
//imem[imem_ptr+2] = 32'h00100213; // ADDI x4,x0,1
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

// Expected:
// x4 = 1
// x5 = 0


// ==================================================
// BNE (taken)
// ==================================================
//imem[imem_ptr]   = 32'h00309463; // BNE x1,x3,+8
//imem[imem_ptr+1] = 32'h00300313; // ADDI x6,x0,3 (skipped)
//imem[imem_ptr+2] = 32'h00400393; // ADDI x7,x0,4
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x6 = 0
//// x7 = 4


//// ==================================================
//// BNE (not taken)
//// ==================================================
//imem[imem_ptr]   = 32'h00209463; // BNE x1,x2,+8
//imem[imem_ptr+1] = 32'h00500413; // ADDI x8,x0,5
//imem[imem_ptr+2] = 32'h00600493; // ADDI x9,x0,6
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x8 = 5
//// x9 = 6


//// ==================================================
//// BLT (taken)
//// 5 < 10
//// ==================================================
//imem[imem_ptr]   = 32'h0021C463; // BLT x3,x2,+8
//imem[imem_ptr+1] = 32'h00700513; // ADDI x10,x0,7 (skipped)
//imem[imem_ptr+2] = 32'h00800593; // ADDI x11,x0,8
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x10 = 0
//// x11 = 8


//// ==================================================
//// BLT (not taken)
//// 10 < 5 false
//// ==================================================
//imem[imem_ptr]   = 32'h0030C463; // BLT x1,x3,+8
//imem[imem_ptr+1] = 32'h00900613; // ADDI x12,x0,9
//imem[imem_ptr+2] = 32'h00A00693; // ADDI x13,x0,10
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x12 = 9
//// x13 = 10


//// ==================================================
//// BGE (taken)
//// 10 >= 5
//// ==================================================
//imem[imem_ptr]   = 32'h0030D463; // BGE x1,x3,+8
//imem[imem_ptr+1] = 32'h00B00713; // ADDI x14,x0,11 (skipped)
//imem[imem_ptr+2] = 32'h00C00793; // ADDI x15,x0,12
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x14 = 0
//// x15 = 12


//// ==================================================
//// BGE (not taken)
//// 5 >= 10 false
//// ==================================================
//imem[imem_ptr]   = 32'h0021D463; // BGE x3,x2,+8
//imem[imem_ptr+1] = 32'h00D00813; // ADDI x16,x0,13
//imem[imem_ptr+2] = 32'h00E00893; // ADDI x17,x0,14
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

//// Expected:
//// x16 = 13
//// x17 = 14


//// ==================================================
//// BLTU (taken)
//// x18 = 1
//// x19 = FFFFFFFF
//// ==================================================
load_instr(32'h00100913); // ADDI x18,x0,1
load_instr(32'hFFF00993); // ADDI x19,x0,-1

imem[imem_ptr]   = 32'h01396463; // BLTU x18,x19,+8
imem[imem_ptr+1] = 32'h00F00A13; // ADDI x20,x0,15 (skipped)
imem[imem_ptr+2] = 32'h01000A93; // ADDI x21,x0,16
imem[imem_ptr+3] = 32'h00000013;
imem_ptr += 4;

//// Expected:
//// x20 = 0
//// x21 = 16


//// ==================================================
//// BGEU (taken)
//// FFFFFFFF >= 1 (unsigned)
//// ==================================================
//imem[imem_ptr]   = 32'h0129F463; // BGEU x19,x18,+8
//imem[imem_ptr+1] = 32'h01100B13; // ADDI x22,x0,17 (skipped)
//imem[imem_ptr+2] = 32'h01200B93; // ADDI x23,x0,18
//imem[imem_ptr+3] = 32'h00000013;
//imem_ptr += 4;

// Expected:
// x22 = 0
// x23 = 18


    // Fill rest with NOPs
    while (imem_ptr < 256) begin
        imem[imem_ptr] = 32'h00000013;
        imem_ptr = imem_ptr + 1;
    end

    // Release reset
    repeat(5) @(posedge clk);
    reset = 0;

    $display("\n==== RV32I AXI4 DATAPATH TEST ====\n");

//wait_reg(4 , 32'd1 , "BEQ TAKEN"      , 50);
//wait_reg(7 , 32'd4 , "BNE TAKEN"      , 50);
//wait_reg(8 , 32'd5 , "BNE NOT TAKEN"  , 50);
//wait_reg(9 , 32'd6 , "BNE NOT TAKEN2" , 50);

//wait_reg(11, 32'd8 , "BLT TAKEN"      , 50);
//wait_reg(12, 32'd9 , "BLT NOT TAKEN"  , 50);
//wait_reg(13, 32'd10, "BLT NOT TAKEN2" , 50);

//wait_reg(15, 32'd12, "BGE TAKEN"      , 50);
//wait_reg(16, 32'd13, "BGE NOT TAKEN"  , 50);
//wait_reg(17, 32'd14, "BGE NOT TAKEN2" , 50);

wait_reg(21, 32'd16, "BLTU TAKEN"     , 50);
//wait_reg(23, 32'd18, "BGEU TAKEN"     , 50);
    // x0 protection
    wait_reg(0, 32'd0, "X0 PROTECTION", 10);

    $display("\n==== TEST COMPLETE ====\n");
    $finish;

end

endmodule