// ============================================================================
// SecVeriRL — AXI-Lite GPIO
// ============================================================================

module axi_lite_gpio
  import secverirl_pkg::*;
#(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int GPIO_W   = 16
)(
  input  logic              clk,
  input  logic              rst_n,
  // AXI-Lite Slave
  input  logic              awvalid, output logic              awready,
  input  logic [ADDR_W-1:0] awaddr,
  input  logic              wvalid,  output logic              wready,
  input  logic [DATA_W-1:0] wdata,   input  logic [3:0]        wstrb,
  output logic              bvalid,  input  logic              bready,
  output logic [1:0]        bresp,
  input  logic              arvalid, output logic              arready,
  input  logic [ADDR_W-1:0] araddr,
  output logic              rvalid,  input  logic              rready,
  output logic [DATA_W-1:0] rdata,   output logic [1:0]        rresp,
  // GPIO pins
  output logic [GPIO_W-1:0] gpio_out,
  input  logic [GPIO_W-1:0] gpio_in,
  output logic [GPIO_W-1:0] gpio_oe    // Output enable
);

  // REG_OUT=0x0, REG_IN=0x4, REG_OE=0x8
  logic [GPIO_W-1:0] out_reg, oe_reg;
  assign gpio_out = out_reg;
  assign gpio_oe  = oe_reg;

  // Write FSM
  typedef enum logic [1:0] { WI, WD, WR } wst_e;
  wst_e wst;
  logic [ADDR_W-1:0] wa;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wst <= WI; awready <= 1'b0; wready <= 1'b0;
      bvalid <= 1'b0; bresp <= 2'b00;
      out_reg <= '0; oe_reg <= '0; wa <= '0;
    end else case (wst)
      WI: begin awready<=1'b1; bvalid<=1'b0;
        if (awvalid) begin wa<=awaddr; awready<=1'b0; wready<=1'b1; wst<=WD; end end
      WD: if (wvalid) begin
        case (wa[3:0])
          4'h0: out_reg <= wdata[GPIO_W-1:0];
          4'h8: oe_reg  <= wdata[GPIO_W-1:0];
          default: ;
        endcase
        wready<=1'b0; bvalid<=1'b1; bresp<=2'b00; wst<=WR; end
      WR: if (bready) begin bvalid<=1'b0; wst<=WI; end
      default: wst <= WI;
    endcase
  end

  // Read FSM
  typedef enum logic { RI, RD } rst_e;
  rst_e rs;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rs<=RI; arready<=1'b0; rvalid<=1'b0; rdata<='0; rresp<=2'b00;
    end else case (rs)
      RI: begin arready<=1'b1; rvalid<=1'b0;
        if (arvalid) begin arready<=1'b0; rvalid<=1'b1; rresp<=2'b00;
          case (araddr[3:0])
            4'h0: rdata <= {{(DATA_W-GPIO_W){1'b0}}, out_reg};
            4'h4: rdata <= {{(DATA_W-GPIO_W){1'b0}}, gpio_in};
            4'h8: rdata <= {{(DATA_W-GPIO_W){1'b0}}, oe_reg};
            default: rdata <= '0;
          endcase
          rs<=RD; end end
      RD: if (rready) begin rvalid<=1'b0; rs<=RI; end
    endcase
  end

endmodule
