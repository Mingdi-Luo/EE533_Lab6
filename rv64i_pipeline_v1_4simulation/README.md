# RV64I 5-Stage Pipelined Processor

## Architecture Overview

A complete 5-stage pipelined RISC-V RV64I processor implemented in Verilog.

```
┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│ IF  │──▶│ ID  │──▶│ EX  │──▶│ MEM │──▶│ WB  │
└─────┘   └─────┘   └─────┘   └─────┘   └─────┘
     IF/ID    ID/EX    EX/MEM    MEM/WB
```

## Parameters
| Component          | Width  | Depth | Total     |
|--------------------|--------|-------|-----------|
| Instruction Memory | 32-bit | 512   | 2 KB      |
| Data Memory        | 64-bit | 256   | 2 KB      |
| Register File      | 64-bit | 32    | x0 – x31  |

## Supported Instructions (RV64I Base)

### R-type
ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
ADDW, SUBW, SLLW, SRLW, SRAW (32-bit variants)

### I-type
ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
ADDIW, SLLIW, SRLIW, SRAIW (32-bit variants)
LB, LH, LW, LD, LBU, LHU, LWU (loads)
JALR

### S-type
SB, SH, SW, SD (stores)

### B-type
BEQ, BNE, BLT, BGE, BLTU, BGEU (branches)

### U-type
LUI, AUIPC

### J-type
JAL

## Pipeline Hazard Handling

- **Data Forwarding**: Full forwarding from EX/MEM and MEM/WB stages
- **Load-Use Hazard**: 1-cycle stall via Hazard Detection Unit
- **Control Hazard**: Flush on branch/jump taken (branch resolved in EX stage)

## File Structure

```
rv64i_pipeline/
├── rv64i_pipeline_top.v    # Top-level module with full datapath
├── program_counter.v       # PC with stall support
├── instruction_memory.v    # 32-bit × 512 ROM
├── data_memory.v           # 64-bit × 256 RAM (LB/LH/LW/LD/LBU/LHU/LWU/SB/SH/SW/SD)
├── register_file.v         # 64-bit × 32 with internal forwarding
├── control_unit.v          # Main control signal generation
├── imm_gen.v               # Immediate generator (I/S/B/U/J types)
├── alu_control_unit.v      # ALU operation decoder
├── alu_64bit.v             # 64-bit ALU with all RV64I operations
├── pipeline_registers.v    # IF/ID, ID/EX, EX/MEM, MEM/WB registers
├── forwarding_hazard.v     # Forwarding unit + Hazard detection unit
├── tb_rv64i_pipeline.v     # Testbench with sample program
├── Makefile                # Build & simulate with Icarus Verilog
└── README.md               # This file
```

## Simulation

### Using Icarus Verilog
```bash
make sim        # Compile and run simulation
make wave       # Open waveform in GTKWave
make clean      # Clean generated files
```

### Using Vivado
```tcl
read_verilog {rv64i_pipeline_top.v program_counter.v instruction_memory.v data_memory.v register_file.v control_unit.v imm_gen.v alu_control_unit.v alu_64bit.v pipeline_registers.v forwarding_hazard.v}
read_verilog -sv tb_rv64i_pipeline.v
set_property top tb_rv64i_pipeline [current_fileset -simset]
launch_simulation
```

### Loading Custom Programs
Edit `instruction_memory.v` to load from a hex file:
```verilog
initial begin
    $readmemh("program.hex", mem);
end
```

## Datapath Diagram

```
                         ┌─────────────────────── PCSrc ──────────────────────┐
                         │                                                     │
    ┌────┐  ┌───────────┐│ IF/ID  ┌──────────┐ ID/EX  ┌─────┐ EX/MEM  ┌──────────┐ MEM/WB  ┌─────┐
    │    │  │  Instr    ││        │ Register │        │     │         │  Data    │         │     │
 ──▶│ PC │─▶│  Memory   │├──┬───▶│  File    │──┬───▶│ ALU │───┬───▶│  Memory  │───┬───▶│ MUX │──┐
    │    │  │ 32b × 512 ││  │    │ 64b × 32 │  │    │     │   │    │ 64b × 256│   │    │     │  │
    └────┘  └───────────┘│  │    └──────────┘  │    └─────┘   │    └──────────┘   │    └─────┘  │
      ▲                  │  │    ┌──────────┐  │    ┌───┐     │                   │             │
      │     ┌─────┐      │  ├──▶│ Control  │  ├──▶│MUX│     │                   │             │
      └─────│ +4  │◀─────┘  │   └──────────┘  │   └───┘     │                   │             │
            └─────┘         │   ┌──────────┐   │              │                   │             │
                            └──▶│ Imm Gen  │───┘              │                   │             │
                                └──────────┘                  │                   │             │
                                                              │  ┌────────────┐   │             │
                            ┌── Forwarding Unit ◀─────────────┘  │ Hazard Det │   │             │
                            │                                    └────────────┘   │             │
                            └─────────────────── Write Back ◀─────────────────────┘─────────────┘
```
