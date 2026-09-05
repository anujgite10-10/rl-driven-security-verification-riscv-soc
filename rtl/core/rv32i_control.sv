// ============================================================================
// SecVeriRL — RV32I Control Unit (CSR + Privilege + Trap Handling)
// ============================================================================
// Manages: CSR registers, privilege modes, exception/interrupt handling,
// MRET/ECALL. This is the security-critical module.
// ============================================================================

module rv32i_control
  import secverirl_pkg::*;
#(
  parameter int XLEN          = 32,
  parameter int PMP_REGIONS   = 4
)(
  input  logic              clk,
  input  logic              rst_n,

  // Instruction decode signals
  input  logic              is_csr,
  input  logic              is_mret,
  input  logic              is_ecall,
  input  logic              is_ebreak,
  input  logic              illegal_insn,
  input  logic [2:0]        funct3,
  input  logic [11:0]       csr_addr_i,
  input  logic [XLEN-1:0]  rs1_data,
  input  logic [4:0]        rs1_addr,       // For CSRI variants
  input  logic [XLEN-1:0]  pc,

  // Exception inputs
  input  logic              load_misalign,
  input  logic              store_misalign,
  input  logic              load_fault,
  input  logic              store_fault,
  input  logic              insn_fault,

  // Interrupt inputs
  input  logic              ext_irq,
  input  logic              timer_irq,
  input  logic              sw_irq,

  // CSR read output
  output logic [XLEN-1:0]  csr_rdata,

  // Privilege & trap outputs
  output priv_mode_e        current_priv,
  output logic              trap_taken,
  output logic [XLEN-1:0]  trap_target,     // mtvec
  output logic              mret_taken,
  output logic [XLEN-1:0]  mepc_out,

  // PMP configuration outputs (directly to PMP unit)
  output pmp_cfg_t          pmp_cfg   [PMP_REGIONS],
  output logic [XLEN-1:0]  pmp_addr  [PMP_REGIONS],

  // Pipeline control
  output logic              pipeline_flush,
  
  // Security monitor outputs
  output logic              csr_denied
);

  // -----------------------------------------------------------------------
  // CSR Registers
  // -----------------------------------------------------------------------
  logic [XLEN-1:0] mstatus;
  logic [XLEN-1:0] misa;
  logic [XLEN-1:0] mie;
  logic [XLEN-1:0] mtvec;
  logic [XLEN-1:0] mscratch;
  logic [XLEN-1:0] mepc;
  logic [XLEN-1:0] mcause;
  logic [XLEN-1:0] mtval;
  logic [XLEN-1:0] mip;
  logic [XLEN-1:0] mcycle;
  logic [XLEN-1:0] minstret;

  // PMP CSRs
  logic [XLEN-1:0] pmpcfg0;
  logic [XLEN-1:0] pmpaddr_regs [PMP_REGIONS];

  // Current privilege mode
  priv_mode_e priv_mode;

  assign current_priv = priv_mode;

  // -----------------------------------------------------------------------
  // MISA: RV32I + M extension
  // -----------------------------------------------------------------------
  assign misa = {2'b01,               // MXL = 32-bit
                 4'b0000,             // reserved
                 26'b00000000000001000100000000};  // I + M

  // -----------------------------------------------------------------------
  // MIP (interrupt pending — directly from inputs)
  // -----------------------------------------------------------------------
  always_comb begin
    mip        = '0;
    mip[11]    = ext_irq;     // MEIP
    mip[7]     = timer_irq;   // MTIP
    mip[3]     = sw_irq;      // MSIP
  end

  // -----------------------------------------------------------------------
  // Exception / Interrupt detection
  // -----------------------------------------------------------------------
  logic        exception_taken;
  logic        interrupt_taken;
  logic [3:0]  exc_cause;
  logic        any_interrupt;

  // Global interrupt enable (MIE bit in mstatus)
  logic mstatus_mie;
  assign mstatus_mie = mstatus[3];

  // Previous interrupt enable
  logic mstatus_mpie;
  assign mstatus_mpie = mstatus[7];

  // Previous privilege mode
  priv_mode_e mstatus_mpp;
  assign mstatus_mpp = priv_mode_e'(mstatus[12:11]);

  // Interrupt check: enabled and pending
  assign any_interrupt = mstatus_mie && |(mie & mip);

  // Exception priority encoder
  always_comb begin
    exception_taken = 1'b0;
    exc_cause       = '0;

    if (insn_fault) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_INSN_FAULT;
    end else if (illegal_insn) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_ILLEGAL_INSN;
    end else if (is_ebreak) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_BREAKPOINT;
    end else if (is_ecall) begin
      exception_taken = 1'b1;
      exc_cause       = (priv_mode == PRIV_M) ? EXC_ECALL_M : EXC_ECALL_U;
    end else if (load_misalign) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_LOAD_MISALIGN;
    end else if (store_misalign) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_STORE_MISALIGN;
    end else if (load_fault) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_LOAD_FAULT;
    end else if (store_fault) begin
      exception_taken = 1'b1;
      exc_cause       = EXC_STORE_FAULT;
    end
  end

  assign interrupt_taken = any_interrupt && !exception_taken;
  assign trap_taken      = exception_taken || interrupt_taken;
  assign mret_taken      = is_mret && (priv_mode == PRIV_M);
  assign pipeline_flush  = trap_taken || mret_taken;

  // Trap target
  always_comb begin
    if (mtvec[1:0] == 2'b00)  // Direct mode
      trap_target = {mtvec[XLEN-1:2], 2'b00};
    else  // Vectored mode (for interrupts)
      trap_target = {mtvec[XLEN-1:2], 2'b00} + {26'b0, exc_cause, 2'b00};
  end

  assign mepc_out = mepc;

  // -----------------------------------------------------------------------
  // CSR Read Logic
  // -----------------------------------------------------------------------
  logic csr_read_illegal;
  assign csr_denied = csr_read_illegal;

  always_comb begin
    csr_rdata       = '0;
    csr_read_illegal = 1'b0;

    // Check privilege: CSR[9:8] encodes minimum privilege
    if (is_csr && (csr_addr_i[9:8] > priv_mode))
      csr_read_illegal = 1'b1;

    case (csr_addr_i)
      CSR_MSTATUS:   csr_rdata = mstatus;
      CSR_MISA:      csr_rdata = misa;
      CSR_MIE:       csr_rdata = mie;
      CSR_MTVEC:     csr_rdata = mtvec;
      CSR_MSCRATCH:  csr_rdata = mscratch;
      CSR_MEPC:      csr_rdata = mepc;
      CSR_MCAUSE:    csr_rdata = mcause;
      CSR_MTVAL:     csr_rdata = mtval;
      CSR_MIP:       csr_rdata = mip;
      CSR_PMPCFG0:   csr_rdata = pmpcfg0;
      CSR_PMPADDR0:  csr_rdata = pmpaddr_regs[0];
      CSR_PMPADDR1:  csr_rdata = pmpaddr_regs[1];
      CSR_PMPADDR2:  csr_rdata = pmpaddr_regs[2];
      CSR_PMPADDR3:  csr_rdata = pmpaddr_regs[3];
      CSR_MCYCLE:    csr_rdata = mcycle;
      CSR_MINSTRET:  csr_rdata = minstret;
      default: begin
        if (is_csr) csr_read_illegal = 1'b1;
      end
    endcase
  end

  // -----------------------------------------------------------------------
  // CSR Write Logic
  // -----------------------------------------------------------------------
  logic [XLEN-1:0] csr_wdata;

  // CSR write value computation (CSRRW/CSRRS/CSRRC and their I variants)
  always_comb begin
    logic [XLEN-1:0] write_val;

    // Source value: rs1_data for CSRRx, zero-extended rs1_addr for CSRRxI
    write_val = (funct3[2]) ? {27'b0, rs1_addr} : rs1_data;

    case (funct3[1:0])
      2'b01: csr_wdata = write_val;                    // CSRRW
      2'b10: csr_wdata = csr_rdata | write_val;        // CSRRS
      2'b11: csr_wdata = csr_rdata & ~write_val;       // CSRRC
      default: csr_wdata = csr_rdata;
    endcase
  end

  // -----------------------------------------------------------------------
  // CSR + State Update (Sequential)
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      priv_mode  <= PRIV_M;
      mstatus    <= 32'h0000_1800;  // MPP=M, MIE=0
      mie        <= '0;
      mtvec      <= '0;
      mscratch   <= '0;
      mepc       <= '0;
      mcause     <= '0;
      mtval      <= '0;
      mcycle     <= '0;
      minstret   <= '0;
      pmpcfg0    <= '0;
      for (int i = 0; i < PMP_REGIONS; i++)
        pmpaddr_regs[i] <= '0;
    end else begin
      // Cycle counter
      mcycle <= mcycle + 1;

      // Trap handling
      if (trap_taken) begin
        mepc   <= pc;
        mcause <= {interrupt_taken, 27'b0, exc_cause};
        mtval  <= '0;

        // Save previous MIE to MPIE, clear MIE, save current mode to MPP
        mstatus[7]     <= mstatus_mie;       // MPIE = MIE
        mstatus[3]     <= 1'b0;              // MIE = 0
        mstatus[12:11] <= priv_mode;         // MPP = current
        priv_mode      <= PRIV_M;            // Trap to M-mode
      end

      // MRET handling
      else if (mret_taken) begin
        mstatus[3]     <= mstatus_mpie;      // MIE = MPIE
        mstatus[7]     <= 1'b1;              // MPIE = 1
        priv_mode      <= mstatus_mpp;       // Restore privilege
        mstatus[12:11] <= PRIV_U;            // MPP = U (lowest)
      end

      // CSR writes (only when no trap)
      else if (is_csr && !csr_read_illegal) begin
        case (csr_addr_i)
          CSR_MSTATUS:  mstatus  <= csr_wdata & 32'h0000_1888;  // Mask writable bits
          CSR_MIE:      mie      <= csr_wdata;
          CSR_MTVEC:    mtvec    <= csr_wdata;
          CSR_MSCRATCH: mscratch <= csr_wdata;
          CSR_MEPC:     mepc     <= {csr_wdata[XLEN-1:2], 2'b00};
          CSR_MCAUSE:   mcause   <= csr_wdata;
          CSR_MTVAL:    mtval    <= csr_wdata;
          CSR_PMPCFG0:  pmpcfg0  <= csr_wdata;
          CSR_PMPADDR0: pmpaddr_regs[0] <= csr_wdata;
          CSR_PMPADDR1: pmpaddr_regs[1] <= csr_wdata;
          CSR_PMPADDR2: pmpaddr_regs[2] <= csr_wdata;
          CSR_PMPADDR3: pmpaddr_regs[3] <= csr_wdata;
          default: ; // Read-only or unimplemented
        endcase
      end

      // Instruction retire counter
      if (!trap_taken && !mret_taken)
        minstret <= minstret + 1;
    end
  end

  // -----------------------------------------------------------------------
  // PMP Configuration Extraction
  // -----------------------------------------------------------------------
  generate
    for (genvar i = 0; i < PMP_REGIONS; i++) begin : gen_pmp_cfg
      assign pmp_cfg[i].lock      = pmpcfg0[i*8 + 7];
      assign pmp_cfg[i].reserved  = pmpcfg0[i*8+6 : i*8+5];
      assign pmp_cfg[i].addr_mode = pmp_addr_mode_e'(pmpcfg0[i*8+4 : i*8+3]);
      assign pmp_cfg[i].exec      = pmpcfg0[i*8 + 2];
      assign pmp_cfg[i].write     = pmpcfg0[i*8 + 1];
      assign pmp_cfg[i].read      = pmpcfg0[i*8 + 0];
      assign pmp_addr[i]          = pmpaddr_regs[i];
    end
  endgenerate

endmodule
