module prefetch_buffer (
    input  logic clk,
    input  logic reset,

    input  logic [31:0] instr_in,
    input  logic        instr_valid,

    input  logic        consume,
    output logic [31:0] instr_out,
    output logic        instr_available,

    input  logic        flush,

    output logic [3:0]  fifo_count  // changed from fifo_full
);

logic [31:0] fifo [7:0];   // depth 8
logic [2:0]  head;
logic [2:0]  tail;
logic [3:0]  count;        // needs 4 bits for 0-8

logic push;
logic pop;

assign pop  = consume && instr_available;
assign push = instr_valid && (count < 8);

always_ff @(posedge clk) begin
    if (reset) begin
        head  <= 0;
        tail  <= 0;
        count <= 0;
    end
    else if (flush) begin
        head  <= tail;
        count <= 0;
    end
    else begin
        if (push) begin
            fifo[tail] <= instr_in;
            tail       <= tail + 1;
        end
        if (pop) begin
            head <= head + 1;
        end
        case ({push, pop})
            2'b10: count <= count + 1;
            2'b01: count <= count - 1;
            default: ;
        endcase
    end
end

assign instr_out       = instr_available ? fifo[head] : 32'h00000013;
assign instr_available = (count != 0);
assign fifo_count      = count;

endmodule