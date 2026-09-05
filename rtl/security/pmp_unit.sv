// ============================================================================
// SecVeriRL — Physical Memory Protection (PMP) Unit
// ============================================================================
// Implements RISC-V PMP checks for all memory accesses.
// Supports NAPOT, NA4, TOR address matching for configurable regions.
// This is the PRIMARY security-critical module in the design.
// ============================================================================

module pmp_unit
  import secverirl_pkg::*;
#(
  parameter int XLEN        = 32,
  parameter int PMP_REGIONS = 4
)(
  input  priv_mode_e       current_priv,
  input  pmp_cfg_t         pmp_cfg  [PMP_REGIONS],
  input  logic [XLEN-1:0] pmp_addr [PMP_REGIONS],

  // Access request
  input  logic [XLEN-1:0] access_addr,
  input  logic             access_read,
  input  logic             access_write,
  input  logic             access_exec,

  // Check result
  output logic             pmp_allow,
  output logic             pmp_deny,
  output logic [3:0]       pmp_match_region  // Which region matched (-1 if none)
);

  // Per-region match and permission signals
  logic [PMP_REGIONS-1:0] region_match;
  logic [PMP_REGIONS-1:0] region_allow;

  // NAPOT address decoding
  logic [XLEN-1:0] region_base [PMP_REGIONS];
  logic [XLEN-1:0] region_mask [PMP_REGIONS];

  // Pre-declared variables for use inside generate/always_comb
  logic [XLEN-1:0] napot_mask   [PMP_REGIONS];
  logic [XLEN-1:0] napot_base   [PMP_REGIONS];
  logic [XLEN-1:0] shifted_addr [PMP_REGIONS];
  logic [XLEN-1:0] tor_lo       [PMP_REGIONS];
  logic [XLEN-1:0] tor_hi       [PMP_REGIONS];
  logic             r_ok         [PMP_REGIONS];
  logic             w_ok         [PMP_REGIONS];
  logic             x_ok         [PMP_REGIONS];

  // Priority encoder helper
  logic any_match;

  generate
    for (genvar i = 0; i < PMP_REGIONS; i++) begin : gen_pmp_check

      // Address range calculation
      always_comb begin
        region_base[i] = '0;
        region_mask[i] = '0;
        region_match[i] = 1'b0;
        napot_mask[i] = '0;
        napot_base[i] = '0;
        shifted_addr[i] = '0;
        tor_lo[i] = '0;
        tor_hi[i] = '0;

        case (pmp_cfg[i].addr_mode)
          PMP_OFF: begin
            region_match[i] = 1'b0;
          end

          PMP_NA4: begin
            // Naturally aligned 4-byte region
            region_base[i] = {pmp_addr[i][XLEN-1:0], 2'b00};
            region_match[i] = (access_addr[XLEN-1:2] == pmp_addr[i][XLEN-3:0]);
          end

          PMP_NAPOT: begin
            // NAPOT: find trailing ones to determine size
            shifted_addr[i] = {pmp_addr[i], 2'b00};

            // Compute mask: find lowest 0 bit in pmpaddr, everything below is size
            napot_mask[i] = ~(shifted_addr[i] ^ (shifted_addr[i] + 4));
            napot_base[i] = shifted_addr[i] & napot_mask[i];

            region_base[i] = napot_base[i];
            region_mask[i] = napot_mask[i];
            region_match[i] = ((access_addr & napot_mask[i]) == napot_base[i]);
          end

          PMP_TOR: begin
            // Top of Range: region is [pmpaddr[i-1], pmpaddr[i])
            if (i == 0)
              tor_lo[i] = '0;
            else
              tor_lo[i] = {pmp_addr[i-1], 2'b00};
            tor_hi[i] = {pmp_addr[i], 2'b00};

            region_base[i] = tor_lo[i];
            region_match[i] = (access_addr >= tor_lo[i]) && (access_addr < tor_hi[i]);
          end

          default: region_match[i] = 1'b0;
        endcase
      end

      // Permission check for matched region
      always_comb begin
        region_allow[i] = 1'b0;
        r_ok[i] = 1'b0;
        w_ok[i] = 1'b0;
        x_ok[i] = 1'b0;

        if (region_match[i]) begin
          // M-mode with no lock: allow everything
          if ((current_priv == PRIV_M) && !pmp_cfg[i].lock) begin
            region_allow[i] = 1'b1;
          end else begin
            // Check specific permissions
            r_ok[i] = !access_read  || pmp_cfg[i].read;
            w_ok[i] = !access_write || pmp_cfg[i].write;
            x_ok[i] = !access_exec  || pmp_cfg[i].exec;
            region_allow[i] = r_ok[i] && w_ok[i] && x_ok[i];
          end
        end
      end

    end
  endgenerate

  // Priority encoder: first matching region wins
  always_comb begin
    pmp_allow        = 1'b0;
    pmp_deny         = 1'b0;
    pmp_match_region = 4'hF;  // No match
    any_match        = |region_match;

    if (any_match) begin
      // Find first matching region (priority order)
      for (int i = 0; i < PMP_REGIONS; i++) begin
        if (region_match[i]) begin
          pmp_match_region = i[3:0];
          pmp_allow        = region_allow[i];
          pmp_deny         = !region_allow[i];
          break;
        end
      end
    end else begin
      // No match
      if (current_priv == PRIV_M) begin
        pmp_allow = 1'b1;  // M-mode: default allow
        pmp_deny  = 1'b0;
      end else begin
        pmp_allow = 1'b0;  // U-mode: default deny
        pmp_deny  = 1'b1;
      end
    end
  end

endmodule
