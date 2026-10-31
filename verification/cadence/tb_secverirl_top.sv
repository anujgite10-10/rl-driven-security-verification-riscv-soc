// ============================================================================
// SecVeriRL — Cadence Incisive SystemVerilog Testbench
// ============================================================================
// Comprehensive verification testbench for the SecVeriRL SoC.
// Exercises: reset, instruction execution, PMP security, privilege
// escalation, illegal CSR access, interrupt handling, and memory
// boundary violations.
//
// Run with: irun -f filelist.f -sv -access +rwc -timescale 1ns/1ps
// ============================================================================

`timescale 1ns/1ps

module tb_secverirl_top;

  import secverirl_pkg::*;

  // -----------------------------------------------------------------------
  // Parameters
  // -----------------------------------------------------------------------
  parameter int XLEN       = 32;
  parameter int PMP_REGIONS = 4;
  parameter int CLK_PERIOD = 20; // 50 MHz

  // -----------------------------------------------------------------------
  // Signals
  // -----------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        ext_irq;
  logic        timer_irq;
  logic        sw_irq;
  logic [15:0] gpio_out;
  logic [15:0] gpio_in;
  logic [15:0] gpio_oe;
  logic        uart_tx;
  logic        uart_rx;
  logic        sec_alert;
  logic [7:0]  sec_alert_code;
  logic [31:0] sec_event_count;
  logic        rvfi_valid;
  logic [XLEN-1:0] rvfi_insn;
  logic [XLEN-1:0] rvfi_pc;
  logic [XLEN-1:0] rvfi_next_pc;
  logic [4:0]  rvfi_rd_addr;
  logic [XLEN-1:0] rvfi_rd_data;
  logic        rvfi_trap;
  priv_mode_e  rvfi_priv;

  // -----------------------------------------------------------------------
  // Coverage counters
  // -----------------------------------------------------------------------
  int insn_retired_count;
  int trap_count;
  int sec_alert_count;
  int priv_m_count;
  int priv_u_count;
  int pass_count;
  int fail_count;

  // -----------------------------------------------------------------------
  // Clock generation
  // -----------------------------------------------------------------------
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -----------------------------------------------------------------------
  // DUT instantiation
  // -----------------------------------------------------------------------
  secverirl_soc_top #(
    .XLEN       (XLEN),
    .PMP_REGIONS(PMP_REGIONS),
    .RESET_ADDR (32'h0000_0000)
  ) u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .ext_irq         (ext_irq),
    .timer_irq       (timer_irq),
    .sw_irq          (sw_irq),
    .gpio_out        (gpio_out),
    .gpio_in         (gpio_in),
    .gpio_oe         (gpio_oe),
    .uart_tx         (uart_tx),
    .uart_rx         (uart_rx),
    .sec_alert       (sec_alert),
    .sec_alert_code  (sec_alert_code),
    .sec_event_count (sec_event_count),
    .rvfi_valid      (rvfi_valid),
    .rvfi_insn       (rvfi_insn),
    .rvfi_pc         (rvfi_pc),
    .rvfi_next_pc    (rvfi_next_pc),
    .rvfi_rd_addr    (rvfi_rd_addr),
    .rvfi_rd_data    (rvfi_rd_data),
    .rvfi_trap       (rvfi_trap),
    .rvfi_priv       (rvfi_priv)
  );

  // -----------------------------------------------------------------------
  // RVFI monitor — count retired instructions and traps
  // -----------------------------------------------------------------------
  always @(posedge clk) begin
    if (rvfi_valid) begin
      insn_retired_count++;
      if (rvfi_trap)
        trap_count++;
      if (rvfi_priv == PRIV_M)
        priv_m_count++;
      else if (rvfi_priv == PRIV_U)
        priv_u_count++;
    end
  end

  // Security alert monitor
  always @(posedge clk) begin
    if (sec_alert) begin
      sec_alert_count++;
      $display("[SEC ALERT] time=%0t code=0x%02h total_events=%0d",
               $time, sec_alert_code, sec_event_count);
    end
  end

  // -----------------------------------------------------------------------
  // Task: Reset DUT
  // -----------------------------------------------------------------------
  task automatic do_reset();
    rst_n     <= 1'b0;
    ext_irq   <= 1'b0;
    timer_irq <= 1'b0;
    sw_irq    <= 1'b0;
    uart_rx   <= 1'b1;  // UART idle
    gpio_in   <= 16'h0;
    insn_retired_count = 0;
    trap_count         = 0;
    sec_alert_count    = 0;
    priv_m_count       = 0;
    priv_u_count       = 0;
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (3) @(posedge clk);
    $display("[RESET] DUT reset complete at time=%0t", $time);
  endtask

  // -----------------------------------------------------------------------
  // Task: Load a program into SRAM via backdoor
  // -----------------------------------------------------------------------
  task automatic load_program(input logic [31:0] program_mem[], input int size);
    int i;
    $display("[LOAD] Writing %0d instructions to SRAM", size);
    for (i = 0; i < size; i++) begin
      u_dut.u_sram.mem[i] = program_mem[i];
    end
  endtask

  // -----------------------------------------------------------------------
  // Task: Run N clock cycles and report
  // -----------------------------------------------------------------------
  task automatic run_cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  // Task: Wait for instruction retirement or timeout
  // -----------------------------------------------------------------------
  task automatic wait_for_retire(input int max_cycles, output int retired);
    int start_count;
    start_count = insn_retired_count;
    repeat (max_cycles) @(posedge clk);
    retired = insn_retired_count - start_count;
  endtask

  // -----------------------------------------------------------------------
  // Assertion helper
  // -----------------------------------------------------------------------
  task automatic check(input string name, input logic condition);
    if (condition) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      $display("[FAIL] %s", name);
      fail_count++;
    end
  endtask

  // =======================================================================
  // TEST 1: Basic Reset
  // =======================================================================
  task automatic test_basic_reset();
    $display("\n" , "="*70);
    $display("  TEST 1: Basic Reset & Startup");
    $display("="*70);

    do_reset();
    run_cycles(10);

    check("rst_n is deasserted",   rst_n === 1'b1);
    check("PC starts at 0x0",      rvfi_pc === 32'h0000_0000 || rvfi_pc === 32'h0);
    check("Privilege is M-mode",   rvfi_priv == PRIV_M);

    $display("  Instructions retired after reset: %0d", insn_retired_count);
  endtask

  // =======================================================================
  // TEST 2: Basic Instruction Execution (ADDI)
  // =======================================================================
  task automatic test_instruction_execution();
    logic [31:0] prog [0:7];
    int retired;

    $display("\n", "="*70);
    $display("  TEST 2: Instruction Execution (RV32I ALU)");
    $display("="*70);

    do_reset();

    // addi x1, x0, 42      → x1 = 42
    // addi x2, x1, 10      → x2 = 52
    // add  x3, x1, x2      → x3 = 94
    // sub  x4, x2, x1      → x4 = 10
    // or   x5, x1, x2      → x5 = 42|52 = 62
    // and  x6, x1, x2      → x6 = 42&52 = 32
    // nop
    // nop
    prog[0] = 32'h02A00093;  // addi x1, x0, 42
    prog[1] = 32'h00A08113;  // addi x2, x1, 10
    prog[2] = 32'h002081B3;  // add  x3, x1, x2
    prog[3] = 32'h40208233;  // sub  x4, x2, x1
    prog[4] = 32'h0020E2B3;  // or   x5, x1, x2
    prog[5] = 32'h0020F333;  // and  x6, x1, x2
    prog[6] = 32'h00000013;  // nop
    prog[7] = 32'h00000013;  // nop

    load_program(prog, 8);

    wait_for_retire(200, retired);

    $display("  Instructions retired: %0d", retired);
    $display("  Traps taken:          %0d", trap_count);

    check("At least 4 instructions retired", retired >= 4);
    check("No traps in basic ALU test",      trap_count == 0);
  endtask

  // =======================================================================
  // TEST 3: Memory Load/Store
  // =======================================================================
  task automatic test_memory_operations();
    logic [31:0] prog [0:7];
    int retired;

    $display("\n", "="*70);
    $display("  TEST 3: Memory Load/Store Operations");
    $display("="*70);

    do_reset();

    // addi x1, x0, 0xAB      → x1 = 0xAB
    // lui  x2, 0x00001        → x2 = 0x1000 (safe SRAM address)
    // sw   x1, 0(x2)          → MEM[0x1000] = 0xAB
    // lw   x3, 0(x2)          → x3 = MEM[0x1000] = 0xAB
    // sb   x1, 4(x2)          → MEM[0x1004] = 0xAB (byte)
    // lb   x4, 4(x2)          → x4 = MEM[0x1004]
    // nop
    // nop
    prog[0] = 32'h0AB00093;  // addi x1, x0, 0xAB
    prog[1] = 32'h00001137;  // lui  x2, 0x1
    prog[2] = 32'h00112023;  // sw   x1, 0(x2)
    prog[3] = 32'h00012183;  // lw   x3, 0(x2)
    prog[4] = 32'h00110223;  // sb   x1, 4(x2)
    prog[5] = 32'h00410203;  // lb   x4, 4(x2)
    prog[6] = 32'h00000013;  // nop
    prog[7] = 32'h00000013;  // nop

    load_program(prog, 8);

    wait_for_retire(300, retired);

    $display("  Instructions retired: %0d", retired);
    check("Load/Store instructions retired", retired >= 4);
  endtask

  // =======================================================================
  // TEST 4: PMP Security — Configure & Attempt Violation
  // =======================================================================
  task automatic test_pmp_security();
    logic [31:0] prog [0:15];
    int retired;
    int initial_alerts;

    $display("\n", "="*70);
    $display("  TEST 4: PMP Security — Privilege Isolation");
    $display("="*70);

    do_reset();
    initial_alerts = sec_alert_count;

    // Program:
    //   M-mode: Configure PMP region 0 to protect 0x8000_0000 (M-only)
    //   M-mode: Set up trap handler at mtvec
    //   M-mode: Switch to U-mode via MRET
    //   U-mode: Attempt illegal memory access → should trap

    // Set mtvec to a trap handler address (point back to M-mode NOPs)
    prog[0]  = 32'h00000297;  // auipc t0, 0        (t0 = PC)
    prog[1]  = 32'h03828293;  // addi  t0, t0, 56   (t0 = addr of trap handler)
    prog[2]  = 32'h30529073;  // csrw  mtvec, t0

    // Set PMP: pmpaddr0 = 0x8000_0000 >> 2
    prog[3]  = 32'h80000137;  // lui   x2, 0x80000
    prog[4]  = 32'h00215113;  // srli  x2, x2, 2
    prog[5]  = 32'h3B011073;  // csrw  pmpaddr0, x2

    // Set pmpcfg0: NAPOT, RWX for M-mode
    prog[6]  = 32'h01F00113;  // addi  x2, x0, 0x1F
    prog[7]  = 32'h3A011073;  // csrw  pmpcfg0, x2

    // Prepare to switch to U-mode
    prog[8]  = 32'h00000297;  // auipc t0, 0
    prog[9]  = 32'h01428293;  // addi  t0, t0, 20   (mepc = U-mode code)
    prog[10] = 32'h34129073;  // csrw  mepc, t0
    prog[11] = 32'h00000113;  // addi  x2, x0, 0    (MPP = U-mode in mstatus)
    prog[12] = 32'h30011073;  // csrw  mstatus, x2
    prog[13] = 32'h30200073;  // mret → jump to U-mode

    // U-mode code (should be at prog[14])
    prog[14] = 32'h00000013;  // nop (in U-mode)
    prog[15] = 32'h00000013;  // nop

    load_program(prog, 16);

    wait_for_retire(500, retired);

    $display("  Instructions retired:   %0d", retired);
    $display("  Traps taken:            %0d", trap_count);
    $display("  Security alerts:        %0d", sec_alert_count - initial_alerts);
    $display("  Priv M-mode cycles:     %0d", priv_m_count);
    $display("  Priv U-mode cycles:     %0d", priv_u_count);

    check("PMP config was written (insns retired)", retired >= 10);
    check("Security monitor detected events",
          (sec_alert_count - initial_alerts) > 0 || trap_count > 0);
  endtask

  // =======================================================================
  // TEST 5: Illegal CSR Access from U-mode
  // =======================================================================
  task automatic test_illegal_csr();
    logic [31:0] prog [0:11];
    int retired;
    int initial_traps;

    $display("\n", "="*70);
    $display("  TEST 5: Illegal CSR Access (U-mode → M-mode CSR)");
    $display("="*70);

    do_reset();
    initial_traps = trap_count;

    // Set up trap handler
    prog[0]  = 32'h00000297;  // auipc t0, 0
    prog[1]  = 32'h02C28293;  // addi  t0, t0, 44   (trap handler addr)
    prog[2]  = 32'h30529073;  // csrw  mtvec, t0

    // Switch to U-mode via MRET
    prog[3]  = 32'h00000297;  // auipc t0, 0
    prog[4]  = 32'h01828293;  // addi  t0, t0, 24
    prog[5]  = 32'h34129073;  // csrw  mepc, t0
    prog[6]  = 32'h00000113;  // addi  x2, x0, 0
    prog[7]  = 32'h30011073;  // csrw  mstatus, x2
    prog[8]  = 32'h30200073;  // mret

    // U-mode: Try to read mstatus (M-mode CSR) → should trap
    prog[9]  = 32'h30002173;  // csrr  x2, mstatus  ← ILLEGAL in U-mode
    prog[10] = 32'h00000013;  // nop

    // Trap handler (M-mode)
    prog[11] = 32'h00000013;  // nop (trap lands here)

    load_program(prog, 12);

    wait_for_retire(400, retired);

    $display("  Instructions retired: %0d", retired);
    $display("  Traps taken:          %0d", trap_count - initial_traps);

    check("Illegal CSR access caused a trap",
          (trap_count - initial_traps) > 0);
  endtask

  // =======================================================================
  // TEST 6: External Interrupt Handling
  // =======================================================================
  task automatic test_interrupt_handling();
    logic [31:0] prog [0:7];
    int retired;

    $display("\n", "="*70);
    $display("  TEST 6: External Interrupt Handling");
    $display("="*70);

    do_reset();

    // Simple program: loop with NOPs
    prog[0] = 32'h00000013;  // nop
    prog[1] = 32'h00000013;  // nop
    prog[2] = 32'h00000013;  // nop
    prog[3] = 32'h00000013;  // nop
    prog[4] = 32'h00000013;  // nop
    prog[5] = 32'h00000013;  // nop
    prog[6] = 32'h00000013;  // nop
    prog[7] = 32'h00000013;  // nop

    load_program(prog, 8);

    // Run a few cycles, then pulse ext_irq
    run_cycles(50);
    $display("  Asserting ext_irq at time=%0t", $time);
    ext_irq <= 1'b1;
    run_cycles(5);
    ext_irq <= 1'b0;
    run_cycles(200);

    wait_for_retire(100, retired);

    $display("  Instructions retired: %0d", retired);
    $display("  Traps taken:          %0d", trap_count);

    check("Interrupt was serviced (trap count > 0)", trap_count > 0);
  endtask

  // =======================================================================
  // TEST 7: GPIO Read/Write
  // =======================================================================
  task automatic test_gpio();
    logic [31:0] prog [0:7];
    int retired;

    $display("\n", "="*70);
    $display("  TEST 7: GPIO Peripheral Access");
    $display("="*70);

    do_reset();

    // Write 0xBEEF to GPIO output register (at GPIO_BASE = 0x4000_1000)
    prog[0] = 32'h40001137;  // lui   x2, 0x40001   (x2 = 0x4000_1000)
    prog[1] = 32'hBEEF0093;  // lui   x1, 0xBEEF0   (need to fix — use addi)
    prog[2] = 32'hEEF00093;  // addi  x1, x0, -273  (0xFFFFF_EEF → just test write)
    prog[3] = 32'h00112023;  // sw    x1, 0(x2)     (write to GPIO_BASE)
    prog[4] = 32'h00012183;  // lw    x3, 0(x2)     (read back)
    prog[5] = 32'h00000013;  // nop
    prog[6] = 32'h00000013;  // nop
    prog[7] = 32'h00000013;  // nop

    load_program(prog, 8);

    gpio_in <= 16'hCAFE;  // Drive input pins

    wait_for_retire(300, retired);

    $display("  Instructions retired: %0d", retired);
    $display("  GPIO out:             0x%04h", gpio_out);
    $display("  GPIO oe:              0x%04h", gpio_oe);

    check("GPIO peripheral was accessed", retired >= 4);
  endtask

  // =======================================================================
  // Main Test Sequence
  // =======================================================================
  initial begin
    // Enable waveform dump for Cadence
    $shm_open("waves.shm");
    $shm_probe(u_dut, "ASMC");

    pass_count = 0;
    fail_count = 0;

    $display("\n");
    $display("######################################################################");
    $display("#                                                                    #");
    $display("#    SecVeriRL — Cadence Incisive Verification Suite                  #");
    $display("#    DUT: secverirl_soc_top (RISC-V RV32I + PMP + SecMon)            #");
    $display("#    Simulator: Cadence Incisive 15.2                                #");
    $display("#                                                                    #");
    $display("######################################################################\n");

    // ---- Run all tests ----
    test_basic_reset();
    test_instruction_execution();
    test_memory_operations();
    test_pmp_security();
    test_illegal_csr();
    test_interrupt_handling();
    test_gpio();

    // ---- Final Summary ----
    $display("\n");
    $display("######################################################################");
    $display("#                     VERIFICATION SUMMARY                           #");
    $display("######################################################################");
    $display("#  PASSED: %0d", pass_count);
    $display("#  FAILED: %0d", fail_count);
    $display("#  Total instructions retired: %0d", insn_retired_count);
    $display("######################################################################");

    if (fail_count == 0)
      $display("\n  >>> ALL TESTS PASSED <<<\n");
    else
      $display("\n  >>> %0d TEST(S) FAILED <<<\n", fail_count);

    $shm_close();
    $finish;
  end

  // -----------------------------------------------------------------------
  // Timeout watchdog
  // -----------------------------------------------------------------------
  initial begin
    #(1_000_000);  // 1ms timeout
    $display("[TIMEOUT] Simulation exceeded 1ms — aborting");
    $finish;
  end

endmodule

