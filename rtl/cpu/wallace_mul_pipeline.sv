`timescale 1ns/1ps

module wallace_mul_pipeline (
    input  logic        clk,
    input  logic        reset,

    input  logic [31:0]a,
    input  logic [31:0] b,
    input  logic        start,
    input  logic [1:0]  mul_mode,

    output logic [63:0] result,     // answer in result[31:0]
    output logic        done
);

    localparam logic [1:0] MUL    = 2'b00;
    localparam logic [1:0] MULH   = 2'b01;
    localparam logic [1:0] MULHU  = 2'b10;
    localparam logic [1:0] MULHSU = 2'b11;

    // ======================================================================
    // STAGE 1 : BOOTH PARTIAL-PRODUCT GENERATION
    // ======================================================================

    logic [63:0] A_ext;       // 64-bit zero- or sign-extended A
    logic [63:0] negA_ext;    // 2's complement of A_ext
    logic [33:0] B_ext;       // 34-bit Booth-extended B (see design notes above)
    logic [5:0]  n_pairs;     // 32 for signed B, 33 for unsigned B

    // 33 partial products max (unsigned B needs one extra pair)
    logic [63:0] pp_s1 [0:32];

    always_comb begin

        // ------------------------------------------------------------------
        // Step 1: Build A_ext (64-bit)
        //   MULHU: A is unsigned -> zero-extend
        //   all others: A is signed -> sign-extend
        // ------------------------------------------------------------------
        if (mul_mode == MULHU)
            A_ext = { 32'b0, a };
        else
            A_ext = { {32{a[31]}}, a };

        negA_ext = (~A_ext) + 64'd1;

        // ------------------------------------------------------------------
        // Step 2: Build B_ext (34 bits) and set n_pairs
        //
        //   Layout: B_ext[0]    = 0  (appended sentinel)
        //           B_ext[32:1] = B[31:0]
        //           B_ext[33]   = guard bit (B[31] for signed, 0 for unsigned)
        //
        //   Signed B (MUL, MULH):
        //     guard = B[31]; loop k=0..31 (32 pairs)
        //
        //   Unsigned B (MULHU, MULHSU):
        //     guard = 0;     loop k=0..32 (33 pairs)
        //     The 33rd pair { B_ext[33], B_ext[32] } = { 0, B[31] }
        //     evaluates to 01 when B[31]=1, adding +A<<32 correctly.
        // ------------------------------------------------------------------
        if (mul_mode == MUL || mul_mode == MULH) begin
            // Signed B: guard bit = B[31] (2's complement sign extension)
            B_ext   = { 1'b0, b[31], b, 1'b0 };
            n_pairs = 6'd32;
        end else begin
            // Unsigned B: guard bit = 0
            B_ext   = { 2'b0, b, 1'b0 };
            n_pairs = 6'd33;
        end

        // ------------------------------------------------------------------
        // Step 3: Generate partial products
        // ------------------------------------------------------------------
        for (int k = 0; k <= 32; k++) begin
            if (k < int'(n_pairs)) begin
                case ({ B_ext[k+1], B_ext[k] })
                    2'b01:   pp_s1[k] = (A_ext    << k) & 64'hFFFFFFFFFFFFFFFF;
                    2'b10:   pp_s1[k] = (negA_ext << k) & 64'hFFFFFFFFFFFFFFFF;
                    default: pp_s1[k] = 64'd0;
                endcase
            end else begin
                pp_s1[k] = 64'd0;   // unused slots zeroed
            end
        end
    end

    // ──────────────────────────────────────────────────────────────────────
    // Pipeline register: Stage 1 -> Stage 2
    // ──────────────────────────────────────────────────────────────────────
    logic [63:0] pp_s2 [0:32];
    logic        valid_s2;
    logic [1:0]  mode_s2;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int k = 0; k <= 32; k++) pp_s2[k] <= 64'd0;
            valid_s2 <= 1'b0;
            mode_s2  <= 2'b00;
        end else begin
            for (int k = 0; k <= 32; k++) pp_s2[k] <= pp_s1[k];
            valid_s2 <= start;
            mode_s2  <= mul_mode;
        end
    end

    // ======================================================================
    // STAGE 2 : WALLACE-TREE CSA REDUCTION
    // ======================================================================
    //
    // Linear CSA chain reduces 33 partial products to {sum, carry}.
    // A synthesis tool will restructure this into a balanced Wallace tree.
    //
    //   sum_new   = A ^ B ^ C
    //   carry_new = majority(A, B, C) << 1
    // ──────────────────────────────────────────────────────────────────────

    logic [63:0] csa_sum;
    logic [63:0] csa_carry;

    always_comb begin
        csa_sum   = pp_s2[0];
        csa_carry = 64'd0;

        for (int k = 1; k <= 32; k++) begin
            automatic logic [63:0] ns, nc;
            ns        = csa_sum ^ csa_carry ^ pp_s2[k];
            nc        = ((csa_sum   & csa_carry) |
                         (csa_carry & pp_s2[k])  |
                         (csa_sum   & pp_s2[k])) << 1;
            csa_sum   = ns;
            csa_carry = nc;
        end
    end

    // ──────────────────────────────────────────────────────────────────────
    // Pipeline register: Stage 2 -> Stage 3
    // ──────────────────────────────────────────────────────────────────────
    logic [63:0] sum_s3;
    logic [63:0] carry_s3;
    logic        valid_s3;
    logic [1:0]  mode_s3;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sum_s3   <= 64'd0;
            carry_s3 <= 64'd0;
            valid_s3 <= 1'b0;
            mode_s3  <= 2'b00;
        end else begin
            sum_s3   <= csa_sum;
            carry_s3 <= csa_carry;
            valid_s3 <= valid_s2;
            mode_s3  <= mode_s2;
        end
    end

    // ======================================================================
    // STAGE 3 : FINAL ADDER + OUTPUT MUX
    // ======================================================================
   
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            result    <= 64'd0;
            done <= 1'b0;
        end else begin
            automatic logic [63:0] product;
            product = sum_s3 + carry_s3;
            result<=product;

           done <= valid_s3;
        end
    end

endmodule

