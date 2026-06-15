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

    logic is_signed;
    logic is_rem;
    assign is_signed = ~funct3[0];
    assign is_rem    = funct3[1];

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
            state       <= IDLE;
            div_done   <= 0;
            div_result <= 0;
        end else begin
            case (state)
                IDLE: begin
                    div_done <= 0;
                    if (div_start) begin
                        // Setup absolute values
                        logic [31:0] abs_a = (is_signed && op_a[31]) ? -op_a : op_a;
                        logic [31:0] abs_b = (is_signed && op_b[31]) ? -op_b : op_b;
                        
                        sign_a <= is_signed && op_a[31];
                        sign_b <= is_signed && op_b[31];
                        res_sign_q <= is_signed && (op_a[31] ^ op_b[31]);
                        res_sign_r <= is_signed && op_a[31]; // Remainder matches sign of dividend
                        
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
                        R <= op_a;
                        state <= FINISH;
                    end else begin
                        Q <= next_Q;
                        R <= next_R;
                        if (cycle_count == 0) state <= FINISH;
                        else cycle_count <= cycle_count - 1;
                    end
                end

                FINISH: begin
                    // Apply signs
                    logic [31:0] final_q = res_sign_q ? -Q : Q;
                    logic [31:0] final_r = res_sign_r ? -R[31:0] : R[31:0];
                    
                    if (div_by_zero) begin
                         div_result <= is_rem ? op_a : 32'hFFFFFFFF;
                    end else begin
                         div_result <= is_rem ? final_r : final_q;
                    end
                    
                    div_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule