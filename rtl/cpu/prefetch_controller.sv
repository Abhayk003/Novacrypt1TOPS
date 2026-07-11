`timescale 1ns/1ps

module prefetch_controller (

    input  logic        clk,
    input  logic        reset,

    input  logic [31:0] branch_immediate,
    input  logic [3:0]  fifo_count,
    input  logic        branch_taken,

    // AR Channel
    output logic [31:0] ARADDR,
    output logic [7:0]  ARLEN,
    output logic [2:0]  ARSIZE,
    output logic [1:0]  ARBURST,
    output logic        ARVALID,
    input  logic        ARREADY,

    // R Channel
    input  logic [31:0] RDATA,
    input  logic        RVALID,
    input  logic        RLAST,
    input  logic [1:0]  RRESP,
    output logic        RREADY,

    // Buffer Interface
    output logic [31:0] instr_out,
    output logic        instr_valid

);

localparam BURST_LEN     = 4;
localparam BURST_LEN_AXI = BURST_LEN - 1;
localparam FIFO_DEPTH    = 8;

typedef enum logic [2:0] {
    IDLE,
    AR_WAIT,   // FIX: hold ARVALID asserted until ARREADY completes the AR handshake
    FETCH,
    FLUSH
} state_t;

state_t state, next_state;

logic [31:0] fetch_pc;
logic [31:0] fetch_pc_next;

logic [3:0] fifo_free;
assign fifo_free = FIFO_DEPTH - fifo_count;

always_ff @(posedge clk) begin
    if (reset) begin
        state    <= IDLE;
        fetch_pc <= 32'd0;
    end
    else begin
        state    <= next_state;
        fetch_pc <= fetch_pc_next;
    end
end

always_comb begin
    // defaults
    next_state    = state;
    fetch_pc_next = fetch_pc;

    ARVALID = 1'b0;
    ARADDR  = fetch_pc;
    ARLEN   = BURST_LEN_AXI;
    ARSIZE  = 3'b010;
    ARBURST = 2'b01;
    RREADY  = 1'b1;

    instr_out   = RDATA;
    instr_valid = 1'b0;

    if (reset) begin
        ARVALID = 1'b0;
        RREADY  = 1'b0;
    end
    else begin
        case (state)

        IDLE: begin
            if (branch_taken) begin
                fetch_pc_next = branch_immediate;
            end
            else if (fifo_free >= BURST_LEN) begin
                // Assert ARVALID and present ARADDR = fetch_pc. Do NOT advance
                // fetch_pc yet and do NOT move to FETCH unconditionally -- the
                // AR handshake only completes when ARREADY is also high. With a
                // zero-latency memory ARREADY is high immediately (so we take the
                // handshake this cycle); with a latency-inserting AXI slave we
                // must hold ARVALID until ARREADY (handled in AR_WAIT).
                ARVALID = 1'b1;
                if (ARREADY) begin
                    // AR accepted this cycle: advance PC and start receiving beats.
                    fetch_pc_next = fetch_pc + (BURST_LEN * 4);
                    next_state    = FETCH;
                end
                else begin
                    // AR not yet accepted: keep ARVALID asserted next cycle.
                    next_state    = AR_WAIT;
                end
            end
        end

        // FIX: new state -- hold ARVALID/ARADDR stable until the slave asserts
        // ARREADY. Only then advance fetch_pc and proceed to receive the burst.
        // The previous FSM advanced fetch_pc and left IDLE the moment it asserted
        // ARVALID, ignoring ARREADY entirely; that silently dropped/duplicated
        // bursts whenever the instruction memory inserted any AR latency (which
        // the SoC's zero-wait SRAM never did, but a realistic AXI slave -- e.g.
        // the UVM instruction responder -- does), causing whole 4-instruction
        // bursts to be skipped.
        AR_WAIT: begin
            if (branch_taken) begin
                // A redirect arrived while we were still waiting for AR accept.
                // Drop this fetch; re-issue from the branch target in IDLE.
                fetch_pc_next = branch_immediate;
                next_state    = IDLE;
            end
            else begin
                ARVALID = 1'b1;                 // hold request stable
                if (ARREADY) begin
                    fetch_pc_next = fetch_pc + (BURST_LEN * 4);
                    next_state    = FETCH;
                end
            end
        end

        FETCH: begin
            if (branch_taken) begin
                fetch_pc_next = branch_immediate;
                instr_valid = 1'b0;
                if (RVALID && RLAST)
                    next_state = IDLE;
                else
                    next_state = FLUSH;
            end
            else begin
                if (RVALID) begin
                    instr_valid = 1'b1;
                    if (RLAST)
                        next_state = IDLE;
                end
            end
        end

        FLUSH: begin
            RREADY      = 1'b1;
            instr_valid = 1'b0;
            if (RVALID && RLAST)
                next_state = IDLE;
        end

    endcase
end
end

endmodule
