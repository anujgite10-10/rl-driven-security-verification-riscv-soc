// ============================================================================
// SecVeriRL — RV32I Load/Store Unit
// ============================================================================
// Handles memory load and store operations with byte/halfword/word support.
// Interfaces with the bus via AXI-Lite-like signals.
// Generates misalignment exceptions.
// ============================================================================

module rv32i_lsu
  import secverirl_pkg::*;
#(
  parameter int XLEN = 32
)(
  input  logic              clk,
  input  logic              rst_n,

  // Core interface
  input  logic              mem_read,
  input  logic              mem_write,
  input  logic [2:0]        funct3,       // Size encoding
  input  logic [XLEN-1:0]  addr,
  input  logic [XLEN-1:0]  write_data,
  output logic [XLEN-1:0]  read_data,
  output logic              mem_ready,
  output logic              load_misalign,
  output logic              store_misalign,

  // Memory bus interface (simplified AXI-Lite style)
  output logic              bus_req,
  output logic              bus_we,
  output logic [XLEN-1:0]  bus_addr,
  output logic [XLEN-1:0]  bus_wdata,
  output logic [3:0]        bus_wstrb,
  input  logic [XLEN-1:0]  bus_rdata,
  input  logic              bus_ready,
  input  logic              bus_error
);

  typedef enum logic [1:0] {
    LSU_IDLE,
    LSU_WAIT,
    LSU_DONE
  } lsu_state_e;

  lsu_state_e state, next_state;

  logic [1:0] byte_offset;
  logic       misaligned;

  assign byte_offset = addr[1:0];

  // Misalignment check
  always_comb begin
    misaligned = 1'b0;
    case (funct3[1:0])
      2'b01: misaligned = addr[0];         // Halfword: must be 2-aligned
      2'b10: misaligned = |addr[1:0];      // Word: must be 4-aligned
      default: misaligned = 1'b0;          // Byte: always aligned
    endcase
  end

  assign load_misalign  = mem_read  & misaligned;
  assign store_misalign = mem_write & misaligned;

  // Bus request generation
  assign bus_req  = (mem_read | mem_write) & ~misaligned;
  assign bus_we   = mem_write & ~misaligned;
  assign bus_addr = {addr[XLEN-1:2], 2'b00};  // Word-aligned

  // Write strobe generation
  always_comb begin
    bus_wstrb = 4'b0000;
    bus_wdata = '0;
    if (mem_write && !misaligned) begin
      case (funct3[1:0])
        2'b00: begin  // SB
          bus_wstrb = 4'b0001 << byte_offset;
          bus_wdata = write_data[7:0] << (byte_offset * 8);
        end
        2'b01: begin  // SH
          bus_wstrb = 4'b0011 << byte_offset;
          bus_wdata = write_data[15:0] << (byte_offset * 8);
        end
        2'b10: begin  // SW
          bus_wstrb = 4'b1111;
          bus_wdata = write_data;
        end
        default: begin
          bus_wstrb = 4'b0000;
          bus_wdata = '0;
        end
      endcase
    end
  end

  // Read data extraction with sign/zero extension
  always_comb begin
    read_data = '0;
    if (mem_read && bus_ready) begin
      case (funct3)
        3'b000: begin  // LB (sign-extend)
          case (byte_offset)
            2'b00: read_data = {{24{bus_rdata[7]}},  bus_rdata[7:0]};
            2'b01: read_data = {{24{bus_rdata[15]}}, bus_rdata[15:8]};
            2'b10: read_data = {{24{bus_rdata[23]}}, bus_rdata[23:16]};
            2'b11: read_data = {{24{bus_rdata[31]}}, bus_rdata[31:24]};
          endcase
        end
        3'b001: begin  // LH (sign-extend)
          case (byte_offset[1])
            1'b0: read_data = {{16{bus_rdata[15]}}, bus_rdata[15:0]};
            1'b1: read_data = {{16{bus_rdata[31]}}, bus_rdata[31:16]};
          endcase
        end
        3'b010: begin  // LW
          read_data = bus_rdata;
        end
        3'b100: begin  // LBU (zero-extend)
          case (byte_offset)
            2'b00: read_data = {24'b0, bus_rdata[7:0]};
            2'b01: read_data = {24'b0, bus_rdata[15:8]};
            2'b10: read_data = {24'b0, bus_rdata[23:16]};
            2'b11: read_data = {24'b0, bus_rdata[31:24]};
          endcase
        end
        3'b101: begin  // LHU (zero-extend)
          case (byte_offset[1])
            1'b0: read_data = {16'b0, bus_rdata[15:0]};
            1'b1: read_data = {16'b0, bus_rdata[31:16]};
          endcase
        end
        default: read_data = bus_rdata;
      endcase
    end
  end

  // State machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= LSU_IDLE;
    else        state <= next_state;
  end

  always_comb begin
    next_state = state;
    mem_ready  = 1'b0;
    case (state)
      LSU_IDLE: begin
        if ((mem_read || mem_write) && !misaligned)
          next_state = LSU_WAIT;
        else if (misaligned)
          mem_ready = 1'b1;  // Exception path
      end
      LSU_WAIT: begin
        if (bus_ready || bus_error) begin
          next_state = LSU_IDLE;
          mem_ready  = 1'b1;
        end
      end
      default: next_state = LSU_IDLE;
    endcase
  end

endmodule
