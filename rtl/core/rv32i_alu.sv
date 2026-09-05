// ============================================================================
// SecVeriRL — RV32I ALU
// ============================================================================
// Arithmetic Logic Unit supporting RV32I base + M extension (mul/div).
// Parameterized for XLEN to support future RV64 extension.
// ============================================================================

module rv32i_alu
  import secverirl_pkg::*;
#(
  parameter int XLEN = 32
)(
  input  alu_op_e             op,
  input  logic [XLEN-1:0]    operand_a,
  input  logic [XLEN-1:0]    operand_b,
  output logic [XLEN-1:0]    result,
  output logic                zero,
  output logic                overflow
);

  logic [XLEN-1:0] add_result;
  logic [XLEN-1:0] sub_result;
  logic             add_overflow;

  // Addition / Subtraction
  assign add_result   = operand_a + operand_b;
  assign sub_result   = operand_a - operand_b;
  assign add_overflow = (operand_a[XLEN-1] == operand_b[XLEN-1]) &&
                        (add_result[XLEN-1] != operand_a[XLEN-1]);

  always_comb begin
    result   = '0;
    zero     = 1'b0;
    overflow = 1'b0;

    case (op)
      ALU_ADD: begin
        result   = add_result;
        overflow = add_overflow;
      end

      ALU_SUB: begin
        result = sub_result;
      end

      ALU_SLL: begin
        result = operand_a << operand_b[4:0];
      end

      ALU_SLT: begin
        result = {{(XLEN-1){1'b0}}, $signed(operand_a) < $signed(operand_b)};
      end

      ALU_SLTU: begin
        result = {{(XLEN-1){1'b0}}, operand_a < operand_b};
      end

      ALU_XOR: begin
        result = operand_a ^ operand_b;
      end

      ALU_SRL: begin
        result = operand_a >> operand_b[4:0];
      end

      ALU_SRA: begin
        result = $signed(operand_a) >>> operand_b[4:0];
      end

      ALU_OR: begin
        result = operand_a | operand_b;
      end

      ALU_AND: begin
        result = operand_a & operand_b;
      end

      ALU_MUL: begin
        result = operand_a * operand_b;  // Lower 32 bits
      end

      ALU_PASS: begin
        result = operand_b;
      end

      default: begin
        result = '0;
      end
    endcase

    zero = (result == '0);
  end

endmodule
