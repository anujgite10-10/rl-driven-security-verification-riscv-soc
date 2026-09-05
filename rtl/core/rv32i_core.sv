// ============================================================================
// SecVeriRL — RV32I Core Top
// ============================================================================
// Multi-cycle RV32I processor integrating decoder, ALU, regfile, LSU, and
// control unit. Simple multi-cycle FSM (not pipelined — keeps formal
// verification tractable while demonstrating all security features).
// ============================================================================

module rv32i_core
  import secverirl_pkg::*;
#(
  parameter int XLEN        = 32,
  parameter int PMP_REGIONS = 4,
  parameter logic [31:0] RESET_ADDR = 32'h0000_0000
)(
  input  logic              clk,
  input  logic              rst_n,

  // Instruction memory interface
  output logic [XLEN-1:0]  imem_addr,
  input  logic [XLEN-1:0]  imem_rdata,
  output logic              imem_req,
  input  logic              imem_ready,
  input  logic              imem_fault,

  // Data memory interface
  output logic              dmem_req,
  output logic              dmem_we,
  output logic [XLEN-1:0]  dmem_addr,
  output logic [XLEN-1:0]  dmem_wdata,
  output logic [3:0]        dmem_wstrb,
  input  logic [XLEN-1:0]  dmem_rdata,
  input  logic              dmem_ready,
  input  logic              dmem_error,

  // Interrupts
  input  logic              ext_irq,
  input  logic              timer_irq,
  input  logic              sw_irq,

  // Security outputs (for external monitor)
  output priv_mode_e        current_priv,
  output pmp_cfg_t          pmp_cfg   [PMP_REGIONS],
  output logic [XLEN-1:0]  pmp_addr  [PMP_REGIONS],
  output logic              is_mret,
  output logic              is_ecall,
  output logic              is_csr,
  output logic [11:0]       csr_addr,
  output logic              csr_denied,

  // Debug / verification interface (RVFI-like)
  output logic              rvfi_valid,
  output logic [XLEN-1:0]  rvfi_insn,
  output logic [XLEN-1:0]  rvfi_pc,
  output logic [XLEN-1:0]  rvfi_next_pc,
  output logic [4:0]        rvfi_rd_addr,
  output logic [XLEN-1:0]  rvfi_rd_data,
  output logic              rvfi_trap
);

  // -----------------------------------------------------------------------
  // State Machine
  // -----------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_FETCH,
    ST_DECODE,
    ST_EXECUTE,
    ST_MEMORY,
    ST_WRITEBACK
  } core_state_e;

  core_state_e state, next_state;

  // -----------------------------------------------------------------------
  // Internal signals
  // -----------------------------------------------------------------------
  logic [XLEN-1:0] pc, next_pc;
  logic [XLEN-1:0] instr_reg;

  // Decoder outputs
  logic [4:0]       dec_rs1, dec_rs2, dec_rd;
  logic [XLEN-1:0] dec_imm;
  alu_op_e          dec_alu_op;
  logic             dec_alu_src_b_imm;
  logic             dec_reg_write, dec_mem_read, dec_mem_write;
  logic             dec_branch, dec_jump, dec_jal, dec_jalr;
  logic             dec_lui, dec_auipc;
  logic             dec_is_system, dec_is_csr, dec_is_mret;
  logic             dec_is_ecall, dec_is_ebreak, dec_is_fence;
  logic             dec_illegal;
  logic [11:0]      dec_csr_addr;

  // Regfile
  logic [XLEN-1:0] rs1_data, rs2_data;
  logic             rf_wr_en;
  logic [XLEN-1:0] rf_wr_data;

  // ALU
  logic [XLEN-1:0] alu_result;
  logic             alu_zero, alu_overflow;
  logic [XLEN-1:0] alu_op_a, alu_op_b;

  // LSU
  logic [XLEN-1:0] lsu_rdata;
  logic             lsu_ready, lsu_load_misalign, lsu_store_misalign;

  // Control
  logic [XLEN-1:0] csr_rdata;
  logic             trap_taken, mret_taken;
  logic [XLEN-1:0] trap_target, mepc_out;
  logic             pipeline_flush;

  // Branch resolution
  logic branch_taken;

  // -----------------------------------------------------------------------
  // Decoder
  // -----------------------------------------------------------------------
  rv32i_decoder #(.XLEN(XLEN)) u_decoder (
    .instr         (instr_reg),
    .current_priv  (current_priv),
    .rs1_addr      (dec_rs1),
    .rs2_addr      (dec_rs2),
    .rd_addr       (dec_rd),
    .imm           (dec_imm),
    .alu_op        (dec_alu_op),
    .alu_src_b_imm (dec_alu_src_b_imm),
    .reg_write     (dec_reg_write),
    .mem_read      (dec_mem_read),
    .mem_write     (dec_mem_write),
    .branch        (dec_branch),
    .jump          (dec_jump),
    .jal           (dec_jal),
    .jalr          (dec_jalr),
    .lui           (dec_lui),
    .auipc         (dec_auipc),
    .is_system     (dec_is_system),
    .is_csr        (dec_is_csr),
    .is_mret       (dec_is_mret),
    .is_ecall      (dec_is_ecall),
    .is_ebreak     (dec_is_ebreak),
    .is_fence      (dec_is_fence),
    .illegal_insn  (dec_illegal),
    .csr_addr      (dec_csr_addr)
  );

  // -----------------------------------------------------------------------
  // Register File
  // -----------------------------------------------------------------------
  rv32i_regfile #(.XLEN(XLEN)) u_regfile (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (dec_rs1),
    .rs1_data (rs1_data),
    .rs2_addr (dec_rs2),
    .rs2_data (rs2_data),
    .wr_en    (rf_wr_en),
    .rd_addr  (dec_rd),
    .rd_data  (rf_wr_data)
  );

  // -----------------------------------------------------------------------
  // ALU
  // -----------------------------------------------------------------------
  assign alu_op_a = dec_auipc ? pc : rs1_data;
  assign alu_op_b = dec_alu_src_b_imm ? dec_imm : rs2_data;

  rv32i_alu #(.XLEN(XLEN)) u_alu (
    .op        (dec_alu_op),
    .operand_a (alu_op_a),
    .operand_b (alu_op_b),
    .result    (alu_result),
    .zero      (alu_zero),
    .overflow  (alu_overflow)
  );

  // -----------------------------------------------------------------------
  // Load/Store Unit
  // -----------------------------------------------------------------------
  rv32i_lsu #(.XLEN(XLEN)) u_lsu (
    .clk            (clk),
    .rst_n          (rst_n),
    .mem_read       (dec_mem_read && (state == ST_MEMORY)),
    .mem_write      (dec_mem_write && (state == ST_MEMORY)),
    .funct3         (instr_reg[14:12]),
    .addr           (alu_result),
    .write_data     (rs2_data),
    .read_data      (lsu_rdata),
    .mem_ready      (lsu_ready),
    .load_misalign  (lsu_load_misalign),
    .store_misalign (lsu_store_misalign),
    .bus_req        (dmem_req),
    .bus_we         (dmem_we),
    .bus_addr       (dmem_addr),
    .bus_wdata      (dmem_wdata),
    .bus_wstrb      (dmem_wstrb),
    .bus_rdata      (dmem_rdata),
    .bus_ready      (dmem_ready),
    .bus_error      (dmem_error)
  );

  // -----------------------------------------------------------------------
  // Control Unit
  // -----------------------------------------------------------------------
  rv32i_control #(.XLEN(XLEN), .PMP_REGIONS(PMP_REGIONS)) u_control (
    .clk            (clk),
    .rst_n          (rst_n),
    .is_csr         (dec_is_csr && (state == ST_EXECUTE)),
    .is_mret        (dec_is_mret && (state == ST_EXECUTE)),
    .is_ecall       (dec_is_ecall && (state == ST_EXECUTE)),
    .is_ebreak      (dec_is_ebreak && (state == ST_EXECUTE)),
    .illegal_insn   (dec_illegal && (state == ST_DECODE)),
    .funct3         (instr_reg[14:12]),
    .csr_addr_i     (dec_csr_addr),
    .rs1_data       (rs1_data),
    .rs1_addr       (dec_rs1),
    .pc             (pc),
    .load_misalign  (lsu_load_misalign),
    .store_misalign (lsu_store_misalign),
    .load_fault     (dmem_error && dec_mem_read),
    .store_fault    (dmem_error && dec_mem_write),
    .insn_fault     (imem_fault),
    .ext_irq        (ext_irq),
    .timer_irq      (timer_irq),
    .sw_irq         (sw_irq),
    .csr_rdata      (csr_rdata),
    .current_priv   (current_priv),
    .trap_taken     (trap_taken),
    .trap_target    (trap_target),
    .mret_taken     (mret_taken),
    .mepc_out       (mepc_out),
    .pmp_cfg        (pmp_cfg),
    .pmp_addr       (pmp_addr),
    .pipeline_flush (pipeline_flush),
    .csr_denied     (csr_denied)
  );

  // Expose security signals to monitor
  assign is_mret  = dec_is_mret && (state == ST_EXECUTE);
  assign is_ecall = dec_is_ecall && (state == ST_EXECUTE);
  assign is_csr   = dec_is_csr && (state == ST_EXECUTE);
  assign csr_addr = dec_csr_addr;

  // -----------------------------------------------------------------------
  // Branch resolution
  // -----------------------------------------------------------------------
  always_comb begin
    branch_taken = 1'b0;
    if (dec_branch) begin
      case (instr_reg[14:12])
        3'b000: branch_taken =  alu_zero;  // BEQ
        3'b001: branch_taken = !alu_zero;  // BNE
        3'b100: branch_taken =  alu_result[0]; // BLT
        3'b101: branch_taken = !alu_result[0]; // BGE
        3'b110: branch_taken =  alu_result[0]; // BLTU
        3'b111: branch_taken = !alu_result[0]; // BGEU
        default: branch_taken = 1'b0;
      endcase
    end
  end

  // -----------------------------------------------------------------------
  // Next PC calculation
  // -----------------------------------------------------------------------
  always_comb begin
    if (trap_taken)
      next_pc = trap_target;
    else if (mret_taken)
      next_pc = mepc_out;
    else if (dec_jal)
      next_pc = pc + dec_imm;
    else if (dec_jalr)
      next_pc = {alu_result[XLEN-1:1], 1'b0};
    else if (branch_taken)
      next_pc = pc + dec_imm;
    else
      next_pc = pc + 4;
  end

  // -----------------------------------------------------------------------
  // Register writeback mux
  // -----------------------------------------------------------------------
  always_comb begin
    rf_wr_data = alu_result;
    if (dec_mem_read)
      rf_wr_data = lsu_rdata;
    else if (dec_jump)
      rf_wr_data = pc + 4;
    else if (dec_is_csr)
      rf_wr_data = csr_rdata;
    else if (dec_lui)
      rf_wr_data = dec_imm;
  end

  // -----------------------------------------------------------------------
  // State Machine
  // -----------------------------------------------------------------------
  assign imem_addr = pc;
  assign imem_req  = (state == ST_FETCH);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_FETCH;
      pc        <= RESET_ADDR;
      instr_reg <= 32'h0000_0013;  // NOP (addi x0,x0,0)
    end else begin
      state <= next_state;

      case (state)
        ST_FETCH: begin
          if (imem_ready)
            instr_reg <= imem_rdata;
        end
        ST_WRITEBACK: begin
          pc <= next_pc;
        end
        default: ;
      endcase

      // Override on trap/mret
      if (pipeline_flush && (state == ST_EXECUTE || state == ST_DECODE)) begin
        pc    <= next_pc;
        state <= ST_FETCH;
      end
    end
  end

  always_comb begin
    next_state = state;
    rf_wr_en   = 1'b0;

    case (state)
      ST_FETCH: begin
        if (imem_ready)
          next_state = ST_DECODE;
      end
      ST_DECODE: begin
        if (pipeline_flush)
          next_state = ST_FETCH;
        else
          next_state = ST_EXECUTE;
      end
      ST_EXECUTE: begin
        if (pipeline_flush)
          next_state = ST_FETCH;
        else if (dec_is_fence)
          next_state = ST_WRITEBACK;  // FENCE = NOP in single-core; skip memory
        else if (dec_mem_read || dec_mem_write)
          next_state = ST_MEMORY;
        else
          next_state = ST_WRITEBACK;
      end
      ST_MEMORY: begin
        if (lsu_ready)
          next_state = ST_WRITEBACK;
      end
      ST_WRITEBACK: begin
        rf_wr_en   = dec_reg_write;
        next_state = ST_FETCH;
      end
      default: next_state = ST_FETCH;
    endcase
  end

  // -----------------------------------------------------------------------
  // RVFI (Verification Interface)
  // -----------------------------------------------------------------------
  assign rvfi_valid   = (state == ST_WRITEBACK);
  assign rvfi_insn    = instr_reg;
  assign rvfi_pc      = pc;
  assign rvfi_next_pc = next_pc;
  assign rvfi_rd_addr = dec_rd;
  assign rvfi_rd_data = rf_wr_data;
  assign rvfi_trap    = trap_taken;

endmodule
