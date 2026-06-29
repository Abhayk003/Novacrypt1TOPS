`timescale 1ns / 1ps
// ============================================================================
// csr.sv - M-mode CSRs with interrupt/trap support (RV32)
//
// Implements the machine-mode trap CSRs as explicit registers (not a RAM):
//   mstatus (0x300) : MIE bit3, MPIE bit7
//   mie     (0x304) : MSIE bit3, MTIE bit7, MEIE bit11
//   mtvec   (0x305) : trap vector base (direct mode)
//   mscratch(0x340)
//   mepc    (0x341) : saved PC on trap
//   mcause  (0x342) : interrupt flag (bit31) + cause code
//   mtval   (0x343)
//   mip     (0x344) : MSIP bit3, MTIP bit7, MEIP bit11 (driven by HW irq pins)
//
// Interrupt taken when: mstatus.MIE && (mie & mip) != 0
// Priority (RISC-V): external (11) > software (3) > timer (7)
//
// Trap entry (combinational decision, registered effect):
//   mepc   <- cur_pc
//   mcause <- {1'b1, cause}
//   mstatus.MPIE <- MIE ; mstatus.MIE <- 0
//   PC redirect -> mtvec   (trap_taken_o / trap_target_o)
// MRET:
//   mstatus.MIE <- MPIE ; MPIE <- 1
//   PC redirect -> mepc   (mret_taken_o / mret_target_o)
// ============================================================================
module csr(
    input  logic        clk,
    input  logic        reset,

    // CSR instruction interface
    input  logic        csr_en,        // a CSR instruction is executing
    input  logic [2:0]  funct3,
    input  logic [11:0] csr_addr,
    input  logic [31:0] rs1_data,
    input  logic [31:0] imm,
    output logic [31:0] csr_rdata,

    // pipeline context
    input  logic [31:0] cur_pc,        // PC of the instruction in EX
    input  logic        is_mret,       // current instruction is MRET
    input  logic        is_ecall,      // current instruction is ECALL
    input  logic        is_ebreak,     // current instruction is EBREAK
    input  logic        is_illegal,    // current instruction has an unknown opcode
    input  logic        load_misalign, // misaligned load address
    input  logic        store_misalign,// misaligned store address
    input  logic [31:0] bad_addr,      // effective address for misalign mtval
    input  logic        inst_valid,    // EX holds a valid instruction

    // hardware interrupt request lines (level-sensitive)
    input  logic        irq_timer_i,
    input  logic        irq_software_i,
    input  logic        irq_external_i,

    // redirect outputs to the fetch/PC logic
    output logic        trap_taken_o,
    output logic        exc_taken_o,    // trap was a synchronous exception (squash EX/MEM)
    output logic [31:0] trap_target_o,
    output logic        mret_taken_o,
    output logic [31:0] mret_target_o
);

  // ---- CSR addresses ----
  localparam logic [11:0] MSTATUS = 12'h300;
  localparam logic [11:0] MIE     = 12'h304;
  localparam logic [11:0] MTVEC   = 12'h305;
  localparam logic [11:0] MSCRATCH= 12'h340;
  localparam logic [11:0] MEPC    = 12'h341;
  localparam logic [11:0] MCAUSE  = 12'h342;
  localparam logic [11:0] MTVAL   = 12'h343;
  localparam logic [11:0] MIP     = 12'h344;

  // ---- architectural state ----
  logic        mstatus_mie, mstatus_mpie;
  logic        mie_msie, mie_mtie, mie_meie;
  logic [31:0] mtvec_q;
  logic [31:0] mscratch_q;
  logic [31:0] mepc_q;
  logic [31:0] mcause_q;
  logic [31:0] mtval_q;

  // mip pending bits are driven directly by the hardware irq lines (level)
  wire mip_msip = irq_software_i;
  wire mip_mtip = irq_timer_i;
  wire mip_meip = irq_external_i;

  // ---- assemble readable CSR values ----
  logic [31:0] mstatus_val, mie_val, mip_val;
  always_comb begin
    mstatus_val = 32'b0;
    mstatus_val[3]  = mstatus_mie;   // MIE
    mstatus_val[7]  = mstatus_mpie;  // MPIE
    mstatus_val[12:11] = 2'b11;      // MPP = M-mode (fixed)

    mie_val = 32'b0;
    mie_val[3]  = mie_msie;
    mie_val[7]  = mie_mtie;
    mie_val[11] = mie_meie;

    mip_val = 32'b0;
    mip_val[3]  = mip_msip;
    mip_val[7]  = mip_mtip;
    mip_val[11] = mip_meip;
  end

  // ---- CSR read mux ----
  always_comb begin
    case (csr_addr)
      MSTATUS : csr_rdata = mstatus_val;
      MIE     : csr_rdata = mie_val;
      MTVEC   : csr_rdata = mtvec_q;
      MSCRATCH: csr_rdata = mscratch_q;
      MEPC    : csr_rdata = mepc_q;
      MCAUSE  : csr_rdata = mcause_q;
      MTVAL   : csr_rdata = mtval_q;
      MIP     : csr_rdata = mip_val;
      default : csr_rdata = 32'b0;
    endcase
  end

  // ---- CSR write value (per funct3) ----
  // funct3: 001 RW, 010 RS, 011 RC, 101 RWI, 110 RSI, 111 RCI
  logic        is_csr_rw;     // a real CSR read/write instruction (not mret/ecall)
  logic [31:0] csr_src;       // source operand (rs1 or zimm)
  logic [31:0] csr_wval;      // value to write back
  assign is_csr_rw = csr_en && (funct3 != 3'b000);
  assign csr_src   = funct3[2] ? imm : rs1_data;
  always_comb begin
    case (funct3)
      3'b001, 3'b101: csr_wval = csr_src;               // RW / RWI
      3'b010, 3'b110: csr_wval = csr_rdata | csr_src;   // RS / RSI
      3'b011, 3'b111: csr_wval = csr_rdata & ~csr_src;  // RC / RCI
      default       : csr_wval = csr_rdata;
    endcase
  end

  // ---- interrupt decision ----
  logic        irq_pending;
  logic [3:0]  irq_cause;
  always_comb begin
    irq_pending = 1'b0;
    irq_cause   = 4'd0;
    if (mstatus_mie) begin
      if (mie_meie && mip_meip) begin irq_pending = 1'b1; irq_cause = 4'd11; end // external
      else if (mie_msie && mip_msip) begin irq_pending = 1'b1; irq_cause = 4'd3; end // software
      else if (mie_mtie && mip_mtip) begin irq_pending = 1'b1; irq_cause = 4'd7; end // timer
    end
  end

  // Take the interrupt only on a valid instruction boundary, and not on the
  // same cycle we are already redirecting via mret.
  wire take_irq = irq_pending && inst_valid && !is_mret;

  // Synchronous exceptions: trap unconditionally on a valid instruction (not
  // gated by mstatus.MIE), unless we are already doing mret.
  wire any_exc = is_illegal || is_ecall || is_ebreak || load_misalign || store_misalign;
  wire take_exc = any_exc && inst_valid && !is_mret;

  // Cause selection by RISC-V synchronous priority (highest first):
  //   illegal(2) > breakpoint(3) > load-misalign(4) > store-misalign(6) > ecall(11)
  // mtval: faulting address for misaligned load/store, else 0.
  logic [31:0] exc_cause, exc_tval;
  always_comb begin
    if (is_illegal)            begin exc_cause = 32'd2;  exc_tval = 32'd0; end
    else if (is_ebreak)        begin exc_cause = 32'd3;  exc_tval = 32'd0; end
    else if (load_misalign)    begin exc_cause = 32'd4;  exc_tval = bad_addr; end
    else if (store_misalign)   begin exc_cause = 32'd6;  exc_tval = bad_addr; end
    else                       begin exc_cause = 32'd11; exc_tval = 32'd0; end // ECALL
  end

  // An exception takes priority over an interrupt in the same cycle.
  assign trap_taken_o  = take_irq || take_exc;
  assign exc_taken_o   = take_exc;
  assign trap_target_o = mtvec_q;          // direct mode: jump straight to base
  assign mret_taken_o  = is_mret && inst_valid;
  assign mret_target_o = mepc_q;

  // ---- state update ----
  always_ff @(posedge clk) begin
    if (reset) begin
      mstatus_mie  <= 1'b0;
      mstatus_mpie <= 1'b0;
      mie_msie     <= 1'b0;
      mie_mtie     <= 1'b0;
      mie_meie     <= 1'b0;
      mtvec_q      <= 32'b0;
      mscratch_q   <= 32'b0;
      mepc_q       <= 32'b0;
      mcause_q     <= 32'b0;
      mtval_q      <= 32'b0;
    end else begin
      // Priority: synchronous exception > interrupt > mret > CSR write.
      if (take_exc) begin
        mepc_q       <= cur_pc;                 // faulting PC
        mcause_q     <= {1'b0, exc_cause[30:0]}; // interrupt bit = 0
        mtval_q      <= exc_tval;                // faulting address (misalign) or 0
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (take_irq) begin
        mepc_q       <= cur_pc;
        mcause_q     <= {1'b1, 27'b0, irq_cause};
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (mret_taken_o) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end else if (is_csr_rw) begin
        case (csr_addr)
          MSTATUS : begin mstatus_mie <= csr_wval[3]; mstatus_mpie <= csr_wval[7]; end
          MIE     : begin mie_msie <= csr_wval[3]; mie_mtie <= csr_wval[7]; mie_meie <= csr_wval[11]; end
          MTVEC   : mtvec_q    <= csr_wval;
          MSCRATCH: mscratch_q <= csr_wval;
          MEPC    : mepc_q     <= csr_wval;
          MCAUSE  : mcause_q   <= csr_wval;
          MTVAL   : mtval_q    <= csr_wval;
          default : ; // mip is read-only here (driven by HW lines)
        endcase
      end
    end
  end

endmodule
