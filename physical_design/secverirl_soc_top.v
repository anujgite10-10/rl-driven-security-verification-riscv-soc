module rv32i_alu (
	op,
	operand_a,
	operand_b,
	result,
	zero,
	overflow
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	input wire [3:0] op;
	input wire [XLEN - 1:0] operand_a;
	input wire [XLEN - 1:0] operand_b;
	output reg [XLEN - 1:0] result;
	output reg zero;
	output reg overflow;
	wire [XLEN - 1:0] add_result;
	wire [XLEN - 1:0] sub_result;
	wire add_overflow;
	assign add_result = operand_a + operand_b;
	assign sub_result = operand_a - operand_b;
	assign add_overflow = (operand_a[XLEN - 1] == operand_b[XLEN - 1]) && (add_result[XLEN - 1] != operand_a[XLEN - 1]);
	always @(*) begin
		if (_sv2v_0)
			;
		result = 1'sb0;
		zero = 1'b0;
		overflow = 1'b0;
		case (op)
			4'b0000: begin
				result = add_result;
				overflow = add_overflow;
			end
			4'b0001: result = sub_result;
			4'b0010: result = operand_a << operand_b[4:0];
			4'b0011: result = {{XLEN - 1 {1'b0}}, $signed(operand_a) < $signed(operand_b)};
			4'b0100: result = {{XLEN - 1 {1'b0}}, operand_a < operand_b};
			4'b0101: result = operand_a ^ operand_b;
			4'b0110: result = operand_a >> operand_b[4:0];
			4'b0111: result = $signed(operand_a) >>> operand_b[4:0];
			4'b1000: result = operand_a | operand_b;
			4'b1001: result = operand_a & operand_b;
			4'b1010: result = operand_a * operand_b;
			4'b1111: result = operand_b;
			default: result = 1'sb0;
		endcase
		zero = result == {XLEN {1'sb0}};
	end
	initial _sv2v_0 = 0;
endmodule
module rv32i_regfile (
	clk,
	rst_n,
	rs1_addr,
	rs1_data,
	rs2_addr,
	rs2_data,
	wr_en,
	rd_addr,
	rd_data
);
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] NUM_REGS = 32;
	parameter signed [31:0] ADDR_W = 5;
	input wire clk;
	input wire rst_n;
	input wire [ADDR_W - 1:0] rs1_addr;
	output wire [XLEN - 1:0] rs1_data;
	input wire [ADDR_W - 1:0] rs2_addr;
	output wire [XLEN - 1:0] rs2_data;
	input wire wr_en;
	input wire [ADDR_W - 1:0] rd_addr;
	input wire [XLEN - 1:0] rd_data;
	reg [XLEN - 1:0] regs [0:NUM_REGS - 1];
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < NUM_REGS; i = i + 1)
				regs[i] <= 1'sb0;
		end
		else if (wr_en && (rd_addr != {ADDR_W {1'sb0}}))
			regs[rd_addr] <= rd_data;
	assign rs1_data = (rs1_addr == {ADDR_W {1'sb0}} ? {XLEN {1'sb0}} : regs[rs1_addr]);
	assign rs2_data = (rs2_addr == {ADDR_W {1'sb0}} ? {XLEN {1'sb0}} : regs[rs2_addr]);
endmodule
module rv32i_decoder (
	instr,
	current_priv,
	rs1_addr,
	rs2_addr,
	rd_addr,
	imm,
	alu_op,
	alu_src_b_imm,
	reg_write,
	mem_read,
	mem_write,
	branch,
	jump,
	jal,
	jalr,
	lui,
	auipc,
	is_system,
	is_csr,
	is_mret,
	is_ecall,
	is_ebreak,
	is_fence,
	illegal_insn,
	csr_addr
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	input wire [XLEN - 1:0] instr;
	input wire [1:0] current_priv;
	output wire [4:0] rs1_addr;
	output wire [4:0] rs2_addr;
	output wire [4:0] rd_addr;
	output reg [XLEN - 1:0] imm;
	output reg [3:0] alu_op;
	output reg alu_src_b_imm;
	output reg reg_write;
	output reg mem_read;
	output reg mem_write;
	output reg branch;
	output reg jump;
	output reg jal;
	output reg jalr;
	output reg lui;
	output reg auipc;
	output reg is_system;
	output reg is_csr;
	output reg is_mret;
	output reg is_ecall;
	output reg is_ebreak;
	output reg is_fence;
	output reg illegal_insn;
	output wire [11:0] csr_addr;
	wire [6:0] opcode;
	wire [2:0] funct3;
	wire [6:0] funct7;
	assign opcode = instr[6:0];
	assign funct3 = instr[14:12];
	assign funct7 = instr[31:25];
	assign rs1_addr = instr[19:15];
	assign rs2_addr = instr[24:20];
	assign rd_addr = instr[11:7];
	assign csr_addr = instr[31:20];
	always @(*) begin
		if (_sv2v_0)
			;
		imm = 1'sb0;
		case (opcode)
			7'b0010011, 7'b0000011, 7'b1100111: imm = {{20 {instr[31]}}, instr[31:20]};
			7'b0100011: imm = {{20 {instr[31]}}, instr[31:25], instr[11:7]};
			7'b1100011: imm = {{19 {instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
			7'b0110111, 7'b0010111: imm = {instr[31:12], 12'b000000000000};
			7'b1101111: imm = {{11 {instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
			7'b1110011: imm = {27'b000000000000000000000000000, instr[19:15]};
			default: imm = 1'sb0;
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		alu_op = 4'b0000;
		alu_src_b_imm = 1'b0;
		reg_write = 1'b0;
		mem_read = 1'b0;
		mem_write = 1'b0;
		branch = 1'b0;
		jump = 1'b0;
		jal = 1'b0;
		jalr = 1'b0;
		lui = 1'b0;
		auipc = 1'b0;
		is_system = 1'b0;
		is_csr = 1'b0;
		is_mret = 1'b0;
		is_ecall = 1'b0;
		is_ebreak = 1'b0;
		is_fence = 1'b0;
		illegal_insn = 1'b0;
		case (opcode)
			7'b0110111: begin
				lui = 1'b1;
				reg_write = 1'b1;
				alu_op = 4'b1111;
				alu_src_b_imm = 1'b1;
			end
			7'b0010111: begin
				auipc = 1'b1;
				reg_write = 1'b1;
				alu_op = 4'b0000;
				alu_src_b_imm = 1'b1;
			end
			7'b1101111: begin
				jal = 1'b1;
				jump = 1'b1;
				reg_write = 1'b1;
			end
			7'b1100111: begin
				jalr = 1'b1;
				jump = 1'b1;
				reg_write = 1'b1;
				alu_src_b_imm = 1'b1;
				alu_op = 4'b0000;
			end
			7'b1100011: begin
				branch = 1'b1;
				case (funct3)
					3'b000: alu_op = 4'b0001;
					3'b001: alu_op = 4'b0001;
					3'b100: alu_op = 4'b0011;
					3'b101: alu_op = 4'b0011;
					3'b110: alu_op = 4'b0100;
					3'b111: alu_op = 4'b0100;
					default: illegal_insn = 1'b1;
				endcase
			end
			7'b0000011: begin
				mem_read = 1'b1;
				reg_write = 1'b1;
				alu_op = 4'b0000;
				alu_src_b_imm = 1'b1;
				if (funct3 > 3'b101)
					illegal_insn = 1'b1;
			end
			7'b0100011: begin
				mem_write = 1'b1;
				alu_op = 4'b0000;
				alu_src_b_imm = 1'b1;
				if (funct3 > 3'b010)
					illegal_insn = 1'b1;
			end
			7'b0010011: begin
				reg_write = 1'b1;
				alu_src_b_imm = 1'b1;
				case (funct3)
					3'b000: alu_op = 4'b0000;
					3'b001: alu_op = 4'b0010;
					3'b010: alu_op = 4'b0011;
					3'b011: alu_op = 4'b0100;
					3'b100: alu_op = 4'b0101;
					3'b101: alu_op = (funct7[5] ? 4'b0111 : 4'b0110);
					3'b110: alu_op = 4'b1000;
					3'b111: alu_op = 4'b1001;
					default: illegal_insn = 1'b1;
				endcase
			end
			7'b0110011: begin
				reg_write = 1'b1;
				case ({funct7, funct3})
					10'b0000000000: alu_op = 4'b0000;
					10'b0100000000: alu_op = 4'b0001;
					10'b0000000001: alu_op = 4'b0010;
					10'b0000000010: alu_op = 4'b0011;
					10'b0000000011: alu_op = 4'b0100;
					10'b0000000100: alu_op = 4'b0101;
					10'b0000000101: alu_op = 4'b0110;
					10'b0100000101: alu_op = 4'b0111;
					10'b0000000110: alu_op = 4'b1000;
					10'b0000000111: alu_op = 4'b1001;
					10'b0000001000: alu_op = 4'b1010;
					default: illegal_insn = 1'b1;
				endcase
			end
			7'b0001111: is_fence = 1'b1;
			7'b1110011: begin
				is_system = 1'b1;
				case (funct3)
					3'b000:
						case (instr[31:20])
							12'b000000000000: is_ecall = 1'b1;
							12'b000000000001: is_ebreak = 1'b1;
							12'b001100000010: begin
								is_mret = 1'b1;
								if (current_priv != 2'b11)
									illegal_insn = 1'b1;
							end
							default: illegal_insn = 1'b1;
						endcase
					3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111: begin
						is_csr = 1'b1;
						reg_write = 1'b1;
					end
					default: illegal_insn = 1'b1;
				endcase
			end
			default: illegal_insn = 1'b1;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module rv32i_lsu (
	clk,
	rst_n,
	mem_read,
	mem_write,
	funct3,
	addr,
	write_data,
	read_data,
	mem_ready,
	load_misalign,
	store_misalign,
	bus_req,
	bus_we,
	bus_addr,
	bus_wdata,
	bus_wstrb,
	bus_rdata,
	bus_ready,
	bus_error
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	input wire clk;
	input wire rst_n;
	input wire mem_read;
	input wire mem_write;
	input wire [2:0] funct3;
	input wire [XLEN - 1:0] addr;
	input wire [XLEN - 1:0] write_data;
	output reg [XLEN - 1:0] read_data;
	output reg mem_ready;
	output wire load_misalign;
	output wire store_misalign;
	output wire bus_req;
	output wire bus_we;
	output wire [XLEN - 1:0] bus_addr;
	output reg [XLEN - 1:0] bus_wdata;
	output reg [3:0] bus_wstrb;
	input wire [XLEN - 1:0] bus_rdata;
	input wire bus_ready;
	input wire bus_error;
	reg [1:0] state;
	reg [1:0] next_state;
	wire [1:0] byte_offset;
	reg misaligned;
	assign byte_offset = addr[1:0];
	always @(*) begin
		if (_sv2v_0)
			;
		misaligned = 1'b0;
		case (funct3[1:0])
			2'b01: misaligned = addr[0];
			2'b10: misaligned = |addr[1:0];
			default: misaligned = 1'b0;
		endcase
	end
	assign load_misalign = mem_read & misaligned;
	assign store_misalign = mem_write & misaligned;
	assign bus_req = (mem_read | mem_write) & ~misaligned;
	assign bus_we = mem_write & ~misaligned;
	assign bus_addr = {addr[XLEN - 1:2], 2'b00};
	always @(*) begin
		if (_sv2v_0)
			;
		bus_wstrb = 4'b0000;
		bus_wdata = 1'sb0;
		if (mem_write && !misaligned)
			case (funct3[1:0])
				2'b00: begin
					bus_wstrb = 4'b0001 << byte_offset;
					bus_wdata = write_data[7:0] << (byte_offset * 8);
				end
				2'b01: begin
					bus_wstrb = 4'b0011 << byte_offset;
					bus_wdata = write_data[15:0] << (byte_offset * 8);
				end
				2'b10: begin
					bus_wstrb = 4'b1111;
					bus_wdata = write_data;
				end
				default: begin
					bus_wstrb = 4'b0000;
					bus_wdata = 1'sb0;
				end
			endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		read_data = 1'sb0;
		if (mem_read && bus_ready)
			case (funct3)
				3'b000:
					case (byte_offset)
						2'b00: read_data = {{24 {bus_rdata[7]}}, bus_rdata[7:0]};
						2'b01: read_data = {{24 {bus_rdata[15]}}, bus_rdata[15:8]};
						2'b10: read_data = {{24 {bus_rdata[23]}}, bus_rdata[23:16]};
						2'b11: read_data = {{24 {bus_rdata[31]}}, bus_rdata[31:24]};
					endcase
				3'b001:
					case (byte_offset[1])
						1'b0: read_data = {{16 {bus_rdata[15]}}, bus_rdata[15:0]};
						1'b1: read_data = {{16 {bus_rdata[31]}}, bus_rdata[31:16]};
					endcase
				3'b010: read_data = bus_rdata;
				3'b100:
					case (byte_offset)
						2'b00: read_data = {24'b000000000000000000000000, bus_rdata[7:0]};
						2'b01: read_data = {24'b000000000000000000000000, bus_rdata[15:8]};
						2'b10: read_data = {24'b000000000000000000000000, bus_rdata[23:16]};
						2'b11: read_data = {24'b000000000000000000000000, bus_rdata[31:24]};
					endcase
				3'b101:
					case (byte_offset[1])
						1'b0: read_data = {16'b0000000000000000, bus_rdata[15:0]};
						1'b1: read_data = {16'b0000000000000000, bus_rdata[31:16]};
					endcase
				default: read_data = bus_rdata;
			endcase
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n)
			state <= 2'd0;
		else
			state <= next_state;
	always @(*) begin
		if (_sv2v_0)
			;
		next_state = state;
		mem_ready = 1'b0;
		case (state)
			2'd0:
				if ((mem_read || mem_write) && !misaligned)
					next_state = 2'd1;
				else if (misaligned)
					mem_ready = 1'b1;
			2'd1:
				if (bus_ready || bus_error) begin
					next_state = 2'd0;
					mem_ready = 1'b1;
				end
			default: next_state = 2'd0;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module rv32i_control (
	clk,
	rst_n,
	is_csr,
	is_mret,
	is_ecall,
	is_ebreak,
	illegal_insn,
	funct3,
	csr_addr_i,
	rs1_data,
	rs1_addr,
	pc,
	load_misalign,
	store_misalign,
	load_fault,
	store_fault,
	insn_fault,
	ext_irq,
	timer_irq,
	sw_irq,
	csr_rdata,
	current_priv,
	trap_taken,
	trap_target,
	mret_taken,
	mepc_out,
	pmp_cfg,
	pmp_addr,
	pipeline_flush,
	csr_denied
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] PMP_REGIONS = 4;
	input wire clk;
	input wire rst_n;
	input wire is_csr;
	input wire is_mret;
	input wire is_ecall;
	input wire is_ebreak;
	input wire illegal_insn;
	input wire [2:0] funct3;
	input wire [11:0] csr_addr_i;
	input wire [XLEN - 1:0] rs1_data;
	input wire [4:0] rs1_addr;
	input wire [XLEN - 1:0] pc;
	input wire load_misalign;
	input wire store_misalign;
	input wire load_fault;
	input wire store_fault;
	input wire insn_fault;
	input wire ext_irq;
	input wire timer_irq;
	input wire sw_irq;
	output reg [XLEN - 1:0] csr_rdata;
	output wire [1:0] current_priv;
	output wire trap_taken;
	output reg [XLEN - 1:0] trap_target;
	output wire mret_taken;
	output wire [XLEN - 1:0] mepc_out;
	output wire [(PMP_REGIONS * 8) - 1:0] pmp_cfg;
	output wire [(PMP_REGIONS * XLEN) - 1:0] pmp_addr;
	output wire pipeline_flush;
	output wire csr_denied;
	reg [XLEN - 1:0] mstatus;
	wire [XLEN - 1:0] misa;
	reg [XLEN - 1:0] mie;
	reg [XLEN - 1:0] mtvec;
	reg [XLEN - 1:0] mscratch;
	reg [XLEN - 1:0] mepc;
	reg [XLEN - 1:0] mcause;
	reg [XLEN - 1:0] mtval;
	reg [XLEN - 1:0] mip;
	reg [XLEN - 1:0] mcycle;
	reg [XLEN - 1:0] minstret;
	reg [XLEN - 1:0] pmpcfg0;
	reg [XLEN - 1:0] pmpaddr_regs [0:PMP_REGIONS - 1];
	reg [1:0] priv_mode;
	assign current_priv = priv_mode;
	assign misa = 32'b01000000000000000001000100000000;
	always @(*) begin
		if (_sv2v_0)
			;
		mip = 1'sb0;
		mip[11] = ext_irq;
		mip[7] = timer_irq;
		mip[3] = sw_irq;
	end
	reg exception_taken;
	wire interrupt_taken;
	reg [3:0] exc_cause;
	wire any_interrupt;
	wire mstatus_mie;
	assign mstatus_mie = mstatus[3];
	wire mstatus_mpie;
	assign mstatus_mpie = mstatus[7];
	wire [1:0] mstatus_mpp;
	assign mstatus_mpp = mstatus[12:11];
	assign any_interrupt = mstatus_mie && |(mie & mip);
	always @(*) begin
		if (_sv2v_0)
			;
		exception_taken = 1'b0;
		exc_cause = 1'sb0;
		if (insn_fault) begin
			exception_taken = 1'b1;
			exc_cause = 4'd1;
		end
		else if (illegal_insn) begin
			exception_taken = 1'b1;
			exc_cause = 4'd2;
		end
		else if (is_ebreak) begin
			exception_taken = 1'b1;
			exc_cause = 4'd3;
		end
		else if (is_ecall) begin
			exception_taken = 1'b1;
			exc_cause = (priv_mode == 2'b11 ? 4'd11 : 4'd8);
		end
		else if (load_misalign) begin
			exception_taken = 1'b1;
			exc_cause = 4'd4;
		end
		else if (store_misalign) begin
			exception_taken = 1'b1;
			exc_cause = 4'd6;
		end
		else if (load_fault) begin
			exception_taken = 1'b1;
			exc_cause = 4'd5;
		end
		else if (store_fault) begin
			exception_taken = 1'b1;
			exc_cause = 4'd7;
		end
	end
	assign interrupt_taken = any_interrupt && !exception_taken;
	assign trap_taken = exception_taken || interrupt_taken;
	assign mret_taken = is_mret && (priv_mode == 2'b11);
	assign pipeline_flush = trap_taken || mret_taken;
	always @(*) begin
		if (_sv2v_0)
			;
		if (mtvec[1:0] == 2'b00)
			trap_target = {mtvec[XLEN - 1:2], 2'b00};
		else
			trap_target = {mtvec[XLEN - 1:2], 2'b00} + {26'b00000000000000000000000000, exc_cause, 2'b00};
	end
	assign mepc_out = mepc;
	reg csr_read_illegal;
	assign csr_denied = csr_read_illegal;
	localparam [11:0] secverirl_pkg_CSR_MCAUSE = 12'h342;
	localparam [11:0] secverirl_pkg_CSR_MCYCLE = 12'hb00;
	localparam [11:0] secverirl_pkg_CSR_MEPC = 12'h341;
	localparam [11:0] secverirl_pkg_CSR_MIE = 12'h304;
	localparam [11:0] secverirl_pkg_CSR_MINSTRET = 12'hb02;
	localparam [11:0] secverirl_pkg_CSR_MIP = 12'h344;
	localparam [11:0] secverirl_pkg_CSR_MISA = 12'h301;
	localparam [11:0] secverirl_pkg_CSR_MSCRATCH = 12'h340;
	localparam [11:0] secverirl_pkg_CSR_MSTATUS = 12'h300;
	localparam [11:0] secverirl_pkg_CSR_MTVAL = 12'h343;
	localparam [11:0] secverirl_pkg_CSR_MTVEC = 12'h305;
	localparam [11:0] secverirl_pkg_CSR_PMPADDR0 = 12'h3b0;
	localparam [11:0] secverirl_pkg_CSR_PMPADDR1 = 12'h3b1;
	localparam [11:0] secverirl_pkg_CSR_PMPADDR2 = 12'h3b2;
	localparam [11:0] secverirl_pkg_CSR_PMPADDR3 = 12'h3b3;
	localparam [11:0] secverirl_pkg_CSR_PMPCFG0 = 12'h3a0;
	always @(*) begin
		if (_sv2v_0)
			;
		csr_rdata = 1'sb0;
		csr_read_illegal = 1'b0;
		if (is_csr && (csr_addr_i[9:8] > priv_mode))
			csr_read_illegal = 1'b1;
		case (csr_addr_i)
			secverirl_pkg_CSR_MSTATUS: csr_rdata = mstatus;
			secverirl_pkg_CSR_MISA: csr_rdata = misa;
			secverirl_pkg_CSR_MIE: csr_rdata = mie;
			secverirl_pkg_CSR_MTVEC: csr_rdata = mtvec;
			secverirl_pkg_CSR_MSCRATCH: csr_rdata = mscratch;
			secverirl_pkg_CSR_MEPC: csr_rdata = mepc;
			secverirl_pkg_CSR_MCAUSE: csr_rdata = mcause;
			secverirl_pkg_CSR_MTVAL: csr_rdata = mtval;
			secverirl_pkg_CSR_MIP: csr_rdata = mip;
			secverirl_pkg_CSR_PMPCFG0: csr_rdata = pmpcfg0;
			secverirl_pkg_CSR_PMPADDR0: csr_rdata = pmpaddr_regs[0];
			secverirl_pkg_CSR_PMPADDR1: csr_rdata = pmpaddr_regs[1];
			secverirl_pkg_CSR_PMPADDR2: csr_rdata = pmpaddr_regs[2];
			secverirl_pkg_CSR_PMPADDR3: csr_rdata = pmpaddr_regs[3];
			secverirl_pkg_CSR_MCYCLE: csr_rdata = mcycle;
			secverirl_pkg_CSR_MINSTRET: csr_rdata = minstret;
			default:
				if (is_csr)
					csr_read_illegal = 1'b1;
		endcase
	end
	reg [XLEN - 1:0] csr_wdata;
	always @(*) begin : sv2v_autoblock_1
		reg [XLEN - 1:0] write_val;
		if (_sv2v_0)
			;
		write_val = (funct3[2] ? {27'b000000000000000000000000000, rs1_addr} : rs1_data);
		case (funct3[1:0])
			2'b01: csr_wdata = write_val;
			2'b10: csr_wdata = csr_rdata | write_val;
			2'b11: csr_wdata = csr_rdata & ~write_val;
			default: csr_wdata = csr_rdata;
		endcase
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			priv_mode <= 2'b11;
			mstatus <= 32'h00001800;
			mie <= 1'sb0;
			mtvec <= 1'sb0;
			mscratch <= 1'sb0;
			mepc <= 1'sb0;
			mcause <= 1'sb0;
			mtval <= 1'sb0;
			mcycle <= 1'sb0;
			minstret <= 1'sb0;
			pmpcfg0 <= 1'sb0;
			begin : sv2v_autoblock_2
				reg signed [31:0] i;
				for (i = 0; i < PMP_REGIONS; i = i + 1)
					pmpaddr_regs[i] <= 1'sb0;
			end
		end
		else begin
			mcycle <= mcycle + 1;
			if (trap_taken) begin
				mepc <= pc;
				mcause <= {interrupt_taken, 27'b000000000000000000000000000, exc_cause};
				mtval <= 1'sb0;
				mstatus[7] <= mstatus_mie;
				mstatus[3] <= 1'b0;
				mstatus[12:11] <= priv_mode;
				priv_mode <= 2'b11;
			end
			else if (mret_taken) begin
				mstatus[3] <= mstatus_mpie;
				mstatus[7] <= 1'b1;
				priv_mode <= mstatus_mpp;
				mstatus[12:11] <= 2'b00;
			end
			else if (is_csr && !csr_read_illegal)
				case (csr_addr_i)
					secverirl_pkg_CSR_MSTATUS: mstatus <= csr_wdata & 32'h00001888;
					secverirl_pkg_CSR_MIE: mie <= csr_wdata;
					secverirl_pkg_CSR_MTVEC: mtvec <= csr_wdata;
					secverirl_pkg_CSR_MSCRATCH: mscratch <= csr_wdata;
					secverirl_pkg_CSR_MEPC: mepc <= {csr_wdata[XLEN - 1:2], 2'b00};
					secverirl_pkg_CSR_MCAUSE: mcause <= csr_wdata;
					secverirl_pkg_CSR_MTVAL: mtval <= csr_wdata;
					secverirl_pkg_CSR_PMPCFG0: pmpcfg0 <= csr_wdata;
					secverirl_pkg_CSR_PMPADDR0: pmpaddr_regs[0] <= csr_wdata;
					secverirl_pkg_CSR_PMPADDR1: pmpaddr_regs[1] <= csr_wdata;
					secverirl_pkg_CSR_PMPADDR2: pmpaddr_regs[2] <= csr_wdata;
					secverirl_pkg_CSR_PMPADDR3: pmpaddr_regs[3] <= csr_wdata;
					default:
						;
				endcase
			if (!trap_taken && !mret_taken)
				minstret <= minstret + 1;
		end
	genvar _gv_i_1;
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	generate
		for (_gv_i_1 = 0; _gv_i_1 < PMP_REGIONS; _gv_i_1 = _gv_i_1 + 1) begin : gen_pmp_cfg
			localparam i = _gv_i_1;
			assign pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 7] = pmpcfg0[(i * 8) + 7];
			assign pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 6-:2] = pmpcfg0[(i * 8) + 6:(i * 8) + 5];
			assign pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 4-:2] = sv2v_cast_2(pmpcfg0[(i * 8) + 4:(i * 8) + 3]);
			assign pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 2] = pmpcfg0[(i * 8) + 2];
			assign pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 1] = pmpcfg0[(i * 8) + 1];
			assign pmp_cfg[((PMP_REGIONS - 1) - i) * 8] = pmpcfg0[(i * 8) + 0];
			assign pmp_addr[((PMP_REGIONS - 1) - i) * XLEN+:XLEN] = pmpaddr_regs[i];
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module rv32i_core (
	clk,
	rst_n,
	imem_addr,
	imem_rdata,
	imem_req,
	imem_ready,
	imem_fault,
	dmem_req,
	dmem_we,
	dmem_addr,
	dmem_wdata,
	dmem_wstrb,
	dmem_rdata,
	dmem_ready,
	dmem_error,
	ext_irq,
	timer_irq,
	sw_irq,
	current_priv,
	pmp_cfg,
	pmp_addr,
	is_mret,
	is_ecall,
	is_csr,
	csr_addr,
	csr_denied,
	rvfi_valid,
	rvfi_insn,
	rvfi_pc,
	rvfi_next_pc,
	rvfi_rd_addr,
	rvfi_rd_data,
	rvfi_trap
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] PMP_REGIONS = 4;
	parameter [31:0] RESET_ADDR = 32'h00000000;
	input wire clk;
	input wire rst_n;
	output wire [XLEN - 1:0] imem_addr;
	input wire [XLEN - 1:0] imem_rdata;
	output wire imem_req;
	input wire imem_ready;
	input wire imem_fault;
	output wire dmem_req;
	output wire dmem_we;
	output wire [XLEN - 1:0] dmem_addr;
	output wire [XLEN - 1:0] dmem_wdata;
	output wire [3:0] dmem_wstrb;
	input wire [XLEN - 1:0] dmem_rdata;
	input wire dmem_ready;
	input wire dmem_error;
	input wire ext_irq;
	input wire timer_irq;
	input wire sw_irq;
	output wire [1:0] current_priv;
	output wire [(PMP_REGIONS * 8) - 1:0] pmp_cfg;
	output wire [(PMP_REGIONS * XLEN) - 1:0] pmp_addr;
	output wire is_mret;
	output wire is_ecall;
	output wire is_csr;
	output wire [11:0] csr_addr;
	output wire csr_denied;
	output wire rvfi_valid;
	output wire [XLEN - 1:0] rvfi_insn;
	output wire [XLEN - 1:0] rvfi_pc;
	output wire [XLEN - 1:0] rvfi_next_pc;
	output wire [4:0] rvfi_rd_addr;
	output wire [XLEN - 1:0] rvfi_rd_data;
	output wire rvfi_trap;
	reg [2:0] state;
	reg [2:0] next_state;
	reg [XLEN - 1:0] pc;
	reg [XLEN - 1:0] next_pc;
	reg [XLEN - 1:0] instr_reg;
	wire [4:0] dec_rs1;
	wire [4:0] dec_rs2;
	wire [4:0] dec_rd;
	wire [XLEN - 1:0] dec_imm;
	wire [3:0] dec_alu_op;
	wire dec_alu_src_b_imm;
	wire dec_reg_write;
	wire dec_mem_read;
	wire dec_mem_write;
	wire dec_branch;
	wire dec_jump;
	wire dec_jal;
	wire dec_jalr;
	wire dec_lui;
	wire dec_auipc;
	wire dec_is_system;
	wire dec_is_csr;
	wire dec_is_mret;
	wire dec_is_ecall;
	wire dec_is_ebreak;
	wire dec_is_fence;
	wire dec_illegal;
	wire [11:0] dec_csr_addr;
	wire [XLEN - 1:0] rs1_data;
	wire [XLEN - 1:0] rs2_data;
	reg rf_wr_en;
	reg [XLEN - 1:0] rf_wr_data;
	wire [XLEN - 1:0] alu_result;
	wire alu_zero;
	wire alu_overflow;
	wire [XLEN - 1:0] alu_op_a;
	wire [XLEN - 1:0] alu_op_b;
	wire [XLEN - 1:0] lsu_rdata;
	wire lsu_ready;
	wire lsu_load_misalign;
	wire lsu_store_misalign;
	wire [XLEN - 1:0] csr_rdata;
	wire trap_taken;
	wire mret_taken;
	wire [XLEN - 1:0] trap_target;
	wire [XLEN - 1:0] mepc_out;
	wire pipeline_flush;
	reg branch_taken;
	rv32i_decoder #(.XLEN(XLEN)) u_decoder(
		.instr(instr_reg),
		.current_priv(current_priv),
		.rs1_addr(dec_rs1),
		.rs2_addr(dec_rs2),
		.rd_addr(dec_rd),
		.imm(dec_imm),
		.alu_op(dec_alu_op),
		.alu_src_b_imm(dec_alu_src_b_imm),
		.reg_write(dec_reg_write),
		.mem_read(dec_mem_read),
		.mem_write(dec_mem_write),
		.branch(dec_branch),
		.jump(dec_jump),
		.jal(dec_jal),
		.jalr(dec_jalr),
		.lui(dec_lui),
		.auipc(dec_auipc),
		.is_system(dec_is_system),
		.is_csr(dec_is_csr),
		.is_mret(dec_is_mret),
		.is_ecall(dec_is_ecall),
		.is_ebreak(dec_is_ebreak),
		.is_fence(dec_is_fence),
		.illegal_insn(dec_illegal),
		.csr_addr(dec_csr_addr)
	);
	rv32i_regfile #(.XLEN(XLEN)) u_regfile(
		.clk(clk),
		.rst_n(rst_n),
		.rs1_addr(dec_rs1),
		.rs1_data(rs1_data),
		.rs2_addr(dec_rs2),
		.rs2_data(rs2_data),
		.wr_en(rf_wr_en),
		.rd_addr(dec_rd),
		.rd_data(rf_wr_data)
	);
	assign alu_op_a = (dec_auipc ? pc : rs1_data);
	assign alu_op_b = (dec_alu_src_b_imm ? dec_imm : rs2_data);
	rv32i_alu #(.XLEN(XLEN)) u_alu(
		.op(dec_alu_op),
		.operand_a(alu_op_a),
		.operand_b(alu_op_b),
		.result(alu_result),
		.zero(alu_zero),
		.overflow(alu_overflow)
	);
	rv32i_lsu #(.XLEN(XLEN)) u_lsu(
		.clk(clk),
		.rst_n(rst_n),
		.mem_read(dec_mem_read && (state == 3'd3)),
		.mem_write(dec_mem_write && (state == 3'd3)),
		.funct3(instr_reg[14:12]),
		.addr(alu_result),
		.write_data(rs2_data),
		.read_data(lsu_rdata),
		.mem_ready(lsu_ready),
		.load_misalign(lsu_load_misalign),
		.store_misalign(lsu_store_misalign),
		.bus_req(dmem_req),
		.bus_we(dmem_we),
		.bus_addr(dmem_addr),
		.bus_wdata(dmem_wdata),
		.bus_wstrb(dmem_wstrb),
		.bus_rdata(dmem_rdata),
		.bus_ready(dmem_ready),
		.bus_error(dmem_error)
	);
	rv32i_control #(
		.XLEN(XLEN),
		.PMP_REGIONS(PMP_REGIONS)
	) u_control(
		.clk(clk),
		.rst_n(rst_n),
		.is_csr(dec_is_csr && (state == 3'd2)),
		.is_mret(dec_is_mret && (state == 3'd2)),
		.is_ecall(dec_is_ecall && (state == 3'd2)),
		.is_ebreak(dec_is_ebreak && (state == 3'd2)),
		.illegal_insn(dec_illegal && (state == 3'd1)),
		.funct3(instr_reg[14:12]),
		.csr_addr_i(dec_csr_addr),
		.rs1_data(rs1_data),
		.rs1_addr(dec_rs1),
		.pc(pc),
		.load_misalign(lsu_load_misalign),
		.store_misalign(lsu_store_misalign),
		.load_fault(dmem_error && dec_mem_read),
		.store_fault(dmem_error && dec_mem_write),
		.insn_fault(imem_fault),
		.ext_irq(ext_irq),
		.timer_irq(timer_irq),
		.sw_irq(sw_irq),
		.csr_rdata(csr_rdata),
		.current_priv(current_priv),
		.trap_taken(trap_taken),
		.trap_target(trap_target),
		.mret_taken(mret_taken),
		.mepc_out(mepc_out),
		.pmp_cfg(pmp_cfg),
		.pmp_addr(pmp_addr),
		.pipeline_flush(pipeline_flush),
		.csr_denied(csr_denied)
	);
	assign is_mret = dec_is_mret && (state == 3'd2);
	assign is_ecall = dec_is_ecall && (state == 3'd2);
	assign is_csr = dec_is_csr && (state == 3'd2);
	assign csr_addr = dec_csr_addr;
	always @(*) begin
		if (_sv2v_0)
			;
		branch_taken = 1'b0;
		if (dec_branch)
			case (instr_reg[14:12])
				3'b000: branch_taken = alu_zero;
				3'b001: branch_taken = !alu_zero;
				3'b100: branch_taken = alu_result[0];
				3'b101: branch_taken = !alu_result[0];
				3'b110: branch_taken = alu_result[0];
				3'b111: branch_taken = !alu_result[0];
				default: branch_taken = 1'b0;
			endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if (trap_taken)
			next_pc = trap_target;
		else if (mret_taken)
			next_pc = mepc_out;
		else if (dec_jal)
			next_pc = pc + dec_imm;
		else if (dec_jalr)
			next_pc = {alu_result[XLEN - 1:1], 1'b0};
		else if (branch_taken)
			next_pc = pc + dec_imm;
		else
			next_pc = pc + 4;
	end
	always @(*) begin
		if (_sv2v_0)
			;
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
	assign imem_addr = pc;
	assign imem_req = state == 3'd0;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			state <= 3'd0;
			pc <= RESET_ADDR;
			instr_reg <= 32'h00000013;
		end
		else begin
			state <= next_state;
			case (state)
				3'd0:
					if (imem_ready)
						instr_reg <= imem_rdata;
				3'd4: pc <= next_pc;
				default:
					;
			endcase
			if (pipeline_flush && ((state == 3'd2) || (state == 3'd1))) begin
				pc <= next_pc;
				state <= 3'd0;
			end
		end
	always @(*) begin
		if (_sv2v_0)
			;
		next_state = state;
		rf_wr_en = 1'b0;
		case (state)
			3'd0:
				if (imem_ready)
					next_state = 3'd1;
			3'd1:
				if (pipeline_flush)
					next_state = 3'd0;
				else
					next_state = 3'd2;
			3'd2:
				if (pipeline_flush)
					next_state = 3'd0;
				else if (dec_is_fence)
					next_state = 3'd4;
				else if (dec_mem_read || dec_mem_write)
					next_state = 3'd3;
				else
					next_state = 3'd4;
			3'd3:
				if (lsu_ready)
					next_state = 3'd4;
			3'd4: begin
				rf_wr_en = dec_reg_write;
				next_state = 3'd0;
			end
			default: next_state = 3'd0;
		endcase
	end
	assign rvfi_valid = state == 3'd4;
	assign rvfi_insn = instr_reg;
	assign rvfi_pc = pc;
	assign rvfi_next_pc = next_pc;
	assign rvfi_rd_addr = dec_rd;
	assign rvfi_rd_data = rf_wr_data;
	assign rvfi_trap = trap_taken;
	initial _sv2v_0 = 0;
endmodule
module pmp_unit (
	current_priv,
	pmp_cfg,
	pmp_addr,
	access_addr,
	access_read,
	access_write,
	access_exec,
	pmp_allow,
	pmp_deny,
	pmp_match_region
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] PMP_REGIONS = 4;
	input wire [1:0] current_priv;
	input wire [(PMP_REGIONS * 8) - 1:0] pmp_cfg;
	input wire [(PMP_REGIONS * XLEN) - 1:0] pmp_addr;
	input wire [XLEN - 1:0] access_addr;
	input wire access_read;
	input wire access_write;
	input wire access_exec;
	output reg pmp_allow;
	output reg pmp_deny;
	output reg [3:0] pmp_match_region;
	reg [PMP_REGIONS - 1:0] region_match;
	reg [PMP_REGIONS - 1:0] region_allow;
	reg [XLEN - 1:0] region_base [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] region_mask [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] napot_mask [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] napot_base [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] shifted_addr [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] tor_lo [0:PMP_REGIONS - 1];
	reg [XLEN - 1:0] tor_hi [0:PMP_REGIONS - 1];
	reg r_ok [0:PMP_REGIONS - 1];
	reg w_ok [0:PMP_REGIONS - 1];
	reg x_ok [0:PMP_REGIONS - 1];
	reg any_match;
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < PMP_REGIONS; _gv_i_2 = _gv_i_2 + 1) begin : gen_pmp_check
			localparam i = _gv_i_2;
			always @(*) begin
				if (_sv2v_0)
					;
				region_base[i] = 1'sb0;
				region_mask[i] = 1'sb0;
				region_match[i] = 1'b0;
				napot_mask[i] = 1'sb0;
				napot_base[i] = 1'sb0;
				shifted_addr[i] = 1'sb0;
				tor_lo[i] = 1'sb0;
				tor_hi[i] = 1'sb0;
				case (pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 4-:2])
					2'b00: region_match[i] = 1'b0;
					2'b10: begin
						region_base[i] = {pmp_addr[(((PMP_REGIONS - 1) - i) * XLEN) + (XLEN - 1)-:XLEN], 2'b00};
						region_match[i] = access_addr[XLEN - 1:2] == pmp_addr[(((PMP_REGIONS - 1) - i) * XLEN) + ((XLEN - 3) >= 0 ? XLEN - 3 : ((XLEN - 3) + ((XLEN - 3) >= 0 ? XLEN - 2 : 4 - XLEN)) - 1)-:((XLEN - 3) >= 0 ? XLEN - 2 : 4 - XLEN)];
					end
					2'b11: begin
						shifted_addr[i] = {pmp_addr[((PMP_REGIONS - 1) - i) * XLEN+:XLEN], 2'b00};
						napot_mask[i] = ~(shifted_addr[i] ^ (shifted_addr[i] + 4));
						napot_base[i] = shifted_addr[i] & napot_mask[i];
						region_base[i] = napot_base[i];
						region_mask[i] = napot_mask[i];
						region_match[i] = (access_addr & napot_mask[i]) == napot_base[i];
					end
					2'b01: begin
						if (i == 0)
							tor_lo[i] = 1'sb0;
						else
							tor_lo[i] = {pmp_addr[((PMP_REGIONS - 1) - (i - 1)) * XLEN+:XLEN], 2'b00};
						tor_hi[i] = {pmp_addr[((PMP_REGIONS - 1) - i) * XLEN+:XLEN], 2'b00};
						region_base[i] = tor_lo[i];
						region_match[i] = (access_addr >= tor_lo[i]) && (access_addr < tor_hi[i]);
					end
					default: region_match[i] = 1'b0;
				endcase
			end
			always @(*) begin
				if (_sv2v_0)
					;
				region_allow[i] = 1'b0;
				r_ok[i] = 1'b0;
				w_ok[i] = 1'b0;
				x_ok[i] = 1'b0;
				if (region_match[i]) begin
					if ((current_priv == 2'b11) && !pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 7])
						region_allow[i] = 1'b1;
					else begin
						r_ok[i] = !access_read || pmp_cfg[((PMP_REGIONS - 1) - i) * 8];
						w_ok[i] = !access_write || pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 1];
						x_ok[i] = !access_exec || pmp_cfg[(((PMP_REGIONS - 1) - i) * 8) + 2];
						region_allow[i] = (r_ok[i] && w_ok[i]) && x_ok[i];
					end
				end
			end
		end
	endgenerate
	always @(*) begin : sv2v_autoblock_1
		reg [0:1] _sv2v_jump;
		_sv2v_jump = 2'b00;
		if (_sv2v_0)
			;
		pmp_allow = 1'b0;
		pmp_deny = 1'b0;
		pmp_match_region = 4'hf;
		any_match = |region_match;
		if (any_match) begin : sv2v_autoblock_2
			reg signed [31:0] i;
			begin : sv2v_autoblock_3
				reg signed [31:0] _sv2v_value_on_break;
				for (i = 0; i < PMP_REGIONS; i = i + 1)
					if (_sv2v_jump < 2'b10) begin
						_sv2v_jump = 2'b00;
						if (region_match[i]) begin
							pmp_match_region = i[3:0];
							pmp_allow = region_allow[i];
							pmp_deny = !region_allow[i];
							_sv2v_jump = 2'b10;
						end
						_sv2v_value_on_break = i;
					end
				if (!(_sv2v_jump < 2'b10))
					i = _sv2v_value_on_break;
				if (_sv2v_jump != 2'b11)
					_sv2v_jump = 2'b00;
			end
		end
		else if (current_priv == 2'b11) begin
			pmp_allow = 1'b1;
			pmp_deny = 1'b0;
		end
		else begin
			pmp_allow = 1'b0;
			pmp_deny = 1'b1;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module security_monitor (
	clk,
	rst_n,
	current_priv,
	prev_priv,
	priv_changed,
	pmp_deny,
	pmp_match_region,
	access_addr,
	access_read,
	access_write,
	access_exec,
	illegal_insn,
	is_ecall,
	is_mret,
	trap_taken,
	csr_access,
	csr_addr,
	csr_denied,
	sec_alert,
	sec_alert_code,
	sec_event_count,
	sec_log_data,
	sec_log_idx
);
	reg _sv2v_0;
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] LOG_DEPTH = 16;
	parameter signed [31:0] PMP_REGIONS = 4;
	input wire clk;
	input wire rst_n;
	input wire [1:0] current_priv;
	input wire [1:0] prev_priv;
	input wire priv_changed;
	input wire pmp_deny;
	input wire [3:0] pmp_match_region;
	input wire [XLEN - 1:0] access_addr;
	input wire access_read;
	input wire access_write;
	input wire access_exec;
	input wire illegal_insn;
	input wire is_ecall;
	input wire is_mret;
	input wire trap_taken;
	input wire csr_access;
	input wire [11:0] csr_addr;
	input wire csr_denied;
	output wire sec_alert;
	output reg [7:0] sec_alert_code;
	output wire [31:0] sec_event_count;
	output wire [XLEN - 1:0] sec_log_data;
	input wire [3:0] sec_log_idx;
	localparam [7:0] ALERT_NONE = 8'h00;
	localparam [7:0] ALERT_PMP_VIOLATION = 8'h01;
	localparam [7:0] ALERT_PRIV_ESCALATION = 8'h02;
	localparam [7:0] ALERT_ILLEGAL_CSR = 8'h03;
	localparam [7:0] ALERT_ILLEGAL_INSN = 8'h04;
	localparam [7:0] ALERT_SECURE_REGION = 8'h05;
	localparam [7:0] ALERT_RAPID_TRAPS = 8'h06;
	reg [31:0] event_counter;
	reg [31:0] event_log [0:LOG_DEPTH - 1];
	reg [3:0] log_wr_ptr;
	reg [3:0] trap_counter;
	reg [7:0] trap_window_counter;
	localparam signed [31:0] TRAP_WINDOW = 64;
	localparam signed [31:0] TRAP_THRESHOLD = 8;
	assign sec_event_count = event_counter;
	wire alert_pmp;
	wire alert_priv;
	wire alert_csr;
	wire alert_insn;
	wire alert_secure;
	wire alert_rapid_trap;
	assign alert_pmp = pmp_deny && (current_priv != 2'b11);
	assign alert_priv = (((priv_changed && (prev_priv == 2'b00)) && (current_priv == 2'b11)) && !trap_taken) && !is_mret;
	assign alert_csr = csr_denied;
	assign alert_insn = illegal_insn && (current_priv == 2'b00);
	localparam [31:0] secverirl_pkg_SECURE_ROM_BASE = 32'h80000000;
	localparam [31:0] secverirl_pkg_SECURE_ROM_SIZE = 32'h00004000;
	assign alert_secure = ((((access_read || access_write) || access_exec) && (current_priv == 2'b00)) && (access_addr >= secverirl_pkg_SECURE_ROM_BASE)) && (access_addr < (secverirl_pkg_SECURE_ROM_BASE + secverirl_pkg_SECURE_ROM_SIZE));
	assign alert_rapid_trap = trap_counter >= TRAP_THRESHOLD[3:0];
	assign sec_alert = ((((alert_pmp || alert_priv) || alert_csr) || alert_insn) || alert_secure) || alert_rapid_trap;
	always @(*) begin
		if (_sv2v_0)
			;
		if (alert_pmp)
			sec_alert_code = ALERT_PMP_VIOLATION;
		else if (alert_priv)
			sec_alert_code = ALERT_PRIV_ESCALATION;
		else if (alert_csr)
			sec_alert_code = ALERT_ILLEGAL_CSR;
		else if (alert_insn)
			sec_alert_code = ALERT_ILLEGAL_INSN;
		else if (alert_secure)
			sec_alert_code = ALERT_SECURE_REGION;
		else if (alert_rapid_trap)
			sec_alert_code = ALERT_RAPID_TRAPS;
		else
			sec_alert_code = ALERT_NONE;
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			event_counter <= 1'sb0;
			log_wr_ptr <= 1'sb0;
			trap_counter <= 1'sb0;
			trap_window_counter <= 1'sb0;
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 0; i < LOG_DEPTH; i = i + 1)
					event_log[i] <= 1'sb0;
			end
		end
		else begin
			if (trap_window_counter >= TRAP_WINDOW[7:0]) begin
				trap_window_counter <= 1'sb0;
				trap_counter <= 1'sb0;
			end
			else begin
				trap_window_counter <= trap_window_counter + 1;
				if (trap_taken)
					trap_counter <= trap_counter + 1;
			end
			if (sec_alert) begin
				event_counter <= event_counter + 1;
				event_log[log_wr_ptr] <= {sec_alert_code, current_priv, 6'b000000, access_addr[15:0]};
				log_wr_ptr <= log_wr_ptr + 1;
			end
		end
	assign sec_log_data = event_log[sec_log_idx];
	initial _sv2v_0 = 0;
endmodule
module axi_lite_sram (
	clk,
	rst_n,
	awvalid,
	awready,
	awaddr,
	wvalid,
	wready,
	wdata,
	wstrb,
	bvalid,
	bready,
	bresp,
	arvalid,
	arready,
	araddr,
	rvalid,
	rready,
	rdata,
	rresp
);
	parameter signed [31:0] ADDR_W = 32;
	parameter signed [31:0] DATA_W = 32;
	parameter signed [31:0] MEM_DEPTH = 16384;
	parameter signed [31:0] MEM_AW = $clog2(MEM_DEPTH);
	input wire clk;
	input wire rst_n;
	input wire awvalid;
	output reg awready;
	input wire [ADDR_W - 1:0] awaddr;
	input wire wvalid;
	output reg wready;
	input wire [DATA_W - 1:0] wdata;
	input wire [3:0] wstrb;
	output reg bvalid;
	input wire bready;
	output reg [1:0] bresp;
	input wire arvalid;
	output reg arready;
	input wire [ADDR_W - 1:0] araddr;
	output reg rvalid;
	input wire rready;
	output reg [DATA_W - 1:0] rdata;
	output reg [1:0] rresp;
	reg [DATA_W - 1:0] mem [0:MEM_DEPTH - 1];
	reg [1:0] wr_state;
	reg [1:0] rd_state;
	reg [ADDR_W - 1:0] wr_addr_reg;
	reg [ADDR_W - 1:0] rd_addr_reg;
	wire [MEM_AW - 1:0] wr_word_addr;
	assign wr_word_addr = wr_addr_reg[MEM_AW + 1:2];
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			wr_state <= 2'd0;
			awready <= 1'b0;
			wready <= 1'b0;
			bvalid <= 1'b0;
			bresp <= 2'b00;
			wr_addr_reg <= 1'sb0;
		end
		else
			case (wr_state)
				2'd0: begin
					bvalid <= 1'b0;
					awready <= 1'b1;
					wready <= 1'b0;
					if (awvalid && awready) begin
						wr_addr_reg <= awaddr;
						awready <= 1'b0;
						wready <= 1'b1;
						wr_state <= 2'd1;
					end
				end
				2'd1:
					if (wvalid && wready) begin
						if (wstrb[0])
							mem[wr_word_addr][7:0] <= wdata[7:0];
						if (wstrb[1])
							mem[wr_word_addr][15:8] <= wdata[15:8];
						if (wstrb[2])
							mem[wr_word_addr][23:16] <= wdata[23:16];
						if (wstrb[3])
							mem[wr_word_addr][31:24] <= wdata[31:24];
						wready <= 1'b0;
						bvalid <= 1'b1;
						bresp <= 2'b00;
						wr_state <= 2'd2;
					end
				2'd2:
					if (bready) begin
						bvalid <= 1'b0;
						wr_state <= 2'd0;
					end
				default: wr_state <= 2'd0;
			endcase
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			rd_state <= 2'd0;
			arready <= 1'b0;
			rvalid <= 1'b0;
			rdata <= 1'sb0;
			rresp <= 2'b00;
			rd_addr_reg <= 1'sb0;
		end
		else
			case (rd_state)
				2'd0: begin
					arready <= 1'b1;
					rvalid <= 1'b0;
					if (arvalid && arready) begin
						rd_addr_reg <= araddr;
						arready <= 1'b0;
						rvalid <= 1'b1;
						rdata <= mem[araddr[MEM_AW + 1:2]];
						rresp <= 2'b00;
						rd_state <= 2'd1;
					end
				end
				2'd1:
					if (rready) begin
						rvalid <= 1'b0;
						rd_state <= 2'd0;
					end
				default: rd_state <= 2'd0;
			endcase
	initial begin : sv2v_autoblock_1
		reg signed [31:0] i;
		for (i = 0; i < MEM_DEPTH; i = i + 1)
			mem[i] = 1'sb0;
	end
endmodule
module axi_lite_uart (
	clk,
	rst_n,
	awvalid,
	awready,
	awaddr,
	wvalid,
	wready,
	wdata,
	wstrb,
	bvalid,
	bready,
	bresp,
	arvalid,
	arready,
	araddr,
	rvalid,
	rready,
	rdata,
	rresp,
	uart_tx,
	uart_rx,
	uart_irq
);
	parameter signed [31:0] ADDR_W = 32;
	parameter signed [31:0] DATA_W = 32;
	input wire clk;
	input wire rst_n;
	input wire awvalid;
	output reg awready;
	input wire [ADDR_W - 1:0] awaddr;
	input wire wvalid;
	output reg wready;
	input wire [DATA_W - 1:0] wdata;
	input wire [3:0] wstrb;
	output reg bvalid;
	input wire bready;
	output reg [1:0] bresp;
	input wire arvalid;
	output reg arready;
	input wire [ADDR_W - 1:0] araddr;
	output reg rvalid;
	input wire rready;
	output reg [DATA_W - 1:0] rdata;
	output reg [1:0] rresp;
	output reg uart_tx;
	input wire uart_rx;
	output wire uart_irq;
	localparam [3:0] REG_DATA = 4'h0;
	localparam [3:0] REG_STATUS = 4'h4;
	localparam [3:0] REG_CTRL = 4'h8;
	reg [7:0] tx_data;
	reg [7:0] rx_data;
	reg tx_busy;
	reg rx_valid;
	reg tx_irq_en;
	reg rx_irq_en;
	reg [3:0] tx_bit_count;
	wire [9:0] tx_shift;
	reg tx_active;
	assign uart_irq = (tx_irq_en && !tx_busy) || (rx_irq_en && rx_valid);
	wire [DATA_W - 1:0] status_reg;
	assign status_reg = {28'b0000000000000000000000000000, rx_irq_en, tx_irq_en, rx_valid, !tx_busy};
	reg [1:0] wst;
	reg [ADDR_W - 1:0] wa_reg;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			wst <= 2'd0;
			awready <= 1'b0;
			wready <= 1'b0;
			bvalid <= 1'b0;
			bresp <= 2'b00;
			tx_data <= 1'sb0;
			tx_irq_en <= 1'b0;
			rx_irq_en <= 1'b0;
			wa_reg <= 1'sb0;
		end
		else
			case (wst)
				2'd0: begin
					awready <= 1'b1;
					bvalid <= 1'b0;
					if (awvalid) begin
						wa_reg <= awaddr;
						awready <= 1'b0;
						wready <= 1'b1;
						wst <= 2'd1;
					end
				end
				2'd1:
					if (wvalid) begin
						case (wa_reg[3:0])
							REG_DATA: tx_data <= wdata[7:0];
							REG_CTRL: begin
								tx_irq_en <= wdata[1];
								rx_irq_en <= wdata[0];
							end
							default:
								;
						endcase
						wready <= 1'b0;
						bvalid <= 1'b1;
						bresp <= 2'b00;
						wst <= 2'd2;
					end
				2'd2:
					if (bready) begin
						bvalid <= 1'b0;
						wst <= 2'd0;
					end
				default: wst <= 2'd0;
			endcase
	reg rst_state;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			rst_state <= 1'd0;
			arready <= 1'b0;
			rvalid <= 1'b0;
			rdata <= 1'sb0;
			rresp <= 2'b00;
		end
		else
			case (rst_state)
				1'd0: begin
					arready <= 1'b1;
					rvalid <= 1'b0;
					if (arvalid) begin
						arready <= 1'b0;
						rvalid <= 1'b1;
						rresp <= 2'b00;
						case (araddr[3:0])
							REG_DATA: rdata <= {24'b000000000000000000000000, rx_data};
							REG_STATUS: rdata <= status_reg;
							REG_CTRL: rdata <= {30'b000000000000000000000000000000, rx_irq_en, tx_irq_en};
							default: rdata <= 1'sb0;
						endcase
						rst_state <= 1'd1;
					end
				end
				1'd1:
					if (rready) begin
						rvalid <= 1'b0;
						rst_state <= 1'd0;
					end
			endcase
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			tx_busy <= 1'b0;
			tx_active <= 1'b0;
			tx_bit_count <= 1'sb0;
			uart_tx <= 1'b1;
			rx_data <= 1'sb0;
			rx_valid <= 1'b0;
		end
		else begin
			if (((wst == 2'd1) && wvalid) && (wa_reg[3:0] == REG_DATA)) begin
				tx_busy <= 1'b1;
				tx_bit_count <= 4'd10;
			end
			if (tx_busy && (tx_bit_count > 0))
				tx_bit_count <= tx_bit_count - 1;
			else if (tx_busy && (tx_bit_count == 0)) begin
				tx_busy <= 1'b0;
				rx_data <= tx_data;
				rx_valid <= 1'b1;
			end
		end
endmodule
module axi_lite_gpio (
	clk,
	rst_n,
	awvalid,
	awready,
	awaddr,
	wvalid,
	wready,
	wdata,
	wstrb,
	bvalid,
	bready,
	bresp,
	arvalid,
	arready,
	araddr,
	rvalid,
	rready,
	rdata,
	rresp,
	gpio_out,
	gpio_in,
	gpio_oe
);
	parameter signed [31:0] ADDR_W = 32;
	parameter signed [31:0] DATA_W = 32;
	parameter signed [31:0] GPIO_W = 16;
	input wire clk;
	input wire rst_n;
	input wire awvalid;
	output reg awready;
	input wire [ADDR_W - 1:0] awaddr;
	input wire wvalid;
	output reg wready;
	input wire [DATA_W - 1:0] wdata;
	input wire [3:0] wstrb;
	output reg bvalid;
	input wire bready;
	output reg [1:0] bresp;
	input wire arvalid;
	output reg arready;
	input wire [ADDR_W - 1:0] araddr;
	output reg rvalid;
	input wire rready;
	output reg [DATA_W - 1:0] rdata;
	output reg [1:0] rresp;
	output wire [GPIO_W - 1:0] gpio_out;
	input wire [GPIO_W - 1:0] gpio_in;
	output wire [GPIO_W - 1:0] gpio_oe;
	reg [GPIO_W - 1:0] out_reg;
	reg [GPIO_W - 1:0] oe_reg;
	assign gpio_out = out_reg;
	assign gpio_oe = oe_reg;
	reg [1:0] wst;
	reg [ADDR_W - 1:0] wa;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			wst <= 2'd0;
			awready <= 1'b0;
			wready <= 1'b0;
			bvalid <= 1'b0;
			bresp <= 2'b00;
			out_reg <= 1'sb0;
			oe_reg <= 1'sb0;
			wa <= 1'sb0;
		end
		else
			case (wst)
				2'd0: begin
					awready <= 1'b1;
					bvalid <= 1'b0;
					if (awvalid) begin
						wa <= awaddr;
						awready <= 1'b0;
						wready <= 1'b1;
						wst <= 2'd1;
					end
				end
				2'd1:
					if (wvalid) begin
						case (wa[3:0])
							4'h0: out_reg <= wdata[GPIO_W - 1:0];
							4'h8: oe_reg <= wdata[GPIO_W - 1:0];
							default:
								;
						endcase
						wready <= 1'b0;
						bvalid <= 1'b1;
						bresp <= 2'b00;
						wst <= 2'd2;
					end
				2'd2:
					if (bready) begin
						bvalid <= 1'b0;
						wst <= 2'd0;
					end
				default: wst <= 2'd0;
			endcase
	reg rs;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			rs <= 1'd0;
			arready <= 1'b0;
			rvalid <= 1'b0;
			rdata <= 1'sb0;
			rresp <= 2'b00;
		end
		else
			case (rs)
				1'd0: begin
					arready <= 1'b1;
					rvalid <= 1'b0;
					if (arvalid) begin
						arready <= 1'b0;
						rvalid <= 1'b1;
						rresp <= 2'b00;
						case (araddr[3:0])
							4'h0: rdata <= {{DATA_W - GPIO_W {1'b0}}, out_reg};
							4'h4: rdata <= {{DATA_W - GPIO_W {1'b0}}, gpio_in};
							4'h8: rdata <= {{DATA_W - GPIO_W {1'b0}}, oe_reg};
							default: rdata <= 1'sb0;
						endcase
						rs <= 1'd1;
					end
				end
				1'd1:
					if (rready) begin
						rvalid <= 1'b0;
						rs <= 1'd0;
					end
			endcase
endmodule
module axi_lite_interconnect (
	clk,
	rst_n,
	m_awvalid,
	m_awready,
	m_awaddr,
	m_wvalid,
	m_wready,
	m_wdata,
	m_wstrb,
	m_bvalid,
	m_bready,
	m_bresp,
	m_arvalid,
	m_arready,
	m_araddr,
	m_rvalid,
	m_rready,
	m_rdata,
	m_rresp,
	s0_awvalid,
	s0_awready,
	s0_awaddr,
	s0_wvalid,
	s0_wready,
	s0_wdata,
	s0_wstrb,
	s0_bvalid,
	s0_bready,
	s0_bresp,
	s0_arvalid,
	s0_arready,
	s0_araddr,
	s0_rvalid,
	s0_rready,
	s0_rdata,
	s0_rresp,
	s1_awvalid,
	s1_awready,
	s1_awaddr,
	s1_wvalid,
	s1_wready,
	s1_wdata,
	s1_wstrb,
	s1_bvalid,
	s1_bready,
	s1_bresp,
	s1_arvalid,
	s1_arready,
	s1_araddr,
	s1_rvalid,
	s1_rready,
	s1_rdata,
	s1_rresp,
	s2_awvalid,
	s2_awready,
	s2_awaddr,
	s2_wvalid,
	s2_wready,
	s2_wdata,
	s2_wstrb,
	s2_bvalid,
	s2_bready,
	s2_bresp,
	s2_arvalid,
	s2_arready,
	s2_araddr,
	s2_rvalid,
	s2_rready,
	s2_rdata,
	s2_rresp
);
	reg _sv2v_0;
	parameter signed [31:0] ADDR_W = 32;
	parameter signed [31:0] DATA_W = 32;
	parameter signed [31:0] NUM_SLAVES = 3;
	input wire clk;
	input wire rst_n;
	input wire m_awvalid;
	output reg m_awready;
	input wire [ADDR_W - 1:0] m_awaddr;
	input wire m_wvalid;
	output reg m_wready;
	input wire [DATA_W - 1:0] m_wdata;
	input wire [3:0] m_wstrb;
	output reg m_bvalid;
	input wire m_bready;
	output reg [1:0] m_bresp;
	input wire m_arvalid;
	output reg m_arready;
	input wire [ADDR_W - 1:0] m_araddr;
	output reg m_rvalid;
	input wire m_rready;
	output reg [DATA_W - 1:0] m_rdata;
	output reg [1:0] m_rresp;
	output reg s0_awvalid;
	input wire s0_awready;
	output reg [ADDR_W - 1:0] s0_awaddr;
	output reg s0_wvalid;
	input wire s0_wready;
	output reg [DATA_W - 1:0] s0_wdata;
	output reg [3:0] s0_wstrb;
	input wire s0_bvalid;
	output reg s0_bready;
	input wire [1:0] s0_bresp;
	output reg s0_arvalid;
	input wire s0_arready;
	output reg [ADDR_W - 1:0] s0_araddr;
	input wire s0_rvalid;
	output reg s0_rready;
	input wire [DATA_W - 1:0] s0_rdata;
	input wire [1:0] s0_rresp;
	output reg s1_awvalid;
	input wire s1_awready;
	output reg [ADDR_W - 1:0] s1_awaddr;
	output reg s1_wvalid;
	input wire s1_wready;
	output reg [DATA_W - 1:0] s1_wdata;
	output reg [3:0] s1_wstrb;
	input wire s1_bvalid;
	output reg s1_bready;
	input wire [1:0] s1_bresp;
	output reg s1_arvalid;
	input wire s1_arready;
	output reg [ADDR_W - 1:0] s1_araddr;
	input wire s1_rvalid;
	output reg s1_rready;
	input wire [DATA_W - 1:0] s1_rdata;
	input wire [1:0] s1_rresp;
	output reg s2_awvalid;
	input wire s2_awready;
	output reg [ADDR_W - 1:0] s2_awaddr;
	output reg s2_wvalid;
	input wire s2_wready;
	output reg [DATA_W - 1:0] s2_wdata;
	output reg [3:0] s2_wstrb;
	input wire s2_bvalid;
	output reg s2_bready;
	input wire [1:0] s2_bresp;
	output reg s2_arvalid;
	input wire s2_arready;
	output reg [ADDR_W - 1:0] s2_araddr;
	input wire s2_rvalid;
	output reg s2_rready;
	input wire [DATA_W - 1:0] s2_rdata;
	input wire [1:0] s2_rresp;
	wire [1:0] wr_sel;
	wire [1:0] rd_sel;
	localparam [31:0] secverirl_pkg_GPIO_BASE = 32'h40001000;
	localparam [31:0] secverirl_pkg_GPIO_SIZE = 32'h00001000;
	localparam [31:0] secverirl_pkg_UART_BASE = 32'h40000000;
	function automatic [1:0] addr_decode;
		input reg [ADDR_W - 1:0] addr;
		if (addr < secverirl_pkg_UART_BASE)
			addr_decode = 2'd0;
		else if (addr < secverirl_pkg_GPIO_BASE)
			addr_decode = 2'd1;
		else if (addr < (secverirl_pkg_GPIO_BASE + secverirl_pkg_GPIO_SIZE))
			addr_decode = 2'd2;
		else
			addr_decode = 2'd0;
	endfunction
	assign wr_sel = addr_decode(m_awaddr);
	assign rd_sel = addr_decode(m_araddr);
	always @(*) begin
		if (_sv2v_0)
			;
		s0_awvalid = 1'b0;
		s0_awaddr = m_awaddr;
		s0_wvalid = 1'b0;
		s0_wdata = m_wdata;
		s0_wstrb = m_wstrb;
		s0_bready = 1'b0;
		s1_awvalid = 1'b0;
		s1_awaddr = m_awaddr;
		s1_wvalid = 1'b0;
		s1_wdata = m_wdata;
		s1_wstrb = m_wstrb;
		s1_bready = 1'b0;
		s2_awvalid = 1'b0;
		s2_awaddr = m_awaddr;
		s2_wvalid = 1'b0;
		s2_wdata = m_wdata;
		s2_wstrb = m_wstrb;
		s2_bready = 1'b0;
		m_awready = 1'b0;
		m_wready = 1'b0;
		m_bvalid = 1'b0;
		m_bresp = 2'b00;
		case (wr_sel)
			2'd0: begin
				s0_awvalid = m_awvalid;
				m_awready = s0_awready;
				s0_wvalid = m_wvalid;
				m_wready = s0_wready;
				m_bvalid = s0_bvalid;
				s0_bready = m_bready;
				m_bresp = s0_bresp;
			end
			2'd1: begin
				s1_awvalid = m_awvalid;
				m_awready = s1_awready;
				s1_wvalid = m_wvalid;
				m_wready = s1_wready;
				m_bvalid = s1_bvalid;
				s1_bready = m_bready;
				m_bresp = s1_bresp;
			end
			2'd2: begin
				s2_awvalid = m_awvalid;
				m_awready = s2_awready;
				s2_wvalid = m_wvalid;
				m_wready = s2_wready;
				m_bvalid = s2_bvalid;
				s2_bready = m_bready;
				m_bresp = s2_bresp;
			end
			default: begin
				m_awready = 1'b1;
				m_wready = 1'b1;
				m_bvalid = 1'b1;
				m_bresp = 2'b11;
			end
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		s0_arvalid = 1'b0;
		s0_araddr = m_araddr;
		s0_rready = 1'b0;
		s1_arvalid = 1'b0;
		s1_araddr = m_araddr;
		s1_rready = 1'b0;
		s2_arvalid = 1'b0;
		s2_araddr = m_araddr;
		s2_rready = 1'b0;
		m_arready = 1'b0;
		m_rvalid = 1'b0;
		m_rdata = 1'sb0;
		m_rresp = 2'b00;
		case (rd_sel)
			2'd0: begin
				s0_arvalid = m_arvalid;
				m_arready = s0_arready;
				m_rvalid = s0_rvalid;
				s0_rready = m_rready;
				m_rdata = s0_rdata;
				m_rresp = s0_rresp;
			end
			2'd1: begin
				s1_arvalid = m_arvalid;
				m_arready = s1_arready;
				m_rvalid = s1_rvalid;
				s1_rready = m_rready;
				m_rdata = s1_rdata;
				m_rresp = s1_rresp;
			end
			2'd2: begin
				s2_arvalid = m_arvalid;
				m_arready = s2_arready;
				m_rvalid = s2_rvalid;
				s2_rready = m_rready;
				m_rdata = s2_rdata;
				m_rresp = s2_rresp;
			end
			default: begin
				m_arready = 1'b1;
				m_rvalid = 1'b1;
				m_rdata = 1'sb0;
				m_rresp = 2'b11;
			end
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module secverirl_soc_top (
	clk,
	rst_n,
	ext_irq,
	timer_irq,
	sw_irq,
	gpio_out,
	gpio_in,
	gpio_oe,
	uart_tx,
	uart_rx,
	sec_alert,
	sec_alert_code,
	sec_event_count,
	rvfi_valid,
	rvfi_insn,
	rvfi_pc,
	rvfi_next_pc,
	rvfi_rd_addr,
	rvfi_rd_data,
	rvfi_trap,
	rvfi_priv
);
	parameter signed [31:0] XLEN = 32;
	parameter signed [31:0] PMP_REGIONS = 4;
	parameter [31:0] RESET_ADDR = 32'h00000000;
	input wire clk;
	input wire rst_n;
	input wire ext_irq;
	input wire timer_irq;
	input wire sw_irq;
	output wire [15:0] gpio_out;
	input wire [15:0] gpio_in;
	output wire [15:0] gpio_oe;
	output wire uart_tx;
	input wire uart_rx;
	output wire sec_alert;
	output wire [7:0] sec_alert_code;
	output wire [31:0] sec_event_count;
	output wire rvfi_valid;
	output wire [XLEN - 1:0] rvfi_insn;
	output wire [XLEN - 1:0] rvfi_pc;
	output wire [XLEN - 1:0] rvfi_next_pc;
	output wire [4:0] rvfi_rd_addr;
	output wire [XLEN - 1:0] rvfi_rd_data;
	output wire rvfi_trap;
	output wire [1:0] rvfi_priv;
	wire imem_req;
	wire imem_ready;
	wire imem_fault;
	wire [XLEN - 1:0] imem_addr;
	wire [XLEN - 1:0] imem_rdata;
	wire dmem_req;
	wire dmem_we;
	wire dmem_ready;
	wire dmem_error;
	wire [XLEN - 1:0] dmem_addr;
	wire [XLEN - 1:0] dmem_wdata;
	wire [XLEN - 1:0] dmem_rdata;
	wire [3:0] dmem_wstrb;
	wire [1:0] current_priv;
	wire [(PMP_REGIONS * 8) - 1:0] pmp_cfg;
	wire [(PMP_REGIONS * XLEN) - 1:0] pmp_addr;
	wire pmp_imem_allow;
	wire pmp_imem_deny;
	wire pmp_dmem_allow;
	wire pmp_dmem_deny;
	wire [3:0] pmp_imem_region;
	wire [3:0] pmp_dmem_region;
	wire bus_awvalid;
	wire bus_awready;
	wire [XLEN - 1:0] bus_awaddr;
	wire bus_wvalid;
	wire bus_wready;
	wire [XLEN - 1:0] bus_wdata;
	wire [3:0] bus_wstrb;
	wire bus_bvalid;
	wire bus_bready;
	wire [1:0] bus_bresp;
	wire bus_arvalid;
	wire bus_arready;
	wire [XLEN - 1:0] bus_araddr;
	wire bus_rvalid;
	wire bus_rready;
	wire [XLEN - 1:0] bus_rdata;
	wire [1:0] bus_rresp;
	wire s0_awv;
	wire s0_awr;
	wire s0_wv;
	wire s0_wr;
	wire s0_bv;
	wire s0_br;
	wire [XLEN - 1:0] s0_awa;
	wire [XLEN - 1:0] s0_wd;
	wire [XLEN - 1:0] s0_rd;
	wire [3:0] s0_ws;
	wire [1:0] s0_brs;
	wire [1:0] s0_rrs;
	wire s0_arv;
	wire s0_arr;
	wire s0_rv;
	wire s0_rr;
	wire [XLEN - 1:0] s0_ara;
	wire s1_awv;
	wire s1_awr;
	wire s1_wv;
	wire s1_wr;
	wire s1_bv;
	wire s1_br;
	wire [XLEN - 1:0] s1_awa;
	wire [XLEN - 1:0] s1_wd;
	wire [XLEN - 1:0] s1_rd;
	wire [3:0] s1_ws;
	wire [1:0] s1_brs;
	wire [1:0] s1_rrs;
	wire s1_arv;
	wire s1_arr;
	wire s1_rv;
	wire s1_rr;
	wire [XLEN - 1:0] s1_ara;
	wire s2_awv;
	wire s2_awr;
	wire s2_wv;
	wire s2_wr;
	wire s2_bv;
	wire s2_br;
	wire [XLEN - 1:0] s2_awa;
	wire [XLEN - 1:0] s2_wd;
	wire [XLEN - 1:0] s2_rd;
	wire [3:0] s2_ws;
	wire [1:0] s2_brs;
	wire [1:0] s2_rrs;
	wire s2_arv;
	wire s2_arr;
	wire s2_rv;
	wire s2_rr;
	wire [XLEN - 1:0] s2_ara;
	wire uart_irq_w;
	wire core_is_mret;
	wire core_is_ecall;
	wire core_is_csr;
	wire [11:0] core_csr_addr;
	wire core_csr_denied;
	rv32i_core #(
		.XLEN(XLEN),
		.PMP_REGIONS(PMP_REGIONS),
		.RESET_ADDR(RESET_ADDR)
	) u_core(
		.clk(clk),
		.rst_n(rst_n),
		.imem_addr(imem_addr),
		.imem_rdata(imem_rdata),
		.imem_req(imem_req),
		.imem_ready(imem_ready),
		.imem_fault(pmp_imem_deny),
		.dmem_req(dmem_req),
		.dmem_we(dmem_we),
		.dmem_addr(dmem_addr),
		.dmem_wdata(dmem_wdata),
		.dmem_wstrb(dmem_wstrb),
		.dmem_rdata(dmem_rdata),
		.dmem_ready(dmem_ready),
		.dmem_error(dmem_error | pmp_dmem_deny),
		.ext_irq(ext_irq | uart_irq_w),
		.timer_irq(timer_irq),
		.sw_irq(sw_irq),
		.current_priv(current_priv),
		.pmp_cfg(pmp_cfg),
		.pmp_addr(pmp_addr),
		.rvfi_valid(rvfi_valid),
		.rvfi_insn(rvfi_insn),
		.rvfi_pc(rvfi_pc),
		.rvfi_next_pc(rvfi_next_pc),
		.rvfi_rd_addr(rvfi_rd_addr),
		.rvfi_rd_data(rvfi_rd_data),
		.rvfi_trap(rvfi_trap),
		.is_mret(core_is_mret),
		.is_ecall(core_is_ecall),
		.is_csr(core_is_csr),
		.csr_addr(core_csr_addr),
		.csr_denied(core_csr_denied)
	);
	assign rvfi_priv = current_priv;
	pmp_unit #(
		.XLEN(XLEN),
		.PMP_REGIONS(PMP_REGIONS)
	) u_pmp_imem(
		.current_priv(current_priv),
		.pmp_cfg(pmp_cfg),
		.pmp_addr(pmp_addr),
		.access_addr(imem_addr),
		.access_read(1'b1),
		.access_write(1'b0),
		.access_exec(1'b1),
		.pmp_allow(pmp_imem_allow),
		.pmp_deny(pmp_imem_deny),
		.pmp_match_region(pmp_imem_region)
	);
	pmp_unit #(
		.XLEN(XLEN),
		.PMP_REGIONS(PMP_REGIONS)
	) u_pmp_dmem(
		.current_priv(current_priv),
		.pmp_cfg(pmp_cfg),
		.pmp_addr(pmp_addr),
		.access_addr(dmem_addr),
		.access_read(dmem_req & ~dmem_we),
		.access_write(dmem_req & dmem_we),
		.access_exec(1'b0),
		.pmp_allow(pmp_dmem_allow),
		.pmp_deny(pmp_dmem_deny),
		.pmp_match_region(pmp_dmem_region)
	);
	reg imem_pending;
	always @(posedge clk or negedge rst_n)
		if (!rst_n)
			imem_pending <= 1'b0;
		else if ((bus_arvalid && bus_arready) && imem_req)
			imem_pending <= 1'b1;
		else if (bus_rvalid)
			imem_pending <= 1'b0;
	wire dmem_rd_req;
	assign dmem_rd_req = (dmem_req & ~dmem_we) & pmp_dmem_allow;
	assign bus_arvalid = (dmem_rd_req ? 1'b1 : (imem_req & pmp_imem_allow) & ~imem_pending);
	assign bus_araddr = (dmem_rd_req ? dmem_addr : imem_addr);
	assign imem_rdata = bus_rdata;
	assign imem_ready = (~dmem_rd_req & (imem_req | imem_pending)) & bus_rvalid;
	assign bus_rready = 1'b1;
	assign dmem_rdata = bus_rdata;
	assign dmem_ready = dmem_req & (bus_rvalid | bus_bvalid);
	assign dmem_error = ((dmem_req & bus_rvalid) & (bus_rresp != 2'b00)) | ((dmem_req & bus_bvalid) & (bus_bresp != 2'b00));
	assign bus_awvalid = (dmem_req & dmem_we) & pmp_dmem_allow;
	assign bus_awaddr = dmem_addr;
	assign bus_wvalid = (dmem_req & dmem_we) & pmp_dmem_allow;
	assign bus_wdata = dmem_wdata;
	assign bus_wstrb = dmem_wstrb;
	assign bus_bready = 1'b1;
	axi_lite_interconnect #(
		.ADDR_W(XLEN),
		.DATA_W(XLEN)
	) u_interconnect(
		.clk(clk),
		.rst_n(rst_n),
		.m_awvalid(bus_awvalid),
		.m_awready(bus_awready),
		.m_awaddr(bus_awaddr),
		.m_wvalid(bus_wvalid),
		.m_wready(bus_wready),
		.m_wdata(bus_wdata),
		.m_wstrb(bus_wstrb),
		.m_bvalid(bus_bvalid),
		.m_bready(bus_bready),
		.m_bresp(bus_bresp),
		.m_arvalid(bus_arvalid),
		.m_arready(bus_arready),
		.m_araddr(bus_araddr),
		.m_rvalid(bus_rvalid),
		.m_rready(bus_rready),
		.m_rdata(bus_rdata),
		.m_rresp(bus_rresp),
		.s0_awvalid(s0_awv),
		.s0_awready(s0_awr),
		.s0_awaddr(s0_awa),
		.s0_wvalid(s0_wv),
		.s0_wready(s0_wr),
		.s0_wdata(s0_wd),
		.s0_wstrb(s0_ws),
		.s0_bvalid(s0_bv),
		.s0_bready(s0_br),
		.s0_bresp(s0_brs),
		.s0_arvalid(s0_arv),
		.s0_arready(s0_arr),
		.s0_araddr(s0_ara),
		.s0_rvalid(s0_rv),
		.s0_rready(s0_rr),
		.s0_rdata(s0_rd),
		.s0_rresp(s0_rrs),
		.s1_awvalid(s1_awv),
		.s1_awready(s1_awr),
		.s1_awaddr(s1_awa),
		.s1_wvalid(s1_wv),
		.s1_wready(s1_wr),
		.s1_wdata(s1_wd),
		.s1_wstrb(s1_ws),
		.s1_bvalid(s1_bv),
		.s1_bready(s1_br),
		.s1_bresp(s1_brs),
		.s1_arvalid(s1_arv),
		.s1_arready(s1_arr),
		.s1_araddr(s1_ara),
		.s1_rvalid(s1_rv),
		.s1_rready(s1_rr),
		.s1_rdata(s1_rd),
		.s1_rresp(s1_rrs),
		.s2_awvalid(s2_awv),
		.s2_awready(s2_awr),
		.s2_awaddr(s2_awa),
		.s2_wvalid(s2_wv),
		.s2_wready(s2_wr),
		.s2_wdata(s2_wd),
		.s2_wstrb(s2_ws),
		.s2_bvalid(s2_bv),
		.s2_bready(s2_br),
		.s2_bresp(s2_brs),
		.s2_arvalid(s2_arv),
		.s2_arready(s2_arr),
		.s2_araddr(s2_ara),
		.s2_rvalid(s2_rv),
		.s2_rready(s2_rr),
		.s2_rdata(s2_rd),
		.s2_rresp(s2_rrs)
	);
	axi_lite_sram #(
		.ADDR_W(XLEN),
		.DATA_W(XLEN),
		.MEM_DEPTH(16384)
	) u_sram(
		.clk(clk),
		.rst_n(rst_n),
		.awvalid(s0_awv),
		.awready(s0_awr),
		.awaddr(s0_awa),
		.wvalid(s0_wv),
		.wready(s0_wr),
		.wdata(s0_wd),
		.wstrb(s0_ws),
		.bvalid(s0_bv),
		.bready(s0_br),
		.bresp(s0_brs),
		.arvalid(s0_arv),
		.arready(s0_arr),
		.araddr(s0_ara),
		.rvalid(s0_rv),
		.rready(s0_rr),
		.rdata(s0_rd),
		.rresp(s0_rrs)
	);
	axi_lite_uart #(
		.ADDR_W(XLEN),
		.DATA_W(XLEN)
	) u_uart(
		.clk(clk),
		.rst_n(rst_n),
		.awvalid(s1_awv),
		.awready(s1_awr),
		.awaddr(s1_awa),
		.wvalid(s1_wv),
		.wready(s1_wr),
		.wdata(s1_wd),
		.wstrb(s1_ws),
		.bvalid(s1_bv),
		.bready(s1_br),
		.bresp(s1_brs),
		.arvalid(s1_arv),
		.arready(s1_arr),
		.araddr(s1_ara),
		.rvalid(s1_rv),
		.rready(s1_rr),
		.rdata(s1_rd),
		.rresp(s1_rrs),
		.uart_tx(uart_tx),
		.uart_rx(uart_rx),
		.uart_irq(uart_irq_w)
	);
	axi_lite_gpio #(
		.ADDR_W(XLEN),
		.DATA_W(XLEN)
	) u_gpio(
		.clk(clk),
		.rst_n(rst_n),
		.awvalid(s2_awv),
		.awready(s2_awr),
		.awaddr(s2_awa),
		.wvalid(s2_wv),
		.wready(s2_wr),
		.wdata(s2_wd),
		.wstrb(s2_ws),
		.bvalid(s2_bv),
		.bready(s2_br),
		.bresp(s2_brs),
		.arvalid(s2_arv),
		.arready(s2_arr),
		.araddr(s2_ara),
		.rvalid(s2_rv),
		.rready(s2_rr),
		.rdata(s2_rd),
		.rresp(s2_rrs),
		.gpio_out(gpio_out),
		.gpio_in(gpio_in),
		.gpio_oe(gpio_oe)
	);
	reg [1:0] prev_priv_r;
	wire priv_changed_r;
	always @(posedge clk or negedge rst_n)
		if (!rst_n)
			prev_priv_r <= 2'b11;
		else
			prev_priv_r <= current_priv;
	assign priv_changed_r = current_priv != prev_priv_r;
	security_monitor #(
		.XLEN(XLEN),
		.PMP_REGIONS(PMP_REGIONS)
	) u_secmon(
		.clk(clk),
		.rst_n(rst_n),
		.current_priv(current_priv),
		.prev_priv(prev_priv_r),
		.priv_changed(priv_changed_r),
		.pmp_deny(pmp_dmem_deny | pmp_imem_deny),
		.pmp_match_region(pmp_dmem_region),
		.access_addr(dmem_addr),
		.access_read(dmem_req & ~dmem_we),
		.access_write(dmem_req & dmem_we),
		.access_exec(imem_req),
		.illegal_insn(rvfi_trap),
		.is_ecall(core_is_ecall),
		.is_mret(core_is_mret),
		.trap_taken(rvfi_trap),
		.csr_access(core_is_csr),
		.csr_addr(core_csr_addr),
		.csr_denied(core_csr_denied),
		.sec_alert(sec_alert),
		.sec_alert_code(sec_alert_code),
		.sec_event_count(sec_event_count),
		.sec_log_data(),
		.sec_log_idx(4'b0000)
	);
endmodule