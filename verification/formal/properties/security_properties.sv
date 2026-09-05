// ============================================================================
// SecVeriRL — Security Properties for Formal Verification
// ============================================================================
// SystemVerilog Assertions (SVA) for security-critical properties.
// These are bound to the SoC top module during formal verification.
// ============================================================================

module security_properties
  import secverirl_pkg::*;
(
  input logic        clk,
  input logic        rst_n,

  // From core
  input priv_mode_e  current_priv,
  input logic [31:0] pc,
  input logic [31:0] rvfi_insn,
  input logic        rvfi_valid,
  input logic        rvfi_trap,

  // From PMP
  input logic        pmp_imem_deny,
  input logic        pmp_dmem_deny,
  input logic        pmp_imem_allow,
  input logic        pmp_dmem_allow,

  // From data bus
  input logic [31:0] dmem_addr,
  input logic        dmem_req,
  input logic        dmem_we,
  input logic        dmem_error,

  // From security monitor
  input logic        sec_alert,
  input logic [7:0]  sec_alert_code,

  // PMP config
  input pmp_cfg_t    pmp_cfg [4],
  input logic [31:0] pmp_addr_regs [4]
);

  // =========================================================================
  // Property 1: PMP Read Enforcement
  // If U-mode reads a PMP-protected region, access must be denied
  // =========================================================================
  property prop_pmp_read_enforce;
    @(posedge clk) disable iff (!rst_n)
    (dmem_req && !dmem_we && (current_priv == PRIV_U) && pmp_dmem_deny)
    |-> dmem_error;
  endproperty
  assert_pmp_read: assert property (prop_pmp_read_enforce)
    else $error("SECURITY: PMP read violation not enforced");

  // =========================================================================
  // Property 2: PMP Write Enforcement
  // =========================================================================
  property prop_pmp_write_enforce;
    @(posedge clk) disable iff (!rst_n)
    (dmem_req && dmem_we && (current_priv == PRIV_U) && pmp_dmem_deny)
    |-> dmem_error;
  endproperty
  assert_pmp_write: assert property (prop_pmp_write_enforce)
    else $error("SECURITY: PMP write violation not enforced");

  // =========================================================================
  // Property 3: PMP Execute Enforcement
  // If U-mode fetches from non-executable PMP region, fault must occur
  // =========================================================================
  property prop_pmp_exec_enforce;
    @(posedge clk) disable iff (!rst_n)
    (pmp_imem_deny && (current_priv == PRIV_U))
    |=> rvfi_trap;
  endproperty
  assert_pmp_exec: assert property (prop_pmp_exec_enforce)
    else $error("SECURITY: PMP exec violation not enforced");

  // =========================================================================
  // Property 4: No Privilege Escalation Without Trap
  // U→M transition can only happen via trap/exception
  // =========================================================================
  priv_mode_e prev_priv;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) prev_priv <= PRIV_M;
    else        prev_priv <= current_priv;
  end

  property prop_priv_no_escalation;
    @(posedge clk) disable iff (!rst_n)
    (prev_priv == PRIV_U) && (current_priv == PRIV_M)
    |-> rvfi_trap || (rvfi_valid && (rvfi_insn == 32'h30200073));  // MRET exception
  endproperty
  assert_no_escalation: assert property (prop_priv_no_escalation)
    else $error("SECURITY: Illegal privilege escalation U->M without trap");

  // =========================================================================
  // Property 5: CSR Access Control
  // U-mode cannot access M-mode CSRs (addr[9:8] == 2'b11)
  // =========================================================================
  logic is_csr_insn;
  logic [11:0] csr_addr_from_insn;
  assign is_csr_insn = rvfi_valid && (rvfi_insn[6:0] == 7'h73) &&
                       (rvfi_insn[14:12] != 3'b000);  // CSR instructions
  assign csr_addr_from_insn = rvfi_insn[31:20];

  property prop_csr_access_control;
    @(posedge clk) disable iff (!rst_n)
    (is_csr_insn && (current_priv == PRIV_U) && (csr_addr_from_insn[9:8] == 2'b11))
    |-> rvfi_trap;
  endproperty
  assert_csr_access: assert property (prop_csr_access_control)
    else $error("SECURITY: U-mode accessed M-mode CSR without trap");

  // =========================================================================
  // Property 6: Illegal Instruction Must Trap
  // =========================================================================
  property prop_illegal_insn_trap;
    @(posedge clk) disable iff (!rst_n)
    (rvfi_valid && (rvfi_insn[6:0] == 7'b0000000))  // All-zero = illegal
    |-> rvfi_trap;
  endproperty
  assert_illegal_trap: assert property (prop_illegal_insn_trap)
    else $error("SECURITY: Illegal instruction did not cause trap");

  // =========================================================================
  // Property 7: Secure Region Protection
  // U-mode data access to SECURE_ROM region must be denied
  // =========================================================================
  property prop_secure_region;
    @(posedge clk) disable iff (!rst_n)
    (dmem_req && (current_priv == PRIV_U) &&
     (dmem_addr >= SECURE_ROM_BASE) &&
     (dmem_addr < (SECURE_ROM_BASE + SECURE_ROM_SIZE)))
    |-> dmem_error || pmp_dmem_deny;
  endproperty
  assert_secure_region: assert property (prop_secure_region)
    else $error("SECURITY: U-mode accessed secure ROM region");

  // =========================================================================
  // Property 8: M-mode Always Has Full Access (when PMP not locked)
  // =========================================================================
  property prop_mmode_access;
    @(posedge clk) disable iff (!rst_n)
    (dmem_req && (current_priv == PRIV_M) && !pmp_cfg[0].lock &&
     !pmp_cfg[1].lock && !pmp_cfg[2].lock && !pmp_cfg[3].lock)
    |-> pmp_dmem_allow;
  endproperty
  assert_mmode_access: assert property (prop_mmode_access)
    else $error("SECURITY: M-mode access denied with no PMP locks");

  // =========================================================================
  // Cover Properties — for coverage-driven formal verification
  // =========================================================================

  // Cover: PMP violation occurs
  cover_pmp_violation: cover property (
    @(posedge clk) pmp_dmem_deny && (current_priv == PRIV_U)
  );

  // Cover: Privilege transition M→U
  cover_priv_m_to_u: cover property (
    @(posedge clk) (prev_priv == PRIV_M) && (current_priv == PRIV_U)
  );

  // Cover: Privilege transition U→M (via trap)
  cover_priv_u_to_m: cover property (
    @(posedge clk) (prev_priv == PRIV_U) && (current_priv == PRIV_M)
  );

  // Cover: Security alert raised
  cover_sec_alert: cover property (
    @(posedge clk) sec_alert
  );

  // Cover: All PMP regions active
  cover_all_pmp_active: cover property (
    @(posedge clk) (pmp_cfg[0].addr_mode != PMP_OFF) &&
                   (pmp_cfg[1].addr_mode != PMP_OFF) &&
                   (pmp_cfg[2].addr_mode != PMP_OFF) &&
                   (pmp_cfg[3].addr_mode != PMP_OFF)
  );

endmodule
