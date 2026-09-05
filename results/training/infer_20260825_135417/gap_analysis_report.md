# SecVeriRL — Coverage Gap Analysis Report

## Coverage Summary
- Functional: 63.9%
- Security: 68.7%
- PMP: 55.0%

## Identified Gaps
## Missing Instruction Types
  - opcode 0x13: IMM (ADDI/SLTI/ANDI/ORI/XORI/SLLI/SRLI/SRAI)
  - opcode 0x33: REG (ADD/SUB/SLL/SLT/XOR/SRL/SRA/OR/AND)
  - opcode 0x0F: FENCE
  - opcode 0x73: SYSTEM (ECALL/EBREAK/CSR instructions)

## Missing Security Alerts
  - alert 0x05: Secure Region Access (access to secure peripheral space)
  - alert 0x06: Rapid Traps (excessive trap frequency — DoS detection)

## Missing PMP Scenarios
  - m_write_all: Machine-mode WRITE to all regions (baseline)
  - pmp_cfg_written: PMP configuration register was written
  - pmp_locked: PMP region was locked (L-bit set in pmpcfg)

## Missing Privilege Modes
  - Mode 0: User (U)
  - Mode 1: Supervisor (S)


## Gemini Analysis
Here is the detailed coverage gap analysis and resolution plan for the **SecVeriRL** RISC-V SoC design.

---

# SecVeriRL Coverage Gap Analysis & Action Plan

---

## Gap 1: Missing Privilege Modes (User Mode 0 & Supervisor Mode 1)

### 1. Root Cause
The core powers up in Machine Mode (`PRIV_M = 2'b11`). The test generator currently lacks the routine to drop privilege levels. To switch to User (`PRIV_U = 2'b00`) or Supervisor (`PRIV_S = 2'b01`) mode in RISC-V:
1. `mstatus.MPP` (bits [12:11]) must be set to `00` or `01`.
2. `mepc` (CSR `0x341`) must be configured with the target instruction address.
3. An `MRET` instruction (`0x30200073`) must be executed.

Because the RL agent does not execute this 3-step sequence, the CPU remains trapped in `PRIV_M` for the entire duration of the test run, resulting in 0% coverage for User and Supervisor privilege modes.

### 2. Specific Fix

#### Test Generator Fix (`cocotb` testbench / Python generator):
Add explicit helper functions to generate the privilege transition sequences:

```python
def _privilege_switch_sequence(target_mode):
    """
    Generate sequence to switch from M-mode to U-mode (0) or S-mode (1).
    target_mode: 0 for User, 1 for Supervisor
    """
    seq = []
    # 1. LI x1, (target_mode << 11) -> mstatus.MPP
    mpp_val = (target_mode & 0x3) << 11
    seq.append(0x000000B7 | (mpp_val << 12))     # LUI x1, mpp_val
    seq.append(0x30009073)                        # CSRRW x0, mstatus (0x300), x1
    
    # 2. Set mepc (0x341) to target PC (current PC + 16 to skip sequence)
    seq.append(0x34101073)                        # CSRRW x0, mepc (0x341), x0 (or PC relative)
    
    # 3. MRET instruction to execute privilege drop
    seq.append(0x30200073)                        # MRET (0x30200073)
    
    return seq
```

Integrate into `generate_test_program(knobs)`:
```python
    elif scenario == 'privilege_switch':
        # Drop to User mode (0) or Supervisor mode (1)
        target = random.choice([0, 1])
        program.extend(_privilege_switch_sequence(target))
```

### 3. Verification Command
```bash
pytest test_top.py -k "test_privilege_switch" --knobs="test_scenario=privilege_switch"
```

---

## Gap 2: Missing Security Alerts (Alert 0x05 & Alert 0x06)

### 1. Root Cause
- **Alert 0x05 (Secure Region Access Violation):** Triggered when an unprivileged mode (U/S mode) attempts to access protected peripheral ranges or when a PMP rule denies access. Because the core never enters U/S mode (Gap 1), this alert is never triggered.
- **Alert 0x06 (Rapid Traps / DoS Detection):** Triggered when consecutive traps (illegal instructions, ECALLs, memory faults) occur within a small cycle window. The test generator only generates isolated illegal instructions with `illegal_insn_rate`, which space out traps too far apart to trigger the hardware DoS monitor.

### 2. Specific Fix

#### Test Generator Fix (`cocotb` testbench):

```python
def _generate_secure_region_access_violation():
    """Switch to U-mode and access secure peripheral range (Alert 0x05)."""
    seq = _privilege_switch_sequence(target_mode=0) # Drop to U-mode
    # Attempt LW from secure peripheral space (e.g., 0x4000_0000)
    seq.append(0x40000083)  # LW x1, 0(x0) targeting secure address
    return seq

def _generate_rapid_traps_sequence(count=8):
    """Generate back-to-back illegal instructions to trigger Alert 0x06."""
    # Consecutive illegal opcodes (0x00000000)
    return [0x00000000] * count
```

Update `generate_test_program(knobs)`:
```python
    elif scenario == 'security_alerts':
        alert_type = knobs.get('target_alert', 'rapid_traps')
        if alert_type == 'secure_access':
            program.extend(_generate_secure_region_access_violation())
        elif alert_type == 'rapid_traps':
            program.extend(_generate_rapid_traps_sequence(count=10))
```

### 3. Verification Command
```bash
pytest test_top.py -k "test_security_alerts" --knobs="test_scenario=security_alerts,target_alert=rapid_traps"
pytest test_top.py -k "test_security_alerts" --knobs="test_scenario=security_alerts,target_alert=secure_access"
```

---

## Gap 3: Missing PMP Scenarios (`m_write_all`, `pmp_cfg_written`, `pmp_locked`)

### 1. Root Cause
1. **`pmp_cfg_written`:** The PMP configuration registers (`pmpcfg0` at CSR `0x3A0`) are not being targeted by CSR write instructions (`CSRRW`/`CSRRS`).
2. **`pmp_locked`:** The `L` bit (bit 7 of `pmpcfgX`) is never set to `1` in the generated CSR values. When `L=0`, M-mode bypasses standard PMP permission checks.
3. **`m_write_all`:** In M-mode, memory store operations (`opcode 0x23`) are only issuing writes to region 0 (SRAM), never hitting addresses that fall into PMP regions 1, 2, and 3.

### 2. Specific Fix

#### Test Generator Fix (`cocotb` testbench):

```python
def _pmp_setup_sequence(pmp_mode):
    """Program PMP registers including lock bit and multiple matching regions."""
    seq = []
    
    # 1. Write pmpaddr0 (CSR 0x3B0) with address threshold
    seq.append(0x200000b7) # LUI x1, 0x20000
    seq.append(0x3b009073) # CSRRW x0, pmpaddr0 (0x3B0), x1
    
    # 2. Write pmpcfg0 (CSR 0x3A0) with Lock bit set (0x8F = Locked, NAPOT, R/W/X)
    if pmp_mode == 'locked':
        seq.append(0x08f00093) # ADDI x1, x0, 0x8F (L=1, A=NAPOT, R=1, W=1, X=1)
    else:
        seq.append(0x00f00093) # ADDI x1, x0, 0x0F (L=0)
        
    seq.append(0x3a009073) # CSRRW x0, pmpcfg0 (0x3A0), x1 (hits pmp_cfg_written)
    return seq

def _generate_m_write_all_regions():
    """Issue Machine-mode stores targeting all 4 PMP region address bounds."""
    seq = []
    region_addresses = [0x00001000, 0x10000000, 0x20000000, 0x30000000]
    for addr in region_addresses:
        # LUI x1, upper 20 bits
        seq.append((addr & 0xFFFFF000) | 0x000000B7)
        # SW x0, 0(x1)
        seq.append(0x0000A023)
    return seq
```

### 3. Verification Command
```bash
pytest test_top.py -k "test_pmp_coverage" --knobs="pmp_config_mode=locked,test_scenario=m_write_all"
```

---

## Gap 4: Missing Instruction Types (Opcode 0x13 IMM, Opcode 0x33 REG, Opcode 0x0F FENCE, Opcode 0x73 SYSTEM)

### 1. Root Cause
- **Opcode 0x0F (FENCE Hanging the Core):** `rv32i_decoder.sv` correctly asserts `is_fence = 1'b1`. However, the core FSM in `rv32i_core.sv` does not handle `is_fence` in `ST_EXECUTE`. As a result, when a `FENCE` instruction is executed, the state machine stalls indefinitely in `ST_EXECUTE`. This stops all subsequent instructions from retiring (`rvfi_valid` drops to 0), causing the simulation to stall and starving the coverage monitor.
- **Opcode 0x73 (SYSTEM Hanging on Traps):** Executing `ECALL` or `EBREAK` triggers a trap into `u_control`. Because `mtvec` (trap vector) is uninitialized (0x00000000), the core fetches instructions from address 0x0, entering an infinite loop/hang.
- **Opcode 0x13 (IMM) & Opcode 0x33 (REG):** These instruction classes failed to achieve coverage because early test runs stalled out whenever `FENCE` or `SYSTEM` instructions were encountered in `mixed` mode, preventing the rest of the stream from being decoded.

### 2. Specific Fix

#### RTL Fix 1: Fix FENCE instruction handling in `rtl/core/rv32i_core.sv`
Add `is_fence` logic to complete the instruction cycle cleanly without stalling:

```systemverilog
// Inside rv32i_core.sv state machine logic (ST_EXECUTE / Next State logic)
always_comb begin
  next_state = state;
  case (state)
    ST_DECODE: begin
      next_state = ST_EXECUTE;
    end
    
    ST_EXECUTE: begin
      if (dec_is_fence) begin
        // FENCE in this single-core implementation is a NOP; advance PC and finish
        next_state = ST_FETCH;
      end else if (dec_mem_read || dec_mem_write) begin
        next_state = ST_MEMORY;
      end else begin
        next_state = ST_WRITEBACK;
      end
    end
    
    // ... rest of state machine
  endcase
end
```

#### RTL Fix 2: Handle PC increment for FENCE in `rtl/core/rv32i_core.sv`
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    pc <= RESET_ADDR;
  end else if (state == ST_EXECUTE && dec_is_fence) begin
    pc <= pc + 4; // Advance PC for FENCE
  end else if (state == ST_WRITEBACK) begin
    pc <= next_pc;
  end
end
```

#### Testbench Fix: Ensure `mtvec` is initialized in test sequences
```python
def _setup_trap_vector():
    """Initialize mtvec (0x305) to point to a safe trap handler routine."""
    seq = []
    seq.append(0x000000b7) # LUI x1, 0x00000
    seq.append(0x10008093) # ADDI x1, x1, 0x100 (trap handler at 0x100)
    seq.append(0x30509073) # CSRRW x0, mtvec (0x305), x1
    return seq
```

### 3. Verification Command
```bash
pytest test_top.py -k "test_all_opcodes" --knobs="test_scenario=mixed,illegal_insn_rate=0.0"
```

---

## Summary Table of Action Items

| Missing Coverage Target | Primary Module | Root Cause Type | Required Action |
| :--- | :--- | :--- | :--- |
| **Opcode 0x0F (FENCE)** | `rv32i_core.sv` | **RTL Bug** | Add execution completion logic for `is_fence` in core state machine. |
| **Opcode 0x73 (SYSTEM)** | `cocotb` Testbench | **Testbench Bug** | Initialize `mtvec` CSR before triggering `ECALL`/`EBREAK` traps. |
| **Opcodes 0x13 / 0x33** | `cocotb` Testbench | **Testbench Starvation** | Resolved automatically once FENCE/SYSTEM RTL hangs are fixed. |
| **Privilege Modes 0 & 1** | `cocotb` Testbench | **Missing Sequence** | Add `_privilege_switch_sequence()` with `mstatus.MPP` write + `MRET`. |
| **Alert 0x05 / 0x06** | `cocotb` Testbench | **Missing Sequence** | Add targeted U-mode secure access and rapid back-to-back trap bursts. |
| **PMP Locked / CFG** | `cocotb` Testbench | **Missing Configuration** | Execute explicit CSR writes to `pmpcfg0` (`0x3A0`) with `L=1` (bit 7). |
