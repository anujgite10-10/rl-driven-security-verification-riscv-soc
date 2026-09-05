// ============================================================================
// SecVeriRL — AXI-Lite Interconnect (Address Decoder + Mux)
// ============================================================================
// Routes master requests to one of N slaves based on address decoding.
// Single-master, multi-slave crossbar.
// ============================================================================

module axi_lite_interconnect
  import secverirl_pkg::*;
#(
  parameter int ADDR_W     = 32,
  parameter int DATA_W     = 32,
  parameter int NUM_SLAVES = 3
)(
  input  logic              clk,
  input  logic              rst_n,

  // Master interface (from core/PMP)
  input  logic              m_awvalid, output logic              m_awready,
  input  logic [ADDR_W-1:0] m_awaddr,
  input  logic              m_wvalid,  output logic              m_wready,
  input  logic [DATA_W-1:0] m_wdata,   input  logic [3:0]        m_wstrb,
  output logic              m_bvalid,  input  logic              m_bready,
  output logic [1:0]        m_bresp,
  input  logic              m_arvalid, output logic              m_arready,
  input  logic [ADDR_W-1:0] m_araddr,
  output logic              m_rvalid,  input  logic              m_rready,
  output logic [DATA_W-1:0] m_rdata,   output logic [1:0]        m_rresp,

  // Slave 0: SRAM (0x0000_0000)
  output logic              s0_awvalid, input  logic              s0_awready,
  output logic [ADDR_W-1:0] s0_awaddr,
  output logic              s0_wvalid,  input  logic              s0_wready,
  output logic [DATA_W-1:0] s0_wdata,   output logic [3:0]        s0_wstrb,
  input  logic              s0_bvalid,  output logic              s0_bready,
  input  logic [1:0]        s0_bresp,
  output logic              s0_arvalid, input  logic              s0_arready,
  output logic [ADDR_W-1:0] s0_araddr,
  input  logic              s0_rvalid,  output logic              s0_rready,
  input  logic [DATA_W-1:0] s0_rdata,   input  logic [1:0]        s0_rresp,

  // Slave 1: UART (0x4000_0000)
  output logic              s1_awvalid, input  logic              s1_awready,
  output logic [ADDR_W-1:0] s1_awaddr,
  output logic              s1_wvalid,  input  logic              s1_wready,
  output logic [DATA_W-1:0] s1_wdata,   output logic [3:0]        s1_wstrb,
  input  logic              s1_bvalid,  output logic              s1_bready,
  input  logic [1:0]        s1_bresp,
  output logic              s1_arvalid, input  logic              s1_arready,
  output logic [ADDR_W-1:0] s1_araddr,
  input  logic              s1_rvalid,  output logic              s1_rready,
  input  logic [DATA_W-1:0] s1_rdata,   input  logic [1:0]        s1_rresp,

  // Slave 2: GPIO (0x4000_1000)
  output logic              s2_awvalid, input  logic              s2_awready,
  output logic [ADDR_W-1:0] s2_awaddr,
  output logic              s2_wvalid,  input  logic              s2_wready,
  output logic [DATA_W-1:0] s2_wdata,   output logic [3:0]        s2_wstrb,
  input  logic              s2_bvalid,  output logic              s2_bready,
  input  logic [1:0]        s2_bresp,
  output logic              s2_arvalid, input  logic              s2_arready,
  output logic [ADDR_W-1:0] s2_araddr,
  input  logic              s2_rvalid,  output logic              s2_rready,
  input  logic [DATA_W-1:0] s2_rdata,   input  logic [1:0]        s2_rresp
);

  // Address decode
  logic [1:0] wr_sel, rd_sel;

  function automatic logic [1:0] addr_decode(input logic [ADDR_W-1:0] addr);
    if (addr < UART_BASE)
      return 2'd0;  // SRAM
    else if (addr < GPIO_BASE)
      return 2'd1;  // UART
    else if (addr < (GPIO_BASE + GPIO_SIZE))
      return 2'd2;  // GPIO
    else
      return 2'd0;  // Default to SRAM
  endfunction

  assign wr_sel = addr_decode(m_awaddr);
  assign rd_sel = addr_decode(m_araddr);

  // Write channel routing
  always_comb begin
    // Defaults: deassert all
    s0_awvalid = 1'b0; s0_awaddr = m_awaddr; s0_wvalid = 1'b0;
    s0_wdata = m_wdata; s0_wstrb = m_wstrb; s0_bready = 1'b0;
    s1_awvalid = 1'b0; s1_awaddr = m_awaddr; s1_wvalid = 1'b0;
    s1_wdata = m_wdata; s1_wstrb = m_wstrb; s1_bready = 1'b0;
    s2_awvalid = 1'b0; s2_awaddr = m_awaddr; s2_wvalid = 1'b0;
    s2_wdata = m_wdata; s2_wstrb = m_wstrb; s2_bready = 1'b0;

    m_awready = 1'b0; m_wready = 1'b0; m_bvalid = 1'b0; m_bresp = 2'b00;

    case (wr_sel)
      2'd0: begin
        s0_awvalid = m_awvalid; m_awready = s0_awready;
        s0_wvalid  = m_wvalid;  m_wready  = s0_wready;
        m_bvalid = s0_bvalid; s0_bready = m_bready; m_bresp = s0_bresp;
      end
      2'd1: begin
        s1_awvalid = m_awvalid; m_awready = s1_awready;
        s1_wvalid  = m_wvalid;  m_wready  = s1_wready;
        m_bvalid = s1_bvalid; s1_bready = m_bready; m_bresp = s1_bresp;
      end
      2'd2: begin
        s2_awvalid = m_awvalid; m_awready = s2_awready;
        s2_wvalid  = m_wvalid;  m_wready  = s2_wready;
        m_bvalid = s2_bvalid; s2_bready = m_bready; m_bresp = s2_bresp;
      end
      default: begin
        m_awready = 1'b1;  // Sink
        m_wready  = 1'b1;
        m_bvalid  = 1'b1;
        m_bresp   = AXI_RESP_DECERR;
      end
    endcase
  end

  // Read channel routing
  always_comb begin
    s0_arvalid = 1'b0; s0_araddr = m_araddr; s0_rready = 1'b0;
    s1_arvalid = 1'b0; s1_araddr = m_araddr; s1_rready = 1'b0;
    s2_arvalid = 1'b0; s2_araddr = m_araddr; s2_rready = 1'b0;

    m_arready = 1'b0; m_rvalid = 1'b0; m_rdata = '0; m_rresp = 2'b00;

    case (rd_sel)
      2'd0: begin
        s0_arvalid = m_arvalid; m_arready = s0_arready;
        m_rvalid = s0_rvalid; s0_rready = m_rready;
        m_rdata = s0_rdata; m_rresp = s0_rresp;
      end
      2'd1: begin
        s1_arvalid = m_arvalid; m_arready = s1_arready;
        m_rvalid = s1_rvalid; s1_rready = m_rready;
        m_rdata = s1_rdata; m_rresp = s1_rresp;
      end
      2'd2: begin
        s2_arvalid = m_arvalid; m_arready = s2_arready;
        m_rvalid = s2_rvalid; s2_rready = m_rready;
        m_rdata = s2_rdata; m_rresp = s2_rresp;
      end
      default: begin
        m_arready = 1'b1;
        m_rvalid  = 1'b1;
        m_rdata   = '0;
        m_rresp   = AXI_RESP_DECERR;
      end
    endcase
  end

endmodule
