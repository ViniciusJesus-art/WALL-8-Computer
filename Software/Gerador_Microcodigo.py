# gerar_microcode.py

ROM_SIZE = 65536

# Valores neutros
ROM1_IDLE = 0xFE
ROM2_IDLE = 0x1F
ROM3_IDLE = 0xF8
ROM4_IDLE = 0xDF
ROM5_IDLE = 0x6F

rom1 = bytearray([ROM1_IDLE] * ROM_SIZE)
rom2 = bytearray([ROM2_IDLE] * ROM_SIZE)
rom3 = bytearray([ROM3_IDLE] * ROM_SIZE)
rom4 = bytearray([ROM4_IDLE] * ROM_SIZE)
rom5 = bytearray([ROM5_IDLE] * ROM_SIZE)

# =========================
# Opcodes
# =========================

# Sistema
NOP = 0x00
HLT = 0x01


# =========================
# Mov / PTR / indireto
# =========================

MOV_A_B = 0x16  # MOV A, B        A = B
MOV_B_A = 0x17  # MOV B, A        B = A

LDA_PTR = 0x18  # LDA [PTR]       A = MEM[PTR]
LDB_PTR = 0x19  # LDB [PTR]       B = MEM[PTR]

STA_PTR = 0x1A  # STA [PTR]       MEM[PTR] = A
STB_PTR = 0x1B  # STB [PTR]       MEM[PTR] = B

LDPTR_ABS = 0x20  # LDPTR $addr   PTR = addr
INC_PTR   = 0x21  # INC PTR       PTR = PTR + 1
DEC_PTR   = 0x22  # DEC PTR       PTR = PTR - 1

LDA_PTR_INC = 0x23  # LDA [PTR+]     A = MEM[PTR], depois PTR++
LDB_PTR_INC = 0x24  # LDB [PTR+]     B = MEM[PTR], depois PTR++

STA_PTR_INC = 0x25  # STA [PTR+]     MEM[PTR] = A, depois PTR++
STB_PTR_INC = 0x26  # STB [PTR+]     MEM[PTR] = B, depois PTR++
# =========================
# Load / Store
# =========================

LDA_IMM = 0x10  # LDA #$xx        A = valor imediato 
LDB_IMM = 0x11  # LDB #$xx        B = valor imediato 

LDA_ABS = 0x12  # LDA $addr       A = MEM[addr]
LDB_ABS = 0x13  # LDB $addr       B = MEM[addr]

STA_ABS = 0x14  # STA $addr       MEM[addr] = A
STB_ABS = 0x15  # STB $addr       MEM[addr] = B

STI     = 0x27  # STI $ENDEREÇO #VALOR  MEM[ENDEREÇO] = VALOR


# =========================
# ALU - Aritmética
# =========================

ADD_A_B = 0x30  # ADD A, B        A = A + B
ADD_B_A = 0x31  # ADD B, A        B = B + A

SUB_A_B = 0x32  # SUB A, B        A = A - B
SUB_B_A = 0x33  # SUB B, A        B = B - A


# =========================
# ALU - Lógica
# =========================

AND_A_B = 0x34  # AND A, B        A = A AND B
AND_B_A = 0x35  # AND B, A        B = B AND A

OR_A_B  = 0x36  # OR A, B         A = A OR B
OR_B_A  = 0x37  # OR B, A         B = B OR A

XOR_A_B = 0x38  # XOR A, B        A = A XOR B
XOR_B_A = 0x39  # XOR B, A        B = B XOR A

NOT_A   = 0x3A  # NOT A           A = NOT A
NOT_B   = 0x3B  # NOT B           B = NOT B


# =========================
# ALU - Shift
# =========================

SHL_A = 0x3C    # SHL A           A = A << 1
SHR_A = 0x3D    # SHR A           A = A >> 1

SHL_B = 0x3E    # SHL B           B = B << 1
SHR_B = 0x3F    # SHR B           B = B >> 1


# =========================
# Comparação / Inc / Dec / Clear
# =========================

CMP_A_B = 0x40  # CMP A, B        flags = A - B
CMP_B_A = 0x41  # CMP B, A        flags = B - A

INC_A = 0x42    # INC A           A = A + 1
DEC_A = 0x43    # DEC A           A = A - 1

INC_B = 0x44    # INC B           B = B + 1
DEC_B = 0x45    # DEC B           B = B - 1

CLR_A = 0x46    # CLR A           A = 0
CLR_B = 0x47    # CLR B           B = 0



# =========================
# ALU com valor imediato
# =========================

ADD_A_IMM = 0x60  # ADD A, #$xx    A = A + imediato
ADD_B_IMM = 0x61  # ADD B, #$xx    B = B + imediato
SUB_A_IMM = 0x62  # SUB A, #$xx    A = A - imediato
SUB_B_IMM = 0x63  # SUB B, #$xx    B = B - imediato
AND_A_IMM = 0x64  # AND A, #$xx    A = A AND imediato
AND_B_IMM = 0x65  # AND B, #$xx    B = B AND imediato
OR_A_IMM  = 0x66  # OR A, #$xx     A = A OR imediato
OR_B_IMM  = 0x67  # OR B, #$xx     B = B OR imediato
XOR_A_IMM = 0x68  # XOR A, #$xx    A = A XOR imediato
XOR_B_IMM = 0x69  # XOR B, #$xx    B = B XOR imediato
CMP_A_IMM = 0x6A  # CMP A, #$xx    flags = A - imediato
CMP_B_IMM = 0x6B  # CMP B, #$xx    flags = B - imediato
TEST_A_IMM = 0x6C # TEST A, #$xx   flags = A AND imediato
TEST_B_IMM = 0x6D # TEST B, #$xx   flags = B AND imediato

# =========================
# Jumps absolutos
# =========================

JMP_ABS = 0x50  # JMP $addr       PC = addr 

JZ_ABS  = 0x51  # JZ $addr        pula se Z = 1
JNZ_ABS = 0x52  # JNZ $addr       pula se Z = 0

JC_ABS  = 0x53  # JC $addr        pula se C = 1
JNC_ABS = 0x54  # JNC $addr       pula se C = 0

JN_ABS  = 0x55  # JN $addr        pula se N = 1
JP_ABS  = 0x56  # JP $addr        pula se N = 0

JV_ABS  = 0x57  # JV $addr        pula se V = 1
JNV_ABS = 0x58  # JNV $addr       pula se V = 0

# =========================
# Stack Point
# =========================

CALL_ABS = 0x59  # CALL $addr
RET      = 0x5A  # RET

PUSH_A   = 0x5B
PUSH_B   = 0x5C
POP_A    = 0x5D
POP_B    = 0x5E

LDSP_ABS = 0x5F  # SP = endereço inicial da pilha
# =========================
# Mapa dos bits de controle
# =========================

# ROM 1
PC_INC      = ("rom1", 0, "H")
PC_LOAD     = ("rom1", 1, "L")  # /PC_LOAD
PC_OUT      = ("rom1", 2, "L")  # /PC_OUT
MAR_LOAD    = ("rom1", 3, "L")  # /MAR_LOAD
MAR_OUT     = ("rom1", 4, "L")  # /MAR_OUT
IR_LOAD     = ("rom1", 5, "L")  # /IR_LOAD
RA_LOAD     = ("rom1", 6, "L")  # /RA_LOAD
RA_OUT      = ("rom1", 7, "L")  # /RA_OUT

# ROM 2
RB_LOAD     = ("rom2", 0, "L")  # /RB_LOAD
RB_OUT      = ("rom2", 1, "L")  # /RB_OUT
ADDR_L_LOAD = ("rom2", 2, "L")  # /ADDR_L_LOAD
ADDR_H_LOAD = ("rom2", 3, "L")  # /ADDR_H_LOAD
ADDR_OUT    = ("rom2", 4, "L")  # /ADDR_OUT
ALU_AB_SWAP = ("rom2", 5, "H")
ALU_NOT_X   = ("rom2", 6, "H")
ALU_SUB     = ("rom2", 7, "H")  # ALU_SUB

# ROM 3
ALU_MUX_0   = ("rom3", 0, "H")
ALU_MUX_1   = ("rom3", 1, "H")
ALU_MUX_2   = ("rom3", 2, "H")
ALU_OUT     = ("rom3", 3, "L")  # /ALU_OUT
MEMORY_OE   = ("rom3", 4, "L")  # /MEMORY_OE
MEMORY_WE   = ("rom3", 5, "L")  # /MEMORY_WE
FLAGS_LOAD  = ("rom3", 6, "L")  # /FLAGS_LOAD
STEP_RESET  = ("rom3", 7, "L")  # /STEP_RESET

# ROM 4
HALT        = ("rom4", 0, "L")  # /HALT
PTR_EN      = ("rom4", 1, "L")  # /PTR_EN
PTR_L_LOAD  = ("rom4", 2, "L")  # /PTR_L_LOAD
PTR_H_LOAD  = ("rom4", 3, "L")  # /PTR_H_LOAD
PTR_OUT     = ("rom4", 4, "L")  # /PTR_OUT
PTR_DOWN    = ("rom4", 5, "H")  
TMP_LOAD    = ("rom4", 6, "L")  # /TMP_LOAD
TMP_OUT     = ("rom4", 7, "L")  # /TMP_OUT

# ROM 4
SP_EN       = ("rom5", 0, "L")  # /SP_EN
SP_L_LOAD   = ("rom5", 1, "L")  # /SP_L_LOAD
SP_H_LOAD   = ("rom5", 2, "L")  # /SP_H_LOAD
SP_OUT      = ("rom5", 3, "L")  # /SP_OUT
SP_DOWN     = ("rom5", 4, "H")  
PC_OUT_L_DATA          = ("rom5", 5, "L")  # /PC_OUT_L_DATA
PC_OUT_H_DATA          = ("rom5", 6, "L")  # /PC_OUT_H_DATA
NA          = ("rom5", 7, "L")  

########################## ALU Control #############################

ALU_ADD_OP  = []
ALU_SUB_OP  = [ALU_SUB]

ALU_AND_OP  = [ALU_MUX_0]
ALU_OR_OP   = [ALU_MUX_1]
ALU_XOR_OP  = [ALU_MUX_1, ALU_MUX_0]
ALU_NOT_OP  = [ALU_MUX_1, ALU_MUX_0, ALU_NOT_X]

ALU_SHR_OP  = [ALU_MUX_2]
ALU_SHL_OP  = [ALU_MUX_2, ALU_MUX_0]

ALU_INC_OP  = [ALU_MUX_2, ALU_MUX_1]
ALU_DEC_OP  = [ALU_MUX_2, ALU_MUX_1, ALU_SUB]

ALU_ZERO_OP = [ALU_MUX_2, ALU_MUX_1, ALU_MUX_0]


################################ FUNÇÕES ################################


def make_flags(Z=0, C=0, N=0, V=0):
    return (Z << 0) | (C << 1) | (N << 2) | (V << 3)


def make_addr(opcode, step, flags):
    return opcode | (flags << 8) | (step << 12)


def activate(value, bit, active_level):
    """
    active_level:
    H = sinal ativo em HIGH
    L = sinal ativo em LOW
    """
    if active_level == "H":
        return value | (1 << bit)
    else:
        return value & ~(1 << bit)


def set_step(opcode, step, signals, flags=None):
    """
    Grava um microstep.

    opcode: valor do opcode, 0x00 até 0xFF
    step: microstep, 0 até 15
    signals: lista de sinais para acionar
    flags: se None, grava para todas as combinações de flags
    """

    if flags is None:
        flag_list = range(16)
    else:
        flag_list = [flags]

    for f in flag_list:
        addr = make_addr(opcode, step, f)

        for sig in signals:
            rom_name, bit, active_level = sig

            if rom_name == "rom1":
                rom1[addr] = activate(rom1[addr], bit, active_level)

            elif rom_name == "rom2":
                rom2[addr] = activate(rom2[addr], bit, active_level)

            elif rom_name == "rom3":
                rom3[addr] = activate(rom3[addr], bit, active_level)

            elif rom_name == "rom4":
                rom4[addr] = activate(rom4[addr], bit, active_level)

            elif rom_name == "rom5":
                rom5[addr] = activate(rom5[addr], bit, active_level)

########################## INSTRUÇÕES dos OPCODES ##################################################

# =========================
# FETCH comum de todas os opcodes para pegaar o endereço lido
# =========================

# T0: PC -> MAR
# T1: memória -> IR, PC++


for opcode in range(256):
    set_step(opcode, 0, [PC_OUT, MAR_LOAD])
    set_step(opcode, 1, [MEMORY_OE, IR_LOAD, PC_INC, MAR_OUT])


# =========================
# Instrução NOP
# =========================

set_step(NOP, 2, [STEP_RESET])


################################### Tools #########################################

# =========================
# Instrução JMP
# =========================
set_step(JMP_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JMP_ABS, 3, [MEMORY_OE, ADDR_L_LOAD, PC_INC, MAR_OUT])
set_step(JMP_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JMP_ABS, 5, [MEMORY_OE, ADDR_H_LOAD, PC_INC, MAR_OUT])
set_step(JMP_ABS, 6, [PC_LOAD, ADDR_OUT])
set_step(JMP_ABS, 7, [STEP_RESET])

################################ Manipulaçao Registradores ############################


# =========================
# Instrução LDA #imediato
# =========================

set_step(LDA_IMM, 2, [PC_OUT, MAR_LOAD])
set_step(LDA_IMM, 3, [MEMORY_OE, RA_LOAD, PC_INC, MAR_OUT])
set_step(LDA_IMM, 4, [STEP_RESET])

# =========================
# Instrução LDA #Obsoluto
# =========================

set_step(LDA_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(LDA_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])
set_step(LDA_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(LDA_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])
set_step(LDA_ABS, 6, [ADDR_OUT, MAR_LOAD])
set_step(LDA_ABS, 7, [MAR_OUT, MEMORY_OE, RA_LOAD])
set_step(LDA_ABS, 8, [STEP_RESET])

# =========================
# Instrução LDB #imediato
# =========================

set_step(LDB_IMM, 2, [PC_OUT, MAR_LOAD])
set_step(LDB_IMM, 3, [MEMORY_OE, RB_LOAD, PC_INC, MAR_OUT])
set_step(LDB_IMM, 4, [STEP_RESET])

# =========================
# Instrução LDB #Obsoluto
# =========================

set_step(LDB_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(LDB_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])
set_step(LDB_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(LDB_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])
set_step(LDB_ABS, 6, [ADDR_OUT, MAR_LOAD])
set_step(LDB_ABS, 7, [MAR_OUT, MEMORY_OE, RB_LOAD])
set_step(LDB_ABS, 8, [STEP_RESET])


# =========================
# Instrução STA $addr
# MEM[addr] = A
#
# Formato:
# STA $1234 -> 14 34 12
# =========================

set_step(STA_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(STA_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])
set_step(STA_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(STA_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])
set_step(STA_ABS, 6, [ADDR_OUT, MAR_LOAD])
# Setup: endereço externo e dado no barramento
set_step(STA_ABS, 7, [MAR_OUT, RA_OUT])
# Escrita
set_step(STA_ABS, 8, [MAR_OUT, RA_OUT, MEMORY_WE])
set_step(STA_ABS, 9, [STEP_RESET])


# =========================
# Instrução STB $addr
# MEM[addr] = B
#
# Formato:
# STB $1234 -> 15 34 12
# =========================

set_step(STB_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(STB_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])
set_step(STB_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(STB_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])
set_step(STB_ABS, 6, [ADDR_OUT, MAR_LOAD])
# Setup: endereço externo e dado no barramento
set_step(STB_ABS, 7, [MAR_OUT, RB_OUT])
# Escrita
set_step(STB_ABS, 8, [MAR_OUT, RB_OUT, MEMORY_WE])
set_step(STB_ABS, 9, [STEP_RESET])


# =========================
# Instrução STB $addr
# MEM[addr] = B
#
# Formato:
# STB $1234 -> 15 34 12
# =========================

set_step(STI, 2, [PC_OUT, MAR_LOAD])
set_step(STI, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])
set_step(STI, 4, [PC_OUT, MAR_LOAD])
set_step(STI, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

# Busca valor imediato e guarda no TMP
set_step(STI, 6, [PC_OUT, MAR_LOAD])
set_step(STI, 7, [MAR_OUT, MEMORY_OE, TMP_LOAD, PC_INC])

# Coloca endereço final no MAR
set_step(STI, 8, [ADDR_OUT, MAR_LOAD])

# Escreve TMP no endereço
set_step(STI, 9, [MAR_OUT, TMP_OUT])
set_step(STI, 10, [MAR_OUT, TMP_OUT, MEMORY_WE])

set_step(STI, 11, [STEP_RESET])





# =========================
# Instrução HLT
# Trava o clock da CPU
# =========================

set_step(HLT, 2, [HALT])
set_step(HLT, 3, [HALT])

# =========================
# Instrução MOV A, B
# A = B
# =========================

set_step(MOV_A_B, 2, [RB_OUT, RA_LOAD])
set_step(MOV_A_B, 3, [STEP_RESET])


# =========================
# Instrução MOV B, A
# B = A
# =========================

set_step(MOV_B_A, 2, [RA_OUT, RB_LOAD])
set_step(MOV_B_A, 3, [STEP_RESET])


# =========================
# Instrução LDPTR $addr
# PTR = addr
#
# Formato:
# LDPTR $1234 -> 20 34 12
# =========================

set_step(LDPTR_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(LDPTR_ABS, 3, [MAR_OUT, MEMORY_OE, PTR_L_LOAD, PC_INC])

set_step(LDPTR_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(LDPTR_ABS, 5, [MAR_OUT, MEMORY_OE, PTR_H_LOAD, PC_INC])

set_step(LDPTR_ABS, 6, [STEP_RESET])


# =========================
# Instrução LDA [PTR]
# A = MEM[PTR]
# =========================

set_step(LDA_PTR, 2, [PTR_OUT, MAR_LOAD])
set_step(LDA_PTR, 3, [MAR_OUT, MEMORY_OE, RA_LOAD])
set_step(LDA_PTR, 4, [STEP_RESET])


# =========================
# Instrução LDB [PTR]
# B = MEM[PTR]
# =========================

set_step(LDB_PTR, 2, [PTR_OUT, MAR_LOAD])
set_step(LDB_PTR, 3, [MAR_OUT, MEMORY_OE, RB_LOAD])
set_step(LDB_PTR, 4, [STEP_RESET])


# =========================
# Instrução STA [PTR]
# MEM[PTR] = A
# =========================

set_step(STA_PTR, 2, [PTR_OUT, MAR_LOAD])

# Setup: endereço externo e dado no barramento
set_step(STA_PTR, 3, [MAR_OUT, RA_OUT])

# Escrita
set_step(STA_PTR, 4, [MAR_OUT, RA_OUT, MEMORY_WE])

set_step(STA_PTR, 5, [STEP_RESET])


# =========================
# Instrução STB [PTR]
# MEM[PTR] = B
# =========================

set_step(STB_PTR, 2, [PTR_OUT, MAR_LOAD])

# Setup: endereço externo e dado no barramento
set_step(STB_PTR, 3, [MAR_OUT, RB_OUT])

# Escrita
set_step(STB_PTR, 4, [MAR_OUT, RB_OUT, MEMORY_WE])

set_step(STB_PTR, 5, [STEP_RESET])


# =========================
# Instrução INC PTR
# PTR = PTR + 1
#
# PTR_DOWN = 0
# /PTR_EN = 0
# =========================

set_step(INC_PTR, 2, [PTR_EN])
set_step(INC_PTR, 3, [STEP_RESET])


# =========================
# Instrução DEC PTR
# PTR = PTR - 1
#
# PTR_DOWN = 1
# /PTR_EN = 0
# =========================

set_step(DEC_PTR, 2, [PTR_DOWN, PTR_EN])
set_step(DEC_PTR, 3, [STEP_RESET])




# =========================
# Instrução LDA [PTR+]
# A = MEM[PTR]
# Depois PTR = PTR + 1
# =========================

set_step(LDA_PTR_INC, 2, [PTR_OUT, MAR_LOAD])
set_step(LDA_PTR_INC, 3, [MAR_OUT, MEMORY_OE, RA_LOAD])

# PTR_DOWN fica 0 no idle, então incrementa
set_step(LDA_PTR_INC, 4, [PTR_EN])

set_step(LDA_PTR_INC, 5, [STEP_RESET])


# =========================
# Instrução LDB [PTR+]
# B = MEM[PTR]
# Depois PTR = PTR + 1
# =========================

set_step(LDB_PTR_INC, 2, [PTR_OUT, MAR_LOAD])
set_step(LDB_PTR_INC, 3, [MAR_OUT, MEMORY_OE, RB_LOAD])

# PTR_DOWN fica 0 no idle, então incrementa
set_step(LDB_PTR_INC, 4, [PTR_EN])

set_step(LDB_PTR_INC, 5, [STEP_RESET])


# =========================
# Instrução STA [PTR+]
# MEM[PTR] = A
# Depois PTR = PTR + 1
# =========================

set_step(STA_PTR_INC, 2, [PTR_OUT, MAR_LOAD])

# Setup: endereço externo e dado no barramento
set_step(STA_PTR_INC, 3, [MAR_OUT, RA_OUT])

# Escrita
set_step(STA_PTR_INC, 4, [MAR_OUT, RA_OUT, MEMORY_WE])

# PTR_DOWN fica 0 no idle, então incrementa
set_step(STA_PTR_INC, 5, [PTR_EN])

set_step(STA_PTR_INC, 6, [STEP_RESET])


# =========================
# Instrução STB [PTR+]
# MEM[PTR] = B
# Depois PTR = PTR + 1
# =========================

set_step(STB_PTR_INC, 2, [PTR_OUT, MAR_LOAD])

# Setup: endereço externo e dado no barramento
set_step(STB_PTR_INC, 3, [MAR_OUT, RB_OUT])

# Escrita
set_step(STB_PTR_INC, 4, [MAR_OUT, RB_OUT, MEMORY_WE])

# PTR_DOWN fica 0 no idle, então incrementa
set_step(STB_PTR_INC, 5, [PTR_EN])

set_step(STB_PTR_INC, 6, [STEP_RESET])





############################### Aritimetrica ###############################

# =========================
# Instrução ADD A, B
# A = A + B
# =========================

set_step(ADD_A_B, 2, ALU_ADD_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(ADD_A_B, 3, [STEP_RESET])

# =========================
# Instrução ADD B, A
# B = B + A
# =========================

set_step(ADD_B_A, 2, ALU_ADD_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(ADD_B_A, 3, [STEP_RESET])

# =========================
# Instrução SUB A, B
# A = A - B
# =========================

set_step(SUB_A_B, 2, ALU_SUB_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(SUB_A_B, 3, [STEP_RESET])

# =========================
# Instrução SUB B, A
# B = B - A
# =========================

set_step(SUB_B_A, 2, ALU_SUB_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(SUB_B_A, 3, [STEP_RESET])



###################################### LÓGICA ###################################

# =========================
# Instrução AND A, B
# A = A AND B
# =========================

set_step(AND_A_B, 2, ALU_AND_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(AND_A_B, 3, [STEP_RESET])


# =========================
# Instrução AND B, A
# B = B AND A
# =========================

set_step(AND_B_A, 2, ALU_AND_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(AND_B_A, 3, [STEP_RESET])


# =========================
# Instrução OR A, B
# A = A OR B
# =========================

set_step(OR_A_B, 2, ALU_OR_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(OR_A_B, 3, [STEP_RESET])


# =========================
# Instrução OR B, A
# B = B OR A
# =========================

set_step(OR_B_A, 2, ALU_OR_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(OR_B_A, 3, [STEP_RESET])


# =========================
# Instrução XOR A, B
# A = A XOR B
# =========================

set_step(XOR_A_B, 2, ALU_XOR_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(XOR_A_B, 3, [STEP_RESET])


# =========================
# Instrução XOR B, A
# B = B XOR A
# =========================

set_step(XOR_B_A, 2, ALU_XOR_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(XOR_B_A, 3, [STEP_RESET])


# =========================
# Instrução NOT A
# A = NOT A
# =========================

set_step(NOT_A, 2, ALU_NOT_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(NOT_A, 3, [STEP_RESET])


# =========================
# Instrução NOT B
# B = NOT B
#
# Usa ALU_AB_SWAP para ALU_X = B
# =========================

set_step(NOT_B, 2, ALU_NOT_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(NOT_B, 3, [STEP_RESET])

###################################### SHIFT ###################################

# =========================
# Instrução SHL A
# A = A << 1
# =========================

set_step(SHL_A, 2, ALU_SHL_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(SHL_A, 3, [STEP_RESET])


# =========================
# Instrução SHR A
# A = A >> 1
# =========================

set_step(SHR_A, 2, ALU_SHR_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(SHR_A, 3, [STEP_RESET])


# =========================
# Instrução SHL B
# B = B << 1
#
# Usa ALU_AB_SWAP para ALU_X = B
# =========================

set_step(SHL_B, 2, ALU_SHL_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(SHL_B, 3, [STEP_RESET])


# =========================
# Instrução SHR B
# B = B >> 1
#
# Usa ALU_AB_SWAP para ALU_X = B
# =========================

set_step(SHR_B, 2, ALU_SHR_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(SHR_B, 3, [STEP_RESET])


###################################### INC / DEC / CLR ###################################

# =========================
# Instrução INC A
# A = A + 1
# =========================

set_step(INC_A, 2, ALU_INC_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(INC_A, 3, [STEP_RESET])


# =========================
# Instrução DEC A
# A = A - 1
# =========================

set_step(DEC_A, 2, ALU_DEC_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(DEC_A, 3, [STEP_RESET])


# =========================
# Instrução INC B
# B = B + 1
#
# Usa ALU_AB_SWAP para ALU_X = B
# =========================

set_step(INC_B, 2, ALU_INC_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(INC_B, 3, [STEP_RESET])


# =========================
# Instrução DEC B
# B = B - 1
#
# Usa ALU_AB_SWAP para ALU_X = B
# =========================

set_step(DEC_B, 2, ALU_DEC_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(DEC_B, 3, [STEP_RESET])


# =========================
# Instrução CLR A
# A = 0
# =========================

set_step(CLR_A, 2, ALU_ZERO_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(CLR_A, 3, [STEP_RESET])


# =========================
# Instrução CLR B
# B = 0
# =========================

set_step(CLR_B, 2, ALU_ZERO_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(CLR_B, 3, [STEP_RESET])


###################################### COMPARAÇÃO ###################################

# =========================
# Instrução CMP A, B
# flags = A - B
#
# Não altera A nem B.
# =========================

set_step(CMP_A_B, 2, ALU_SUB_OP + [FLAGS_LOAD])
set_step(CMP_A_B, 3, [STEP_RESET])


# =========================
# Instrução CMP B, A
# flags = B - A
#
# Não altera A nem B.
# =========================

set_step(CMP_B_A, 2, ALU_SUB_OP + [ALU_AB_SWAP, FLAGS_LOAD])
set_step(CMP_B_A, 3, [STEP_RESET])




###################################### ALU IMEDIATA ###################################

# O TMP não entra diretamente na ALU. Ele é usado para preservar o
# registrador que servirá temporariamente como segundo operando.
#
# Operações sobre A:
#   TMP = B -> B = imediato -> ALU usa A/B -> TMP restaura B
#
# Operações sobre B:
#   TMP = A -> A = imediato -> ALU usa B/A -> TMP restaura A


def immediate_to_b_prefix(opcode):
    """Preserva B no TMP e carrega o byte imediato em B."""
    set_step(opcode, 2, [RB_OUT, TMP_LOAD])
    set_step(opcode, 3, [PC_OUT, MAR_LOAD])
    set_step(opcode, 4, [MAR_OUT, MEMORY_OE, RB_LOAD, PC_INC])


def immediate_to_a_prefix(opcode):
    """Preserva A no TMP e carrega o byte imediato em A."""
    set_step(opcode, 2, [RA_OUT, TMP_LOAD])
    set_step(opcode, 3, [PC_OUT, MAR_LOAD])
    set_step(opcode, 4, [MAR_OUT, MEMORY_OE, RA_LOAD, PC_INC])


# ADD A, #imediato
immediate_to_b_prefix(ADD_A_IMM)
set_step(ADD_A_IMM, 5, ALU_ADD_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(ADD_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(ADD_A_IMM, 7, [STEP_RESET])

# ADD B, #imediato
immediate_to_a_prefix(ADD_B_IMM)
set_step(ADD_B_IMM, 5, ALU_ADD_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(ADD_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(ADD_B_IMM, 7, [STEP_RESET])

# SUB A, #imediato
immediate_to_b_prefix(SUB_A_IMM)
set_step(SUB_A_IMM, 5, ALU_SUB_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(SUB_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(SUB_A_IMM, 7, [STEP_RESET])

# SUB B, #imediato: ALU_AB_SWAP produz B - A
immediate_to_a_prefix(SUB_B_IMM)
set_step(SUB_B_IMM, 5, ALU_SUB_OP + [ALU_AB_SWAP, ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(SUB_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(SUB_B_IMM, 7, [STEP_RESET])

# AND A, #imediato
immediate_to_b_prefix(AND_A_IMM)
set_step(AND_A_IMM, 5, ALU_AND_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(AND_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(AND_A_IMM, 7, [STEP_RESET])

# AND B, #imediato
immediate_to_a_prefix(AND_B_IMM)
set_step(AND_B_IMM, 5, ALU_AND_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(AND_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(AND_B_IMM, 7, [STEP_RESET])

# OR A, #imediato
immediate_to_b_prefix(OR_A_IMM)
set_step(OR_A_IMM, 5, ALU_OR_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(OR_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(OR_A_IMM, 7, [STEP_RESET])

# OR B, #imediato
immediate_to_a_prefix(OR_B_IMM)
set_step(OR_B_IMM, 5, ALU_OR_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(OR_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(OR_B_IMM, 7, [STEP_RESET])

# XOR A, #imediato
immediate_to_b_prefix(XOR_A_IMM)
set_step(XOR_A_IMM, 5, ALU_XOR_OP + [ALU_OUT, RA_LOAD, FLAGS_LOAD])
set_step(XOR_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(XOR_A_IMM, 7, [STEP_RESET])

# XOR B, #imediato
immediate_to_a_prefix(XOR_B_IMM)
set_step(XOR_B_IMM, 5, ALU_XOR_OP + [ALU_OUT, RB_LOAD, FLAGS_LOAD])
set_step(XOR_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(XOR_B_IMM, 7, [STEP_RESET])

# CMP A, #imediato: atualiza flags e restaura B
immediate_to_b_prefix(CMP_A_IMM)
set_step(CMP_A_IMM, 5, ALU_SUB_OP + [FLAGS_LOAD])
set_step(CMP_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(CMP_A_IMM, 7, [STEP_RESET])

# CMP B, #imediato: ALU_AB_SWAP produz B - A
immediate_to_a_prefix(CMP_B_IMM)
set_step(CMP_B_IMM, 5, ALU_SUB_OP + [ALU_AB_SWAP, FLAGS_LOAD])
set_step(CMP_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(CMP_B_IMM, 7, [STEP_RESET])

# TEST A, #imediato: AND apenas nas flags, sem alterar A
immediate_to_b_prefix(TEST_A_IMM)
set_step(TEST_A_IMM, 5, ALU_AND_OP + [FLAGS_LOAD])
set_step(TEST_A_IMM, 6, [TMP_OUT, RB_LOAD])
set_step(TEST_A_IMM, 7, [STEP_RESET])

# TEST B, #imediato: AND apenas nas flags, sem alterar B
immediate_to_a_prefix(TEST_B_IMM)
set_step(TEST_B_IMM, 5, ALU_AND_OP + [FLAGS_LOAD])
set_step(TEST_B_IMM, 6, [TMP_OUT, RA_LOAD])
set_step(TEST_B_IMM, 7, [STEP_RESET])


###################################### CONDICIONAIS ###################################

# Ordem das flags no endereço do microcódigo:
# make_flags(Z, C, N, V)
#
# bit 0 = Z
# bit 1 = C
# bit 2 = N
# bit 3 = V


# =========================
# JZ $addr
# Pula se Z = 1
# =========================

set_step(JZ_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JZ_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JZ_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JZ_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [1, 3, 5, 7, 9, 11, 13, 15]:
    set_step(JZ_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JZ_ABS, 7, [STEP_RESET])


# =========================
# JNZ $addr
# Pula se Z = 0
# =========================

set_step(JNZ_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JNZ_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JNZ_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JNZ_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [0, 2, 4, 6, 8, 10, 12, 14]:
    set_step(JNZ_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JNZ_ABS, 7, [STEP_RESET])


# =========================
# JC $addr
# Pula se C = 1
# =========================

set_step(JC_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JC_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JC_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JC_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [2, 3, 6, 7, 10, 11, 14, 15]:
    set_step(JC_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JC_ABS, 7, [STEP_RESET])


# =========================
# JNC $addr
# Pula se C = 0
# =========================

set_step(JNC_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JNC_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JNC_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JNC_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [0, 1, 4, 5, 8, 9, 12, 13]:
    set_step(JNC_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JNC_ABS, 7, [STEP_RESET])


# =========================
# JN $addr
# Pula se N = 1
# =========================

set_step(JN_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JN_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JN_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JN_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [4, 5, 6, 7, 12, 13, 14, 15]:
    set_step(JN_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JN_ABS, 7, [STEP_RESET])


# =========================
# JP $addr
# Pula se N = 0
# =========================

set_step(JP_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JP_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JP_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JP_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [0, 1, 2, 3, 8, 9, 10, 11]:
    set_step(JP_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JP_ABS, 7, [STEP_RESET])


# =========================
# JV $addr
# Pula se V = 1
# =========================

set_step(JV_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JV_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JV_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JV_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [8, 9, 10, 11, 12, 13, 14, 15]:
    set_step(JV_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JV_ABS, 7, [STEP_RESET])


# =========================
# JNV $addr
# Pula se V = 0
# =========================

set_step(JNV_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(JNV_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

set_step(JNV_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(JNV_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

for f in [0, 1, 2, 3, 4, 5, 6, 7]:
    set_step(JNV_ABS, 6, [ADDR_OUT, PC_LOAD], flags=f)

set_step(JNV_ABS, 7, [STEP_RESET])


# =========================
# PUSH A
#SP = SP - 1
#MEM[SP] = A
# =========================

# PUSH A
set_step(PUSH_A, 2, [SP_DOWN, SP_EN])          # SP--
set_step(PUSH_A, 3, [SP_OUT, MAR_LOAD])        # MAR = SP
set_step(PUSH_A, 4, [MAR_OUT, RA_OUT])         # setup endereço + dado
set_step(PUSH_A, 5, [MAR_OUT, RA_OUT, MEMORY_WE])
set_step(PUSH_A, 6, [STEP_RESET])



# PUSH B
set_step(PUSH_B, 2, [SP_DOWN, SP_EN])          
set_step(PUSH_B, 3, [SP_OUT, MAR_LOAD])        
set_step(PUSH_B, 4, [MAR_OUT, RB_OUT])         
set_step(PUSH_B, 5, [MAR_OUT, RB_OUT, MEMORY_WE])
set_step(PUSH_B, 6, [STEP_RESET])

# =========================
# PUSH A
# A = MEM[SP]
# SP = SP + 1
# =========================

# POP A
set_step(POP_A, 2, [SP_OUT, MAR_LOAD])             # MAR = SP
set_step(POP_A, 3, [MAR_OUT, MEMORY_OE, RA_LOAD])  # A = MEM[SP]
set_step(POP_A, 4, [SP_EN])                        # SP++
set_step(POP_A, 5, [STEP_RESET])

# POP B
set_step(POP_B, 2, [SP_OUT, MAR_LOAD])
set_step(POP_B, 3, [MAR_OUT, MEMORY_OE, RB_LOAD])
set_step(POP_B, 4, [SP_EN])
set_step(POP_B, 5, [STEP_RESET])




# =========================
# CALL $addr
# Formato: CALL low high
# =========================

# Busca endereço destino low
set_step(CALL_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(CALL_ABS, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD, PC_INC])

# Busca endereço destino high
set_step(CALL_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(CALL_ABS, 5, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD, PC_INC])

# Agora PC já aponta para a próxima instrução.
# Vamos salvar PC na pilha.

# SP--, salva PC HIGH
set_step(CALL_ABS, 6, [SP_DOWN, SP_EN])
set_step(CALL_ABS, 7, [SP_OUT, MAR_LOAD])
set_step(CALL_ABS, 8, [MAR_OUT, PC_OUT_H_DATA])
set_step(CALL_ABS, 9, [MAR_OUT, PC_OUT_H_DATA, MEMORY_WE])

# SP--, salva PC LOW
set_step(CALL_ABS, 10, [SP_DOWN, SP_EN])
set_step(CALL_ABS, 11, [SP_OUT, MAR_LOAD])
set_step(CALL_ABS, 12, [MAR_OUT, PC_OUT_L_DATA])
set_step(CALL_ABS, 13, [MAR_OUT, PC_OUT_L_DATA, MEMORY_WE])

# PC = destino
set_step(CALL_ABS, 14, [ADDR_OUT, PC_LOAD])
set_step(CALL_ABS, 15, [STEP_RESET])


# =========================
#  RET
# =========================


# Lê byte LOW do endereço de retorno
set_step(RET, 2, [SP_OUT, MAR_LOAD])
set_step(RET, 3, [MAR_OUT, MEMORY_OE, ADDR_L_LOAD])
set_step(RET, 4, [SP_EN])  # SP++

# Lê byte HIGH do endereço de retorno
set_step(RET, 5, [SP_OUT, MAR_LOAD])
set_step(RET, 6, [MAR_OUT, MEMORY_OE, ADDR_H_LOAD])
set_step(RET, 7, [SP_EN])  # SP++

# PC = endereço recuperado
set_step(RET, 8, [ADDR_OUT, PC_LOAD])
set_step(RET, 9, [STEP_RESET])


# =========================
# LDSP $addr
# =========================

set_step(LDSP_ABS, 2, [PC_OUT, MAR_LOAD])
set_step(LDSP_ABS, 3, [MAR_OUT, MEMORY_OE, SP_L_LOAD, PC_INC])

set_step(LDSP_ABS, 4, [PC_OUT, MAR_LOAD])
set_step(LDSP_ABS, 5, [MAR_OUT, MEMORY_OE, SP_H_LOAD, PC_INC])

set_step(LDSP_ABS, 6, [STEP_RESET])
























# =========================
# Salvar arquivos .bin
# =========================

with open("microcode_rom1.bin", "wb") as f:
    f.write(rom1)

with open("microcode_rom2.bin", "wb") as f:
    f.write(rom2)

with open("microcode_rom3.bin", "wb") as f:
    f.write(rom3)

with open("microcode_rom4.bin", "wb") as f:
    f.write(rom4)

with open("microcode_rom5.bin", "wb") as f:
    f.write(rom5)

print("Arquivos gerados:")
print("microcode_rom1.bin")
print("microcode_rom2.bin")
print("microcode_rom3.bin")
print("microcode_rom4.bin")
print("microcode_rom5.bin")