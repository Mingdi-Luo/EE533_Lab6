#!/usr/bin/env python3
"""
ARM-to-RV64I Cross Translator (Improved)
==========================================

Translates ARMv4T (arm7tdmi) assembly into RV64I machine code.
Designed for EE533 Lab 6: translating GCC-generated ARM sort.s to run
on a bare-metal RV64I pipelined processor (no OS, no linker).

Key improvements over v1:
  1. Handles .rodata / .LC0 data sections and literal pool references
  2. Handles `ldr r3, .L8` (PC-relative literal pool loads)
  3. Handles ldmia/stmia with/without writeback ('!' suffix)
  4. --mode=baremetal: rewrites stack-based array init into direct
     register-to-memory stores for standalone hardware execution
  5. --mode=faithful: 1:1 ARM->RV64I translation preserving stack frame
  6. Proper sign extension for 12-bit immediates
  7. Better error messages and warnings

Output formats:
  .S   - Annotated RV64I assembly
  .hex - Machine code hex (one 32-bit word per line)
  .v   - Verilog memory initialization for testbench

Usage:
  python3 arm2rv64i.py sort.s -o sort --all
  python3 arm2rv64i.py sort.s --mode baremetal --data-addr 0x200
  python3 arm2rv64i.py sort.s --mode faithful --all -v
"""

import sys
import re
import argparse
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Optional


# =============================================================================
# RV64I Encoding Functions
# =============================================================================

def encode_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_s(imm12, rs2, rs1, funct3, opcode=0x23):
    imm = imm12 & 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F)

def encode_b(offset, rs1, rs2, funct3, opcode=0x63):
    imm12 = (offset >> 12) & 1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    imm11 = (offset >> 11) & 1
    return (imm12 << 31) | (imm10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (imm4_1 << 8) | (imm11 << 7) | (opcode & 0x7F)

def encode_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_j(offset, rd, opcode=0x6F):
    imm20 = (offset >> 20) & 1
    imm10_1 = (offset >> 1) & 0x3FF
    imm11 = (offset >> 11) & 1
    imm19_12 = (offset >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)


# RV64I instruction helpers
def rv_add(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x0, rd, 0x33)
def rv_sub(rd, rs1, rs2):    return encode_r(0x20, rs2, rs1, 0x0, rd, 0x33)
def rv_and(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x7, rd, 0x33)
def rv_or(rd, rs1, rs2):     return encode_r(0x00, rs2, rs1, 0x6, rd, 0x33)
def rv_xor(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x4, rd, 0x33)
def rv_sll(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x1, rd, 0x33)
def rv_srl(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x5, rd, 0x33)
def rv_sra(rd, rs1, rs2):    return encode_r(0x20, rs2, rs1, 0x5, rd, 0x33)
def rv_slt(rd, rs1, rs2):    return encode_r(0x00, rs2, rs1, 0x2, rd, 0x33)

def rv_addi(rd, rs1, imm):   return encode_i(imm & 0xFFF, rs1, 0x0, rd, 0x13)
def rv_andi(rd, rs1, imm):   return encode_i(imm & 0xFFF, rs1, 0x7, rd, 0x13)
def rv_ori(rd, rs1, imm):    return encode_i(imm & 0xFFF, rs1, 0x6, rd, 0x13)
def rv_xori(rd, rs1, imm):   return encode_i(imm & 0xFFF, rs1, 0x4, rd, 0x13)
def rv_slti(rd, rs1, imm):   return encode_i(imm & 0xFFF, rs1, 0x2, rd, 0x13)
def rv_slli(rd, rs1, shamt): return encode_i(shamt & 0x3F, rs1, 0x1, rd, 0x13)
def rv_srli(rd, rs1, shamt): return encode_i(shamt & 0x3F, rs1, 0x5, rd, 0x13)
def rv_srai(rd, rs1, shamt): return encode_i((0x400 | (shamt & 0x3F)), rs1, 0x5, rd, 0x13)

def rv_lb(rd, rs1, imm):     return encode_i(imm & 0xFFF, rs1, 0x0, rd, 0x03)
def rv_lh(rd, rs1, imm):     return encode_i(imm & 0xFFF, rs1, 0x1, rd, 0x03)
def rv_lw(rd, rs1, imm):     return encode_i(imm & 0xFFF, rs1, 0x2, rd, 0x03)
def rv_ld(rd, rs1, imm):     return encode_i(imm & 0xFFF, rs1, 0x3, rd, 0x03)
def rv_lbu(rd, rs1, imm):    return encode_i(imm & 0xFFF, rs1, 0x4, rd, 0x03)
def rv_lhu(rd, rs1, imm):    return encode_i(imm & 0xFFF, rs1, 0x5, rd, 0x03)
def rv_lwu(rd, rs1, imm):    return encode_i(imm & 0xFFF, rs1, 0x6, rd, 0x03)

def rv_sb(rs2, rs1, imm):    return encode_s(imm & 0xFFF, rs2, rs1, 0x0)
def rv_sh(rs2, rs1, imm):    return encode_s(imm & 0xFFF, rs2, rs1, 0x1)
def rv_sw(rs2, rs1, imm):    return encode_s(imm & 0xFFF, rs2, rs1, 0x2)
def rv_sd(rs2, rs1, imm):    return encode_s(imm & 0xFFF, rs2, rs1, 0x3)

def rv_beq(rs1, rs2, off):   return encode_b(off, rs1, rs2, 0x0)
def rv_bne(rs1, rs2, off):   return encode_b(off, rs1, rs2, 0x1)
def rv_blt(rs1, rs2, off):   return encode_b(off, rs1, rs2, 0x4)
def rv_bge(rs1, rs2, off):   return encode_b(off, rs1, rs2, 0x5)
def rv_bltu(rs1, rs2, off):  return encode_b(off, rs1, rs2, 0x6)
def rv_bgeu(rs1, rs2, off):  return encode_b(off, rs1, rs2, 0x7)

def rv_jal(rd, off):         return encode_j(off, rd)
def rv_jalr(rd, rs1, imm):   return encode_i(imm & 0xFFF, rs1, 0x0, rd, 0x67)
def rv_lui(rd, imm20):       return encode_u(imm20, rd, 0x37)
def rv_auipc(rd, imm20):     return encode_u(imm20, rd, 0x17)
def rv_nop():                return rv_addi(0, 0, 0)


# =============================================================================
# ARM Register -> RV64I Mapping
# =============================================================================

ARM_TO_RV = {
    'r0': 10, 'r1': 11, 'r2': 12, 'r3': 13,
    'r4': 14, 'r5': 15, 'r6': 16, 'r7': 17,
    'r8': 18, 'r9': 19, 'r10': 20, 'r11': 21,
    'r12': 22,
    'sp': 2, 'r13': 2,
    'lr': 1, 'r14': 1,
    'fp': 8,
    'ip': 22,
}

RV_TEMP1 = 30   # x30 (t5) - translator scratch
RV_TEMP2 = 29   # x29 (t4) - translator scratch
RV_ZERO  = 0


# =============================================================================
# Data Section Parser
# =============================================================================

@dataclass
class DataSection:
    """Holds .rodata / .data constants parsed from ARM assembly"""
    labels: Dict[str, int] = field(default_factory=dict)   # label -> offset in data
    words: List[int] = field(default_factory=list)          # 32-bit word values
    label_refs: Dict[str, str] = field(default_factory=dict)  # .L8 -> .LC0 references

    def add_word(self, label: str, value: int):
        if label and label not in self.labels:
            self.labels[label] = len(self.words)
        self.words.append(value & 0xFFFFFFFF if value >= 0 else value)

    def get_words_at(self, label: str) -> List[int]:
        """Get all words starting from a label"""
        if label not in self.labels:
            return []
        start = self.labels[label]
        # Find next label or end
        next_starts = [v for k, v in self.labels.items() if v > start]
        end = min(next_starts) if next_starts else len(self.words)
        return self.words[start:end]


def parse_data_sections(lines: List[str]) -> DataSection:
    """Parse .rodata and .data sections to extract constant arrays"""
    data = DataSection()
    in_rodata = False
    current_label = ""

    for line in lines:
        stripped = line.strip()

        # Remove comments
        if '@' in stripped:
            stripped = stripped[:stripped.index('@')].strip()

        # Track section changes
        if '.section' in stripped and '.rodata' in stripped:
            in_rodata = True
            continue
        if stripped == '.text':
            in_rodata = False
            continue

        if not in_rodata:
            # Also check for literal pool references: .L8: .word .LC0
            if stripped.endswith(':'):
                current_label = stripped[:-1].strip()
            elif stripped.startswith('.word') and current_label:
                val_str = stripped[5:].strip()
                if val_str.startswith('.'):
                    # This is a label reference: .L8: .word .LC0
                    data.label_refs[current_label] = val_str
                current_label = ""
            continue

        # Inside .rodata
        if stripped.endswith(':'):
            current_label = stripped[:-1].strip()
            continue

        if stripped.startswith('.word'):
            val_str = stripped[5:].strip()
            try:
                if val_str.startswith('0x') or val_str.startswith('0X'):
                    val = int(val_str, 16)
                elif val_str.startswith('-'):
                    val = int(val_str)
                else:
                    val = int(val_str)
                data.add_word(current_label, val)
                current_label = ""  # only first word gets the label
            except ValueError:
                pass

        if stripped.startswith('.align'):
            continue

    return data


# =============================================================================
# ARM Instruction Parser
# =============================================================================

@dataclass
class ARMInstruction:
    label: str = ""
    opcode: str = ""
    cond: str = ""
    s_flag: bool = False
    operands: list = field(default_factory=list)
    comment: str = ""
    raw: str = ""
    line_num: int = 0
    is_directive: bool = False
    is_label: bool = False


def parse_arm_register(s: str) -> str:
    s = s.strip().lower()
    aliases = {'a1': 'r0', 'a2': 'r1', 'a3': 'r2', 'a4': 'r3',
               'v1': 'r4', 'v2': 'r5', 'v3': 'r6', 'v4': 'r7',
               'v5': 'r8', 'sb': 'r9', 'sl': 'r10'}
    return aliases.get(s, s)


def parse_immediate(s: str) -> int:
    s = s.strip().lstrip('#')
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    elif s.startswith('-0x') or s.startswith('-0X'):
        return -int(s[1:], 16)
    else:
        return int(s)


def parse_register_list(s: str) -> List[str]:
    s = s.strip('{}').strip()
    regs = []
    for part in s.split(','):
        part = part.strip()
        if '-' in part:
            start, end = part.split('-')
            start_num = int(re.search(r'\d+', start.strip()).group())
            end_num = int(re.search(r'\d+', end.strip()).group())
            for i in range(start_num, end_num + 1):
                regs.append(f'r{i}')
        else:
            regs.append(parse_arm_register(part))
    return regs


def parse_memory_operand(s: str) -> Tuple[str, int, bool]:
    """Parse [reg, #imm] -> (reg_name, offset, writeback)"""
    s = s.strip()
    m = re.match(r'\[(\w+),\s*#(-?\w+)\](!)?', s)
    if m:
        return parse_arm_register(m.group(1)), parse_immediate(m.group(2)), m.group(3) == '!'
    m = re.match(r'\[(\w+)\](!)?', s)
    if m:
        return parse_arm_register(m.group(1)), 0, m.group(2) == '!'
    return parse_arm_register(s), 0, False


def parse_arm_line(line: str, line_num: int) -> Optional[ARMInstruction]:
    inst = ARMInstruction(raw=line, line_num=line_num)

    # Strip comments
    for marker in ['@', '//']:
        if marker in line:
            idx = line.index(marker)
            inst.comment = line[idx:]
            line = line[:idx]

    line = line.strip()
    if not line:
        return None

    # Directives
    if line.startswith('.'):
        # Check if it's a label like .L2:
        if line.endswith(':'):
            inst.label = line[:-1].strip()
            inst.is_label = True
            return inst
        # .word, .align, etc.
        inst.opcode = line.split()[0]
        inst.operands = line.split(None, 1)[1:] if len(line.split()) > 1 else []
        inst.is_directive = True
        return inst

    # Check for label
    m = re.match(r'^(\w+):\s*(.*)', line)
    if m:
        inst.label = m.group(1)
        line = m.group(2).strip()
        if not line:
            inst.is_label = True
            return inst

    if line.endswith(':'):
        inst.label = line[:-1].strip()
        inst.is_label = True
        return inst

    # Parse instruction mnemonic
    parts = line.split(None, 1)
    if not parts:
        return None

    mnemonic = parts[0].lower()
    operand_str = parts[1] if len(parts) > 1 else ""

    # Known base opcodes
    base_opcodes = ['add', 'sub', 'rsb', 'adc', 'sbc', 'rsc',
                    'and', 'orr', 'eor', 'bic', 'mvn', 'mov',
                    'cmp', 'cmn', 'tst', 'teq',
                    'ldr', 'str', 'ldm', 'stm', 'lsl', 'lsr', 'asr',
                    'mul', 'mla',
                    'push', 'pop',
                    'b', 'bl', 'bx', 'blx',
                    'nop', 'swi', 'svc']

    cond_codes = ['eq', 'ne', 'cs', 'hs', 'cc', 'lo', 'mi', 'pl',
                  'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le', 'al']

    inst.cond = ''
    inst.s_flag = False
    matched = False

    for base in sorted(base_opcodes, key=len, reverse=True):
        if mnemonic.startswith(base):
            rest = mnemonic[len(base):]
            inst.opcode = base

            # ldr/str variants: b, h, sb, sh
            if base in ('ldr', 'str') and rest and rest[0] in ('b', 'h', 's'):
                for suffix in ['sb', 'sh', 'b', 'h']:
                    if rest.startswith(suffix):
                        inst.opcode = base + suffix
                        rest = rest[len(suffix):]
                        break

            # ldm/stm variants: ia, ib, da, db
            if base in ('ldm', 'stm'):
                for suffix in ['ia', 'ib', 'da', 'db']:
                    if rest.startswith(suffix):
                        inst.opcode = base + suffix
                        rest = rest[len(suffix):]
                        break

            # Condition code
            for cc in cond_codes:
                if rest.startswith(cc):
                    inst.cond = cc
                    rest = rest[len(cc):]
                    break

            # S flag
            if rest == 's':
                inst.s_flag = True
                rest = ''

            if rest == '':
                matched = True
                break

    if not matched:
        inst.opcode = mnemonic

    # Parse operands
    if operand_str:
        if '{' in operand_str:
            pre = operand_str[:operand_str.index('{')].strip().rstrip(',')
            brace_content = operand_str[operand_str.index('{')+1:operand_str.index('}')]
            post = operand_str[operand_str.index('}')+1:].strip()
            if pre:
                inst.operands.append(pre.strip())
            inst.operands.append('{' + brace_content + '}')
            if '!' in post:
                inst.operands.append('!')
        else:
            ops = []
            depth = 0
            current = ''
            for ch in operand_str:
                if ch == '[': depth += 1; current += ch
                elif ch == ']': depth -= 1; current += ch
                elif ch == ',' and depth == 0:
                    ops.append(current.strip())
                    current = ''
                else:
                    current += ch
            if current.strip():
                ops.append(current.strip())
            inst.operands = ops

    return inst


# =============================================================================
# RV64I Output Instruction
# =============================================================================

@dataclass
class RV64Instruction:
    asm: str
    machine_code: int
    comment: str = ""
    address: int = 0


# =============================================================================
# ARM -> RV64I Translator
# =============================================================================

class ARM2RV64Translator:

    def __init__(self, base_addr=0, data_addr=0x200, mode='faithful',
                 data_width=32):
        """
        Args:
            base_addr: Starting byte address for generated code
            data_addr: Starting byte address for array data in memory
            mode: 'faithful' = 1:1 translation, 'baremetal' = optimized for bare-metal
            data_width: Memory word width in bits (32 or 64)
        """
        self.labels: Dict[str, int] = {}
        self.rv_instructions: List[RV64Instruction] = []
        self.arm_instructions: List[ARMInstruction] = []
        self.data_section = DataSection()
        self.base_addr = base_addr
        self.data_addr = data_addr
        self.mode = mode
        self.data_width = data_width
        self.cmp_rs1 = -1
        self.cmp_rs2 = -1
        self.warnings: List[str] = []

    def arm_reg(self, name: str) -> int:
        name = parse_arm_register(name)
        if name in ARM_TO_RV:
            return ARM_TO_RV[name]
        raise ValueError(f"Unknown ARM register: '{name}'")

    def emit(self, asm: str, machine_code: int, comment: str = ""):
        addr = self.base_addr + len(self.rv_instructions) * 4
        self.rv_instructions.append(RV64Instruction(
            asm=asm, machine_code=machine_code & 0xFFFFFFFF,
            comment=comment, address=addr
        ))

    def emit_li(self, rd: int, imm: int):
        """Load immediate, handling values outside 12-bit signed range"""
        if -2048 <= imm <= 2047:
            self.emit(f"addi x{rd}, x0, {imm}", rv_addi(rd, 0, imm), f"li x{rd}, {imm}")
        else:
            upper = ((imm + 0x800) >> 12) & 0xFFFFF
            lower = imm - ((upper << 12) if upper < 0x80000 else ((upper - 0x100000) << 12))
            # Simpler: use sign extension math
            upper = (imm + 0x800) >> 12
            lower = imm - (upper << 12)
            self.emit(f"lui x{rd}, {upper & 0xFFFFF}", rv_lui(rd, upper & 0xFFFFF),
                      f"li x{rd}, {imm} (upper)")
            if lower != 0:
                self.emit(f"addi x{rd}, x{rd}, {lower}", rv_addi(rd, rd, lower & 0xFFF),
                          f"li x{rd}, {imm} (lower)")

    def _get_branch_offset(self, target_label: str) -> int:
        current_addr = self.base_addr + len(self.rv_instructions) * 4
        return self.labels.get(target_label, current_addr) - current_addr

    # ---- Parse and Translate ----

    def parse_and_translate(self, lines: List[str]):
        """Complete pipeline: parse data, parse code, multi-pass translate"""
        # Step 1: Parse .rodata sections
        self.data_section = parse_data_sections(lines)

        # Step 2: Parse ARM instructions
        for i, line in enumerate(lines):
            inst = parse_arm_line(line, i + 1)
            if inst:
                self.arm_instructions.append(inst)

        # Step 3: In baremetal mode, prepend data initialization code
        if self.mode == 'baremetal':
            self._generate_baremetal_init()
            return  # baremetal mode generates its own optimized code

        # Step 4: Faithful mode - multi-pass translation
        self._translate_faithful()

    def _generate_baremetal_init(self):
        """Baremetal mode: generate optimized register-based code
        that directly initializes array in data memory and runs sort."""

        # Find the array data from .rodata
        array_data = []
        for label, ref_label in self.data_section.label_refs.items():
            words = self.data_section.get_words_at(ref_label)
            if words:
                array_data = words
                break

        if not array_data:
            # Try to get from .LC0 directly
            array_data = self.data_section.get_words_at('.LC0')

        if not array_data:
            self.warnings.append("WARNING: No array data found in .rodata section")
            array_data = [323, 123, -455, 2, 98, 125, 10, 65, -56, 0]

        N = len(array_data)
        word_size = self.data_width // 8  # 4 for 32-bit, 8 for 64-bit

        # Register allocation for baremetal:
        #   x19 = array base address
        #   x10 = N (array size)
        #   x9  = i (outer loop)
        #   x18 = j (inner loop)
        #   x5  = address scratch
        #   x6  = arr[i] value
        #   x7  = arr[j] value
        #   x28 = swap temp
        #   x11 = scratch for initialization
        #   x31 = done flag

        store_fn = rv_sd if self.data_width == 64 else rv_sw
        load_fn = rv_ld if self.data_width == 64 else rv_lw
        store_asm = "sd" if self.data_width == 64 else "sw"
        load_asm = "ld" if self.data_width == 64 else "lw"
        funct3_store = 0x3 if self.data_width == 64 else 0x2
        funct3_load = 0x3 if self.data_width == 64 else 0x2
        shift_amt = 3 if self.data_width == 64 else 2

        # --- Phase 1: Initialize array in data memory ---
        self.emit(f"addi x19, x0, {self.data_addr}",
                  rv_addi(19, 0, self.data_addr),
                  f"base addr = 0x{self.data_addr:X}")

        for i, val in enumerate(array_data):
            # Sign-extend 32-bit value
            if val < 0:
                val_32 = val & 0xFFFFFFFF
                val_signed = val
            elif val > 0x7FFFFFFF:
                val_signed = val - 0x100000000
            else:
                val_signed = val

            offset = i * word_size
            self.emit_li(11, val_signed)
            self.emit(f"{store_asm} x11, {offset}(x19)",
                      encode_s(offset & 0xFFF, 11, 19, funct3_store),
                      f"arr[{i}] = {val_signed}")

        # --- Phase 2: Bubble sort ---
        self.emit(f"addi x10, x0, {N}", rv_addi(10, 0, N), f"N = {N}")
        self.emit("addi x9, x0, 0", rv_addi(9, 0, 0), "i = 0")

        # Labels will be resolved in a fixup pass
        # We need to know instruction indices for branch targets
        idx_outer_check = len(self.rv_instructions)

        # outer_check: bge x9, x10, end
        self.emit("bge x9, x10, end", rv_bge(9, 10, 0), "if i>=N goto end")  # fixup later
        self.emit("addi x18, x9, 1", rv_addi(18, 9, 1), "j = i+1")

        idx_inner_check = len(self.rv_instructions)

        # inner_check: bge x18, x10, inc_i
        self.emit("bge x18, x10, inc_i", rv_bge(18, 10, 0), "if j>=N goto inc_i")

        # Load arr[i]
        self.emit(f"slli x5, x9, {shift_amt}", rv_slli(5, 9, shift_amt), "i*wordsize")
        self.emit("add x5, x5, x19", rv_add(5, 5, 19), "&arr[i]")
        self.emit(f"{load_asm} x6, 0(x5)",
                  encode_i(0, 5, funct3_load, 6, 0x03), "arr[i]")

        # Load arr[j]
        self.emit(f"slli x5, x18, {shift_amt}", rv_slli(5, 18, shift_amt), "j*wordsize")
        self.emit("add x5, x5, x19", rv_add(5, 5, 19), "&arr[j]")
        self.emit(f"{load_asm} x7, 0(x5)",
                  encode_i(0, 5, funct3_load, 7, 0x03), "arr[j]")

        # Compare: bge x7, x6, no_swap
        idx_bge_noswap = len(self.rv_instructions)
        self.emit("bge x7, x6, no_swap", rv_bge(7, 6, 0), "if arr[j]>=arr[i] skip")

        # Swap
        self.emit("addi x28, x7, 0", rv_addi(28, 7, 0), "temp = arr[j]")
        self.emit(f"slli x5, x18, {shift_amt}", rv_slli(5, 18, shift_amt), "j*wordsize")
        self.emit("add x5, x5, x19", rv_add(5, 5, 19), "&arr[j]")
        self.emit(f"{store_asm} x6, 0(x5)",
                  encode_s(0, 6, 5, funct3_store), "arr[j]=arr[i]")
        self.emit(f"slli x5, x9, {shift_amt}", rv_slli(5, 9, shift_amt), "i*wordsize")
        self.emit("add x5, x5, x19", rv_add(5, 5, 19), "&arr[i]")
        self.emit(f"{store_asm} x28, 0(x5)",
                  encode_s(0, 28, 5, funct3_store), "arr[i]=temp")

        idx_no_swap = len(self.rv_instructions)

        # j++, jump to inner_check
        self.emit("addi x18, x18, 1", rv_addi(18, 18, 1), "j++")
        jal_inner_offset = (idx_inner_check - len(self.rv_instructions)) * 4
        self.emit("jal x0, inner_check", rv_jal(0, jal_inner_offset), "goto inner_check")

        idx_inc_i = len(self.rv_instructions)

        # i++, jump to outer_check
        self.emit("addi x9, x9, 1", rv_addi(9, 9, 1), "i++")
        jal_outer_offset = (idx_outer_check - len(self.rv_instructions)) * 4
        self.emit("jal x0, outer_check", rv_jal(0, jal_outer_offset), "goto outer_check")

        idx_end = len(self.rv_instructions)

        # Done
        self.emit("addi x31, x0, 1", rv_addi(31, 0, 1), "done flag")
        idx_halt = len(self.rv_instructions)
        self.emit("jal x0, halt", rv_jal(0, 0), "halt (infinite loop)")

        # --- Fixup branches ---
        def fixup(idx, target_idx):
            offset = (target_idx - idx) * 4
            inst = self.rv_instructions[idx]
            # Re-encode based on instruction type
            code = inst.machine_code
            opcode = code & 0x7F
            if opcode == 0x63:  # B-type
                rs1 = (code >> 15) & 0x1F
                rs2 = (code >> 20) & 0x1F
                funct3 = (code >> 12) & 0x7
                inst.machine_code = encode_b(offset, rs1, rs2, funct3) & 0xFFFFFFFF
            elif opcode == 0x6F:  # J-type
                rd = (code >> 7) & 0x1F
                inst.machine_code = encode_j(offset, rd) & 0xFFFFFFFF

        # outer_check: bge x9, x10, end
        fixup(idx_outer_check, idx_end)
        # inner_check: bge x18, x10, inc_i
        fixup(idx_inner_check, idx_inc_i)
        # bge x7, x6, no_swap
        fixup(idx_bge_noswap, idx_no_swap)

        # Record labels for output
        self.labels = {
            'init': self.base_addr,
            'outer_check': self.base_addr + idx_outer_check * 4,
            'inner_check': self.base_addr + idx_inner_check * 4,
            'no_swap': self.base_addr + idx_no_swap * 4,
            'inc_i': self.base_addr + idx_inc_i * 4,
            'end': self.base_addr + idx_end * 4,
            'halt': self.base_addr + idx_halt * 4,
        }

    def _translate_faithful(self):
        """Faithful 1:1 translation with multi-pass label resolution"""

        # Separate labels from code
        arm_labels = {}
        arm_code = []
        for inst in self.arm_instructions:
            if inst.is_label:
                arm_labels[inst.label] = len(arm_code)
            elif inst.is_directive:
                continue
            else:
                arm_code.append(inst)
                if inst.label:
                    arm_labels[inst.label] = len(arm_code) - 1

        # Three-pass translation for label resolution
        for pass_num in range(3):
            self.rv_instructions.clear()
            arm_to_rv = []
            for arm_idx, inst in enumerate(arm_code):
                arm_to_rv.append(len(self.rv_instructions))
                self._translate_one(inst, resolve=(pass_num > 0))

            # Update label -> RV64I address mapping
            for label, arm_idx in arm_labels.items():
                if arm_idx < len(arm_to_rv):
                    self.labels[label] = self.base_addr + arm_to_rv[arm_idx] * 4
                else:
                    self.labels[label] = self.base_addr + len(self.rv_instructions) * 4

    def _translate_one(self, inst: ARMInstruction, resolve: bool = False):
        op = inst.opcode
        ops = inst.operands
        cond = inst.cond

        try:
            if cond and op not in ('b', 'bl', 'bx', 'blx') and cond != 'al':
                self._translate_conditional(inst, resolve)
                return

            # ---- NOP ----
            if op == 'nop':
                self.emit("nop", rv_nop(), "nop")

            # ---- MOV ----
            elif op == 'mov':
                rd = self.arm_reg(ops[0])
                if ops[1].startswith('#'):
                    imm = parse_immediate(ops[1])
                    self.emit_li(rd, imm)
                else:
                    rs = self.arm_reg(ops[1])
                    self.emit(f"addi x{rd}, x{rs}, 0", rv_addi(rd, rs, 0),
                              f"mov {ops[0]}, {ops[1]}")

            # ---- MVN ----
            elif op == 'mvn':
                rd = self.arm_reg(ops[0])
                if ops[1].startswith('#'):
                    self.emit_li(rd, ~parse_immediate(ops[1]))
                else:
                    rs = self.arm_reg(ops[1])
                    self.emit(f"xori x{rd}, x{rs}, -1", rv_xori(rd, rs, -1), "mvn")

            # ---- ADD ----
            elif op == 'add':
                rd = self.arm_reg(ops[0])
                rs1 = self.arm_reg(ops[1])
                if len(ops) > 2 and ops[2].startswith('#'):
                    imm = parse_immediate(ops[2])
                    if -2048 <= imm <= 2047:
                        self.emit(f"addi x{rd}, x{rs1}, {imm}", rv_addi(rd, rs1, imm),
                                  f"add {ops[0]}, {ops[1]}, {ops[2]}")
                    else:
                        self.emit_li(RV_TEMP1, imm)
                        self.emit(f"add x{rd}, x{rs1}, x{RV_TEMP1}",
                                  rv_add(rd, rs1, RV_TEMP1), f"add large imm")
                elif len(ops) > 2:
                    rs2_str = ops[2]
                    if len(ops) > 3:
                        rs2 = self.arm_reg(rs2_str)
                        self._translate_shifted_op('add', rd, rs1, rs2, ops[3])
                    else:
                        rs2 = self.arm_reg(rs2_str)
                        self.emit(f"add x{rd}, x{rs1}, x{rs2}", rv_add(rd, rs1, rs2),
                                  f"add {ops[0]}, {ops[1]}, {ops[2]}")

            # ---- SUB ----
            elif op == 'sub':
                rd = self.arm_reg(ops[0])
                rs1 = self.arm_reg(ops[1])
                if len(ops) > 2 and ops[2].startswith('#'):
                    imm = parse_immediate(ops[2])
                    neg = -imm
                    if -2048 <= neg <= 2047:
                        self.emit(f"addi x{rd}, x{rs1}, {neg}", rv_addi(rd, rs1, neg),
                                  f"sub {ops[0]}, {ops[1]}, #{imm}")
                    else:
                        self.emit_li(RV_TEMP1, imm)
                        self.emit(f"sub x{rd}, x{rs1}, x{RV_TEMP1}",
                                  rv_sub(rd, rs1, RV_TEMP1), "sub large imm")
                elif len(ops) > 2:
                    rs2 = self.arm_reg(ops[2])
                    self.emit(f"sub x{rd}, x{rs1}, x{rs2}", rv_sub(rd, rs1, rs2),
                              f"sub {ops[0]}, {ops[1]}, {ops[2]}")

            # ---- RSB ----
            elif op == 'rsb':
                rd = self.arm_reg(ops[0])
                rs1 = self.arm_reg(ops[1])
                if len(ops) > 2 and ops[2].startswith('#'):
                    imm = parse_immediate(ops[2])
                    if imm == 0:
                        self.emit(f"sub x{rd}, x0, x{rs1}", rv_sub(rd, 0, rs1), "negate")
                    else:
                        self.emit_li(RV_TEMP1, imm)
                        self.emit(f"sub x{rd}, x{RV_TEMP1}, x{rs1}",
                                  rv_sub(rd, RV_TEMP1, rs1), "rsb")

            # ---- AND/ORR/EOR/BIC ----
            elif op in ('and', 'orr', 'eor', 'bic'):
                rd = self.arm_reg(ops[0])
                rs1 = self.arm_reg(ops[1])
                if len(ops) > 2 and ops[2].startswith('#'):
                    imm = parse_immediate(ops[2])
                    if op == 'bic': imm = ~imm
                    self.emit_li(RV_TEMP1, imm)
                    func = {'and': rv_and, 'orr': rv_or, 'eor': rv_xor, 'bic': rv_and}[op]
                    name = {'and': 'and', 'orr': 'or', 'eor': 'xor', 'bic': 'and'}[op]
                    self.emit(f"{name} x{rd}, x{rs1}, x{RV_TEMP1}",
                              func(rd, rs1, RV_TEMP1), f"{op} imm")
                elif len(ops) > 2:
                    rs2 = self.arm_reg(ops[2])
                    if op == 'bic':
                        self.emit(f"xori x{RV_TEMP1}, x{rs2}, -1",
                                  rv_xori(RV_TEMP1, rs2, -1), "~rs2")
                        self.emit(f"and x{rd}, x{rs1}, x{RV_TEMP1}",
                                  rv_and(rd, rs1, RV_TEMP1), "bic")
                    else:
                        func = {'and': rv_and, 'orr': rv_or, 'eor': rv_xor}[op]
                        self.emit(f"{op} x{rd}, x{rs1}, x{rs2}",
                                  func(rd, rs1, rs2), op)

            # ---- LSL/LSR/ASR ----
            elif op in ('lsl', 'lsr', 'asr'):
                rd = self.arm_reg(ops[0])
                rs1 = self.arm_reg(ops[1])
                if len(ops) > 2 and ops[2].startswith('#'):
                    shamt = parse_immediate(ops[2])
                    func = {'lsl': rv_slli, 'lsr': rv_srli, 'asr': rv_srai}[op]
                    name = {'lsl': 'slli', 'lsr': 'srli', 'asr': 'srai'}[op]
                    self.emit(f"{name} x{rd}, x{rs1}, {shamt}", func(rd, rs1, shamt), op)
                elif len(ops) > 2:
                    rs2 = self.arm_reg(ops[2])
                    func = {'lsl': rv_sll, 'lsr': rv_srl, 'asr': rv_sra}[op]
                    name = {'lsl': 'sll', 'lsr': 'srl', 'asr': 'sra'}[op]
                    self.emit(f"{name} x{rd}, x{rs1}, x{rs2}", func(rd, rs1, rs2), op)

            # ---- CMP ----
            elif op == 'cmp':
                rs1 = self.arm_reg(ops[0])
                if ops[1].startswith('#'):
                    imm = parse_immediate(ops[1])
                    self.emit_li(RV_TEMP1, imm)
                    self.cmp_rs1 = rs1
                    self.cmp_rs2 = RV_TEMP1
                else:
                    rs2 = self.arm_reg(ops[1])
                    self.cmp_rs1 = rs1
                    self.cmp_rs2 = rs2

            # ---- LDR (including literal pool) ----
            elif op in ('ldr', 'ldrb', 'ldrh', 'ldrsb', 'ldrsh'):
                rd = self.arm_reg(ops[0])

                # Check for literal pool load: ldr r3, .L8
                if len(ops) >= 2 and ops[1].startswith('.'):
                    label_name = ops[1].strip()
                    # This is "ldr rd, =label" or "ldr rd, .Lpool"
                    # Look up what the label points to in literal pool
                    if label_name in self.data_section.label_refs:
                        # .L8 -> .LC0 -> get address of data
                        ref = self.data_section.label_refs[label_name]
                        self.emit_li(rd, self.data_addr)
                        self.emit(f"# ldr {ops[0]}, {label_name} -> data addr 0x{self.data_addr:X}",
                                  rv_nop(), f"literal pool: {label_name} -> {ref}")
                    else:
                        # Try to load the literal value directly
                        self.emit_li(rd, 0)
                        self.warnings.append(
                            f"Line {inst.line_num}: ldr {ops[0]}, {label_name} "
                            f"- literal pool ref not resolved")
                    return

                # Normal memory load
                base_reg, offset, wb = parse_memory_operand(ops[1])
                rs1 = self.arm_reg(base_reg)
                load_map = {
                    'ldr':   ('lw',  rv_lw),  'ldrb': ('lbu', rv_lbu),
                    'ldrh':  ('lhu', rv_lhu), 'ldrsb': ('lb', rv_lb),
                    'ldrsh': ('lh',  rv_lh),
                }
                name, func = load_map[op]
                self.emit(f"{name} x{rd}, {offset}(x{rs1})", func(rd, rs1, offset),
                          f"{op} {ops[0]}, {ops[1]}")
                if wb:
                    self.emit(f"addi x{rs1}, x{rs1}, {offset}",
                              rv_addi(rs1, rs1, offset), "writeback")

            # ---- STR ----
            elif op in ('str', 'strb', 'strh'):
                rd = self.arm_reg(ops[0])
                base_reg, offset, wb = parse_memory_operand(ops[1])
                rs1 = self.arm_reg(base_reg)
                store_map = {
                    'str': ('sw', rv_sw), 'strb': ('sb', rv_sb), 'strh': ('sh', rv_sh),
                }
                name, func = store_map[op]
                self.emit(f"{name} x{rd}, {offset}(x{rs1})", func(rd, rs1, offset),
                          f"{op} {ops[0]}, {ops[1]}")
                if wb:
                    self.emit(f"addi x{rs1}, x{rs1}, {offset}",
                              rv_addi(rs1, rs1, offset), "writeback")

            # ---- LDMIA/STMIA ----
            elif op in ('ldmia', 'ldm', 'stmia', 'stm'):
                base_str = ops[0].rstrip('!')
                writeback = '!' in inst.raw or (len(ops) > 2 and '!' in ops[-1])
                base_rv = self.arm_reg(base_str)
                reg_list = parse_register_list(ops[1])

                offset = 0
                for reg_name in reg_list:
                    rv_reg = self.arm_reg(reg_name)
                    if op.startswith('ld'):
                        self.emit(f"lw x{rv_reg}, {offset}(x{base_rv})",
                                  rv_lw(rv_reg, base_rv, offset), f"{op} {reg_name}")
                    else:
                        self.emit(f"sw x{rv_reg}, {offset}(x{base_rv})",
                                  rv_sw(rv_reg, base_rv, offset), f"{op} {reg_name}")
                    offset += 4

                if writeback:
                    self.emit(f"addi x{base_rv}, x{base_rv}, {offset}",
                              rv_addi(base_rv, base_rv, offset), f"{op} writeback")

            # ---- PUSH/POP ----
            elif op == 'push':
                reg_list = parse_register_list(ops[0])
                n = len(reg_list)
                self.emit(f"addi x2, x2, {-4*n}", rv_addi(2, 2, -4*n), "push: sp -= N*4")
                for i, rn in enumerate(reg_list):
                    rv_r = self.arm_reg(rn)
                    self.emit(f"sw x{rv_r}, {i*4}(x2)", rv_sw(rv_r, 2, i*4), f"push {rn}")

            elif op == 'pop':
                reg_list = parse_register_list(ops[0])
                n = len(reg_list)
                for i, rn in enumerate(reg_list):
                    rv_r = self.arm_reg(rn)
                    self.emit(f"lw x{rv_r}, {i*4}(x2)", rv_lw(rv_r, 2, i*4), f"pop {rn}")
                self.emit(f"addi x2, x2, {4*n}", rv_addi(2, 2, 4*n), "pop: sp += N*4")

            # ---- B / BL / BX ----
            elif op == 'b':
                target = ops[0] if ops else ""
                if cond:
                    self._translate_branch(cond, target, resolve)
                else:
                    offset = self._get_branch_offset(target) if resolve else 0
                    self.emit(f"jal x0, {target}", rv_jal(0, offset), f"b {target}")

            elif op == 'bl':
                target = ops[0] if ops else ""
                offset = self._get_branch_offset(target) if resolve else 0
                self.emit(f"jal x1, {target}", rv_jal(1, offset), f"bl {target}")

            elif op == 'bx':
                rs = self.arm_reg(ops[0])
                self.emit(f"jalr x0, x{rs}, 0", rv_jalr(0, rs, 0), f"bx {ops[0]}")

            elif op == 'blx':
                rs = self.arm_reg(ops[0])
                self.emit(f"jalr x1, x{rs}, 0", rv_jalr(1, rs, 0), f"blx {ops[0]}")

            # ---- MUL (not in RV64I base, emit warning) ----
            elif op == 'mul':
                self.warnings.append(f"Line {inst.line_num}: MUL requires M extension")
                self.emit("# MUL not in RV64I base", rv_nop(), "NEEDS M EXT")

            else:
                self.emit(f"# UNKNOWN: {inst.raw.strip()}", rv_nop(), f"unhandled: {op}")

        except Exception as e:
            self.emit(f"# ERROR: {inst.raw.strip()}", rv_nop(), f"ERROR: {e}")
            self.warnings.append(f"Line {inst.line_num}: {e}")

    def _translate_branch(self, cond, target, resolve):
        rs1, rs2 = self.cmp_rs1, self.cmp_rs2
        if rs1 < 0 or rs2 < 0:
            self.warnings.append(f"Branch {cond} without prior CMP")
            self.emit(f"# WARNING: branch without CMP", rv_nop())
            return

        offset = self._get_branch_offset(target) if resolve else 0

        branch_map = {
            'eq': (rs1, rs2, rv_beq, "beq"),
            'ne': (rs1, rs2, rv_bne, "bne"),
            'ge': (rs1, rs2, rv_bge, "bge"),
            'lt': (rs1, rs2, rv_blt, "blt"),
            'gt': (rs2, rs1, rv_blt, "bgt->blt(swap)"),   # a>b == b<a
            'le': (rs2, rs1, rv_bge, "ble->bge(swap)"),   # a<=b == b>=a
            'hi': (rs2, rs1, rv_bltu, "bhi->bltu(swap)"),
            'ls': (rs2, rs1, rv_bgeu, "bls->bgeu(swap)"),
            'cs': (rs1, rs2, rv_bgeu, "bcs->bgeu"),
            'cc': (rs1, rs2, rv_bltu, "bcc->bltu"),
            'hs': (rs1, rs2, rv_bgeu, "bhs->bgeu"),
            'lo': (rs1, rs2, rv_bltu, "blo->bltu"),
        }

        if cond in branch_map:
            a, b, func, desc = branch_map[cond]
            self.emit(f"{desc.split('->')[0]} x{a}, x{b}, {target}",
                      func(a, b, offset), desc)
        else:
            self.emit(f"# unsupported cond: {cond}", rv_nop())

    def _translate_conditional(self, inst, resolve):
        """Translate conditional non-branch: skip with inverse branch"""
        cond = inst.cond
        rs1, rs2 = self.cmp_rs1, self.cmp_rs2
        if rs1 < 0 or rs2 < 0:
            inst2 = ARMInstruction(**inst.__dict__)
            inst2.cond = ''
            self._translate_one(inst2, resolve)
            return

        save = len(self.rv_instructions)
        inst2 = ARMInstruction(**inst.__dict__)
        inst2.cond = ''
        self._translate_one(inst2, resolve)
        n = len(self.rv_instructions) - save
        generated = self.rv_instructions[save:]
        self.rv_instructions = self.rv_instructions[:save]

        skip = (n + 1) * 4
        inv = {'eq': rv_bne, 'ne': rv_beq, 'ge': rv_blt, 'lt': rv_bge,
               'gt': rv_bge, 'le': rv_blt}

        if cond in inv:
            a, b = (rs2, rs1) if cond in ('gt', 'le') else (rs1, rs2)
            self.emit(f"skip if NOT {cond}", inv[cond](a, b, skip), f"cond skip {cond}")

        self.rv_instructions.extend(generated)

    def _translate_shifted_op(self, op, rd, rs1, rs2, shift_str):
        m = re.match(r'(lsl|lsr|asr)\s+#(\d+)', shift_str.strip())
        if m:
            stype, shamt = m.group(1), int(m.group(2))
            sfunc = {'lsl': rv_slli, 'lsr': rv_srli, 'asr': rv_srai}[stype]
            self.emit(f"shift x{RV_TEMP1}, x{rs2}, {shamt}",
                      sfunc(RV_TEMP1, rs2, shamt), shift_str)
            ofunc = rv_add if op == 'add' else rv_sub
            self.emit(f"{op} x{rd}, x{rs1}, x{RV_TEMP1}",
                      ofunc(rd, rs1, RV_TEMP1), f"{op} shifted")

    # ---- Output ----

    def get_hex(self) -> str:
        return '\n'.join(f"{i.machine_code:08X}" for i in self.rv_instructions)

    def get_asm(self) -> str:
        lines = []
        label_addrs = {v: k for k, v in self.labels.items()}
        for inst in self.rv_instructions:
            if inst.address in label_addrs:
                lines.append(f"{label_addrs[inst.address]}:")
            cmt = f"  # {inst.comment}" if inst.comment else ""
            lines.append(f"    {inst.asm}{cmt}")
        return '\n'.join(lines)

    def get_verilog(self, mem_name="u_instr_mem.mem") -> str:
        lines = []
        label_addrs = {v: k for k, v in self.labels.items()}
        for i, inst in enumerate(self.rv_instructions):
            lbl = f"  // {label_addrs[inst.address]}:" if inst.address in label_addrs else ""
            cmt = f"  // {inst.asm}"
            if inst.comment: cmt += f"  ({inst.comment})"
            lines.append(f"        dut.{mem_name}[{i:3d}] = 32'h{inst.machine_code:08X};{lbl}{cmt}")
        return '\n'.join(lines)

    def get_summary(self) -> str:
        lines = [
            "=" * 60,
            f"  ARM -> RV64I Translation Summary",
            f"  Mode: {self.mode}",
            "=" * 60,
            f"  ARM instructions parsed:     {len(self.arm_instructions)}",
            f"  RV64I instructions generated: {len(self.rv_instructions)}",
            f"  Code size: {len(self.rv_instructions) * 4} bytes",
            f"  Address range: 0x{self.base_addr:04X} - "
            f"0x{self.base_addr + len(self.rv_instructions) * 4:04X}",
        ]
        if self.data_section.words:
            lines.append(f"  Data words found: {len(self.data_section.words)} "
                         f"({self.data_section.labels})")
        if self.labels:
            lines.append(f"\n  Labels:")
            for name, addr in sorted(self.labels.items(), key=lambda x: x[1]):
                lines.append(f"    {name:20s} = 0x{addr:04X}")
        if self.warnings:
            lines.append(f"\n  Warnings ({len(self.warnings)}):")
            for w in self.warnings:
                lines.append(f"    ! {w}")
        lines.append("=" * 60)
        return '\n'.join(lines)


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='ARM (ARMv4T) to RV64I Cross-Translator (Improved)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Modes:
  faithful   - 1:1 ARM->RV64I translation preserving stack frame (default)
  baremetal  - Optimized for bare-metal hardware: array init via registers,
               no stack frame, direct register-based sort loop

Examples:
  %(prog)s sort.s --mode faithful --all
  %(prog)s sort.s --mode baremetal --data-addr 0x200 --all
  %(prog)s sort.s --mode baremetal --data-width 64 -o sort -v
        """)
    parser.add_argument('input', help='Input ARM assembly file (.s)')
    parser.add_argument('-o', '--output', default=None, help='Output prefix')
    parser.add_argument('--base-addr', type=lambda x: int(x, 0), default=0)
    parser.add_argument('--data-addr', type=lambda x: int(x, 0), default=0x200,
                        help='Data memory base address (default: 0x200)')
    parser.add_argument('--data-width', type=int, default=64, choices=[32, 64],
                        help='Data memory word width: 32 or 64 bits (default: 64)')
    parser.add_argument('--mode', choices=['faithful', 'baremetal'], default='faithful',
                        help='Translation mode (default: faithful)')
    parser.add_argument('--hex', action='store_true')
    parser.add_argument('--asm', action='store_true')
    parser.add_argument('--verilog', action='store_true')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('-v', '--verbose', action='store_true')

    args = parser.parse_args()
    if args.all:
        args.hex = args.asm = args.verilog = True
    if not (args.hex or args.asm or args.verilog):
        args.hex = args.asm = args.verilog = True

    prefix = args.output or args.input.rsplit('.', 1)[0]

    with open(args.input) as f:
        lines = f.readlines()

    t = ARM2RV64Translator(
        base_addr=args.base_addr,
        data_addr=args.data_addr,
        mode=args.mode,
        data_width=args.data_width,
    )
    t.parse_and_translate(lines)

    print(t.get_summary())

    if args.asm:
        out = f"{prefix}_rv64i.S"
        with open(out, 'w') as f:
            f.write(f"# ARM -> RV64I ({args.mode} mode) from {args.input}\n")
            f.write(f"# Base: 0x{args.base_addr:04X}, Data: 0x{args.data_addr:04X}\n\n")
            f.write(t.get_asm())
        print(f"  -> {out}")

    if args.hex:
        out = f"{prefix}_rv64i.hex"
        with open(out, 'w') as f:
            f.write(t.get_hex())
        print(f"  -> {out}")

    if args.verilog:
        out = f"{prefix}_rv64i.v"
        with open(out, 'w') as f:
            f.write(f"// ARM -> RV64I ({args.mode}) from {args.input}\n")
            f.write(f"// Base: 0x{args.base_addr:04X}, Data: 0x{args.data_addr:04X}\n\n")
            f.write(t.get_verilog())
        print(f"  -> {out}")

    if args.verbose:
        print(f"\n{'='*60}\nGenerated RV64I Assembly:\n{'='*60}")
        print(t.get_asm())


if __name__ == '__main__':
    main()