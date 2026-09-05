// ============================================================================
// SecVeriRL — Security Monitor
// ============================================================================
// Hardware security monitor that observes all transactions and raises alerts
// on policy violations. Logs security events for verification analysis.
// This is a CUSTOM security module (not part of standard RISC-V spec).
// ============================================================================

module security_monitor
  import secverirl_pkg::*;
#(
  parameter int XLEN          = 32,
  parameter int LOG_DEPTH     = 16,
  parameter int PMP_REGIONS   = 4
)(
  input  logic              clk,
  input  logic              rst_n,

  // Privilege mode observation
  input  priv_mode_e        current_priv,
  input  priv_mode_e        prev_priv,
  input  logic              priv_changed,

  // PMP check results
  input  logic              pmp_deny,
  input  logic [3:0]        pmp_match_region,

  // Memory access observation
  input  logic [XLEN-1:0]  access_addr,
  input  logic              access_read,
  input  logic              access_write,
  input  logic              access_exec,

  // Instruction observation
  input  logic              illegal_insn,
  input  logic              is_ecall,
  input  logic              is_mret,
  input  logic              trap_taken,

  // CSR access observation
  input  logic              csr_access,
  input  logic [11:0]       csr_addr,
  input  logic              csr_denied,

  // Security alert outputs
  output logic              sec_alert,
  output logic [7:0]        sec_alert_code,
  output logic [31:0]       sec_event_count,

  // Security event log (readable via bus)
  output logic [XLEN-1:0]  sec_log_data,
  input  logic [3:0]        sec_log_idx
);

  // -----------------------------------------------------------------------
  // Security Alert Codes
  // -----------------------------------------------------------------------
  localparam logic [7:0] ALERT_NONE              = 8'h00;
  localparam logic [7:0] ALERT_PMP_VIOLATION     = 8'h01;
  localparam logic [7:0] ALERT_PRIV_ESCALATION   = 8'h02;
  localparam logic [7:0] ALERT_ILLEGAL_CSR       = 8'h03;
  localparam logic [7:0] ALERT_ILLEGAL_INSN      = 8'h04;
  localparam logic [7:0] ALERT_SECURE_REGION     = 8'h05;
  localparam logic [7:0] ALERT_RAPID_TRAPS       = 8'h06;

  // -----------------------------------------------------------------------
  // Internal state
  // -----------------------------------------------------------------------
  logic [31:0] event_counter;
  logic [31:0] event_log [LOG_DEPTH];
  logic [3:0]  log_wr_ptr;

  // Rapid trap detection
  logic [3:0]  trap_counter;
  logic [7:0]  trap_window_counter;
  localparam int TRAP_WINDOW = 64;
  localparam int TRAP_THRESHOLD = 8;

  assign sec_event_count = event_counter;

  // -----------------------------------------------------------------------
  // Security Check Logic
  // -----------------------------------------------------------------------
  logic        alert_pmp;
  logic        alert_priv;
  logic        alert_csr;
  logic        alert_insn;
  logic        alert_secure;
  logic        alert_rapid_trap;

  // PMP violation from U-mode
  assign alert_pmp = pmp_deny && (current_priv != PRIV_M);

  // Privilege escalation: U→M without trap (should not happen)
  assign alert_priv = priv_changed &&
                      (prev_priv == PRIV_U) &&
                      (current_priv == PRIV_M) &&
                      !trap_taken && !is_mret;

  // Unauthorized CSR access
  assign alert_csr = csr_denied;

  // Illegal instruction in U-mode
  assign alert_insn = illegal_insn && (current_priv == PRIV_U);

  // Access to secure memory region from U-mode
  assign alert_secure = (access_read || access_write || access_exec) &&
                        (current_priv == PRIV_U) &&
                        (access_addr >= SECURE_ROM_BASE) &&
                        (access_addr < (SECURE_ROM_BASE + SECURE_ROM_SIZE));

  // Rapid trap detection (possible attack probing)
  assign alert_rapid_trap = (trap_counter >= TRAP_THRESHOLD[3:0]);

  // Aggregate alert
  assign sec_alert = alert_pmp || alert_priv || alert_csr ||
                     alert_insn || alert_secure || alert_rapid_trap;

  // Alert code priority
  always_comb begin
    if (alert_pmp)             sec_alert_code = ALERT_PMP_VIOLATION;
    else if (alert_priv)       sec_alert_code = ALERT_PRIV_ESCALATION;
    else if (alert_csr)        sec_alert_code = ALERT_ILLEGAL_CSR;
    else if (alert_insn)       sec_alert_code = ALERT_ILLEGAL_INSN;
    else if (alert_secure)     sec_alert_code = ALERT_SECURE_REGION;
    else if (alert_rapid_trap) sec_alert_code = ALERT_RAPID_TRAPS;
    else                       sec_alert_code = ALERT_NONE;
  end

  // -----------------------------------------------------------------------
  // Event Logging & Counters
  // -----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      event_counter      <= '0;
      log_wr_ptr         <= '0;
      trap_counter       <= '0;
      trap_window_counter <= '0;
      for (int i = 0; i < LOG_DEPTH; i++)
        event_log[i] <= '0;
    end else begin
      // Trap window counter
      if (trap_window_counter >= TRAP_WINDOW[7:0]) begin
        trap_window_counter <= '0;
        trap_counter        <= '0;
      end else begin
        trap_window_counter <= trap_window_counter + 1;
        if (trap_taken)
          trap_counter <= trap_counter + 1;
      end

      // Log security events
      if (sec_alert) begin
        event_counter <= event_counter + 1;
        event_log[log_wr_ptr] <= {sec_alert_code, current_priv, 6'b0, access_addr[15:0]};
        log_wr_ptr <= log_wr_ptr + 1;
      end
    end
  end

  // Log readback
  assign sec_log_data = event_log[sec_log_idx];

endmodule
