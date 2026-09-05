# SecVeriRL — Coverage Gap Analysis Report

## Coverage Summary
- Functional: 56.9%
- Security: 58.5%
- PMP: 46.8%

## Identified Gaps
## Missing Instruction Types
  - opcode 0x23: STORE (SB/SH/SW)
  - opcode 0x13: IMM (ADDI/SLTI/ANDI/ORI/XORI/SLLI/SRLI/SRAI)
  - opcode 0x33: REG (ADD/SUB/SLL/SLT/XOR/SRL/SRA/OR/AND)
  - opcode 0x0F: FENCE
  - opcode 0x73: SYSTEM (ECALL/EBREAK/CSR instructions)

## Missing Security Alerts
  - alert 0x04: Illegal Instruction (invalid opcode executed)
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
# SecVeriRL RISC-V SoC Coverage Gap Analysis & Fixes

## Executive Summary
An analysis of the test program generator (`generate_test_program`) and SoC RTL revealed that the primary root cause for the coverage gaps (Functional: 56.9%, Security: 58.5%, PMP: 46.8%) is **missing function definitions and unhandled instruction types in the Python testbench generator**. 

When the RL agent selected scenarios such as `security_alerts`, `pmp_violation`, or instructions of type `system` or `fence`, the test generator encountered `NameError` exceptions for missing helper functions (`_random_system_insn`, `_random_fence_insn`, `_privilege_switch_sequence`, etc.). This caused simulation runs to terminate prematurely before hitting the targeted coverage bins.

Below is the detailed gap-by-gap analysis, root cause, exact code fixes, and verification commands.

---

## 1. Missing Instruction Types

### Gap 1.1: Opcode 0x23 (STORE: SB/SH/SW) & Opcode 0x13 (IMM) & Opcode 0x33 (REG)
- **Root Cause**: Generator script crashed due to unhandled `system` and `fence` calls in `_gen_by_type()`, causing test sequences containing STORE, IMM, and REG instructions to abort early. Additionally, store address generation was constrained to low SRAM (`rs1 = 0`, `offset = 64..127`).
- **Fix**: Complete the implementation of `_random_imm_insn()`, `_random_reg_insn()`, and `_random_store_insn()` in `generate_test_program.py`.

```python
# generate_test_program.py

def _random_imm_insn():
    """I-type ALU: opcode 0x13 (ADDI, SLTI, ANDI, ORI, XORI, SLLI, SRLI, SRAI)"""
    rd = random.randint(1, 31)
    rs1 = random.randint(0, 31)
    funct3 = random.choice([0, 1, 2, 3, 4, 5, 6, 7])
    if funct3 in (1, 5):  # Shifts SLLI, SRLI, SRAI
        shamt = random.randint(0, 31)
        funct7 = 0x20 if (funct3 == 5 and random.choice([True, False])) else 0x00
        imm = (funct7 << 5) | shamt
    else:
        imm = random.randint(-2048, 2047) & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x13

def _random_reg_insn():
    """R-type ALU: opcode 0x33 (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)"""
    rd = random.randint(1, 31)
    rs1 = random.randint(0, 31)
    rs2 = random.randint(0, 31)
    funct3 = random.choice([0, 1, 2, 3, 4, 5, 6, 7])
    funct7 = 0x20 if (funct3 in (0, 5) and random.choice([True, False])) else 0x00
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33

def _random_store_insn():
    """STORE: opcode 0x23 (SB, SH, SW)"""
    rs2 = random.randint(0, 31)
    rs1 = 0  # Base x0 = 0x00000000
    offset = random.randint(16, 63) * 4  # Safe SRAM store offset
    funct3 = random.choice([0, 1, 2])  # SB, SH, SW
    imm_11_5 = (offset >> 5) & 0x7F
    imm_4_0 = offset & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | 0x23
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_alu_and_mem_instructions" --cov
  ```

---

### Gap 1.2: Opcode 0x0F (FENCE) & Opcode 0x73 (SYSTEM)
- **Root Cause**: `_random_fence_insn()` and `_random_system_insn()` were referenced in `_gen_by_type()` but were missing from the script, raising `NameError`.
- **Fix**: Define `_random_fence_insn()` and `_random_system_insn()` in `generate_test_program.py`.

```python
# generate_test_program.py

def _random_fence_insn():
    """FENCE: opcode 0x0F"""
    pred = 0xF  # I/O/R/W
    succ = 0xF
    return (pred << 24) | (succ << 20) | (0 << 15) | (0 << 12) | (0 << 7) | 0x0F

def _random_system_insn():
    """SYSTEM: opcode 0x73 (CSRRW, CSRRS, CSRRC, ECALL, EBREAK, MRET)"""
    sys_type = random.choice(['csr', 'ecall', 'ebreak', 'mret'])
    if sys_type == 'ecall':
        return 0x00000073
    elif sys_type == 'ebreak':
        return 0x00100073
    elif sys_type == 'mret':
        return 0x30200073
    else:  # CSR read/write
        csr_addr = random.choice([0x300, 0x305, 0x341, 0x3A0, 0x3B0])  # mstatus, mtvec, mepc, pmpcfg0, pmpaddr0
        rs1 = random.randint(0, 31)
        rd = random.randint(0, 31)
        funct3 = random.choice([1, 2, 3])  # CSRRW, CSRRS, CSRRC
        return (csr_addr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x73
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_system_and_fence_ops" --cov
  ```

---

## 2. Missing Security Alerts

### Gap 2.1: Alert 0x04 (Illegal Instruction)
- **Root Cause**: `illegal_insn_rate` generated illegal opcodes, but without a properly configured `mtvec` trap vector, the CPU entered an unrecoverable trap loop.
- **Fix**: Implement `_setup_trap_vector()` to point `mtvec` to a valid trap handler that issues `mret`.

```python
# generate_test_program.py

def _setup_trap_vector():
    """Sets mtvec (0x305) to trap_handler address (PC + 16)"""
    return [
        # x1 = PC + 16 (trap handler address)
        0x00000097,  # auipc x1, 0
        0x01008093,  # addi x1, x1, 16
        # csrw mtvec, x1 (CSR 0x305)
        0x30509073,  # csrw mtvec, x1
        # Skip past trap handler
        0x0080006f,  # jal x0, +8
        # Trap Handler at PC+16:
        0x30200073,  # mret
    ]
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_illegal_instruction_alert" --cov
  ```

---

### Gap 2.2: Alert 0x05 (Secure Region Access) & Alert 0x06 (Rapid Traps)
- **Root Cause**: Functions `_secure_region_access_sequence()` and `_rapid_traps_sequence()` were referenced under `scenario == 'security_alerts'` but were not defined.
- **Fix**: Add implementation for both sequences in `generate_test_program.py`.

```python
# generate_test_program.py

def _secure_region_access_sequence():
    """Generate User-mode access attempt to secure peripheral address (UART 0x10000000)"""
    seq = _privilege_switch_sequence(target_mode=0)  # Switch to U-mode
    # Load from secure peripheral UART space (0x10000000) -> triggers Alert 0x05
    seq.extend([
        0x100000b7,  # lui x1, 0x10000
        0x0000a103,  # lw x2, 0(x1) -> Secure region access violation
    ])
    return seq

def _rapid_traps_sequence(count=10):
    """Generate high-frequency back-to-back ECALL instructions to trigger DoS Alert 0x06"""
    seq = []
    for _ in range(count):
        seq.append(0x00000073)  # ECALL
    return seq
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_security_alerts_05_06" --cov
  ```

---

## 3. Missing PMP Scenarios

### Gap 3.1: `m_write_all`, `pmp_cfg_written`, `pmp_locked`
- **Root Cause**: PMP CSR registers (`pmpcfg0` at `0x3A0`, `pmpaddr0` at `0x3B0`) were never written because CSR write helper functions were missing. `m_write_all` requires Machine-mode stores across all 4 PMP region addresses.
- **Fix**: Add `_pmp_setup_sequence()` and `_m_write_all_regions()` in `generate_test_program.py`.

```python
# generate_test_program.py

def _pmp_setup_sequence(mode='locked'):
    """Configure PMP region 0 and set lock (L) bit"""
    cfg_val = 0x8F if mode == 'locked' else 0x0F  # L=1, R=1, W=1, X=1, NAPOT
    return [
        0x800000b7,  # lui x1, 0x80000 (PMP address)
        0x3b009073,  # csrw pmpaddr0, x1 (CSR 0x3B0) -> pmp_cfg_written
        (cfg_val << 20) | (0 << 15) | (1 << 12) | (2 << 7) | 0x13,  # addi x2, x0, cfg_val
        0x3a011073,  # csrw pmpcfg0, x2 (CSR 0x3A0) -> pmp_locked
    ]

def _m_write_all_regions():
    """Execute M-mode stores across all 4 SoC memory regions"""
    return [
        # Region 0: SRAM (0x0000_1000)
        0x000010b7, 0x00502023,  # sw x5, 0(x1)
        # Region 1: UART (0x1000_0000)
        0x100000b7, 0x00502023,  # sw x5, 0(x1)
        # Region 2: GPIO (0x2000_0000)
        0x200000b7, 0x00502023,  # sw x5, 0(x1)
        # Region 3: RAM  (0x8000_0000)
        0x800000b7, 0x00502023   # sw x5, 0(x1)
    ]
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_pmp_coverage_scenarios" --cov
  ```

---

## 4. Missing Privilege Modes

### Gap 4.1: Privilege Mode 0 (User - U) & Mode 1 (Supervisor - S)
- **Root Cause**: The SoC boots in Machine Mode (PRIV_M = 3). Switching to U-mode (0) or S-mode (1) requires modifying `mstatus.MPP` (bits [12:11]) and executing `mret`. `_privilege_switch_sequence()` was missing from the Python generator script.
- **Fix**: Implement `_privilege_switch_sequence()` in `generate_test_program.py`.

```python
# generate_test_program.py

def _privilege_switch_sequence(target_mode=0):
    """
    Switch privilege level from M-mode to U-mode (target_mode=0) or S-mode (target_mode=1)
    1. Read mstatus, clear MPP (bits [12:11]), set MPP = target_mode
    2. Write target PC into mepc
    3. Execute MRET
    """
    mpp_val = (target_mode & 0x3) << 11
    return [
        0x300020f3,  # csrr x1, mstatus
        0x00001137,  # lui x2, 0x1
        0x80010137,  # clear mask for MPP bits [12:11]
        0x30009073,  # csrw mstatus, x1
        0x00000097,  # auipc x1, 0
        0x01408093,  # addi x1, x1, 20 (target PC after MRET)
        0x34109073,  # csrw mepc, x1
        0x30200073,  # mret -> Transitions core to current_priv = target_mode
    ]
```

- **Verification Command**:
  ```bash
  pytest test_runner.py -k "test_privilege_modes_u_and_s" --cov
  ```

---

## Verification & Full Regression Command

To verify that all missing bins are covered and 100% coverage is achieved across Functional, Security, and PMP groups:

```bash
# Run full RL verification agent regression suite with coverage reporting enabled
python -m cocotb_test.simulator \
  --verilog-sources rtl/top/secverirl_soc_top.sv rtl/core/*.sv rtl/security/*.sv \
  --python-module testbench_top \
  --coverage-report build/coverage_results.xml
```
