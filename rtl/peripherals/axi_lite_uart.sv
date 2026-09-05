// ============================================================================
// SecVeriRL — AXI-Lite UART (Simplified)
// ============================================================================
// Minimal UART peripheral with AXI-Lite interface for verification.
// TX data register, status register, control register.
// ============================================================================

module axi_lite_uart
  import secverirl_pkg::*;
#(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32
)(
  input  logic              clk,
  input  logic              rst_n,

  // AXI-Lite Slave
  input  logic              awvalid,
  output logic              awready,
  input  logic [ADDR_W-1:0] awaddr,
  input  logic              wvalid,
  output logic              wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [3:0]        wstrb,
  output logic              bvalid,
  input  logic              bready,
  output logic [1:0]        bresp,
  input  logic              arvalid,
  output logic              arready,
  input  logic [ADDR_W-1:0] araddr,
  output logic              rvalid,
  input  logic              rready,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]        rresp,

  // UART external pins
  output logic              uart_tx,
  input  logic              uart_rx,
  output logic              uart_irq
);

  // Register offsets (relative to base)
  localparam logic [3:0] REG_DATA   = 4'h0;  // TX/RX data
  localparam logic [3:0] REG_STATUS = 4'h4;  // Status
  localparam logic [3:0] REG_CTRL   = 4'h8;  // Control

  // Registers
  logic [7:0]  tx_data;
  logic [7:0]  rx_data;
  logic        tx_busy;
  logic        rx_valid;
  logic        tx_irq_en;
  logic        rx_irq_en;

  // Simplified: direct TX (no baud rate generator for verification)
  logic [3:0]  tx_bit_count;
  logic [9:0]  tx_shift;
  logic        tx_active;

  assign uart_irq = (tx_irq_en && !tx_busy) || (rx_irq_en && rx_valid);

  // Status register
  logic [DATA_W-1:0] status_reg;
  assign status_reg = {28'b0, rx_irq_en, tx_irq_en, rx_valid, !tx_busy};

  // -----------------------------------------------------------------------
  // Write handling
  // -----------------------------------------------------------------------
  typedef enum logic [1:0] { WI, WD, WR } wr_st_e;
  wr_st_e wst;
  logic [ADDR_W-1:0] wa_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wst      <= WI;
      awready  <= 1'b0;
      wready   <= 1'b0;
      bvalid   <= 1'b0;
      bresp    <= 2'b00;
      tx_data  <= '0;
      tx_irq_en <= 1'b0;
      rx_irq_en <= 1'b0;
      wa_reg   <= '0;
    end else begin
      case (wst)
        WI: begin
          awready <= 1'b1;
          bvalid  <= 1'b0;
          if (awvalid) begin
            wa_reg  <= awaddr;
            awready <= 1'b0;
            wready  <= 1'b1;
            wst     <= WD;
          end
        end
        WD: begin
          if (wvalid) begin
            case (wa_reg[3:0])
              REG_DATA: tx_data <= wdata[7:0];
              REG_CTRL: begin
                tx_irq_en <= wdata[1];
                rx_irq_en <= wdata[0];
              end
              default: ;
            endcase
            wready <= 1'b0;
            bvalid <= 1'b1;
            bresp  <= 2'b00;
            wst    <= WR;
          end
        end
        WR: begin
          if (bready) begin
            bvalid <= 1'b0;
            wst    <= WI;
          end
        end
        default: wst <= WI;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Read handling
  // -----------------------------------------------------------------------
  typedef enum logic { RI, RD } rd_st_e;
  rd_st_e rst_state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_state <= RI;
      arready   <= 1'b0;
      rvalid    <= 1'b0;
      rdata     <= '0;
      rresp     <= 2'b00;
    end else begin
      case (rst_state)
        RI: begin
          arready <= 1'b1;
          rvalid  <= 1'b0;
          if (arvalid) begin
            arready <= 1'b0;
            rvalid  <= 1'b1;
            rresp   <= 2'b00;
            case (araddr[3:0])
              REG_DATA:   rdata <= {24'b0, rx_data};
              REG_STATUS: rdata <= status_reg;
              REG_CTRL:   rdata <= {30'b0, rx_irq_en, tx_irq_en};
              default:    rdata <= '0;
            endcase
            rst_state <= RD;
          end
        end
        RD: begin
          if (rready) begin
            rvalid    <= 1'b0;
            rst_state <= RI;
          end
        end
      endcase
    end
  end

  // Simplified TX — just model busy flag
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy  <= 1'b0;
      tx_active <= 1'b0;
      tx_bit_count <= '0;
      uart_tx  <= 1'b1;
      rx_data  <= '0;
      rx_valid <= 1'b0;
    end else begin
      // Loopback for verification: TX → RX
      if (wst == WD && wvalid && wa_reg[3:0] == REG_DATA) begin
        tx_busy <= 1'b1;
        tx_bit_count <= 4'd10;
      end
      if (tx_busy && tx_bit_count > 0) begin
        tx_bit_count <= tx_bit_count - 1;
      end else if (tx_busy && tx_bit_count == 0) begin
        tx_busy  <= 1'b0;
        rx_data  <= tx_data;  // Loopback
        rx_valid <= 1'b1;
      end
    end
  end

endmodule
