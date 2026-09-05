// ============================================================================
// SecVeriRL — RV32I Instruction Decoder
// ============================================================================
// Decodes RV32I instructions into control signals, immediate values, and
// register addresses. Detects illegal instructions for trap generation.
// ============================================================================

module rv32i_decoder
  import secverirl_pkg::*;
#(
  parameter int XLEN = 32
)(
  input  logic [XLEN-1:0]  instr,
  input  priv_mode_e       current_priv,

  // Register addresses
  output logic [4:0]       rs1_addr,
  output logic [4:0]       rs2_addr,
  output logic [4:0]       rd_addr,

  // Immediate
  output logic [XLEN-1:0]  imm,

  // Control signals
  output alu_op_e          alu_op,
  output logic             alu_src_b_imm,  // 0: rs2, 1: immediate
  output logic             reg_write,
  output logic             mem_read,
  output logic             mem_write,
  output logic             branch,
  output logic             jump,
  output logic             jal,
  output logic             jalr,
  output logic             lui,
  output logic             auipc,
  output logic             is_system,      // ECALL/EBREAK/CSR
  output logic             is_csr,
  output logic             is_mret,
  output logic             is_ecall,
  output logic             is_ebreak,
  output logic             is_fence,

  // Exception
  output logic             illegal_insn,
  output logic [11:0]      csr_addr
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  // Register addresses
  assign rs1_addr = instr[19:15];
  assign rs2_addr = instr[24:20];
  assign rd_addr  = instr[11:7];

  // CSR address
  assign csr_addr = instr[31:20];

  // Immediate generation
  always_comb begin
    imm = '0;
    case (opcode)
      OP_IMM, OP_LOAD, OP_JALR:  // I-type
        imm = {{20{instr[31]}}, instr[31:20]};

      OP_STORE:  // S-type
        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

      OP_BRANCH:  // B-type
        imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

      OP_LUI, OP_AUIPC:  // U-type
        imm = {instr[31:12], 12'b0};

      OP_JAL:  // J-type
        imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

      OP_SYSTEM:  // CSR immediate
        imm = {27'b0, instr[19:15]};  // zimm for CSRI instructions

      default:
        imm = '0;
    endcase
  end

  // Control signal generation
  always_comb begin
    // Defaults
    alu_op        = ALU_ADD;
    alu_src_b_imm = 1'b0;
    reg_write     = 1'b0;
    mem_read      = 1'b0;
    mem_write     = 1'b0;
    branch        = 1'b0;
    jump          = 1'b0;
    jal           = 1'b0;
    jalr          = 1'b0;
    lui           = 1'b0;
    auipc         = 1'b0;
    is_system     = 1'b0;
    is_csr        = 1'b0;
    is_mret       = 1'b0;
    is_ecall      = 1'b0;
    is_ebreak     = 1'b0;
    is_fence      = 1'b0;
    illegal_insn  = 1'b0;

    case (opcode)
      OP_LUI: begin
        lui           = 1'b1;
        reg_write     = 1'b1;
        alu_op        = ALU_PASS;
        alu_src_b_imm = 1'b1;
      end

      OP_AUIPC: begin
        auipc         = 1'b1;
        reg_write     = 1'b1;
        alu_op        = ALU_ADD;
        alu_src_b_imm = 1'b1;
      end

      OP_JAL: begin
        jal       = 1'b1;
        jump      = 1'b1;
        reg_write = 1'b1;
      end

      OP_JALR: begin
        jalr          = 1'b1;
        jump          = 1'b1;
        reg_write     = 1'b1;
        alu_src_b_imm = 1'b1;
        alu_op        = ALU_ADD;
      end

      OP_BRANCH: begin
        branch = 1'b1;
        case (funct3)
          3'b000: alu_op = ALU_SUB;  // BEQ
          3'b001: alu_op = ALU_SUB;  // BNE
          3'b100: alu_op = ALU_SLT;  // BLT
          3'b101: alu_op = ALU_SLT;  // BGE
          3'b110: alu_op = ALU_SLTU; // BLTU
          3'b111: alu_op = ALU_SLTU; // BGEU
          default: illegal_insn = 1'b1;
        endcase
      end

      OP_LOAD: begin
        mem_read      = 1'b1;
        reg_write     = 1'b1;
        alu_op        = ALU_ADD;
        alu_src_b_imm = 1'b1;
        if (funct3 > 3'b101) illegal_insn = 1'b1;
      end

      OP_STORE: begin
        mem_write     = 1'b1;
        alu_op        = ALU_ADD;
        alu_src_b_imm = 1'b1;
        if (funct3 > 3'b010) illegal_insn = 1'b1;
      end

      OP_IMM: begin
        reg_write     = 1'b1;
        alu_src_b_imm = 1'b1;
        case (funct3)
          3'b000: alu_op = ALU_ADD;   // ADDI
          3'b001: alu_op = ALU_SLL;   // SLLI
          3'b010: alu_op = ALU_SLT;   // SLTI
          3'b011: alu_op = ALU_SLTU;  // SLTIU
          3'b100: alu_op = ALU_XOR;   // XORI
          3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;  // SRAI/SRLI
          3'b110: alu_op = ALU_OR;    // ORI
          3'b111: alu_op = ALU_AND;   // ANDI
          default: illegal_insn = 1'b1;
        endcase
      end

      OP_REG: begin
        reg_write = 1'b1;
        case ({funct7, funct3})
          10'b0000000_000: alu_op = ALU_ADD;  // ADD
          10'b0100000_000: alu_op = ALU_SUB;  // SUB
          10'b0000000_001: alu_op = ALU_SLL;  // SLL
          10'b0000000_010: alu_op = ALU_SLT;  // SLT
          10'b0000000_011: alu_op = ALU_SLTU; // SLTU
          10'b0000000_100: alu_op = ALU_XOR;  // XOR
          10'b0000000_101: alu_op = ALU_SRL;  // SRL
          10'b0100000_101: alu_op = ALU_SRA;  // SRA
          10'b0000000_110: alu_op = ALU_OR;   // OR
          10'b0000000_111: alu_op = ALU_AND;  // AND
          10'b0000001_000: alu_op = ALU_MUL;  // MUL (M ext)
          default: illegal_insn = 1'b1;
        endcase
      end

      OP_FENCE: begin
        is_fence = 1'b1;
      end

      OP_SYSTEM: begin
        is_system = 1'b1;
        case (funct3)
          3'b000: begin
            case (instr[31:20])
              12'b0000_0000_0000: is_ecall  = 1'b1;  // ECALL
              12'b0000_0000_0001: is_ebreak = 1'b1;  // EBREAK
              12'b0011_0000_0010: begin               // MRET
                is_mret = 1'b1;
                if (current_priv != PRIV_M) illegal_insn = 1'b1;
              end
              default: illegal_insn = 1'b1;
            endcase
          end
          3'b001, 3'b010, 3'b011,   // CSRRW, CSRRS, CSRRC
          3'b101, 3'b110, 3'b111: begin // CSRRWI, CSRRSI, CSRRCI
            is_csr    = 1'b1;
            reg_write = 1'b1;
          end
          default: illegal_insn = 1'b1;
        endcase
      end

      default: begin
        illegal_insn = 1'b1;
      end
    endcase
  end

endmodule
