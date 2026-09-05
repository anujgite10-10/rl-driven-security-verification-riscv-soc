// ============================================================================
// SecVeriRL — SoC Top Level
// ============================================================================
// Integrates: RV32I Core + PMP + Security Monitor + AXI-Lite Bus +
// SRAM + UART + GPIO. This is the DUT for verification.
// ============================================================================

module secverirl_soc_top
  import secverirl_pkg::*;
#(
  parameter int XLEN        = 32,
  parameter int PMP_REGIONS = 4,
  parameter logic [31:0] RESET_ADDR = 32'h0000_0000
)(
  input  logic        clk,
  input  logic        rst_n,

  // External interrupts
  input  logic        ext_irq,
  input  logic        timer_irq,
  input  logic        sw_irq,

  // GPIO
  output logic [15:0] gpio_out,
  input  logic [15:0] gpio_in,
  output logic [15:0] gpio_oe,

  // UART
  output logic        uart_tx,
  input  logic        uart_rx,

  // Security monitor outputs (for verification)
  output logic        sec_alert,
  output logic [7:0]  sec_alert_code,
  output logic [31:0] sec_event_count,

  // RVFI verification interface
  output logic              rvfi_valid,
  output logic [XLEN-1:0]  rvfi_insn,
  output logic [XLEN-1:0]  rvfi_pc,
  output logic [XLEN-1:0]  rvfi_next_pc,
  output logic [4:0]        rvfi_rd_addr,
  output logic [XLEN-1:0]  rvfi_rd_data,
  output logic              rvfi_trap,
  output priv_mode_e        rvfi_priv
);

  // -----------------------------------------------------------------------
  // Internal wires
  // -----------------------------------------------------------------------
  // Core ↔ PMP/Bus
  logic              imem_req, imem_ready, imem_fault;
  logic [XLEN-1:0]  imem_addr, imem_rdata;
  logic              dmem_req, dmem_we, dmem_ready, dmem_error;
  logic [XLEN-1:0]  dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]        dmem_wstrb;

  // Core outputs
  priv_mode_e        current_priv;
  pmp_cfg_t          pmp_cfg  [PMP_REGIONS];
  logic [XLEN-1:0]  pmp_addr [PMP_REGIONS];

  // PMP check
  logic              pmp_imem_allow, pmp_imem_deny;
  logic              pmp_dmem_allow, pmp_dmem_deny;
  logic [3:0]        pmp_imem_region, pmp_dmem_region;

  // Bus master signals (post-PMP)
  logic              bus_awvalid, bus_awready;
  logic [XLEN-1:0]  bus_awaddr;
  logic              bus_wvalid, bus_wready;
  logic [XLEN-1:0]  bus_wdata;
  logic [3:0]        bus_wstrb;
  logic              bus_bvalid, bus_bready;
  logic [1:0]        bus_bresp;
  logic              bus_arvalid, bus_arready;
  logic [XLEN-1:0]  bus_araddr;
  logic              bus_rvalid, bus_rready;
  logic [XLEN-1:0]  bus_rdata;
  logic [1:0]        bus_rresp;

  // Slave signals
  // S0: SRAM
  logic s0_awv, s0_awr, s0_wv, s0_wr, s0_bv, s0_br;
  logic [XLEN-1:0] s0_awa, s0_wd, s0_rd;
  logic [3:0] s0_ws;
  logic [1:0] s0_brs, s0_rrs;
  logic s0_arv, s0_arr, s0_rv, s0_rr;
  logic [XLEN-1:0] s0_ara;

  // S1: UART
  logic s1_awv, s1_awr, s1_wv, s1_wr, s1_bv, s1_br;
  logic [XLEN-1:0] s1_awa, s1_wd, s1_rd;
  logic [3:0] s1_ws;
  logic [1:0] s1_brs, s1_rrs;
  logic s1_arv, s1_arr, s1_rv, s1_rr;
  logic [XLEN-1:0] s1_ara;

  // S2: GPIO
  logic s2_awv, s2_awr, s2_wv, s2_wr, s2_bv, s2_br;
  logic [XLEN-1:0] s2_awa, s2_wd, s2_rd;
  logic [3:0] s2_ws;
  logic [1:0] s2_brs, s2_rrs;
  logic s2_arv, s2_arr, s2_rv, s2_rr;
  logic [XLEN-1:0] s2_ara;

  logic uart_irq_w;

  // Signals from core for security monitor
  logic        core_is_mret;
  logic        core_is_ecall;
  logic        core_is_csr;
  logic [11:0] core_csr_addr;
  logic        core_csr_denied;

  // -----------------------------------------------------------------------
  // CPU Core
  // -----------------------------------------------------------------------
  rv32i_core #(
    .XLEN       (XLEN),
    .PMP_REGIONS(PMP_REGIONS),
    .RESET_ADDR (RESET_ADDR)
  ) u_core (
    .clk          (clk),
    .rst_n        (rst_n),
    .imem_addr    (imem_addr),
    .imem_rdata   (imem_rdata),
    .imem_req     (imem_req),
    .imem_ready   (imem_ready),
    .imem_fault   (pmp_imem_deny),
    .dmem_req     (dmem_req),
    .dmem_we      (dmem_we),
    .dmem_addr    (dmem_addr),
    .dmem_wdata   (dmem_wdata),
    .dmem_wstrb   (dmem_wstrb),
    .dmem_rdata   (dmem_rdata),
    .dmem_ready   (dmem_ready),
    .dmem_error   (dmem_error | pmp_dmem_deny),
    .ext_irq      (ext_irq | uart_irq_w),
    .timer_irq    (timer_irq),
    .sw_irq       (sw_irq),
    .current_priv (current_priv),
    .pmp_cfg      (pmp_cfg),
    .pmp_addr     (pmp_addr),
    .rvfi_valid   (rvfi_valid),
    .rvfi_insn    (rvfi_insn),
    .rvfi_pc      (rvfi_pc),
    .rvfi_next_pc (rvfi_next_pc),
    .rvfi_rd_addr (rvfi_rd_addr),
    .rvfi_rd_data (rvfi_rd_data),
    .rvfi_trap    (rvfi_trap),
    .is_mret      (core_is_mret),
    .is_ecall     (core_is_ecall),
    .is_csr       (core_is_csr),
    .csr_addr     (core_csr_addr),
    .csr_denied   (core_csr_denied)
  );

  assign rvfi_priv = current_priv;

  // -----------------------------------------------------------------------
  // PMP — Instruction Fetch Check
  // -----------------------------------------------------------------------
  pmp_unit #(.XLEN(XLEN), .PMP_REGIONS(PMP_REGIONS)) u_pmp_imem (
    .current_priv   (current_priv),
    .pmp_cfg        (pmp_cfg),
    .pmp_addr       (pmp_addr),
    .access_addr    (imem_addr),
    .access_read    (1'b1),
    .access_write   (1'b0),
    .access_exec    (1'b1),
    .pmp_allow      (pmp_imem_allow),
    .pmp_deny       (pmp_imem_deny),
    .pmp_match_region(pmp_imem_region)
  );

  // -----------------------------------------------------------------------
  // PMP — Data Access Check
  // -----------------------------------------------------------------------
  pmp_unit #(.XLEN(XLEN), .PMP_REGIONS(PMP_REGIONS)) u_pmp_dmem (
    .current_priv   (current_priv),
    .pmp_cfg        (pmp_cfg),
    .pmp_addr       (pmp_addr),
    .access_addr    (dmem_addr),
    .access_read    (dmem_req & ~dmem_we),
    .access_write   (dmem_req & dmem_we),
    .access_exec    (1'b0),
    .pmp_allow      (pmp_dmem_allow),
    .pmp_deny       (pmp_dmem_deny),
    .pmp_match_region(pmp_dmem_region)
  );

  // -----------------------------------------------------------------------
  // Instruction memory (direct SRAM read for fetch)
  // -----------------------------------------------------------------------
  // AXI-Lite read: arvalid/arready handshake happens first, then
  // rvalid/rready handshake delivers data on a LATER cycle.
  // imem_ready must only check rvalid (data is available).

  // Track pending fetch so we don't re-issue arvalid after address accepted
  logic imem_pending;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      imem_pending <= 1'b0;
    else if (bus_arvalid && bus_arready && imem_req)
      imem_pending <= 1'b1;
    else if (bus_rvalid)
      imem_pending <= 1'b0;
  end

  // Issue AR: Give data memory reads PRIORITY over instruction fetches.
  // BUG FIX: Previously, ~imem_req blocked all dmem reads because imem_req
  // stays asserted during ST_MEMORY. Now dmem_rd_req takes priority.
  logic dmem_rd_req;
  assign dmem_rd_req = dmem_req & ~dmem_we & pmp_dmem_allow;

  assign bus_arvalid = dmem_rd_req ? 1'b1
                                   : (imem_req & pmp_imem_allow & ~imem_pending);
  assign bus_araddr  = dmem_rd_req ? dmem_addr : imem_addr;
  assign imem_rdata  = bus_rdata;
  assign imem_ready  = ~dmem_rd_req & (imem_req | imem_pending) & bus_rvalid;
  assign bus_rready  = 1'b1;

  // Data read
  assign dmem_rdata = bus_rdata;
  assign dmem_ready = dmem_req & (bus_rvalid | bus_bvalid);
  assign dmem_error = (dmem_req & bus_rvalid & (bus_rresp != AXI_RESP_OKAY)) |
                      (dmem_req & bus_bvalid & (bus_bresp != AXI_RESP_OKAY));

  // Data write
  assign bus_awvalid = dmem_req & dmem_we & pmp_dmem_allow;
  assign bus_awaddr  = dmem_addr;
  assign bus_wvalid  = dmem_req & dmem_we & pmp_dmem_allow;
  assign bus_wdata   = dmem_wdata;
  assign bus_wstrb   = dmem_wstrb;
  assign bus_bready  = 1'b1;

  // -----------------------------------------------------------------------
  // AXI-Lite Interconnect
  // -----------------------------------------------------------------------
  axi_lite_interconnect #(.ADDR_W(XLEN), .DATA_W(XLEN)) u_interconnect (
    .clk(clk), .rst_n(rst_n),
    .m_awvalid(bus_awvalid), .m_awready(bus_awready), .m_awaddr(bus_awaddr),
    .m_wvalid(bus_wvalid), .m_wready(bus_wready), .m_wdata(bus_wdata), .m_wstrb(bus_wstrb),
    .m_bvalid(bus_bvalid), .m_bready(bus_bready), .m_bresp(bus_bresp),
    .m_arvalid(bus_arvalid), .m_arready(bus_arready), .m_araddr(bus_araddr),
    .m_rvalid(bus_rvalid), .m_rready(bus_rready), .m_rdata(bus_rdata), .m_rresp(bus_rresp),
    // S0: SRAM
    .s0_awvalid(s0_awv),.s0_awready(s0_awr),.s0_awaddr(s0_awa),
    .s0_wvalid(s0_wv),.s0_wready(s0_wr),.s0_wdata(s0_wd),.s0_wstrb(s0_ws),
    .s0_bvalid(s0_bv),.s0_bready(s0_br),.s0_bresp(s0_brs),
    .s0_arvalid(s0_arv),.s0_arready(s0_arr),.s0_araddr(s0_ara),
    .s0_rvalid(s0_rv),.s0_rready(s0_rr),.s0_rdata(s0_rd),.s0_rresp(s0_rrs),
    // S1: UART
    .s1_awvalid(s1_awv),.s1_awready(s1_awr),.s1_awaddr(s1_awa),
    .s1_wvalid(s1_wv),.s1_wready(s1_wr),.s1_wdata(s1_wd),.s1_wstrb(s1_ws),
    .s1_bvalid(s1_bv),.s1_bready(s1_br),.s1_bresp(s1_brs),
    .s1_arvalid(s1_arv),.s1_arready(s1_arr),.s1_araddr(s1_ara),
    .s1_rvalid(s1_rv),.s1_rready(s1_rr),.s1_rdata(s1_rd),.s1_rresp(s1_rrs),
    // S2: GPIO
    .s2_awvalid(s2_awv),.s2_awready(s2_awr),.s2_awaddr(s2_awa),
    .s2_wvalid(s2_wv),.s2_wready(s2_wr),.s2_wdata(s2_wd),.s2_wstrb(s2_ws),
    .s2_bvalid(s2_bv),.s2_bready(s2_br),.s2_bresp(s2_brs),
    .s2_arvalid(s2_arv),.s2_arready(s2_arr),.s2_araddr(s2_ara),
    .s2_rvalid(s2_rv),.s2_rready(s2_rr),.s2_rdata(s2_rd),.s2_rresp(s2_rrs)
  );

  // -----------------------------------------------------------------------
  // Peripherals
  // -----------------------------------------------------------------------
  axi_lite_sram #(.ADDR_W(XLEN),.DATA_W(XLEN),.MEM_DEPTH(16384)) u_sram (
    .clk(clk),.rst_n(rst_n),
    .awvalid(s0_awv),.awready(s0_awr),.awaddr(s0_awa),
    .wvalid(s0_wv),.wready(s0_wr),.wdata(s0_wd),.wstrb(s0_ws),
    .bvalid(s0_bv),.bready(s0_br),.bresp(s0_brs),
    .arvalid(s0_arv),.arready(s0_arr),.araddr(s0_ara),
    .rvalid(s0_rv),.rready(s0_rr),.rdata(s0_rd),.rresp(s0_rrs)
  );

  axi_lite_uart #(.ADDR_W(XLEN),.DATA_W(XLEN)) u_uart (
    .clk(clk),.rst_n(rst_n),
    .awvalid(s1_awv),.awready(s1_awr),.awaddr(s1_awa),
    .wvalid(s1_wv),.wready(s1_wr),.wdata(s1_wd),.wstrb(s1_ws),
    .bvalid(s1_bv),.bready(s1_br),.bresp(s1_brs),
    .arvalid(s1_arv),.arready(s1_arr),.araddr(s1_ara),
    .rvalid(s1_rv),.rready(s1_rr),.rdata(s1_rd),.rresp(s1_rrs),
    .uart_tx(uart_tx),.uart_rx(uart_rx),.uart_irq(uart_irq_w)
  );

  axi_lite_gpio #(.ADDR_W(XLEN),.DATA_W(XLEN)) u_gpio (
    .clk(clk),.rst_n(rst_n),
    .awvalid(s2_awv),.awready(s2_awr),.awaddr(s2_awa),
    .wvalid(s2_wv),.wready(s2_wr),.wdata(s2_wd),.wstrb(s2_ws),
    .bvalid(s2_bv),.bready(s2_br),.bresp(s2_brs),
    .arvalid(s2_arv),.arready(s2_arr),.araddr(s2_ara),
    .rvalid(s2_rv),.rready(s2_rr),.rdata(s2_rd),.rresp(s2_rrs),
    .gpio_out(gpio_out),.gpio_in(gpio_in),.gpio_oe(gpio_oe)
  );

  // -----------------------------------------------------------------------
  // Security Monitor
  // -----------------------------------------------------------------------
  priv_mode_e prev_priv_r;
  logic       priv_changed_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_priv_r <= PRIV_M;
    end else begin
      prev_priv_r <= current_priv;
    end
  end
  assign priv_changed_r = (current_priv != prev_priv_r);

  security_monitor #(.XLEN(XLEN), .PMP_REGIONS(PMP_REGIONS)) u_secmon (
    .clk             (clk),
    .rst_n           (rst_n),
    .current_priv    (current_priv),
    .prev_priv       (prev_priv_r),
    .priv_changed    (priv_changed_r),
    .pmp_deny        (pmp_dmem_deny | pmp_imem_deny),
    .pmp_match_region(pmp_dmem_region),
    .access_addr     (dmem_addr),
    .access_read     (dmem_req & ~dmem_we),
    .access_write    (dmem_req & dmem_we),
    .access_exec     (imem_req),
    .illegal_insn    (rvfi_trap),
    .is_ecall        (core_is_ecall),
    .is_mret         (core_is_mret),
    .trap_taken      (rvfi_trap),
    .csr_access      (core_is_csr),
    .csr_addr        (core_csr_addr),
    .csr_denied      (core_csr_denied),
    .sec_alert       (sec_alert),
    .sec_alert_code  (sec_alert_code),
    .sec_event_count (sec_event_count),
    .sec_log_data    (),
    .sec_log_idx     (4'b0)
  );

endmodule
