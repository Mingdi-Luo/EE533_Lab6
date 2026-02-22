#!/usr/bin/env python3
"""
ARM-to-RV64I Cross Translator v3 (Generalized Baremetal)
==========================================================

Translates ARMv4T (arm7tdmi) assembly into RV64I machine code.

Two modes:
  faithful  - 1:1 ARM->RV64I, preserving stack frame and all logic
  baremetal - Replaces stack-based array init with direct sd stores,
              but FAITHFULLY TRANSLATES the actual algorithm logic.
              Works for any algorithm (bubble sort, selection sort, etc.)

Changes from v2:
  - baremetal mode now translates the real ARM algorithm instead of
    hardcoding a bubble sort template
  - Identifies and skips: push/pop, bx lr, ldr-from-literal-pool,
    ldmia/stmia array copy, stack frame setup/teardown
  - Translates remaining ARM instructions (the actual algorithm) faithfully
  - Rewrites stack-relative array access [fp, #-56..] to use data memory base
  - Appends done flag + halt for bare-metal hardware
"""

import sys
import re
import argparse
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Optional


# =============================================================================
# RV64I Encoding
# =============================================================================

def encode_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7&0x7F)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((funct3&0x7)<<12)|((rd&0x1F)<<7)|(opcode&0x7F)

def encode_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12&0xFFF)<<20)|((rs1&0x1F)<<15)|((funct3&0x7)<<12)|((rd&0x1F)<<7)|(opcode&0x7F)

def encode_s(imm12, rs2, rs1, funct3, opcode=0x23):
    imm=imm12&0xFFF
    return (((imm>>5)&0x7F)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((funct3&0x7)<<12)|((imm&0x1F)<<7)|(opcode&0x7F)

def encode_b(offset, rs1, rs2, funct3, opcode=0x63):
    return (((offset>>12)&1)<<31)|(((offset>>5)&0x3F)<<25)|((rs2&0x1F)<<20)|((rs1&0x1F)<<15)|((funct3&0x7)<<12)|(((offset>>1)&0xF)<<8)|(((offset>>11)&1)<<7)|(opcode&0x7F)

def encode_u(imm20, rd, opcode):
    return ((imm20&0xFFFFF)<<12)|((rd&0x1F)<<7)|(opcode&0x7F)

def encode_j(offset, rd, opcode=0x6F):
    return (((offset>>20)&1)<<31)|(((offset>>1)&0x3FF)<<21)|(((offset>>11)&1)<<20)|(((offset>>12)&0xFF)<<12)|((rd&0x1F)<<7)|(opcode&0x7F)

def rv_add(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x0,rd,0x33)
def rv_sub(rd,rs1,rs2):    return encode_r(0x20,rs2,rs1,0x0,rd,0x33)
def rv_and(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x7,rd,0x33)
def rv_or(rd,rs1,rs2):     return encode_r(0x00,rs2,rs1,0x6,rd,0x33)
def rv_xor(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x4,rd,0x33)
def rv_sll(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x1,rd,0x33)
def rv_srl(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x5,rd,0x33)
def rv_sra(rd,rs1,rs2):    return encode_r(0x20,rs2,rs1,0x5,rd,0x33)
def rv_slt(rd,rs1,rs2):    return encode_r(0x00,rs2,rs1,0x2,rd,0x33)
def rv_addi(rd,rs1,imm):   return encode_i(imm&0xFFF,rs1,0x0,rd,0x13)
def rv_andi(rd,rs1,imm):   return encode_i(imm&0xFFF,rs1,0x7,rd,0x13)
def rv_ori(rd,rs1,imm):    return encode_i(imm&0xFFF,rs1,0x6,rd,0x13)
def rv_xori(rd,rs1,imm):   return encode_i(imm&0xFFF,rs1,0x4,rd,0x13)
def rv_slti(rd,rs1,imm):   return encode_i(imm&0xFFF,rs1,0x2,rd,0x13)
def rv_slli(rd,rs1,sh):    return encode_i(sh&0x3F,rs1,0x1,rd,0x13)
def rv_srli(rd,rs1,sh):    return encode_i(sh&0x3F,rs1,0x5,rd,0x13)
def rv_srai(rd,rs1,sh):    return encode_i((0x400|(sh&0x3F)),rs1,0x5,rd,0x13)
def rv_lb(rd,rs1,imm):     return encode_i(imm&0xFFF,rs1,0x0,rd,0x03)
def rv_lh(rd,rs1,imm):     return encode_i(imm&0xFFF,rs1,0x1,rd,0x03)
def rv_lw(rd,rs1,imm):     return encode_i(imm&0xFFF,rs1,0x2,rd,0x03)
def rv_ld(rd,rs1,imm):     return encode_i(imm&0xFFF,rs1,0x3,rd,0x03)
def rv_lbu(rd,rs1,imm):    return encode_i(imm&0xFFF,rs1,0x4,rd,0x03)
def rv_lhu(rd,rs1,imm):    return encode_i(imm&0xFFF,rs1,0x5,rd,0x03)
def rv_sb(rs2,rs1,imm):    return encode_s(imm&0xFFF,rs2,rs1,0x0)
def rv_sh(rs2,rs1,imm):    return encode_s(imm&0xFFF,rs2,rs1,0x1)
def rv_sw(rs2,rs1,imm):    return encode_s(imm&0xFFF,rs2,rs1,0x2)
def rv_sd(rs2,rs1,imm):    return encode_s(imm&0xFFF,rs2,rs1,0x3)
def rv_beq(rs1,rs2,off):   return encode_b(off,rs1,rs2,0x0)
def rv_bne(rs1,rs2,off):   return encode_b(off,rs1,rs2,0x1)
def rv_blt(rs1,rs2,off):   return encode_b(off,rs1,rs2,0x4)
def rv_bge(rs1,rs2,off):   return encode_b(off,rs1,rs2,0x5)
def rv_bltu(rs1,rs2,off):  return encode_b(off,rs1,rs2,0x6)
def rv_bgeu(rs1,rs2,off):  return encode_b(off,rs1,rs2,0x7)
def rv_jal(rd,off):        return encode_j(off,rd)
def rv_jalr(rd,rs1,imm):   return encode_i(imm&0xFFF,rs1,0x0,rd,0x67)
def rv_lui(rd,imm20):      return encode_u(imm20,rd,0x37)
def rv_auipc(rd,imm20):    return encode_u(imm20,rd,0x17)
def rv_nop():              return rv_addi(0,0,0)

ARM_TO_RV = {
    'r0':10,'r1':11,'r2':12,'r3':13,'r4':14,'r5':15,'r6':16,'r7':17,
    'r8':18,'r9':19,'r10':20,'r11':21,'r12':22,
    'sp':2,'r13':2,'lr':1,'r14':1,'fp':8,'ip':22,
}
RV_TEMP1 = 30
RV_TEMP2 = 29


# =============================================================================
# Data Section Parser
# =============================================================================

@dataclass
class DataSection:
    labels: Dict[str,int] = field(default_factory=dict)
    words: List[int] = field(default_factory=list)
    label_refs: Dict[str,str] = field(default_factory=dict)

    def add_word(self, label, value):
        if label and label not in self.labels:
            self.labels[label] = len(self.words)
        self.words.append(value)

    def get_words_at(self, label):
        if label not in self.labels: return []
        start = self.labels[label]
        nexts = [v for k,v in self.labels.items() if v > start]
        end = min(nexts) if nexts else len(self.words)
        return self.words[start:end]


def parse_data_sections(lines):
    data = DataSection()
    in_rodata = False
    cur_label = ""
    for line in lines:
        s = line.strip()
        if '@' in s: s = s[:s.index('@')].strip()
        if '.section' in s and '.rodata' in s:
            in_rodata = True; continue
        if s == '.text':
            in_rodata = False; continue
        if not in_rodata:
            if s.endswith(':'): cur_label = s[:-1].strip()
            elif s.startswith('.word') and cur_label:
                val_str = s[5:].strip()
                if val_str.startswith('.'):
                    data.label_refs[cur_label] = val_str
                cur_label = ""
            continue
        if s.endswith(':'): cur_label = s[:-1].strip(); continue
        if s.startswith('.word'):
            try:
                val = int(s[5:].strip(), 0)
                data.add_word(cur_label, val)
                cur_label = ""
            except: pass
    return data


# =============================================================================
# ARM Parser
# =============================================================================

@dataclass
class ARMInstruction:
    label:str=""; opcode:str=""; cond:str=""; s_flag:bool=False
    operands:list=field(default_factory=list); comment:str=""
    raw:str=""; line_num:int=0; is_directive:bool=False; is_label:bool=False

def parse_arm_register(s):
    s=s.strip().lower()
    aliases={'a1':'r0','a2':'r1','a3':'r2','a4':'r3','v1':'r4','v2':'r5','v3':'r6','v4':'r7','v5':'r8','sb':'r9','sl':'r10'}
    return aliases.get(s,s)

def parse_immediate(s):
    s=s.strip().lstrip('#')
    if s.startswith(('0x','0X')): return int(s,16)
    if s.startswith(('-0x','-0X')): return -int(s[1:],16)
    return int(s)

def parse_register_list(s):
    s=s.strip('{}').strip(); regs=[]
    for p in s.split(','):
        p=p.strip()
        if '-' in p:
            a,b=p.split('-')
            for i in range(int(re.search(r'\d+',a).group()),int(re.search(r'\d+',b).group())+1):
                regs.append(f'r{i}')
        else: regs.append(parse_arm_register(p))
    return regs

def parse_memory_operand(s):
    s=s.strip()
    m=re.match(r'\[(\w+),\s*#(-?\w+)\](!)?',s)
    if m: return parse_arm_register(m.group(1)),parse_immediate(m.group(2)),m.group(3)=='!'
    m=re.match(r'\[(\w+)\](!)?',s)
    if m: return parse_arm_register(m.group(1)),0,m.group(2)=='!'
    return parse_arm_register(s),0,False

def parse_arm_line(line, line_num):
    inst=ARMInstruction(raw=line,line_num=line_num)
    for m in ['@','//']:
        if m in line: inst.comment=line[line.index(m):]; line=line[:line.index(m)]
    line=line.strip()
    if not line: return None
    if line.startswith('.'):
        if line.endswith(':'): inst.label=line[:-1].strip(); inst.is_label=True; return inst
        inst.opcode=line.split()[0]; inst.operands=line.split(None,1)[1:] if len(line.split())>1 else []; inst.is_directive=True; return inst
    m=re.match(r'^(\w+):\s*(.*)',line)
    if m:
        inst.label=m.group(1); line=m.group(2).strip()
        if not line: inst.is_label=True; return inst
    if line.endswith(':'): inst.label=line[:-1].strip(); inst.is_label=True; return inst
    parts=line.split(None,1)
    if not parts: return None
    mnemonic=parts[0].lower(); operand_str=parts[1] if len(parts)>1 else ""
    base_opcodes=['add','sub','rsb','adc','sbc','rsc','and','orr','eor','bic','mvn','mov','cmp','cmn','tst','teq','ldr','str','ldm','stm','lsl','lsr','asr','mul','mla','push','pop','b','bl','bx','blx','nop','swi','svc']
    cond_codes=['eq','ne','cs','hs','cc','lo','mi','pl','vs','vc','hi','ls','ge','lt','gt','le','al']
    inst.cond=''; inst.s_flag=False; matched=False
    for base in sorted(base_opcodes,key=len,reverse=True):
        if mnemonic.startswith(base):
            rest=mnemonic[len(base):]; inst.opcode=base
            if base in ('ldr','str') and rest and rest[0] in ('b','h','s'):
                for sfx in ['sb','sh','b','h']:
                    if rest.startswith(sfx): inst.opcode=base+sfx; rest=rest[len(sfx):]; break
            if base in ('ldm','stm'):
                for sfx in ['ia','ib','da','db']:
                    if rest.startswith(sfx): inst.opcode=base+sfx; rest=rest[len(sfx):]; break
            for cc in cond_codes:
                if rest.startswith(cc): inst.cond=cc; rest=rest[len(cc):]; break
            if rest=='s': inst.s_flag=True; rest=''
            if rest=='': matched=True; break
    if not matched: inst.opcode=mnemonic
    if operand_str:
        if '{' in operand_str:
            pre=operand_str[:operand_str.index('{')].strip().rstrip(',')
            bc=operand_str[operand_str.index('{')+1:operand_str.index('}')]
            post=operand_str[operand_str.index('}')+1:].strip()
            if pre: inst.operands.append(pre.strip())
            inst.operands.append('{'+bc+'}')
            if '!' in post: inst.operands.append('!')
        else:
            ops=[]; depth=0; cur=''
            for ch in operand_str:
                if ch=='[': depth+=1; cur+=ch
                elif ch==']': depth-=1; cur+=ch
                elif ch==',' and depth==0: ops.append(cur.strip()); cur=''
                else: cur+=ch
            if cur.strip(): ops.append(cur.strip())
            inst.operands=ops
    return inst


# =============================================================================
# Output
# =============================================================================

@dataclass
class RV64Instruction:
    asm:str; machine_code:int; comment:str=""; address:int=0


# =============================================================================
# Translator
# =============================================================================

class ARM2RV64Translator:

    def __init__(self, base_addr=0, data_addr=0x200, mode='faithful', data_width=64):
        self.labels: Dict[str,int] = {}
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

    def arm_reg(self, name):
        name=parse_arm_register(name)
        if name in ARM_TO_RV: return ARM_TO_RV[name]
        raise ValueError(f"Unknown ARM register: '{name}'")

    def emit(self, asm, machine_code, comment=""):
        addr=self.base_addr+len(self.rv_instructions)*4
        self.rv_instructions.append(RV64Instruction(asm=asm,machine_code=machine_code&0xFFFFFFFF,comment=comment,address=addr))

    def emit_li(self, rd, imm):
        if -2048<=imm<=2047:
            self.emit(f"addi x{rd}, x0, {imm}",rv_addi(rd,0,imm),f"li x{rd}, {imm}")
        else:
            upper=(imm+0x800)>>12; lower=imm-(upper<<12)
            self.emit(f"lui x{rd}, {upper&0xFFFFF}",rv_lui(rd,upper&0xFFFFF),f"li x{rd}, {imm} (upper)")
            if lower!=0: self.emit(f"addi x{rd}, x{rd}, {lower}",rv_addi(rd,rd,lower&0xFFF),f"li x{rd}, {imm} (lower)")

    def _get_branch_offset(self, target):
        cur=self.base_addr+len(self.rv_instructions)*4
        return self.labels.get(target,cur)-cur

    # ================================================================
    # Main entry
    # ================================================================

    def parse_and_translate(self, lines):
        self.data_section = parse_data_sections(lines)
        for i,line in enumerate(lines):
            inst=parse_arm_line(line,i+1)
            if inst: self.arm_instructions.append(inst)

        if self.mode == 'baremetal':
            self._generate_baremetal()
        else:
            self._translate_faithful()

    # ================================================================
    # Baremetal mode (FIXED: generalized)
    #
    # Strategy:
    #   Phase 1: Generate data init from .rodata (addi+sd)
    #   Phase 2: Translate the ARM sorting logic faithfully,
    #            but SKIP the following ARM-specific boilerplate:
    #            - push/pop (stack frame)
    #            - add fp, sp, #4 / sub sp, sp, #56 (frame setup)
    #            - ldr r3, .L8 (literal pool load for array address)
    #            - sub ip, fp, #56 / mov lr, r3 (array copy setup)
    #            - ldmia/stmia (array copy from .rodata to stack)
    #            - sub sp, fp, #4 (frame teardown)
    #            - bx lr (return)
    #   Phase 3: Append done flag + halt
    # ================================================================

    def _generate_baremetal(self):
        # --- Phase 1: Data init ---
        array_data = []
        for label,ref in self.data_section.label_refs.items():
            w = self.data_section.get_words_at(ref)
            if w: array_data = w; break
        if not array_data:
            array_data = self.data_section.get_words_at('.LC0')
        if not array_data:
            self.warnings.append("No array data found in .rodata")

        # The translated algorithm uses ARM's 32-bit lw/sw with lsl #2 (4-byte stride)
        # through fp-relative addressing. Phase 1 data init must match: use sw, 4-byte stride.
        # This is because we're faithfully translating the ARM algorithm which operates
        # on 32-bit int arrays, not our pipeline's 64-bit data width.
        arm_word_size = 4  # ARM int = 32-bit = 4 bytes

        # Emit: addi x19, x0, data_addr  (array base, also used for sd-based init)
        self.emit(f"addi x19, x0, {self.data_addr}",
                  rv_addi(19,0,self.data_addr), f"base = 0x{self.data_addr:X}")

        for i,val in enumerate(array_data):
            vs = val if -0x80000000<=val<=0x7FFFFFFF else val-0x100000000
            self.emit_li(11, vs)
            off = i * arm_word_size
            # Use sw (32-bit store) to match the ARM algorithm's 32-bit array access
            self.emit(f"sw x11, {off}(x19)",
                      encode_s(off&0xFFF, 11, 19, 0x2),  # funct3=0x2 for sw
                      f"arr[{i}] = {vs}")

        # --- Phase 2: Translate ARM algorithm, skipping boilerplate ---
        # Identify which ARM instructions to skip
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
                    arm_labels[inst.label] = len(arm_code)-1

        # Filter: determine which ARM instructions are "boilerplate" to skip
        # Also extract stack frame info for sp/fp initialization
        skip_indices = set()
        in_array_copy = False
        stack_frame_size = 0   # from "sub sp, sp, #N"
        fp_offset = 0          # from "add fp, sp, #M"
        array_offset = 0       # from "sub ip, fp, #K" — array starts at fp-K

        for idx, inst in enumerate(arm_code):
            op = inst.opcode
            ops = inst.operands
            raw_lower = inst.raw.strip().lower()

            # Skip: push/pop
            if op in ('push','pop'):
                skip_indices.add(idx); continue

            # Skip: add fp, sp, #4  (and capture fp_offset)
            if op=='add' and len(ops)>=3:
                try:
                    if (parse_arm_register(ops[0])=='fp' and
                        parse_arm_register(ops[1])=='sp'):
                        fp_offset = parse_immediate(ops[2])
                        skip_indices.add(idx); continue
                except: pass

            # Skip: sub sp, sp, #56 (stack allocation, capture frame size)
            if op=='sub' and len(ops)>=3:
                try:
                    if (parse_arm_register(ops[0])=='sp' and
                        parse_arm_register(ops[1])=='sp'):
                        stack_frame_size = parse_immediate(ops[2])
                        skip_indices.add(idx); continue
                    # sub sp, fp, #4 (teardown)
                    if (parse_arm_register(ops[0])=='sp' and
                        parse_arm_register(ops[1])=='fp'):
                        skip_indices.add(idx); continue
                    # sub ip, fp, #K (array copy dest setup — K is array offset)
                    if (parse_arm_register(ops[0])=='ip' and
                        parse_arm_register(ops[1])=='fp'):
                        array_offset = parse_immediate(ops[2])
                        skip_indices.add(idx); in_array_copy=True; continue
                except: pass

            # Skip: ldr r3, .L8 (literal pool)
            if op=='ldr' and len(ops)>=2 and ops[1].strip().startswith('.'):
                skip_indices.add(idx); continue

            # Skip: mov lr, r3 (when it's part of array copy setup)
            if op=='mov' and in_array_copy:
                try:
                    if parse_arm_register(ops[0])=='lr':
                        skip_indices.add(idx); continue
                except: pass

            # Skip: ldmia/stmia/ldm/stm (array copy)
            if op in ('ldmia','stmia','ldm','stm'):
                skip_indices.add(idx); continue

            # Skip: bx lr (return)
            if op=='bx':
                try:
                    if parse_arm_register(ops[0])=='lr':
                        skip_indices.add(idx); continue
                except: pass

            # Once we hit a non-skippable instruction, array copy phase is over
            if in_array_copy and idx not in skip_indices:
                in_array_copy = False

        # --- Emit sp/fp initialization ---
        # GCC's stack frame layout (ARM, growing downward):
        #   push {fp, lr}         sp -= 8
        #   add fp, sp, #4        fp = sp + 4
        #   sub sp, sp, #N        sp -= N (allocate locals)
        #
        # So fp points to (original_sp - 8 + 4) = (original_sp - 4)
        # Local array lives at [fp - (N+4) .. fp - 4-array_offset]
        # In ARM's view: arr[0] is at [fp, #-(N-push_size+4)]
        #
        # For baremetal: we place the array at data_addr, and set fp so that
        # [fp, #-(frame_bottom_offset)] == data_addr.
        #
        # The array is copied to [ip..ip+array_size] where ip = fp - frame_size
        # which means arr[0] = [fp, #-frame_size]
        #
        # For GCC: push saves 8 bytes, then fp = sp+4. Locals start at fp-frame_size.
        # We need: fp - frame_size = data_addr
        # Therefore: fp = data_addr + frame_size

        if stack_frame_size > 0:
            # fp calculation:
            # GCC does: sub ip, fp, #K → array starts at fp-K
            # We stored array at data_addr
            # So: fp - K = data_addr → fp = data_addr + K
            # If no "sub ip, fp, #K" was found, fall back to frame_size
            arr_off = array_offset if array_offset > 0 else stack_frame_size
            fp_val = self.data_addr + arr_off
            sp_val = fp_val - fp_offset

            # Initialize fp (x8) = fp_val
            self.emit_li(8, fp_val)
            # Initialize sp (x2) = fp - fp_offset
            neg_offset = -fp_offset
            if neg_offset == 0:
                self.emit(f"addi x2, x8, 0", rv_addi(2, 8, 0), f"sp = fp")
            else:
                self.emit(f"addi x2, x8, {neg_offset}",
                          rv_addi(2, 8, neg_offset & 0xFFF),
                          f"sp = fp - {fp_offset}")

            self.warnings.append(
                f"Baremetal: fp=0x{fp_val:X} (data=0x{self.data_addr:X} + "
                f"arr_off={arr_off}), sp=0x{sp_val:X}")

        # Now do a multi-pass translate of the non-skipped instructions
        # Build filtered instruction list and update label mapping
        filtered_code = []
        filtered_labels = {}  # label -> index in filtered_code

        for label, arm_idx in arm_labels.items():
            # Find the first non-skipped instruction at or after arm_idx
            target = arm_idx
            while target < len(arm_code) and target in skip_indices:
                target += 1
            filtered_labels[label] = target  # temporary, will remap

        # Create mapping: arm_idx -> filtered_idx
        arm_to_filtered = {}
        for idx, inst in enumerate(arm_code):
            if idx not in skip_indices:
                arm_to_filtered[idx] = len(filtered_code)
                filtered_code.append(inst)

        # Remap labels to filtered indices
        for label in list(filtered_labels.keys()):
            arm_idx = filtered_labels[label]
            if arm_idx in arm_to_filtered:
                filtered_labels[label] = arm_to_filtered[arm_idx]
            else:
                # Label points past all code -> end
                filtered_labels[label] = len(filtered_code)

        # Multi-pass translate filtered code
        # Save Phase 1 instructions (data init) - these don't change
        phase1 = self.rv_instructions[:]
        phase1_count = len(phase1)

        for pass_num in range(3):
            # Reset: keep only Phase 1
            self.rv_instructions = list(phase1)
            self.cmp_rs1 = -1
            self.cmp_rs2 = -1
            arm_to_rv = []

            for fi, inst in enumerate(filtered_code):
                arm_to_rv.append(len(self.rv_instructions))
                self._translate_one(inst, resolve=(pass_num>0))

            # Update labels
            for label, fi in filtered_labels.items():
                if fi < len(arm_to_rv):
                    self.labels[label] = self.base_addr + arm_to_rv[fi]*4
                else:
                    self.labels[label] = self.base_addr + len(self.rv_instructions)*4

        # --- Phase 3: Append done flag + halt ---
        # Check if the translated code already ends with a halt-like pattern
        # (e.g., if there was a label 'end' or similar)
        self.labels['_done'] = self.base_addr + len(self.rv_instructions)*4
        self.emit("addi x31, x0, 1", rv_addi(31,0,1), "done flag")
        self.labels['_halt'] = self.base_addr + len(self.rv_instructions)*4
        self.emit("jal x0, 0", rv_jal(0,0), "halt (infinite loop)")

    # ================================================================
    # Faithful mode (unchanged)
    # ================================================================

    def _translate_faithful(self):
        arm_labels={}; arm_code=[]
        for inst in self.arm_instructions:
            if inst.is_label: arm_labels[inst.label]=len(arm_code)
            elif inst.is_directive: continue
            else:
                arm_code.append(inst)
                if inst.label: arm_labels[inst.label]=len(arm_code)-1

        for pass_num in range(3):
            self.rv_instructions.clear(); arm_to_rv=[]
            for idx,inst in enumerate(arm_code):
                arm_to_rv.append(len(self.rv_instructions))
                self._translate_one(inst, resolve=(pass_num>0))
            for label,arm_idx in arm_labels.items():
                if arm_idx<len(arm_to_rv):
                    self.labels[label]=self.base_addr+arm_to_rv[arm_idx]*4
                else:
                    self.labels[label]=self.base_addr+len(self.rv_instructions)*4

    # ================================================================
    # Translate single ARM instruction
    # ================================================================

    def _translate_one(self, inst, resolve=False):
        op=inst.opcode; ops=inst.operands; cond=inst.cond
        try:
            if cond and op not in ('b','bl','bx','blx') and cond!='al':
                self._translate_conditional(inst, resolve); return

            if op=='nop':
                self.emit("nop",rv_nop(),"nop")

            elif op=='mov':
                rd=self.arm_reg(ops[0])
                if ops[1].startswith('#'):
                    self.emit_li(rd,parse_immediate(ops[1]))
                else:
                    rs=self.arm_reg(ops[1])
                    self.emit(f"addi x{rd}, x{rs}, 0",rv_addi(rd,rs,0),f"mov {ops[0]}, {ops[1]}")

            elif op=='mvn':
                rd=self.arm_reg(ops[0])
                if ops[1].startswith('#'): self.emit_li(rd,~parse_immediate(ops[1]))
                else:
                    rs=self.arm_reg(ops[1])
                    self.emit(f"xori x{rd}, x{rs}, -1",rv_xori(rd,rs,-1),"mvn")

            elif op=='add':
                rd=self.arm_reg(ops[0]); rs1=self.arm_reg(ops[1])
                if len(ops)>2 and ops[2].startswith('#'):
                    imm=parse_immediate(ops[2])
                    if -2048<=imm<=2047:
                        self.emit(f"addi x{rd}, x{rs1}, {imm}",rv_addi(rd,rs1,imm),f"add {ops[0]}, {ops[1]}, {ops[2]}")
                    else:
                        self.emit_li(RV_TEMP1,imm)
                        self.emit(f"add x{rd}, x{rs1}, x{RV_TEMP1}",rv_add(rd,rs1,RV_TEMP1),"add large imm")
                elif len(ops)>2:
                    if len(ops)>3:
                        rs2=self.arm_reg(ops[2]); self._translate_shifted_op('add',rd,rs1,rs2,ops[3])
                    else:
                        rs2=self.arm_reg(ops[2])
                        self.emit(f"add x{rd}, x{rs1}, x{rs2}",rv_add(rd,rs1,rs2),f"add {ops[0]}, {ops[1]}, {ops[2]}")

            elif op=='sub':
                rd=self.arm_reg(ops[0]); rs1=self.arm_reg(ops[1])
                if len(ops)>2 and ops[2].startswith('#'):
                    imm=parse_immediate(ops[2]); neg=-imm
                    if -2048<=neg<=2047:
                        self.emit(f"addi x{rd}, x{rs1}, {neg}",rv_addi(rd,rs1,neg),f"sub {ops[0]}, {ops[1]}, #{imm}")
                    else:
                        self.emit_li(RV_TEMP1,imm)
                        self.emit(f"sub x{rd}, x{rs1}, x{RV_TEMP1}",rv_sub(rd,rs1,RV_TEMP1),"sub large imm")
                elif len(ops)>2:
                    rs2=self.arm_reg(ops[2])
                    self.emit(f"sub x{rd}, x{rs1}, x{rs2}",rv_sub(rd,rs1,rs2),f"sub {ops[0]}, {ops[1]}, {ops[2]}")

            elif op=='rsb':
                rd=self.arm_reg(ops[0]); rs1=self.arm_reg(ops[1])
                if len(ops)>2 and ops[2].startswith('#'):
                    imm=parse_immediate(ops[2])
                    if imm==0: self.emit(f"sub x{rd}, x0, x{rs1}",rv_sub(rd,0,rs1),"negate")
                    else: self.emit_li(RV_TEMP1,imm); self.emit(f"sub x{rd}, x{RV_TEMP1}, x{rs1}",rv_sub(rd,RV_TEMP1,rs1),"rsb")

            elif op in ('and','orr','eor','bic'):
                rd=self.arm_reg(ops[0]); rs1=self.arm_reg(ops[1])
                if len(ops)>2 and ops[2].startswith('#'):
                    imm=parse_immediate(ops[2])
                    if op=='bic': imm=~imm
                    self.emit_li(RV_TEMP1,imm)
                    func={'and':rv_and,'orr':rv_or,'eor':rv_xor,'bic':rv_and}[op]
                    name={'and':'and','orr':'or','eor':'xor','bic':'and'}[op]
                    self.emit(f"{name} x{rd}, x{rs1}, x{RV_TEMP1}",func(rd,rs1,RV_TEMP1),f"{op} imm")
                elif len(ops)>2:
                    rs2=self.arm_reg(ops[2])
                    if op=='bic':
                        self.emit(f"xori x{RV_TEMP1}, x{rs2}, -1",rv_xori(RV_TEMP1,rs2,-1),"~rs2")
                        self.emit(f"and x{rd}, x{rs1}, x{RV_TEMP1}",rv_and(rd,rs1,RV_TEMP1),"bic")
                    else:
                        func={'and':rv_and,'orr':rv_or,'eor':rv_xor}[op]
                        self.emit(f"{op} x{rd}, x{rs1}, x{rs2}",func(rd,rs1,rs2),op)

            elif op in ('lsl','lsr','asr'):
                rd=self.arm_reg(ops[0]); rs1=self.arm_reg(ops[1])
                func_i={'lsl':rv_slli,'lsr':rv_srli,'asr':rv_srai}[op]
                func_r={'lsl':rv_sll,'lsr':rv_srl,'asr':rv_sra}[op]
                name_i={'lsl':'slli','lsr':'srli','asr':'srai'}[op]
                name_r={'lsl':'sll','lsr':'srl','asr':'sra'}[op]
                if len(ops)>2 and ops[2].startswith('#'):
                    sh=parse_immediate(ops[2])
                    self.emit(f"{name_i} x{rd}, x{rs1}, {sh}",func_i(rd,rs1,sh),op)
                elif len(ops)>2:
                    rs2=self.arm_reg(ops[2])
                    self.emit(f"{name_r} x{rd}, x{rs1}, x{rs2}",func_r(rd,rs1,rs2),op)

            elif op=='cmp':
                rs1=self.arm_reg(ops[0])
                if ops[1].startswith('#'):
                    imm=parse_immediate(ops[1])
                    self.emit_li(RV_TEMP1,imm)
                    self.cmp_rs1=rs1; self.cmp_rs2=RV_TEMP1
                else:
                    rs2=self.arm_reg(ops[1])
                    self.cmp_rs1=rs1; self.cmp_rs2=rs2

            elif op in ('ldr','ldrb','ldrh','ldrsb','ldrsh'):
                rd=self.arm_reg(ops[0])
                if len(ops)>=2 and ops[1].strip().startswith('.'):
                    lbl=ops[1].strip()
                    if lbl in self.data_section.label_refs:
                        self.emit_li(rd,self.data_addr)
                    else:
                        self.emit_li(rd,0)
                        self.warnings.append(f"Line {inst.line_num}: literal pool ref '{lbl}' unresolved")
                    return
                base,off,wb=parse_memory_operand(ops[1]); rs1=self.arm_reg(base)
                m={'ldr':('lw',rv_lw),'ldrb':('lbu',rv_lbu),'ldrh':('lhu',rv_lhu),'ldrsb':('lb',rv_lb),'ldrsh':('lh',rv_lh)}
                n,f=m[op]
                self.emit(f"{n} x{rd}, {off}(x{rs1})",f(rd,rs1,off),f"{op} {ops[0]}, {ops[1]}")
                if wb: self.emit(f"addi x{rs1}, x{rs1}, {off}",rv_addi(rs1,rs1,off),"writeback")

            elif op in ('str','strb','strh'):
                rd=self.arm_reg(ops[0]); base,off,wb=parse_memory_operand(ops[1]); rs1=self.arm_reg(base)
                m={'str':('sw',rv_sw),'strb':('sb',rv_sb),'strh':('sh',rv_sh)}
                n,f=m[op]
                self.emit(f"{n} x{rd}, {off}(x{rs1})",f(rd,rs1,off),f"{op} {ops[0]}, {ops[1]}")
                if wb: self.emit(f"addi x{rs1}, x{rs1}, {off}",rv_addi(rs1,rs1,off),"writeback")

            elif op in ('ldmia','ldm','stmia','stm'):
                bs=ops[0].rstrip('!'); wb='!' in inst.raw or (len(ops)>2 and '!' in ops[-1])
                br=self.arm_reg(bs); rl=parse_register_list(ops[1]); off=0
                for rn in rl:
                    rv=self.arm_reg(rn)
                    if op.startswith('ld'): self.emit(f"lw x{rv}, {off}(x{br})",rv_lw(rv,br,off),f"{op} {rn}")
                    else: self.emit(f"sw x{rv}, {off}(x{br})",rv_sw(rv,br,off),f"{op} {rn}")
                    off+=4
                if wb: self.emit(f"addi x{br}, x{br}, {off}",rv_addi(br,br,off),f"{op} wb")

            elif op=='push':
                rl=parse_register_list(ops[0]); n=len(rl)
                self.emit(f"addi x2, x2, {-4*n}",rv_addi(2,2,-4*n),"push sp-=")
                for i,rn in enumerate(rl):
                    rv=self.arm_reg(rn); self.emit(f"sw x{rv}, {i*4}(x2)",rv_sw(rv,2,i*4),f"push {rn}")

            elif op=='pop':
                rl=parse_register_list(ops[0]); n=len(rl)
                for i,rn in enumerate(rl):
                    rv=self.arm_reg(rn); self.emit(f"lw x{rv}, {i*4}(x2)",rv_lw(rv,2,i*4),f"pop {rn}")
                self.emit(f"addi x2, x2, {4*n}",rv_addi(2,2,4*n),"pop sp+=")

            elif op=='b':
                target=ops[0] if ops else ""
                if cond: self._translate_branch(cond,target,resolve)
                else:
                    off=self._get_branch_offset(target) if resolve else 0
                    self.emit(f"jal x0, {target}",rv_jal(0,off),f"b {target}")

            elif op=='bl':
                target=ops[0] if ops else ""
                off=self._get_branch_offset(target) if resolve else 0
                self.emit(f"jal x1, {target}",rv_jal(1,off),f"bl {target}")

            elif op=='bx':
                rs=self.arm_reg(ops[0])
                self.emit(f"jalr x0, x{rs}, 0",rv_jalr(0,rs,0),f"bx {ops[0]}")

            elif op=='blx':
                rs=self.arm_reg(ops[0])
                self.emit(f"jalr x1, x{rs}, 0",rv_jalr(1,rs,0),f"blx {ops[0]}")

            elif op=='mul':
                self.warnings.append(f"Line {inst.line_num}: MUL needs M ext")
                self.emit("# MUL (needs M ext)",rv_nop(),"MUL")

            else:
                self.emit(f"# UNKNOWN: {inst.raw.strip()}",rv_nop(),f"unhandled: {op}")

        except Exception as e:
            self.emit(f"# ERROR: {inst.raw.strip()}",rv_nop(),f"ERROR: {e}")
            self.warnings.append(f"Line {inst.line_num}: {e}")

    def _translate_branch(self, cond, target, resolve):
        rs1,rs2=self.cmp_rs1,self.cmp_rs2
        if rs1<0 or rs2<0:
            self.warnings.append(f"Branch {cond} without CMP"); self.emit("# no CMP",rv_nop()); return
        off=self._get_branch_offset(target) if resolve else 0
        bm={
            'eq':(rs1,rs2,rv_beq,"beq"),'ne':(rs1,rs2,rv_bne,"bne"),
            'ge':(rs1,rs2,rv_bge,"bge"),'lt':(rs1,rs2,rv_blt,"blt"),
            'gt':(rs2,rs1,rv_blt,"bgt->blt"),'le':(rs2,rs1,rv_bge,"ble->bge"),
            'hi':(rs2,rs1,rv_bltu,"bhi->bltu"),'ls':(rs2,rs1,rv_bgeu,"bls->bgeu"),
            'cs':(rs1,rs2,rv_bgeu,"bcs->bgeu"),'cc':(rs1,rs2,rv_bltu,"bcc->bltu"),
            'hs':(rs1,rs2,rv_bgeu,"bhs->bgeu"),'lo':(rs1,rs2,rv_bltu,"blo->bltu"),
        }
        if cond in bm:
            a,b,fn,desc=bm[cond]
            self.emit(f"{desc.split('->')[0]} x{a}, x{b}, {target}",fn(a,b,off),desc)
        else: self.emit(f"# unsupported cond: {cond}",rv_nop())

    def _translate_conditional(self, inst, resolve):
        cond=inst.cond; rs1,rs2=self.cmp_rs1,self.cmp_rs2
        if rs1<0 or rs2<0:
            i2=ARMInstruction(**inst.__dict__); i2.cond=''; self._translate_one(i2,resolve); return
        save=len(self.rv_instructions)
        i2=ARMInstruction(**inst.__dict__); i2.cond=''; self._translate_one(i2,resolve)
        n=len(self.rv_instructions)-save; gen=self.rv_instructions[save:]
        self.rv_instructions=self.rv_instructions[:save]
        skip=(n+1)*4
        inv={'eq':rv_bne,'ne':rv_beq,'ge':rv_blt,'lt':rv_bge,'gt':rv_bge,'le':rv_blt}
        if cond in inv:
            a,b=(rs2,rs1) if cond in ('gt','le') else (rs1,rs2)
            self.emit(f"skip if NOT {cond}",inv[cond](a,b,skip),f"cond skip {cond}")
        self.rv_instructions.extend(gen)

    def _translate_shifted_op(self, op, rd, rs1, rs2, shift_str):
        m=re.match(r'(lsl|lsr|asr)\s+#(\d+)',shift_str.strip())
        if m:
            st,sh=m.group(1),int(m.group(2))
            sf={'lsl':rv_slli,'lsr':rv_srli,'asr':rv_srai}[st]
            self.emit(f"shift x{RV_TEMP1}, x{rs2}, {sh}",sf(RV_TEMP1,rs2,sh),shift_str)
            of=rv_add if op=='add' else rv_sub
            self.emit(f"{op} x{rd}, x{rs1}, x{RV_TEMP1}",of(rd,rs1,RV_TEMP1),f"{op} shifted")

    # ---- Output ----

    def get_hex(self):
        return '\n'.join(f"{i.machine_code:08X}" for i in self.rv_instructions)

    def get_asm(self):
        lines=[]; la={v:k for k,v in self.labels.items()}
        for inst in self.rv_instructions:
            if inst.address in la: lines.append(f"{la[inst.address]}:")
            c=f"  # {inst.comment}" if inst.comment else ""
            lines.append(f"    {inst.asm}{c}")
        return '\n'.join(lines)

    def get_verilog(self, mem="u_instr_mem.mem"):
        lines=[]; la={v:k for k,v in self.labels.items()}
        for i,inst in enumerate(self.rv_instructions):
            lb=f"  // {la[inst.address]}:" if inst.address in la else ""
            cm=f"  // {inst.asm}"
            if inst.comment: cm+=f"  ({inst.comment})"
            lines.append(f"        dut.{mem}[{i:3d}] = 32'h{inst.machine_code:08X};{lb}{cm}")
        return '\n'.join(lines)

    def get_summary(self):
        lines=[
            "="*60,
            f"  ARM -> RV64I Translation (mode: {self.mode})",
            "="*60,
            f"  ARM instructions parsed:     {len(self.arm_instructions)}",
            f"  RV64I instructions generated: {len(self.rv_instructions)}",
            f"  Code size: {len(self.rv_instructions)*4} bytes",
            f"  Address: 0x{self.base_addr:04X} - 0x{self.base_addr+len(self.rv_instructions)*4:04X}",
        ]
        if self.data_section.words:
            lines.append(f"  Data: {len(self.data_section.words)} words from .rodata")
        if self.labels:
            lines.append(f"\n  Labels:")
            for n,a in sorted(self.labels.items(),key=lambda x:x[1]):
                lines.append(f"    {n:20s} = 0x{a:04X}")
        if self.warnings:
            lines.append(f"\n  Warnings ({len(self.warnings)}):")
            for w in self.warnings: lines.append(f"    ! {w}")
        lines.append("="*60)
        return '\n'.join(lines)


# =============================================================================
# Main
# =============================================================================

def main():
    p=argparse.ArgumentParser(description='ARM->RV64I Translator v3',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Modes:
  faithful   1:1 translation preserving stack frame
  baremetal  Data init from .rodata + faithful algorithm translation
             (no stack frame, with done flag + halt for bare-metal HW)

Examples:
  %(prog)s sort.s --mode baremetal --data-addr 0x200 --all
  %(prog)s sort.s --mode faithful --all -v
        """)
    p.add_argument('input')
    p.add_argument('-o','--output',default=None)
    p.add_argument('--base-addr',type=lambda x:int(x,0),default=0)
    p.add_argument('--data-addr',type=lambda x:int(x,0),default=0x200)
    p.add_argument('--data-width',type=int,default=64,choices=[32,64])
    p.add_argument('--mode',choices=['faithful','baremetal'],default='faithful')
    p.add_argument('--hex',action='store_true')
    p.add_argument('--asm',action='store_true')
    p.add_argument('--verilog',action='store_true')
    p.add_argument('--all',action='store_true')
    p.add_argument('-v','--verbose',action='store_true')
    args=p.parse_args()

    if args.all: args.hex=args.asm=args.verilog=True
    if not(args.hex or args.asm or args.verilog): args.hex=args.asm=args.verilog=True
    prefix=args.output or args.input.rsplit('.',1)[0]

    with open(args.input) as f: lines=f.readlines()

    t=ARM2RV64Translator(base_addr=args.base_addr,data_addr=args.data_addr,
                          mode=args.mode,data_width=args.data_width)
    t.parse_and_translate(lines)
    print(t.get_summary())

    if args.asm:
        out=f"{prefix}_rv64i.S"
        with open(out,'w') as f:
            f.write(f"# ARM->RV64I ({args.mode}) from {args.input}\n")
            f.write(f"# Base: 0x{args.base_addr:04X}, Data: 0x{args.data_addr:04X}, Width: {args.data_width}\n\n")
            f.write(t.get_asm())
        print(f"  -> {out}")

    if args.hex:
        out=f"{prefix}_rv64i.hex"
        with open(out,'w') as f: f.write(t.get_hex())
        print(f"  -> {out}")

    if args.verilog:
        out=f"{prefix}_rv64i.v"
        with open(out,'w') as f:
            f.write(f"// ARM->RV64I ({args.mode}) from {args.input}\n")
            f.write(f"// Base: 0x{args.base_addr:04X}, Data: 0x{args.data_addr:04X}, Width: {args.data_width}\n\n")
            f.write(t.get_verilog())
        print(f"  -> {out}")

    if args.verbose:
        print(f"\n{'='*60}\nGenerated RV64I Assembly:\n{'='*60}")
        print(t.get_asm())

if __name__=='__main__':
    main()