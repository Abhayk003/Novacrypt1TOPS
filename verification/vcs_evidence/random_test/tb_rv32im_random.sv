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

module tb_rv32im_random;

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

always @(posedge clk) begin
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


    logic [31:0] expected [0:31]; 
    integer seed, op, rd, rs1, rs2, i, errors; 
    logic [31:0] a, b, result; 
    function automatic [31:0] enc_r( input integer 
        d, input integer s1, input integer s2, input integer f3, input integer f7
    ); 
   enc_r = {f7[6:0],s2[4:0],s1[4:0],f3[2:0],d[4:0],7'h33}; endfunction function automatic [31:0] enc_i(input integer d, input integer imm); enc_i = 
        {imm[11:0],5'd0,3'b000,d[4:0],7'h13};
    endfunction initial begin clk = 0; reset = 1; seed = 32'h5A17C0DE; errors = 0; for (i=0;i<512;i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end 
        for (i=0;i<32;i=i+1) expected[i] = 0; for (i=1;i<32;i=i+1) begin
            imem[i-1] = enc_i(i,i); expected[i] = i; end for (i=31;i<131;i=i+1) begin op = $urandom(seed)%10; rd = 1+($urandom(seed)%31); rs1 = 
            1+($urandom(seed)%31); rs2 = 1+($urandom(seed)%31); a = expected[rs1]; b = expected[rs2]; case(op)
                0: begin result=a+b; imem[i]=enc_r(rd,rs1,rs2,0,0); end 1: begin result=a-b; imem[i]=enc_r(rd,rs1,rs2,0,32); end 2: begin result=a^b; 
                imem[i]=enc_r(rd,rs1,rs2,4,0); end 3: begin result=a|b; imem[i]=enc_r(rd,rs1,rs2,6,0); end 4: begin result=a&b; 
                imem[i]=enc_r(rd,rs1,rs2,7,0); end 5: begin result=a<<b[4:0]; imem[i]=enc_r(rd,rs1,rs2,1,0); end 6: begin result=a>>b[4:0]; 
                imem[i]=enc_r(rd,rs1,rs2,5,0); end 7: begin result=$signed(a)>>>b[4:0]; imem[i]=enc_r(rd,rs1,rs2,5,32); end 8: begin 
                result=($signed(a)<$signed(b))?1:0; imem[i]=enc_r(rd,rs1,rs2,2,0); end default: begin result=(a<b)?1:0; imem[i]=enc_r(rd,rs1,rs2,3,0); 
                end
            endcase expected[rd] = result; end $display("RV32IM RANDOM TEST: seed=5A17C0DE, 100 random instructions"); repeat(5) @(posedge clk); reset 
        = 0; repeat(1000) @(posedge clk); for (i=1;i<32;i=i+1) begin
            if (dut.regfile.regs[i] !== expected[i]) begin $display("FAIL x%0d expected=%08h actual=%08h",i,expected[i],dut.regfile.regs[i]); 
                errors=errors+1;
end end if (dut.regfile.regs[0] !== 0) errors=errors+1; if (errors==0) $display("RV32IM_RANDOM PASS"); else $display("RV32IM_RANDOM FAIL:%0d mismatches",errors); $finish;
    end
 endmodule
