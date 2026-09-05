// ============================================================================
// SecVeriRL — RV32I Register File
// ============================================================================
// 32 x XLEN register file. x0 is hardwired to zero.
// Dual read ports, single write port. Synchronous write, async read.
// ============================================================================

module rv32i_regfile
  import secverirl_pkg::*;
#(
  parameter int XLEN     = 32,
  parameter int NUM_REGS = 32,
  parameter int ADDR_W   = 5
)(
  input  logic              clk,
  input  logic              rst_n,

  // Read port A
  input  logic [ADDR_W-1:0] rs1_addr,
  output logic [XLEN-1:0]   rs1_data,

  // Read port B
  input  logic [ADDR_W-1:0] rs2_addr,
  output logic [XLEN-1:0]   rs2_data,

  // Write port
  input  logic              wr_en,
  input  logic [ADDR_W-1:0] rd_addr,
  input  logic [XLEN-1:0]   rd_data
);

  // Register storage
  logic [XLEN-1:0] regs [NUM_REGS];

  // Synchronous write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_REGS; i++) begin
        regs[i] <= '0;
      end
    end else if (wr_en && (rd_addr != '0)) begin
      regs[rd_addr] <= rd_data;
    end
  end

  // Asynchronous read with x0=0 enforcement
  assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];

endmodule
