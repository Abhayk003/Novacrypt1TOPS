`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.05.2026 10:41:43
// Design Name: 
// Module Name: rv32m_div_radix4
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rv32m_div_radix4 (
    input  logic        clk,
    input  logic        reset,
    
    input  logic        div_start,   // High to start division
    input  logic [31:0] op_a,      // Dividend
    input  logic [31:0] op_b,      // Divisor
    input  logic [2:0]  funct3,    // from instruction[14:12]
    
    output logic [31:0] div_result,
    output logic        div_done  // High when division is complete
);

    // Decoding funct3
    // 3'b100: DIV  (signed)
    // 3'b101: DIVU (unsigned)
    // 3'b110: REM  (signed)
    // 3'b111: REMU (unsigned)

    // Combinational decode of the CURRENT funct3 (valid at div_start).
    logic is_signed_comb;
    logic is_rem_comb;
    assign is_signed_comb = ~funct3[0];
    assign is_rem_comb    = funct3[1];

    // FIX: latch the operation type and dividend at div_start. The divide takes
    // ~16 cycles; funct3/op_a are LIVE module inputs that reflect whatever
    // instruction is in EX later, which during the divide's multi-cycle stall
    // may be a bubble (X in VCS) or a different instruction. Reading is_rem /
    // op_a directly in the DIVIDE/FINISH states therefore propagated X into
    // div_result (observed as xxxxxxxx on the store bus). Latching them makes
    // the result depend only on the divide's own captured operands.
    logic        is_rem_q;
    logic        is_signed_q;   // latched (kept for clarity / future use)
    logic [31:0] op_a_q;

    typedef enum logic [1:0] {IDLE, DIVIDE, FINISH} state_t;
    state_t state, next_state;

    logic [3:0]  cycle_count;
    logic [31:0] Q, next_Q;
    logic [33:0] R, next_R;
    
    // Divisor Multiples
    logic [33:0] D1, D2, D3;
    logic sign_a, sign_b;
    logic res_sign_q, res_sign_r;

    // Registers for signs and multiples
    logic [33:0] d1_reg, d2_reg, d3_reg;
    logic div_by_zero;
    // Module-scope temporaries for the div_start absolute-value setup, declared
    // WITHOUT an initializer so they are recomputed on every div_start (see the
    // FIX note in the IDLE/div_start block).
    logic [31:0] abs_a, abs_b;
    // Same treatment for the FINISH sign-application temporaries.
    logic [31:0] final_q, final_r;

    // Combinational logic for shifting and subtracting (Radix-4 core)
    logic [33:0] shifted_R;
    always_comb begin
        shifted_R = {R[31:0], Q[31:30]};
        next_Q    = {Q[29:0], 2'b00};
        next_R    = shifted_R;

        if (shifted_R >= d3_reg) begin
            next_R = shifted_R - d3_reg;
            next_Q[1:0] = 2'b11;
        end else if (shifted_R >= d2_reg) begin
            next_R = shifted_R - d2_reg;
            next_Q[1:0] = 2'b10;
        end else if (shifted_R >= d1_reg) begin
            next_R = shifted_R - d1_reg;
            next_Q[1:0] = 2'b01;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            // FIX (VCS X-safety + tapeout correctness): reset ALL sequential
            // state, not just state/div_done/div_result. VCS starts flip-flops
            // as X (as does real silicon at power-up); Verilator starts them at
            // 0, which masked this. If any of these are read while still X --
            // e.g. res_sign_q/res_sign_r in the FINISH sign-application, or the
            // d*_reg comparands -- the X propagates into div_result and then
            // into the store data (observed as xxxxxxxx on the AXI write bus).
            state       <= IDLE;
            div_done    <= 0;
            div_result  <= 0;
            Q           <= '0;
            R           <= '0;
            cycle_count <= '0;
            d1_reg      <= '0;
            d2_reg      <= '0;
            d3_reg      <= '0;
            sign_a      <= 1'b0;
            sign_b      <= 1'b0;
            res_sign_q  <= 1'b0;
            res_sign_r  <= 1'b0;
            div_by_zero <= 1'b0;
            is_rem_q    <= 1'b0;
            is_signed_q <= 1'b0;
            op_a_q      <= '0;
        end else begin
            case (state)
                IDLE: begin
                    div_done <= 0;
                    if (div_start) begin
                        // Setup absolute values (use the combinational decode of
                        // the CURRENT funct3/op, valid this cycle at div_start).
                        // FIX (VCS X-bug): abs_a/abs_b are declared at MODULE scope
                        // and assigned here with blocking statements. A variable-
                        // with-initializer declared inside a procedural block
                        // ("logic [31:0] abs_a = expr;") is a STATIC variable whose
                        // initializer runs ONCE at time 0 (when op_a/op_b are X) and
                        // is NOT re-evaluated on later executions. VCS enforces this,
                        // so abs_b -- and the d1/d2/d3 divisor multiples derived from
                        // it -- were frozen at X, giving div_result = X for every
                        // divide. Verilator re-evaluated it, hiding the bug.
                        abs_a = (is_signed_comb && op_a[31]) ? -op_a : op_a;
                        abs_b = (is_signed_comb && op_b[31]) ? -op_b : op_b;

                        // Latch operation type + dividend for use in DIVIDE/FINISH.
                        is_rem_q    <= is_rem_comb;
                        is_signed_q <= is_signed_comb;
                        op_a_q      <= op_a;

                        sign_a <= is_signed_comb && op_a[31];
                        sign_b <= is_signed_comb && op_b[31];
                        res_sign_q <= is_signed_comb && (op_a[31] ^ op_b[31]);
                        res_sign_r <= is_signed_comb && op_a[31]; // Remainder matches sign of dividend
                        
                        Q <= abs_a;
                        R <= 0;
                        
                        d1_reg <= {2'b0, abs_b};
                        d2_reg <= {1'b0, abs_b, 1'b0};     // B * 2
                        d3_reg <= {2'b0, abs_b} + {1'b0, abs_b, 1'b0}; // B * 3
                        
                        div_by_zero <= (abs_b == 0);
                        cycle_count <= 15; // 16 iterations for 32-bit Radix-4
                        state <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    if (div_by_zero) begin
                        // RISC-V Spec: Div by zero returns all 1s (Quotient) or Dividend (Remainder)
                        Q <= 32'hFFFFFFFF;
                        R <= op_a_q;
                        state <= FINISH;
                    end else begin
                        Q <= next_Q;
                        R <= next_R;
                        if (cycle_count == 0) state <= FINISH;
                        else cycle_count <= cycle_count - 1;
                    end
                end

                FINISH: begin
                    // Apply signs. FIX (same VCS static-initializer X-bug as
                    // abs_a/abs_b): final_q/final_r are declared at module scope
                    // and assigned here with blocking statements. An in-block
                    // "logic [31:0] final_q = expr;" is a STATIC variable whose
                    // initializer runs once at time 0 (Q/R = X then) and never
                    // re-evaluates, so div_result got X on the non-div-by-zero
                    // path. Blocking assignment recomputes them each FINISH.
                    final_q = res_sign_q ? -Q : Q;
                    final_r = res_sign_r ? -R[31:0] : R[31:0];
                    
                    if (div_by_zero) begin
                         div_result <= is_rem_q ? op_a_q : 32'hFFFFFFFF;
                    end else begin
                         div_result <= is_rem_q ? final_r : final_q;
                    end
                    
                    div_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
