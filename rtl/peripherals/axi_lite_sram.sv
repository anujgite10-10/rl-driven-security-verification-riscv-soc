// ============================================================================
// SecVeriRL — AXI-Lite SRAM
// ============================================================================
// Simple synchronous SRAM with AXI-Lite slave interface.
// Parameterized depth and width.
// ============================================================================

module axi_lite_sram
  import secverirl_pkg::*;
#(
  parameter int ADDR_W    = 32,
  parameter int DATA_W    = 32,
  parameter int MEM_DEPTH = 16384,  // 64KB / 4 = 16K words
  parameter int MEM_AW    = $clog2(MEM_DEPTH)
)(
  input  logic              clk,
  input  logic              rst_n,

  // AXI-Lite Slave Interface
  // Write address
  input  logic              awvalid,
  output logic              awready,
  input  logic [ADDR_W-1:0] awaddr,

  // Write data
  input  logic              wvalid,
  output logic              wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [3:0]        wstrb,

  // Write response
  output logic              bvalid,
  input  logic              bready,
  output logic [1:0]        bresp,

  // Read address
  input  logic              arvalid,
  output logic              arready,
  input  logic [ADDR_W-1:0] araddr,

  // Read data
  output logic              rvalid,
  input  logic              rready,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]        rresp
);

  // Memory array
  logic [DATA_W-1:0] mem [MEM_DEPTH];

  // State machines
  typedef enum logic [1:0] {
    WR_IDLE, WR_DATA, WR_RESP
  } wr_state_e;

  typedef enum logic [1:0] {
    RD_IDLE, RD_DATA
  } rd_state_e;

  wr_state_e wr_state;
  rd_state_e rd_state;

  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ADDR_W-1:0] rd_addr_reg;

  logic [MEM_AW-1:0] wr_word_addr;
  assign wr_word_addr = wr_addr_reg[MEM_AW+1:2];

  // -----------------------------------------------------------------------
  // Write channel
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_state   <= WR_IDLE;
      awready    <= 1'b0;
      wready     <= 1'b0;
      bvalid     <= 1'b0;
      bresp      <= AXI_RESP_OKAY;
      wr_addr_reg <= '0;
    end else begin
      case (wr_state)
        WR_IDLE: begin
          bvalid  <= 1'b0;
          awready <= 1'b1;
          wready  <= 1'b0;
          if (awvalid && awready) begin
            wr_addr_reg <= awaddr;
            awready     <= 1'b0;
            wready      <= 1'b1;
            wr_state    <= WR_DATA;
          end
        end

        WR_DATA: begin
          if (wvalid && wready) begin
            // Byte-lane writes
            if (wstrb[0]) mem[wr_word_addr][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[wr_word_addr][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[wr_word_addr][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[wr_word_addr][31:24] <= wdata[31:24];

            wready   <= 1'b0;
            bvalid   <= 1'b1;
            bresp    <= AXI_RESP_OKAY;
            wr_state <= WR_RESP;
          end
        end

        WR_RESP: begin
          if (bready) begin
            bvalid   <= 1'b0;
            wr_state <= WR_IDLE;
          end
        end

        default: wr_state <= WR_IDLE;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Read channel
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_state   <= RD_IDLE;
      arready    <= 1'b0;
      rvalid     <= 1'b0;
      rdata      <= '0;
      rresp      <= AXI_RESP_OKAY;
      rd_addr_reg <= '0;
    end else begin
      case (rd_state)
        RD_IDLE: begin
          arready <= 1'b1;
          rvalid  <= 1'b0;
          if (arvalid && arready) begin
            rd_addr_reg <= araddr;
            arready     <= 1'b0;
            rvalid      <= 1'b1;
            rdata       <= mem[araddr[MEM_AW+1:2]];
            rresp       <= AXI_RESP_OKAY;
            rd_state    <= RD_DATA;
          end
        end

        RD_DATA: begin
          if (rready) begin
            rvalid   <= 1'b0;
            rd_state <= RD_IDLE;
          end
        end

        default: rd_state <= RD_IDLE;
      endcase
    end
  end

  // Initialize memory to zero (for simulation)
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++)
      mem[i] = '0;
  end

endmodule
