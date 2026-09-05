// ============================================================================
// SecVeriRL — SystemVerilog Package
// ============================================================================
// Global type definitions, parameters, and constants used across the design.
// This package is design-agnostic; DUT-specific parameters are set via
// top-level module parameters.
// ============================================================================

package secverirl_pkg;

  // -------------------------------------------------------------------------
  // ISA Parameters
  // -------------------------------------------------------------------------
  parameter int XLEN = 32;
  parameter int ILEN = 32;
  parameter int NUM_REGS = 32;
  parameter int REG_ADDR_W = 5;

  // -------------------------------------------------------------------------
  // PMP Parameters
  // -------------------------------------------------------------------------
  parameter int PMP_NUM_REGIONS = 4;
  parameter int PMP_ADDR_W = 32;

  // -------------------------------------------------------------------------
  // Bus Parameters
  // -------------------------------------------------------------------------
  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;
  parameter int AXI_STRB_W = AXI_DATA_W / 8;

  // -------------------------------------------------------------------------
  // Memory Map
  // -------------------------------------------------------------------------
  parameter logic [31:0] SRAM_BASE       = 32'h0000_0000;
  parameter logic [31:0] SRAM_SIZE       = 32'h0001_0000;  // 64KB
  parameter logic [31:0] UART_BASE       = 32'h4000_0000;
  parameter logic [31:0] UART_SIZE       = 32'h0000_1000;  // 4KB
  parameter logic [31:0] GPIO_BASE       = 32'h4000_1000;
  parameter logic [31:0] GPIO_SIZE       = 32'h0000_1000;  // 4KB
  parameter logic [31:0] SECURE_ROM_BASE = 32'h8000_0000;
  parameter logic [31:0] SECURE_ROM_SIZE = 32'h0000_4000;  // 16KB

  // -------------------------------------------------------------------------
  // Privilege Modes
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PRIV_U = 2'b00,   // User
    PRIV_S = 2'b01,   // Supervisor (reserved for future)
    PRIV_M = 2'b11    // Machine
  } priv_mode_e;

  // -------------------------------------------------------------------------
  // PMP Types
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PMP_OFF   = 2'b00,
    PMP_TOR   = 2'b01,
    PMP_NA4   = 2'b10,
    PMP_NAPOT = 2'b11
  } pmp_addr_mode_e;

  typedef struct packed {
    logic        lock;     // Lock bit
    logic [1:0]  reserved;
    pmp_addr_mode_e addr_mode;
    logic        exec;    // Execute permission
    logic        write;   // Write permission
    logic        read;    // Read permission
  } pmp_cfg_t;

  // -------------------------------------------------------------------------
  // Instruction Types (RV32I)
  // -------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OP_LUI      = 7'b0110111,
    OP_AUIPC    = 7'b0010111,
    OP_JAL      = 7'b1101111,
    OP_JALR     = 7'b1100111,
    OP_BRANCH   = 7'b1100011,
    OP_LOAD     = 7'b0000011,
    OP_STORE    = 7'b0100011,
    OP_IMM      = 7'b0010011,
    OP_REG      = 7'b0110011,
    OP_FENCE    = 7'b0001111,
    OP_SYSTEM   = 7'b1110011
  } opcode_e;

  // -------------------------------------------------------------------------
  // ALU Operations
  // -------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_SLL  = 4'b0010,
    ALU_SLT  = 4'b0011,
    ALU_SLTU = 4'b0100,
    ALU_XOR  = 4'b0101,
    ALU_SRL  = 4'b0110,
    ALU_SRA  = 4'b0111,
    ALU_OR   = 4'b1000,
    ALU_AND  = 4'b1001,
    ALU_MUL  = 4'b1010,  // M extension
    ALU_DIV  = 4'b1011,
    ALU_REM  = 4'b1100,
    ALU_PASS = 4'b1111
  } alu_op_e;

  // -------------------------------------------------------------------------
  // Exception/Trap Causes
  // -------------------------------------------------------------------------
  typedef enum logic [3:0] {
    EXC_INSN_MISALIGN  = 4'd0,
    EXC_INSN_FAULT     = 4'd1,
    EXC_ILLEGAL_INSN   = 4'd2,
    EXC_BREAKPOINT     = 4'd3,
    EXC_LOAD_MISALIGN  = 4'd4,
    EXC_LOAD_FAULT     = 4'd5,
    EXC_STORE_MISALIGN = 4'd6,
    EXC_STORE_FAULT    = 4'd7,
    EXC_ECALL_U        = 4'd8,
    EXC_ECALL_S        = 4'd9,
    EXC_ECALL_M        = 4'd11
  } exc_cause_e;

  // -------------------------------------------------------------------------
  // AXI-Lite Response
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  // -------------------------------------------------------------------------
  // CSR Addresses (subset for M-mode + U-mode)
  // -------------------------------------------------------------------------
  parameter logic [11:0] CSR_MSTATUS    = 12'h300;
  parameter logic [11:0] CSR_MISA       = 12'h301;
  parameter logic [11:0] CSR_MIE        = 12'h304;
  parameter logic [11:0] CSR_MTVEC      = 12'h305;
  parameter logic [11:0] CSR_MSCRATCH   = 12'h340;
  parameter logic [11:0] CSR_MEPC       = 12'h341;
  parameter logic [11:0] CSR_MCAUSE     = 12'h342;
  parameter logic [11:0] CSR_MTVAL      = 12'h343;
  parameter logic [11:0] CSR_MIP        = 12'h344;
  parameter logic [11:0] CSR_PMPCFG0    = 12'h3A0;
  parameter logic [11:0] CSR_PMPADDR0   = 12'h3B0;
  parameter logic [11:0] CSR_PMPADDR1   = 12'h3B1;
  parameter logic [11:0] CSR_PMPADDR2   = 12'h3B2;
  parameter logic [11:0] CSR_PMPADDR3   = 12'h3B3;
  parameter logic [11:0] CSR_MCYCLE     = 12'hB00;
  parameter logic [11:0] CSR_MINSTRET   = 12'hB02;

  // -------------------------------------------------------------------------
  // Utility Functions
  // -------------------------------------------------------------------------

  // Check if CSR address requires M-mode
  function automatic logic csr_requires_mmode(input logic [11:0] csr_addr);
    // CSRs 0x300-0x3FF and 0xB00-0xBFF are M-mode
    return (csr_addr[9:8] == 2'b11) || (csr_addr[11:10] == 2'b10);
  endfunction

  // Check if address falls within a memory region
  function automatic logic addr_in_region(
    input logic [31:0] addr,
    input logic [31:0] base,
    input logic [31:0] size
  );
    return (addr >= base) && (addr < (base + size));
  endfunction

endpackage
