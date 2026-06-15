`timescale 1ns / 1ps

module top_module (
    input logic clk,
    input logic reset,

    // AXI4 Instruction Bus (AR + R only)
    output logic [31:0] ARADDR_I,
    output logic [7:0]  ARLEN_I,
    output logic [2:0]  ARSIZE_I,
    output logic [1:0]  ARBURST_I,
    output logic        ARVALID_I,
    input  logic        ARREADY_I,

    input  logic [31:0] RDATA_I,
    input  logic        RVALID_I,
    input  logic        RLAST_I,
    input  logic [1:0]  RRESP_I,
    output logic        RREADY_I,

    // AXI4 Data Bus (AR + R + AW + W + B)
    output logic [31:0] ARADDR_D,
    output logic        ARVALID_D,
    input  logic        ARREADY_D,

    input  logic [31:0] RDATA_D,
    input  logic        RVALID_D,
    input  logic [1:0]  RRESP_D,
    output logic        RREADY_D,

    output logic [31:0] AWADDR_D,
    output logic        AWVALID_D,
    input  logic        AWREADY_D,

    output logic [31:0] WDATA_D,
    output logic [3:0]  WSTRB_D,
    output logic        WVALID_D,
    input  logic        WREADY_D,

    input  logic [1:0]  BRESP_D,
    input  logic        BVALID_D,
    output logic        BREADY_D,

    // Interrupt inputs (from CLINT/PLIC), level active-high
    input  logic        irq_timer_i,
    input  logic        irq_software_i,
    input  logic        irq_external_i
);

// Internal memory interface
logic [31:0] fetch_instr;
logic        fetch_valid;

logic [31:0] fifo_instr;
logic        fifo_valid;
logic        consume;
logic [3:0]  fifo_count;

logic [31:0] dmem_addr;
logic [31:0] dmem_wdata;
logic        dmem_we;
logic        dmem_re;
logic [31:0] dmem_rdata;
logic        dmem_rvalid;
logic        dmem_stall;
logic mul_en;
logic mul_busy;
logic mul_done;
logic mul_stall;
logic div_en;
logic div_busy;
logic div_done;
logic div_stall;

assign dmem_stall = ex_memwb_r.mem_read && !dmem_rvalid;

// Store completion tracking: a store stalls the pipeline until its B response
// arrives. Prevents dropped/overwritten writes when a slow slave (e.g. APB
// peripheral behind the bridge) back-pressures the write channel.
logic store_inflight;
logic store_stall;
assign store_stall = dmem_we && !(store_inflight && BVALID_D);

// Pipeline structs
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] immediate;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [11:0] csr_addr;
} ifid_ex_t;

typedef struct packed {
    logic [31:0] ex_result;
    logic [4:0]  rd_ex;
    logic [31:0] mem_address;
    logic [31:0] mem_write_data;
    logic        mem_read;
    logic        mem_write;
    logic        ex_memread;
    logic [2:0]  funct3; // added this for lw variants
    logic        reg_write;
} ex_memwb_t;

ifid_ex_t  ifid_ex_r,  ifid_ex_n, ifid_ex_next;
ex_memwb_t ex_memwb_r, ex_memwb_n, ex_memwb_next;

//ifid_ex_t  ifid_ex_next;
//ex_memwb_t ex_memwb_next;

// IF/ID signals
logic [31:0] pc;
logic [4:0]  rs1, rs2, rd;
logic [31:0] immediate;
logic [6:0]  opcode;
logic [2:0]  funct3;
logic [6:0]  funct7;
logic [11:0] csr_addr;
logic [31:0] branch_immediate;
logic [31:0] jalr_target;
logic        jalr_taken;
logic        stall;

// EX signals
logic [31:0] mem_address;
logic [31:0] mem_write_data;
logic        mem_read;
logic        mem_write;
logic [31:0] ex_result;
logic [4:0]  rd_ex;
logic        ex_regwrite;
logic        forwardA;
logic        forwardB;
logic        branch_taken;
logic        trap_taken;
logic [31:0] trap_target;
logic        mret_taken;
logic [31:0] mret_target;
// Any control-flow redirect (branch/jump/trap/mret) flushes + resteers PC.
logic        redirect;
logic [31:0] redirect_target;
assign redirect        = branch_taken || jalr_taken || trap_taken || mret_taken;
assign redirect_target = trap_taken   ? trap_target :
                         mret_taken    ? mret_target :
                         branch_taken  ? branch_immediate :
                         jalr_taken    ? jalr_target : pc;
logic        ex_memread;

// Register file signals
logic [31:0] rs1_data, rs2_data;
logic [31:0] reg_wdata;
logic [4:0]  reg_waddr;
logic        reg_we;

// Prefetch buffer
prefetch_buffer instr_fifo (
    .clk(clk),
    .reset(reset),
    .instr_in(fetch_instr),
    .instr_valid(fetch_valid),
    .consume(consume),
    .instr_out(fifo_instr),
    .instr_available(fifo_valid),
    .flush(redirect),
    .fifo_count(fifo_count)
);

// Prefetch controller (AXI4)
prefetch_controller fetch_unit (
    .clk(clk),
    .reset(reset),
    .branch_immediate(redirect_target),
    .fifo_count(fifo_count),
    .branch_taken(redirect),
    .ARADDR(ARADDR_I),
    .ARLEN(ARLEN_I),
    .ARSIZE(ARSIZE_I),
    .ARBURST(ARBURST_I),
    .ARVALID(ARVALID_I),
    .ARREADY(ARREADY_I),
    .RDATA(RDATA_I),
    .RVALID(RVALID_I),
    .RLAST(RLAST_I),
    .RRESP(RRESP_I),
    .RREADY(RREADY_I),
    .instr_out(fetch_instr),
    .instr_valid(fetch_valid)
);

// IF/ID stage
if_id if_id_stage (
    .clk(clk),
    .reset(reset),
    .instr_in(fifo_instr),
    .instr_valid(fifo_valid),
    .consume(consume),
    .pc(pc),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .immediate(immediate),
    .opcode(opcode),
    .funct3(funct3),
    .funct7(funct7),
    .csr_addr(csr_addr),
    .stall(stall || dmem_stall || store_stall),
    .branch_taken(redirect),
    .branch_immediate(redirect_target),
    .jalr_target(redirect_target),
    .jalr_taken(redirect)
);

// Register file
registers regfile (
    .clk(clk),
    .reset(reset),
    .rs1(ifid_ex_r.rs1),
    .rs2(ifid_ex_r.rs2),
    .rd(reg_waddr),
    .write_data(reg_wdata),
    .reg_write(reg_we),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

// Execute stage
ex execute_stage (
    .clk(clk),
    .reset(reset),
    .pc(ifid_ex_r.pc),
    .rs1(ifid_ex_r.rs1),
    .rs2(ifid_ex_r.rs2),
    .reg_rdata1(rs1_data),
    .reg_rdata2(rs2_data),
    .immediate(ifid_ex_r.immediate),
    .funct3(ifid_ex_r.funct3),
    .funct7(ifid_ex_r.funct7),
    .opcode(ifid_ex_r.opcode),
    .rd_i(ifid_ex_r.rd),
    .rd_o(rd_ex),
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .csr_addr(ifid_ex_r.csr_addr),
    .ex_result(ex_result),
    .ex_regwrite(ex_regwrite),
    .ex_memread(ex_memread),
    .stall(stall || dmem_stall || store_stall),
    .forwardA(forwardA),
    .forwardB(forwardB),
    //.ex_forward(ex_memwb_r.ex_result),
    .ex_forward(reg_wdata),
    .branch_taken(branch_taken),
    .branch_immediate(branch_immediate),
    .jalr_target(jalr_target),
    .jalr_taken(jalr_taken),
    .mul_stall(mul_stall),
    .div_stall(div_stall),
    .mul_en(mul_en),
    .mul_busy(mul_busy),
    .mul_done(mul_done),
    .div_en(div_en),
    .div_busy(div_busy),
    .div_done(div_done),
    .irq_timer_i(irq_timer_i),
    .irq_software_i(irq_software_i),
    .irq_external_i(irq_external_i),
    .trap_taken_o(trap_taken),
    .trap_target_o(trap_target),
    .mret_taken_o(mret_taken),
    .mret_target_o(mret_target)
);

// MEM/WB stage
mem_wb memwb_stage (
    .clk(clk),
    .reset(reset),
    .ex_result(ex_memwb_r.ex_result),
    .mem_address(ex_memwb_r.mem_address),
    .mem_write_data(ex_memwb_r.mem_write_data),
    .mem_read(ex_memwb_r.mem_read),
    .mem_write(ex_memwb_r.mem_write),
    .rd(ex_memwb_r.rd_ex),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_we(dmem_we),
    .dmem_re(dmem_re),
    .dmem_rdata(dmem_rdata),
    .dmem_rvalid(dmem_rvalid),
    .reg_waddr(reg_waddr),
    .reg_wdata(reg_wdata),
    .reg_we(reg_we),
    .reg_write(ex_memwb_r.reg_write),
    .funct3(ex_memwb_r.funct3)//added for lw variantss
);

// Hazard unit
hazard_unit hazard_unit (
    .reset(reset),
    .id_rs1(ifid_ex_r.rs1),
    .id_rs2(ifid_ex_r.rs2),
    .ex_rd(ex_memwb_r.rd_ex),
    .ex_memread(ex_memwb_r.ex_memread),
    //.ex_regwrite(ex_regwrite),
    .ex_regwrite(ex_memwb_r.reg_write),
    .mem_rd(ex_memwb_r.rd_ex),
    .mem_memread(ex_memwb_r.mem_read),
    .stall(stall),
    .forwardA(forwardA),
    .forwardB(forwardB),
    .mul_stall(mul_stall),
    .div_stall(div_stall),
    // Add to hazard_unit instantiation:
.dmem_rvalid(dmem_rvalid)
);
logic dbus_read_issued;

always_ff @(posedge clk) begin
    if (reset)
        dbus_read_issued <= 0;
    else if (dmem_rvalid)
        dbus_read_issued <= 0;
    else if (ARVALID_D && ARREADY_D)
        dbus_read_issued <= 1;
end
// AXI4 Data Bus - Read channel
always_ff @(posedge clk) begin
    if (reset) begin
        ARVALID_D <= 1'b0;
        ARADDR_D  <= 32'd0;
        RREADY_D  <= 1'b1;
    end
    else begin
        RREADY_D <= 1'b1;
        if (dmem_re && !ARVALID_D && !dbus_read_issued ) begin
            ARADDR_D  <= dmem_addr;
            ARVALID_D <= 1'b1;
        end
        else if (ARREADY_D) begin
            ARVALID_D <= 1'b0;
        end
    end
end

assign dmem_rdata  = RDATA_D;
assign dmem_rvalid = RVALID_D;

//// AXI4 Data Bus - Write channel
logic [3:0] store_wstrb;//added this whole block for sw variants
always_comb begin
    case (ex_memwb_r.funct3)
        3'b000: // SB - one byte lane
            case (ex_memwb_r.mem_address[1:0])
                2'b00: store_wstrb = 4'b0001;
                2'b01: store_wstrb = 4'b0010;
                2'b10: store_wstrb = 4'b0100;
                2'b11: store_wstrb = 4'b1000;
            endcase
        3'b001: // SH - two byte lanes
            store_wstrb = ex_memwb_r.mem_address[1] ? 4'b1100 : 4'b0011;
        default: // SW
            store_wstrb = 4'b1111;
    endcase
end

always_ff @(posedge clk) begin
    if (reset) begin
        AWVALID_D      <= 1'b0;
        WVALID_D       <= 1'b0;
        AWADDR_D       <= 32'd0;
        WDATA_D        <= 32'd0;
        WSTRB_D        <= 4'b1111;
        BREADY_D       <= 1'b1;
        store_inflight <= 1'b0;
    end
    else begin
        BREADY_D <= 1'b1;
        if (dmem_we && !store_inflight && !AWVALID_D && !WVALID_D) begin
            AWADDR_D       <= dmem_addr;
            WDATA_D        <= dmem_wdata;
            WSTRB_D        <= store_wstrb;
            AWVALID_D      <= 1'b1;
            WVALID_D       <= 1'b1;
            store_inflight <= 1'b1;
        end
        else begin
            if (AWREADY_D) AWVALID_D <= 1'b0;
            if (WREADY_D)  WVALID_D  <= 1'b0;
            if (store_inflight && BVALID_D && BREADY_D
                && !AWVALID_D && !WVALID_D)
                store_inflight <= 1'b0;
        end
    end
end

// Pipeline registers
always_comb begin
    // defaults
    ifid_ex_next  = ifid_ex_n;
    ex_memwb_next = ex_memwb_n;

    if (dmem_stall || store_stall) begin
        ifid_ex_next  = ifid_ex_r;   // freeze
        ex_memwb_next = ex_memwb_r;  // freeze
    end
    else if (jalr_taken || trap_taken || mret_taken) begin
        ifid_ex_next  = '0;
        //ex_memwb_next = '0;
    end
    else if (branch_taken) begin
        ifid_ex_next = '0;
        //ex_memwb_next = ex_memwb_r;
        end
    else if (mul_stall || div_stall) begin
        ifid_ex_next  = ifid_ex_r;          // bubble upstream
        ex_memwb_next = ex_memwb_r;  // freeze EX/WB
    end
    else if (stall) begin
        ifid_ex_next  = '0;
        ex_memwb_next = ex_memwb_n;
    end
    // else: defaults already set above (normal advance)
end

// Single clean register - just flops whatever the comb logic decided
always_ff @(posedge clk) begin
    if (reset) begin
        ifid_ex_r  <= '0;
        ex_memwb_r <= '0;
    end
    else begin
        ifid_ex_r  <= ifid_ex_next;
        ex_memwb_r <= ex_memwb_next;
    end
end


always_comb begin
    ifid_ex_n = '0;
    ifid_ex_n.pc        = pc;
    ifid_ex_n.immediate = immediate;
    ifid_ex_n.rs1       = rs1;
    ifid_ex_n.rs2       = rs2;
    ifid_ex_n.rd        = rd;
    ifid_ex_n.opcode    = opcode;
    ifid_ex_n.funct3    = funct3;
    ifid_ex_n.funct7    = funct7;
    ifid_ex_n.csr_addr  = csr_addr;
end

always_comb begin
    ex_memwb_n = '0;
    ex_memwb_n.ex_result      = ex_result;
    ex_memwb_n.rd_ex          = ifid_ex_r.rd;
    ex_memwb_n.mem_address    = mem_address;
    ex_memwb_n.mem_write_data = mem_write_data;
    ex_memwb_n.mem_read       = mem_read;
    ex_memwb_n.mem_write      = mem_write;
    ex_memwb_n.ex_memread     = ex_memread;
    ex_memwb_n.funct3         = ifid_ex_r.funct3; //added for lw variants
    ex_memwb_n.reg_write      = ex_regwrite;
end

endmodule