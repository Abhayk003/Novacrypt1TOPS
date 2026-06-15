`timescale 1ns / 1ps
// ----------------------------------------------------------------------------
// sram.sv - single-port byte-enable SRAM matching axi_to_mem's mem stream IF
//   * 1-cycle read latency  -> use BufDepth = 1 on axi_to_mem
//   * always grants         -> gnt = req
//   * rvalid = req delayed by one cycle (axi_to_mem expects a response for
//     writes as well as reads)
//   * optional $readmemh init for Boot ROM / preloaded program images
// ----------------------------------------------------------------------------
module sram #(
    parameter int unsigned NumWords  = 16384,           // 64 KB @ 32-bit
    parameter              InitFile  = "",
    localparam int unsigned AddrBits = $clog2(NumWords)
)(
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,      // BYTE address from axi_to_mem
    input  logic [31:0] wdata_i,
    input  logic [3:0]  strb_i,
    input  logic        we_i,
    output logic        rvalid_o,
    output logic [31:0] rdata_o
);

    logic [31:0] mem [0:NumWords-1];

    initial begin
        if (InitFile != "") $readmemh(InitFile, mem);
    end

    assign gnt_o = req_i;   // single-port, zero-wait-state

    logic [AddrBits-1:0] word_addr;
    assign word_addr = addr_i[AddrBits+1:2];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i & gnt_o;
            if (req_i & gnt_o) begin
                if (we_i) begin
                    if (strb_i[0]) mem[word_addr][ 7: 0] <= wdata_i[ 7: 0];
                    if (strb_i[1]) mem[word_addr][15: 8] <= wdata_i[15: 8];
                    if (strb_i[2]) mem[word_addr][23:16] <= wdata_i[23:16];
                    if (strb_i[3]) mem[word_addr][31:24] <= wdata_i[31:24];
                end else begin
                    rdata_o <= mem[word_addr];
                end
            end
        end
    end

endmodule
