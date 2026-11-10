//==============================================================================
// clk_if.sv -- clock passthrough for components/sequences that only need
// a posedge to wait on (virtual sequences have no natural virtual
// interface handle of their own).
//==============================================================================
interface clk_if (input logic clk);
endinterface : clk_if
