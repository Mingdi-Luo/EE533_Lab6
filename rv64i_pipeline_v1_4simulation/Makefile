#============================================================================
# Makefile for RV64I Pipeline Processor Simulation
# Simulator: Icarus Verilog (iverilog)
#============================================================================

SRCS = \
	rv64i_pipeline_top.v \
	program_counter.v \
	instruction_memory.v \
	data_memory.v \
	register_file.v \
	control_unit.v \
	imm_gen.v \
	alu_control_unit.v \
	alu_64bit.v \
	pipeline_registers.v \
	forwarding_hazard.v

TB = tb_rv64i_pipeline.v
TOP = tb_rv64i_pipeline
OUT = rv64i_sim

.PHONY: all sim wave clean

all: sim

sim: $(SRCS) $(TB)
	iverilog -g2012 -o $(OUT) $(TB) $(SRCS)
	vvp $(OUT)

wave: sim
	gtkwave rv64i_pipeline.vcd &

clean:
	rm -f $(OUT) rv64i_pipeline.vcd
