#!/usr/bin/env python3
"""
WALL-8 Emulator — emulador funcional em Python/Tkinter

Implementa a ISA atual do WALL-8, incluindo ALU/CMP/TEST imediatos, o mapa de memória de 64 KiB, boot overlay,
RAM, BIOS, cartucho gravável, teclado, display, timer, terminal de vídeo e som.

O núcleo é um emulador por INSTRUÇÃO. Ele preserva os resultados arquiteturais
registradores/memória/flags e contabiliza os ciclos do microcódigo atual, mas não
executa as cinco ROMs de microcódigo sinal por sinal.

Dependências:
    Python 3.10+ com Tkinter.
    pygame é opcional para som real:  pip install pygame

Uso:
    python wall8_emulator_v16.py
    python wall8_emulator_v16.py --bios bios.bin --cart cart.bin
    python wall8_emulator_v16.py --bios eprom_27c512.bin
    python wall8_emulator_v16.py --self-test

Mapeamento físico das 27C512:
    Todas as linhas A0..A15 recebem diretamente o endereço da CPU. O decode
    controla apenas /CE. Por isso uma imagem completa de 64 KiB é mantida
    inteira, e cada janela lê o byte no MESMO endereço físico da EPROM.

Placa de video conforme wall8_placa_video.md:
    F200  VIDEO_DATA  latch de escrita/resultado de leitura da VRAM
    F201  VIDEO_CMD   clear, cursor, selecao de modo e leitura de VRAM
    F202  VIDEO_X     coluna de caractere/byte grafico
    F203  VIDEO_Y     linha logica
    F204  VIDEO_STAT  BUSY, VBLANK, HBLANK e FRAME

Teclado:
    leitura em F000: bit7=KEY_READY, bits6..0=ASCII
    escrita em F000: reconhece/limpa a tecla atual e entrega a próxima da fila

Som conforme o esquema mais recente enviado:
    bit0 NOISE_EN
    bit1 TONE_EN
    bits2..4 TONE_B0..B2
    bits5..7 NOISE_B0..B2

Os nomes /NOISE_EN e /TONE_EN aparecem com barra no esquema, porém os sinais
entram no RESET ativo-baixo dos NE555; portanto nível 1 libera o oscilador.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import tempfile
import time
from array import array
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional


# =============================================================================
# Constantes do WALL-8
# =============================================================================

RAM_START = 0x0000
RAM_END = 0x7FFF
BIOS_START = 0x8000
BIOS_END = 0x9FFF
CART_START = 0xA000
CART_END = 0xEFFF
IO_START = 0xF000
IO_END = 0xFFFF

RAM_SIZE = 0x8000
BIOS_WINDOW_SIZE = 0x2000          # 8 KiB visíveis por janela
EPROM_27C512_SIZE = 0x10000        # 64 KiB físicos por 27C512
CART_WINDOW_SIZE = 0x5000          # 20 KiB visíveis no mapa da CPU

KEY_BASE = 0xF000
DISPLAY_LOW = 0xF100
DISPLAY_HIGH = 0xF101
VIDEO_BASE = 0xF200
TIMER_STATUS = 0xF300
SOUND_CFG = 0xF400
CPU_CFG = 0xF500
PERIPH_CFG = 0xF501

# Sistema
NOP = 0x00
HLT = 0x01

# Load/store/MOV/PTR
LDA_IMM = 0x10
LDB_IMM = 0x11
LDA_ABS = 0x12
LDB_ABS = 0x13
STA_ABS = 0x14
STB_ABS = 0x15
MOV_A_B = 0x16
MOV_B_A = 0x17
LDA_PTR = 0x18
LDB_PTR = 0x19
STA_PTR = 0x1A
STB_PTR = 0x1B
LDPTR_ABS = 0x20
INC_PTR = 0x21
DEC_PTR = 0x22
LDA_PTR_INC = 0x23
LDB_PTR_INC = 0x24
STA_PTR_INC = 0x25
STB_PTR_INC = 0x26
STI = 0x27

# ALU
ADD_A_B = 0x30
ADD_B_A = 0x31
SUB_A_B = 0x32
SUB_B_A = 0x33
AND_A_B = 0x34
AND_B_A = 0x35
OR_A_B = 0x36
OR_B_A = 0x37
XOR_A_B = 0x38
XOR_B_A = 0x39
NOT_A = 0x3A
NOT_B = 0x3B
SHL_A = 0x3C
SHR_A = 0x3D
SHL_B = 0x3E
SHR_B = 0x3F
CMP_A_B = 0x40
CMP_B_A = 0x41
INC_A = 0x42
DEC_A = 0x43
INC_B = 0x44
DEC_B = 0x45
CLR_A = 0x46
CLR_B = 0x47

# ALU com valor imediato
ADD_A_IMM = 0x60
ADD_B_IMM = 0x61
SUB_A_IMM = 0x62
SUB_B_IMM = 0x63
AND_A_IMM = 0x64
AND_B_IMM = 0x65
OR_A_IMM = 0x66
OR_B_IMM = 0x67
XOR_A_IMM = 0x68
XOR_B_IMM = 0x69
CMP_A_IMM = 0x6A
CMP_B_IMM = 0x6B
TEST_A_IMM = 0x6C
TEST_B_IMM = 0x6D

# Saltos e pilha
JMP_ABS = 0x50
JZ_ABS = 0x51
JNZ_ABS = 0x52
JC_ABS = 0x53
JNC_ABS = 0x54
JN_ABS = 0x55
JP_ABS = 0x56
JV_ABS = 0x57
JNV_ABS = 0x58
CALL_ABS = 0x59
RET = 0x5A
PUSH_A = 0x5B
PUSH_B = 0x5C
POP_A = 0x5D
POP_B = 0x5E
LDSP_ABS = 0x5F


# Ciclos conforme o gerador de microcódigo. STI usa T0..T11 = 12 ciclos.
CYCLES = {
    NOP: 3, HLT: 3,
    LDA_IMM: 5, LDB_IMM: 5,
    LDA_ABS: 9, LDB_ABS: 9,
    STA_ABS: 10, STB_ABS: 10,
    MOV_A_B: 4, MOV_B_A: 4,
    LDA_PTR: 5, LDB_PTR: 5,
    STA_PTR: 6, STB_PTR: 6,
    LDPTR_ABS: 7, INC_PTR: 4, DEC_PTR: 4,
    LDA_PTR_INC: 6, LDB_PTR_INC: 6,
    STA_PTR_INC: 7, STB_PTR_INC: 7,
    STI: 12,
    ADD_A_B: 4, ADD_B_A: 4,
    SUB_A_B: 4, SUB_B_A: 4,
    AND_A_B: 4, AND_B_A: 4,
    OR_A_B: 4, OR_B_A: 4,
    XOR_A_B: 4, XOR_B_A: 4,
    NOT_A: 4, NOT_B: 4,
    SHL_A: 4, SHR_A: 4, SHL_B: 4, SHR_B: 4,
    CMP_A_B: 4, CMP_B_A: 4,
    INC_A: 4, DEC_A: 4, INC_B: 4, DEC_B: 4,
    CLR_A: 4, CLR_B: 4,
    ADD_A_IMM: 8, ADD_B_IMM: 8,
    SUB_A_IMM: 8, SUB_B_IMM: 8,
    AND_A_IMM: 8, AND_B_IMM: 8,
    OR_A_IMM: 8, OR_B_IMM: 8,
    XOR_A_IMM: 8, XOR_B_IMM: 8,
    CMP_A_IMM: 8, CMP_B_IMM: 8,
    TEST_A_IMM: 8, TEST_B_IMM: 8,
    JMP_ABS: 8, JZ_ABS: 8, JNZ_ABS: 8,
    JC_ABS: 8, JNC_ABS: 8, JN_ABS: 8, JP_ABS: 8,
    JV_ABS: 8, JNV_ABS: 8,
    CALL_ABS: 16, RET: 10,
    PUSH_A: 7, PUSH_B: 7, POP_A: 6, POP_B: 6,
    LDSP_ABS: 7,
}


OP_NAMES = {
    NOP: "NOP", HLT: "HLT",
    LDA_IMM: "LDA #", LDB_IMM: "LDB #",
    LDA_ABS: "LDA", LDB_ABS: "LDB",
    STA_ABS: "STA", STB_ABS: "STB",
    MOV_A_B: "MOV A, B", MOV_B_A: "MOV B, A",
    LDA_PTR: "LDA [PTR]", LDB_PTR: "LDB [PTR]",
    STA_PTR: "STA [PTR]", STB_PTR: "STB [PTR]",
    LDPTR_ABS: "PTR", INC_PTR: "INC PTR", DEC_PTR: "DEC PTR",
    LDA_PTR_INC: "LDA [PTR+]", LDB_PTR_INC: "LDB [PTR+]",
    STA_PTR_INC: "STA [PTR+]", STB_PTR_INC: "STB [PTR+]",
    STI: "STI",
    ADD_A_B: "ADD A, B", ADD_B_A: "ADD B, A",
    SUB_A_B: "SUB A, B", SUB_B_A: "SUB B, A",
    AND_A_B: "AND A, B", AND_B_A: "AND B, A",
    OR_A_B: "OR A, B", OR_B_A: "OR B, A",
    XOR_A_B: "XOR A, B", XOR_B_A: "XOR B, A",
    NOT_A: "NOT A", NOT_B: "NOT B",
    SHL_A: "SHL A", SHR_A: "SHR A", SHL_B: "SHL B", SHR_B: "SHR B",
    CMP_A_B: "CMP A, B", CMP_B_A: "CMP B, A",
    INC_A: "INC A", DEC_A: "DEC A", INC_B: "INC B", DEC_B: "DEC B",
    CLR_A: "CLR A", CLR_B: "CLR B",
    ADD_A_IMM: "ADD A, #", ADD_B_IMM: "ADD B, #",
    SUB_A_IMM: "SUB A, #", SUB_B_IMM: "SUB B, #",
    AND_A_IMM: "AND A, #", AND_B_IMM: "AND B, #",
    OR_A_IMM: "OR A, #", OR_B_IMM: "OR B, #",
    XOR_A_IMM: "XOR A, #", XOR_B_IMM: "XOR B, #",
    CMP_A_IMM: "CMP A, #", CMP_B_IMM: "CMP B, #",
    TEST_A_IMM: "TEST A, #", TEST_B_IMM: "TEST B, #",
    JMP_ABS: "JMP", JZ_ABS: "JZ", JNZ_ABS: "JNZ",
    JC_ABS: "JC", JNC_ABS: "JNC", JN_ABS: "JN", JP_ABS: "JP",
    JV_ABS: "JV", JNV_ABS: "JNV",
    CALL_ABS: "CALL", RET: "RET",
    PUSH_A: "PUSH A", PUSH_B: "PUSH B", POP_A: "POP A", POP_B: "POP B",
    LDSP_ABS: "SP",
}

IMM_OPS = {
    LDA_IMM, LDB_IMM,
    ADD_A_IMM, ADD_B_IMM,
    SUB_A_IMM, SUB_B_IMM,
    AND_A_IMM, AND_B_IMM,
    OR_A_IMM, OR_B_IMM,
    XOR_A_IMM, XOR_B_IMM,
    CMP_A_IMM, CMP_B_IMM,
    TEST_A_IMM, TEST_B_IMM,
}
ABS_OPS = {
    LDA_ABS, LDB_ABS, STA_ABS, STB_ABS, LDPTR_ABS,
    JMP_ABS, JZ_ABS, JNZ_ABS, JC_ABS, JNC_ABS,
    JN_ABS, JP_ABS, JV_ABS, JNV_ABS, CALL_ABS, LDSP_ABS,
}


class IllegalOpcode(RuntimeError):
    def __init__(self, opcode: int, address: int):
        super().__init__(f"Opcode inválido ${opcode:02X} em ${address:04X}")
        self.opcode = opcode
        self.address = address


# =============================================================================
# Periféricos
# =============================================================================


class KeyboardDevice:
    """Módulo externo de teclado com DATA latched e flip-flop KEY_READY.

    Sinais expostos para a placa principal:
      KEYBOARD_B0..B7 = código de 8 bits mantido em um registrador
      KEY_READY       = saída Q de um flip-flop, lida em $F300 bit 7

    Sequência:
      - novo KeyPress: DATA recebe o código e o flip-flop é SETado;
      - leitura da CPU em $F000: a CPU captura READY+DATA e /KEY_RD
        reseta somente o flip-flop;
      - DATA permanece armazenado depois da leitura;
      - KeyRelease apenas libera a tecla física para uma nova pressão.

    Eventos repetidos do sistema operacional enquanto a mesma tecla continua
    pressionada são ignorados.
    """

    def __init__(self) -> None:
        self._data = 0
        self._ready_ff = False
        self._pressed_host_keys: set[tuple[int, str]] = set()

        self.last_host_keysym = ""
        self.last_host_char = ""
        self.last_host_keycode = 0
        self.last_event = "nenhum"
        self.repeat_ignored = 0
        self.dropped = 0

    def reset(self) -> None:
        self._data = 0
        self._ready_ff = False
        self._pressed_host_keys.clear()
        self.last_host_keysym = ""
        self.last_host_char = ""
        self.last_host_keycode = 0
        self.last_event = "nenhum"
        self.repeat_ignored = 0
        self.dropped = 0

    @staticmethod
    def _host_key_id(keycode: int, keysym: str) -> tuple[int, str]:
        return int(keycode), str(keysym)

    def key_down(
        self,
        code: int,
        *,
        keysym: str = "",
        char: str = "",
        keycode: int = 0,
    ) -> bool:
        """Seta DATA e KEY_READY para uma nova pressão física.

        Retorna False quando o evento é auto-repeat de uma tecla ainda
        pressionada.
        """
        key_id = self._host_key_id(keycode, keysym)

        self.last_host_keysym = keysym
        self.last_host_char = char
        self.last_host_keycode = int(keycode)

        if key_id in self._pressed_host_keys:
            self.last_event = "KEY REPEAT IGNORADO"
            self.repeat_ignored += 1
            return False

        self._pressed_host_keys.add(key_id)
        self._data = code & 0xFF
        self._ready_ff = True
        self.last_event = "KEY DOWN / FF SET"
        return True

    def key_up(
        self,
        *,
        keysym: str = "",
        char: str = "",
        keycode: int = 0,
    ) -> None:
        """Libera a tecla física sem modificar DATA nem KEY_READY."""
        self._pressed_host_keys.discard(
            self._host_key_id(keycode, keysym)
        )
        self.last_host_keysym = keysym
        self.last_host_char = char
        self.last_host_keycode = int(keycode)
        self.last_event = "KEY UP / DATA MANTIDO"

    def release_all(self) -> None:
        """Libera o estado físico das teclas sem alterar DATA ou KEY_READY."""
        self._pressed_host_keys.clear()

    def read_bus(self) -> int:
        """Retorna os oito bits KEYBOARD_B0..B7."""
        return self._data

    def key_rd_pulse(self) -> None:
        """/KEY_RD em LOW reseta somente o flip-flop READY."""
        self._ready_ff = False

    def cpu_read(self) -> int:
        """Retorna KEY_DATA e então aplica o pulso /KEY_RD."""
        value = self.read_bus()
        self.key_rd_pulse()
        return value

    # Compatibilidade com a interface.
    def read(self) -> int:
        return self.read_bus()

    @property
    def ready(self) -> bool:
        return self._ready_ff

    @property
    def current(self) -> Optional[int]:
        return self._data if self._data != 0 else None

    @property
    def queued(self) -> int:
        return 0

    @property
    def pressed_count(self) -> int:
        return len(self._pressed_host_keys)


class TerminalDevice:
    """Superfície de vídeo textual configurável com caracteres de 8x8.

    Os modos 80x60, 40x30 e 20x15 formam, respectivamente, superfícies
    640x480, 320x240 e 160x120. Este dispositivo NÃO mantém scrollback e a
    interface Tkinter NÃO possui barra de rolagem. Quando a BIOS quer rever
    texto antigo, ela precisa reconstruir a tela usando a própria RAM do
    WALL-8 e os registradores VIDEO_X/VIDEO_Y.

    ``pending_wrap`` modela o comportamento comum de terminais: escrever na
    coluna 39 preenche essa célula, mas a mudança para a linha seguinte só
    acontece quando chega outro caractere ou uma quebra de linha. Isso permite
    que a BIOS redesenhe a última linha completa sem provocar um scroll
    acidental da tela inteira.
    """

    def __init__(self, width: int = 80, height: int = 60) -> None:
        self.width = width
        self.height = height
        self.cells = [[" " for _ in range(width)] for _ in range(height)]
        self.x = 0
        self.y = 0
        self.pending_wrap = False
        self.cursor_visible = True
        self.dirty = True

    def reset(self) -> None:
        self.clear()
        self.cursor_visible = True

    def set_geometry(self, width: int, height: int) -> None:
        """Troca o modo textual e recria a superfície sem scrollback."""
        if width == self.width and height == self.height:
            return
        self.width = width
        self.height = height
        self.cells = [[" " for _ in range(width)] for _ in range(height)]
        self.x = 0
        self.y = 0
        self.pending_wrap = False
        self.dirty = True

    def clear(self) -> None:
        for row in self.cells:
            row[:] = [" "] * self.width
        self.x = 0
        self.y = 0
        self.pending_wrap = False
        self.dirty = True

    def home(self) -> None:
        self.x = 0
        self.y = 0
        self.pending_wrap = False
        self.dirty = True

    def clear_line(self) -> None:
        self.cells[self.y][:] = [" "] * self.width
        self.x = 0
        self.pending_wrap = False
        self.dirty = True

    def newline(self) -> None:
        self.x = 0
        self.pending_wrap = False
        self.y += 1
        if self.y >= self.height:
            # Este scroll é o comportamento físico da superfície de vídeo
            # ao receber uma nova linha no rodapé. Não é histórico do host.
            self.cells.pop(0)
            self.cells.append([" "] * self.width)
            self.y = self.height - 1
        self.dirty = True

    def put_char(self, value: int) -> None:
        value &= 0x7F

        if value in (0x0A, 0x0D):
            self.newline()
            return

        if value == 0x08:  # Backspace
            if self.pending_wrap:
                # A última escrita ocupou a coluna 39, mas ainda não houve
                # mudança de linha. Backspace remove exatamente essa célula.
                self.pending_wrap = False
                self.x = self.width - 1
            elif self.x > 0:
                self.x -= 1
            elif self.y > 0:
                self.y -= 1
                self.x = self.width - 1
            self.cells[self.y][self.x] = " "
            self.dirty = True
            return

        if value == 0x09:  # Tabulação do dispositivo de vídeo
            target = min(self.width, ((self.x // 4) + 1) * 4)
            while self.x < target:
                self.put_char(ord(" "))
            return

        if value == 0x0C:  # Form feed
            self.clear()
            return

        if value < 0x20:
            return

        if self.pending_wrap:
            self.newline()

        self.cells[self.y][self.x] = chr(value)
        if self.x >= self.width - 1:
            self.pending_wrap = True
        else:
            self.x += 1
        self.dirty = True

    def write_register(self, offset: int, value: int) -> None:
        offset &= 0xFF
        value &= 0xFF
        if offset == 0:
            self.put_char(value)
        elif offset == 1:
            if value == 0x10:
                self.set_geometry(80, 60)
            elif value == 0x11:
                self.set_geometry(40, 30)
            elif value == 0x12:
                self.set_geometry(20, 15)
            elif value == 0x00:
                self.clear()
            elif value == 0x01:
                self.home()
            elif value == 0x02:
                self.newline()
            elif value == 0x03:
                self.clear_line()
            elif value == 0x04:
                self.cursor_visible = False
                self.dirty = True
            elif value == 0x05:
                self.cursor_visible = True
                self.dirty = True
        elif offset == 2:
            self.x = min(value, self.width - 1)
            self.pending_wrap = False
            self.dirty = True
        elif offset == 3:
            self.y = min(value, self.height - 1)
            self.pending_wrap = False
            self.dirty = True

    def read_register(self, offset: int) -> int:
        offset &= 0xFF
        if offset == 0:
            return 0
        if offset == 1:
            return 0
        if offset == 2:
            return self.x
        if offset == 3:
            return self.y
        if offset == 4:
            return 0x01  # pronto
        return 0

    def text(self) -> str:
        """Retorna somente os caracteres atualmente visíveis."""
        return "\n".join("".join(row) for row in self.cells)


class VideoDevice:
    """Placa de video oficial: VRAM de 32 KiB e interface em F200..F204."""

    VRAM_SIZE = 0x8000
    MODE_TEXT = 0x11
    MODE_GFX_320 = 0x12
    MODE_GFX_160 = 0x13

    def __init__(self) -> None:
        self.vram = bytearray(self.VRAM_SIZE)
        self.mode = self.MODE_TEXT
        self.x = self.y = 0
        self.data_latch = self.read_latch = 0
        self.busy = False
        self.cursor_end = False
        self._pending: Optional[tuple[str, int, int, int]] = None
        self._frame_epoch = time.perf_counter()
        self.cursor_visible = True
        self.dirty = True
        self.reset()

    @property
    def width(self) -> int:
        return 40 if self.mode != self.MODE_GFX_160 else 20

    @property
    def height(self) -> int:
        if self.mode == self.MODE_TEXT:
            return 30
        return 240 if self.mode == self.MODE_GFX_320 else 120

    @property
    def logical_width(self) -> int:
        return 160 if self.mode == self.MODE_GFX_160 else 320

    @property
    def logical_height(self) -> int:
        return 120 if self.mode == self.MODE_GFX_160 else 240

    @property
    def bytes_per_line(self) -> int:
        return 20 if self.mode == self.MODE_GFX_160 else 40

    @property
    def used_size(self) -> int:
        return {self.MODE_TEXT: 1200, self.MODE_GFX_320: 9600,
                self.MODE_GFX_160: 2400}[self.mode]

    @property
    def cells(self) -> list[list[str]]:
        if self.mode != self.MODE_TEXT:
            return []
        return [[chr(v) for v in self.vram[y * 40:(y + 1) * 40]]
                for y in range(30)]

    def reset(self) -> None:
        self.vram[:] = b"\x20" * self.VRAM_SIZE
        self.mode = self.MODE_TEXT
        self.x = self.y = 0
        self.data_latch = self.read_latch = 0
        self.busy = False
        self.cursor_end = False
        self._pending = None
        self._frame_epoch = time.perf_counter()
        self.cursor_visible = True
        self.dirty = True

    def clear(self) -> None:
        fill = 0x20 if self.mode == self.MODE_TEXT else 0
        self.vram[:self.used_size] = bytes([fill]) * self.used_size
        self.x = self.y = 0
        self.cursor_end = False
        self.dirty = True

    def _address(self, x: int, y: int) -> int:
        return y * self.bytes_per_line + x

    def _increment(self) -> None:
        max_x = self.bytes_per_line - 1
        max_y = self.height - 1
        if self.x < max_x:
            self.x += 1
        elif self.y < max_y:
            self.x = 0
            self.y += 1
        else:
            # Em qualquer modo a ultima posicao permanece selecionada. A GPU
            # nao retorna automaticamente ao inicio da area utilizada.
            self.x = max_x
            self.y = max_y
            self.cursor_end = True

    def _newline(self) -> None:
        self.x = 0
        if self.y < 29:
            self.y += 1
        self.dirty = True

    def _put_text(self, value: int) -> None:
        if value in (0x0A, 0x0D):
            self._newline()
        elif value == 0x08:
            if self.x:
                self.x -= 1
            elif self.y:
                self.y -= 1
                self.x = 39
            self.vram[self.y * 40 + self.x] = 0x20
            self.dirty = True
        elif value >= 0x20:
            self.vram[self.y * 40 + self.x] = value
            self._increment()
            self.dirty = True

    def _select_mode(self, mode: int) -> None:
        self.mode = mode
        self.x = self.y = 0
        self.cursor_end = False
        self.dirty = True

    def set_geometry(self, width: int, height: int) -> None:
        """Traduz chamadas antigas da GUI para os tres modos oficiais."""
        mode = {(40, 30): self.MODE_TEXT, (320, 240): self.MODE_GFX_320,
                (160, 120): self.MODE_GFX_160}.get((width, height))
        if mode is not None and not self.busy:
            self._select_mode(mode)

    def _start(self, operation: str, value: int = 0) -> None:
        # O contrato declara invalida qualquer escrita durante BUSY; ela nunca
        # substitui silenciosamente a operacao que ja esta nos latches.
        if not self.busy:
            self.busy = True
            self._pending = (operation, self.x, self.y, value & 0xFF)

    def advance(self) -> None:
        """Executa uma operacao pendente no slot de VRAM seguinte."""
        if self._pending is None:
            return
        operation, x, y, value = self._pending
        if operation == "write":
            self.x, self.y = x, y
            if self.mode == self.MODE_TEXT:
                self._put_text(value)
            else:
                self.vram[self._address(x, y)] = value
                self._increment()
                self.dirty = True
        elif operation == "read":
            self.read_latch = self.vram[self._address(x, y)]
        else:
            self.clear()
        self._pending = None
        self.busy = False

    def write_register(self, offset: int, value: int) -> None:
        offset &= 0xFF
        value &= 0xFF
        if offset == 0:
            if not self.busy:
                self.data_latch = value
            self._start("write", value)
        elif offset == 1:
            if value in (self.MODE_TEXT, self.MODE_GFX_320,
                         self.MODE_GFX_160) and not self.busy:
                self._select_mode(value)
            elif value == 0x00:
                self._start("clear")
            elif value == 0x04 and self.mode == self.MODE_TEXT:
                self.cursor_visible = False
                self.dirty = True
            elif value == 0x05 and self.mode == self.MODE_TEXT:
                self.cursor_visible = True
                self.dirty = True
            elif value == 0x20:
                self._start("read")
        elif offset == 2 and not self.busy:
            self.x = value
            self.cursor_end = False
        elif offset == 3 and not self.busy:
            self.y = value
            self.cursor_end = False

    def read_register(self, offset: int) -> int:
        offset &= 0xFF
        if offset == 0:
            return self.read_latch
        if offset == 2:
            return self.x
        if offset == 3:
            return self.y
        if offset == 4:
            elapsed = time.perf_counter() - self._frame_epoch
            pixel = int((elapsed % (1.0 / 60.0)) * 60.0 * 800 * 525)
            hpos, vpos = pixel % 800, pixel // 800
            return (int(self.busy) | (int(vpos >= 480) << 1) |
                    (int(hpos >= 640) << 2) | ((int(elapsed * 60) & 1) << 3) |
                    (int(self.cursor_end) << 4))
        return 0

    def text(self) -> str:
        if self.mode != self.MODE_TEXT:
            return ""
        return "\n".join("".join(row) for row in self.cells)


class TimerDevice:
    """Flags latched de aproximadamente 1 ms e 500 ms."""

    def __init__(self) -> None:
        self.flag_1ms = False
        self.flag_500ms = False
        now = time.perf_counter()
        self._last_1ms = now
        self._last_500ms = now

    def reset(self) -> None:
        self.flag_1ms = False
        self.flag_500ms = False
        now = time.perf_counter()
        self._last_1ms = now
        self._last_500ms = now

    def update(self) -> None:
        now = time.perf_counter()
        if now - self._last_1ms >= 0.001:
            self.flag_1ms = True
            elapsed = now - self._last_1ms
            self._last_1ms += int(elapsed / 0.001) * 0.001
        if now - self._last_500ms >= 0.500:
            self.flag_500ms = True
            elapsed = now - self._last_500ms
            self._last_500ms += int(elapsed / 0.500) * 0.500

    def read(
        self,
        cart_connected: bool,
        key_ready: bool,
        video_connected: bool = True,
        keyboard_connected: bool = True,
    ) -> int:
        """Monta o registrador de status em $F300.

        bit 0: TIMER_1MS
        bit 1: TIMER_500MS
        bit 4: /CARD_DETECT  (0 quando conectado)
        bit 5: /VIDEO_DETECT (0 quando conectado)
        bit 6: /KEYBOARD_DETECT (0 quando conectado)
        bit 7: KEY_READY
        """
        self.update()
        value = 0
        value |= int(self.flag_1ms) << 0
        value |= int(self.flag_500ms) << 1
        value |= int(not cart_connected) << 4
        value |= int(not video_connected) << 5
        value |= int(not keyboard_connected) << 6
        value |= int(key_ready) << 7
        return value

    def clear(self) -> None:
        self.flag_1ms = False
        self.flag_500ms = False
        now = time.perf_counter()
        self._last_1ms = now
        self._last_500ms = now


class SoundDevice:
    """Emulação opcional do tone/noise do esquema usando pygame."""

    RESISTORS = (27_000, 24_000, 22_000, 20_000, 18_000, 16_000, 14_000, 13_000)
    R_FIXED = 1_000
    C_TIMING = 100e-9
    SAMPLE_RATE = 44_100

    def __init__(self, enabled: bool = True) -> None:
        self.config = 0
        self.available = False
        self.error = ""
        self._pygame = None
        self._channel = None
        self._sound = None
        if enabled:
            self._init_audio()

    @classmethod
    def oscillator_frequency(cls, select: int) -> float:
        r2 = cls.RESISTORS[select & 7]
        return 1.44 / ((cls.R_FIXED + 2 * r2) * cls.C_TIMING)

    def _init_audio(self) -> None:
        try:
            os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
            import pygame  # type: ignore

            pygame.mixer.pre_init(self.SAMPLE_RATE, size=-16, channels=1, buffer=512)
            if not pygame.mixer.get_init():
                pygame.mixer.init()
            self._pygame = pygame
            self._channel = pygame.mixer.Channel(0)
            self.available = True
        except Exception as exc:  # pygame é opcional
            self.available = False
            self.error = str(exc)

    def reset(self) -> None:
        self.write(0)

    @property
    def noise_enabled(self) -> bool:
        return bool(self.config & 0x01)

    @property
    def tone_enabled(self) -> bool:
        return bool(self.config & 0x02)

    @property
    def tone_select(self) -> int:
        return (self.config >> 2) & 0x07

    @property
    def noise_select(self) -> int:
        return (self.config >> 5) & 0x07

    @property
    def tone_frequency(self) -> float:
        return self.oscillator_frequency(self.tone_select)

    @property
    def noise_frequency(self) -> float:
        return self.oscillator_frequency(self.noise_select)

    def describe(self) -> str:
        tone = f"ON {self.tone_frequency:6.1f} Hz" if self.tone_enabled else "OFF"
        noise = f"ON {self.noise_frequency:6.1f} Hz" if self.noise_enabled else "OFF"
        backend = "pygame" if self.available else "sem áudio"
        return f"CFG=${self.config:02X}  Tone: {tone}  Noise: {noise}  [{backend}]"

    def write(self, value: int) -> None:
        value &= 0xFF
        if value == self.config and self._sound is not None:
            return
        self.config = value
        if not self.available:
            return
        self._rebuild_sound()

    @staticmethod
    def _lfsr_step(state: int) -> tuple[int, int]:
        """
        Taps extraídos do esquema enviado:
        feedback = NOT(Q3) XOR Q4 XOR Q5 XOR Q7.
        O 74HC164 desloca Q0->Q1 ... e recebe feedback em Q0.
        """
        q3 = (state >> 3) & 1
        q4 = (state >> 4) & 1
        q5 = (state >> 5) & 1
        q7 = (state >> 7) & 1
        feedback = (1 ^ q3 ^ q4 ^ q5 ^ q7) & 1
        new_state = ((state << 1) & 0xFE) | feedback
        return new_state, feedback

    def _rebuild_sound(self) -> None:
        assert self._pygame is not None
        assert self._channel is not None
        self._channel.stop()
        self._sound = None

        if not self.tone_enabled and not self.noise_enabled:
            return

        duration = 0.50
        count = int(self.SAMPLE_RATE * duration)
        samples = array("h")

        tone_f = self.tone_frequency
        noise_f = self.noise_frequency
        tone_phase = 0.0
        noise_phase = 0.0
        lfsr = 0x00
        noise_bit = 0

        tone_step = tone_f / self.SAMPLE_RATE
        noise_step = noise_f / self.SAMPLE_RATE

        for _ in range(count):
            sample = 0
            if self.tone_enabled:
                tone_phase += tone_step
                if tone_phase >= 1.0:
                    tone_phase -= 1.0
                sample += 6_000 if tone_phase < 0.5 else -6_000

            if self.noise_enabled:
                noise_phase += noise_step
                while noise_phase >= 1.0:
                    noise_phase -= 1.0
                    lfsr, noise_bit = self._lfsr_step(lfsr)
                sample += 4_000 if noise_bit else -4_000

            sample = max(-32768, min(32767, sample))
            samples.append(sample)

        if sys.byteorder != "little":
            samples.byteswap()
        self._sound = self._pygame.mixer.Sound(buffer=samples.tobytes())
        self._channel.play(self._sound, loops=-1)

    def close(self) -> None:
        if self.available and self._channel is not None:
            self._channel.stop()


class Wall8Bus:
    def __init__(self, audio_enabled: bool = True) -> None:
        self.ram = bytearray(RAM_SIZE)

        # As duas 27C512 são mantidas como imagens físicas completas de 64 KiB.
        # O endereço da CPU vai diretamente para A0..A15; o decode só controla /CE.
        self.bios = bytearray([0xFF] * EPROM_27C512_SIZE)
        self.cart = bytearray([0xFF] * EPROM_27C512_SIZE)
        self.cart_connected = False
        self.video_connected = True
        self.keyboard_connected = True
        self.cart_path: Optional[Path] = None
        self.bios_path: Optional[Path] = None
        self.bios_load_mode = "vazia"
        self.cart_load_mode = "vazio"

        self.keyboard = KeyboardDevice()
        self.video = VideoDevice()
        self.timer = TimerDevice()
        self.sound = SoundDevice(audio_enabled)

        self.display_low = 0
        self.display_high = 0
        self.cpu_cfg = 0x00
        self.periph_cfg = 0x00
        self.boot_overlay = True

        self.last_address = 0
        self.last_data = 0
        self.last_access = "-"

    def reset(self, clear_ram: bool = True) -> None:
        if clear_ram:
            self.ram[:] = b"\x00" * RAM_SIZE
        self.keyboard.reset()
        self.video.reset()
        self.timer.reset()
        self.sound.reset()
        self.display_low = 0
        self.display_high = 0
        self.cpu_cfg = 0x00
        self.periph_cfg = 0x00
        self.boot_overlay = True
        self.last_address = 0
        self.last_data = 0
        self.last_access = "RESET"

    def load_bios_bytes(self, raw: bytes, offset: int | None = None) -> None:
        """Carrega a imagem física da 27C512 usada como BIOS.

        A EPROM possui 64 KiB e recebe diretamente A0..A15 do barramento.
        Portanto, um byte armazenado no offset N do arquivo corresponde ao
        endereço físico N da EPROM.

        Regras:
        - Arquivo de 64 KiB: copiado exatamente para 0000h..FFFFh.
        - Arquivo parcial sem offset: copiado exatamente a partir de 0000h.
        - Arquivo parcial com offset: copiado exatamente no offset informado.

        Nenhum bloco é duplicado automaticamente. Para colocar código em
        8000h, use uma imagem completa ou --bios-offset 0x8000.
        """
        if not raw:
            raise ValueError("Arquivo de BIOS vazio")
        if len(raw) > EPROM_27C512_SIZE:
            raise ValueError(
                f"BIOS possui {len(raw)} bytes; uma 27C512 comporta no máximo "
                f"{EPROM_27C512_SIZE} bytes"
            )

        if offset is None:
            offset = 0

        if not 0 <= offset < EPROM_27C512_SIZE:
            raise ValueError("Offset da BIOS fora de 0000h..FFFFh")
        if offset + len(raw) > EPROM_27C512_SIZE:
            raise ValueError("Arquivo de BIOS ultrapassa o fim da 27C512")

        self.bios[:] = b"\xFF" * EPROM_27C512_SIZE
        self.bios[offset:offset + len(raw)] = raw

        if len(raw) == EPROM_27C512_SIZE and offset == 0:
            self.bios_load_mode = "imagem física completa de 64 KiB"
        else:
            self.bios_load_mode = (
                f"imagem física parcial de {len(raw)} bytes em ${offset:04X}"
            )

    def load_bios_file(self, path: str | Path, offset: int | None = None) -> None:
        p = Path(path)
        self.load_bios_bytes(p.read_bytes(), offset)
        self.bios_path = p

    def load_cart_bytes(self, raw: bytes, offset: int | None = None) -> None:
        """Carrega a imagem física da 27C512 do cartucho.

        Arquivos completos de 64 KiB preservam todos os endereços físicos.
        Para conveniência, arquivos de até 20 KiB sem offset são considerados
        o conteúdo lógico da janela A000h..EFFFh e são colocados em A000h.
        """
        if not raw:
            raise ValueError("Arquivo de cartucho vazio")
        if len(raw) > EPROM_27C512_SIZE:
            raise ValueError(
                f"Cartucho possui {len(raw)} bytes; uma 27C512 comporta no máximo "
                f"{EPROM_27C512_SIZE} bytes"
            )

        self.cart[:] = b"\xFF" * EPROM_27C512_SIZE

        if offset is not None:
            if not 0 <= offset < EPROM_27C512_SIZE:
                raise ValueError("Offset do cartucho fora de 0000h..FFFFh")
            if offset + len(raw) > EPROM_27C512_SIZE:
                raise ValueError("Arquivo de cartucho ultrapassa o fim da 27C512")
            self.cart[offset:offset + len(raw)] = raw
            self.cart_load_mode = f"{len(raw)} bytes em ${offset:04X}"
        elif len(raw) == EPROM_27C512_SIZE:
            self.cart[:] = raw
            self.cart_load_mode = "imagem física completa de 64 KiB"
        elif len(raw) <= CART_WINDOW_SIZE:
            self.cart[CART_START:CART_START + len(raw)] = raw
            self.cart_load_mode = (
                f"imagem lógica de {len(raw)} bytes colocada em $A000"
            )
        else:
            self.cart[:len(raw)] = raw
            self.cart_load_mode = f"imagem física parcial de {len(raw)} bytes em $0000"

        self.cart_connected = True

    def load_cart_file(self, path: str | Path, offset: int | None = None) -> None:
        p = Path(path)
        self.load_cart_bytes(p.read_bytes(), offset)
        self.cart_path = p

    def eject_cart(self) -> None:
        self.cart_connected = False
        self.cart_path = None
        self.cart[:] = b"\xFF" * EPROM_27C512_SIZE
        self.cart_load_mode = "vazio"

    def save_cart_file(self, path: str | Path, full_image: bool = True) -> None:
        if full_image:
            Path(path).write_bytes(bytes(self.cart))
        else:
            Path(path).write_bytes(bytes(self.cart[CART_START:CART_END + 1]))

    @staticmethod
    def _normalize_io(address: int) -> int:
        # A11 não entra no 74HC138: F8xx..FFxx espelham F0xx..F7xx.
        if address >= 0xF800:
            return address - 0x0800
        return address

    def peek8(self, address: int) -> int:
        return self.read8(address, side_effects=False)

    def read8(self, address: int, side_effects: bool = True) -> int:
        address &= 0xFFFF
        self.video.advance()

        # Overlay: com /BOOT_ROM_EN ativo, a BIOS responde em toda a metade baixa
        # 0000h..7FFFh. A0..A15 seguem diretamente o barramento, então não
        # existe remapeamento: o endereço físico da EPROM é o próprio endereço.
        if self.boot_overlay and RAM_START <= address <= RAM_END:
            value = self.bios[address]
        elif RAM_START <= address <= RAM_END:
            value = self.ram[address]
        elif BIOS_START <= address <= BIOS_END:
            value = self.bios[address]
        elif CART_START <= address <= CART_END:
            value = self.cart[address] if self.cart_connected else 0xFF
        elif IO_START <= address <= IO_END:
            value = self._read_io(address, side_effects)
        else:
            value = 0xFF

        if side_effects:
            self.last_address = address
            self.last_data = value
            self.last_access = "READ"
        return value & 0xFF

    def write8(self, address: int, value: int) -> None:
        address &= 0xFFFF
        value &= 0xFF
        self.video.advance()

        if self.boot_overlay and RAM_START <= address <= RAM_END:
            # A BIOS está selecionada e a 62256 fica desabilitada em toda
            # a região 0000h..7FFFh.
            pass
        elif RAM_START <= address <= RAM_END:
            self.ram[address] = value
        elif BIOS_START <= address <= BIOS_END:
            pass  # EPROM
        elif CART_START <= address <= CART_END:
            if self.cart_connected:
                # O conector recebe /WE. Em um cartucho 27C512 real a EPROM não
                # gravará em operação normal, mas este backing store permite
                # emular cartuchos RAM/Flash usando a mesma interface.
                self.cart[address] = value
        elif IO_START <= address <= IO_END:
            self._write_io(address, value)

        self.last_address = address
        self.last_data = value
        self.last_access = "WRITE"

    def _read_io(self, address: int, side_effects: bool) -> int:
        address = self._normalize_io(address)
        page = (address >> 8) & 0x07
        offset = address & 0xFF

        if page == 0:  # KEY_DATA, oito bits
            # A leitura de $F000 habilita o 74LS541. Depois de a CPU capturar
            # DATA, /KEY_RD em LOW reseta somente o flip-flop KEY_READY.
            if side_effects:
                return self.keyboard.cpu_read()
            return self.keyboard.read_bus()
        if page == 1:  # display
            if offset == 0:
                return self.display_low
            if offset == 1:
                return self.display_high
            return 0
        if page == 2:  # vídeo/GPU
            return self.video.read_register(offset)
        if page == 3:  # status: timer/detects/KEY_READY
            return self.timer.read(
                self.cart_connected,
                self.keyboard.ready,
                video_connected=self.video_connected,
                keyboard_connected=self.keyboard_connected,
            )
        if page == 4:  # som
            return self.sound.config
        if page == 5:  # GPIO/configuração
            if offset == 0:
                return self.cpu_cfg
            if offset == 1:
                return self.periph_cfg
            return 0
        return 0x00

    def _write_io(self, address: int, value: int) -> None:
        address = self._normalize_io(address)
        page = (address >> 8) & 0x07
        offset = address & 0xFF

        if page == 0:
            # O conector do teclado não recebe /MEMORY_WE.
            # Escritas na página do teclado são ignoradas.
            pass
        elif page == 1:
            if offset == 0:
                self.display_low = value
            elif offset == 1:
                self.display_high = value
        elif page == 2:
            self.video.write_register(offset, value)
        elif page == 3:
            self.timer.clear()
        elif page == 4:
            self.sound.write(value)
        elif page == 5:
            if offset == 0:
                self.cpu_cfg = value
                # /BOOT_ROM_EN: 0 mantém BIOS em 0000h..7FFFh; 1 libera a RAM.
                self.boot_overlay = not bool(value & 0x01)
            elif offset == 1:
                self.periph_cfg = value

    @property
    def display_value(self) -> int:
        return self.display_low | (self.display_high << 8)


# =============================================================================
# CPU
# =============================================================================


@dataclass
class CPUState:
    a: int = 0
    b: int = 0
    pc: int = 0
    sp: int = 0
    ptr: int = 0
    mar: int = 0
    addr: int = 0
    tmp: int = 0
    ir: int = 0
    dbus: int = 0
    alu: int = 0
    z: int = 0
    c: int = 0
    n: int = 0
    v: int = 0
    halted: bool = False
    cycles: int = 0
    instructions: int = 0


class Wall8CPU:
    def __init__(self, bus: Wall8Bus) -> None:
        self.bus = bus
        self.s = CPUState()
        self.last_pc = 0
        self.last_text = "RESET"

    def reset(self) -> None:
        self.s = CPUState()
        self.last_pc = 0
        self.last_text = "RESET"

    def _read(self, address: int) -> int:
        self.s.mar = address & 0xFFFF
        value = self.bus.read8(address)
        self.s.dbus = value
        return value

    def _write(self, address: int, value: int) -> None:
        self.s.mar = address & 0xFFFF
        self.s.dbus = value & 0xFF
        self.bus.write8(address, value)

    def _fetch8(self) -> int:
        value = self._read(self.s.pc)
        self.s.pc = (self.s.pc + 1) & 0xFFFF
        return value

    def _fetch16(self) -> int:
        low = self._fetch8()
        high = self._fetch8()
        value = low | (high << 8)
        self.s.addr = value
        return value

    def _flags(self, result: int, carry: int = 0, overflow: int = 0) -> None:
        result &= 0xFF
        self.s.alu = result
        self.s.z = int(result == 0)
        self.s.c = carry & 1
        self.s.n = (result >> 7) & 1
        self.s.v = overflow & 1

    @staticmethod
    def _add8(x: int, y: int) -> tuple[int, int, int]:
        total = x + y
        result = total & 0xFF
        carry = int(total > 0xFF)
        overflow = int((~(x ^ y) & (x ^ result) & 0x80) != 0)
        return result, carry, overflow

    @staticmethod
    def _sub8(x: int, y: int) -> tuple[int, int, int]:
        result = (x - y) & 0xFF
        carry = int(x >= y)  # carry = NOT borrow
        overflow = int(((x ^ y) & (x ^ result) & 0x80) != 0)
        return result, carry, overflow

    @staticmethod
    def _inc8(x: int) -> tuple[int, int, int]:
        result = (x + 1) & 0xFF
        return result, int(x == 0xFF), int(x == 0x7F)

    @staticmethod
    def _dec8(x: int) -> tuple[int, int, int]:
        result = (x - 1) & 0xFF
        return result, int(x != 0x00), int(x == 0x80)

    def _push8(self, value: int) -> None:
        self.s.sp = (self.s.sp - 1) & 0xFFFF
        self._write(self.s.sp, value)

    def _pop8(self) -> int:
        value = self._read(self.s.sp)
        self.s.sp = (self.s.sp + 1) & 0xFFFF
        return value

    def step(self) -> int:
        if self.s.halted:
            return 0

        self.last_pc = self.s.pc
        opcode = self._fetch8()
        self.s.ir = opcode

        if opcode not in CYCLES:
            raise IllegalOpcode(opcode, self.last_pc)

        # Sistema
        if opcode == NOP:
            pass
        elif opcode == HLT:
            self.s.halted = True

        # Load/store/MOV
        elif opcode == LDA_IMM:
            self.s.a = self._fetch8()
        elif opcode == LDB_IMM:
            self.s.b = self._fetch8()
        elif opcode == LDA_ABS:
            self.s.a = self._read(self._fetch16())
        elif opcode == LDB_ABS:
            self.s.b = self._read(self._fetch16())
        elif opcode == STA_ABS:
            self._write(self._fetch16(), self.s.a)
        elif opcode == STB_ABS:
            self._write(self._fetch16(), self.s.b)
        elif opcode == STI:
            address = self._fetch16()
            self.s.tmp = self._fetch8()
            self._write(address, self.s.tmp)
        elif opcode == MOV_A_B:
            self.s.a = self.s.b
            self.s.dbus = self.s.b
        elif opcode == MOV_B_A:
            self.s.b = self.s.a
            self.s.dbus = self.s.a

        # PTR
        elif opcode == LDPTR_ABS:
            self.s.ptr = self._fetch16()
        elif opcode == INC_PTR:
            self.s.ptr = (self.s.ptr + 1) & 0xFFFF
        elif opcode == DEC_PTR:
            self.s.ptr = (self.s.ptr - 1) & 0xFFFF
        elif opcode == LDA_PTR:
            self.s.a = self._read(self.s.ptr)
        elif opcode == LDB_PTR:
            self.s.b = self._read(self.s.ptr)
        elif opcode == STA_PTR:
            self._write(self.s.ptr, self.s.a)
        elif opcode == STB_PTR:
            self._write(self.s.ptr, self.s.b)
        elif opcode == LDA_PTR_INC:
            self.s.a = self._read(self.s.ptr)
            self.s.ptr = (self.s.ptr + 1) & 0xFFFF
        elif opcode == LDB_PTR_INC:
            self.s.b = self._read(self.s.ptr)
            self.s.ptr = (self.s.ptr + 1) & 0xFFFF
        elif opcode == STA_PTR_INC:
            self._write(self.s.ptr, self.s.a)
            self.s.ptr = (self.s.ptr + 1) & 0xFFFF
        elif opcode == STB_PTR_INC:
            self._write(self.s.ptr, self.s.b)
            self.s.ptr = (self.s.ptr + 1) & 0xFFFF

        # ALU aritmética
        elif opcode == ADD_A_B:
            self.s.a, c, v = self._add8(self.s.a, self.s.b)
            self._flags(self.s.a, c, v)
        elif opcode == ADD_B_A:
            self.s.b, c, v = self._add8(self.s.b, self.s.a)
            self._flags(self.s.b, c, v)
        elif opcode == SUB_A_B:
            self.s.a, c, v = self._sub8(self.s.a, self.s.b)
            self._flags(self.s.a, c, v)
        elif opcode == SUB_B_A:
            self.s.b, c, v = self._sub8(self.s.b, self.s.a)
            self._flags(self.s.b, c, v)

        # ALU lógica — seletor de C e V entrega zero nessas operações.
        elif opcode == AND_A_B:
            self.s.a &= self.s.b
            self._flags(self.s.a)
        elif opcode == AND_B_A:
            self.s.b &= self.s.a
            self._flags(self.s.b)
        elif opcode == OR_A_B:
            self.s.a |= self.s.b
            self._flags(self.s.a)
        elif opcode == OR_B_A:
            self.s.b |= self.s.a
            self._flags(self.s.b)
        elif opcode == XOR_A_B:
            self.s.a ^= self.s.b
            self._flags(self.s.a)
        elif opcode == XOR_B_A:
            self.s.b ^= self.s.a
            self._flags(self.s.b)
        elif opcode == NOT_A:
            self.s.a = (~self.s.a) & 0xFF
            self._flags(self.s.a)
        elif opcode == NOT_B:
            self.s.b = (~self.s.b) & 0xFF
            self._flags(self.s.b)

        # Shifts
        elif opcode == SHL_A:
            old = self.s.a
            self.s.a = (old << 1) & 0xFF
            self._flags(self.s.a, (old >> 7) & 1, 0)
        elif opcode == SHR_A:
            old = self.s.a
            self.s.a = old >> 1
            self._flags(self.s.a, old & 1, 0)
        elif opcode == SHL_B:
            old = self.s.b
            self.s.b = (old << 1) & 0xFF
            self._flags(self.s.b, (old >> 7) & 1, 0)
        elif opcode == SHR_B:
            old = self.s.b
            self.s.b = old >> 1
            self._flags(self.s.b, old & 1, 0)

        # CMP/INC/DEC/CLR
        elif opcode == CMP_A_B:
            result, c, v = self._sub8(self.s.a, self.s.b)
            self._flags(result, c, v)
        elif opcode == CMP_B_A:
            result, c, v = self._sub8(self.s.b, self.s.a)
            self._flags(result, c, v)
        elif opcode == INC_A:
            self.s.a, c, v = self._inc8(self.s.a)
            self._flags(self.s.a, c, v)
        elif opcode == DEC_A:
            self.s.a, c, v = self._dec8(self.s.a)
            self._flags(self.s.a, c, v)
        elif opcode == INC_B:
            self.s.b, c, v = self._inc8(self.s.b)
            self._flags(self.s.b, c, v)
        elif opcode == DEC_B:
            self.s.b, c, v = self._dec8(self.s.b)
            self._flags(self.s.b, c, v)
        elif opcode == CLR_A:
            self.s.a = 0
            self._flags(0)
        elif opcode == CLR_B:
            self.s.b = 0
            self._flags(0)

        # ALU com valor imediato. No hardware, TMP preserva o registrador
        # usado temporariamente como a outra entrada da ALU. O emulador
        # mantém o mesmo estado arquitetural final e registra em TMP o valor
        # que foi preservado pelo microcódigo.
        elif opcode == ADD_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self.s.a, c, v = self._add8(self.s.a, immediate)
            self._flags(self.s.a, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == ADD_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self.s.b, c, v = self._add8(self.s.b, immediate)
            self._flags(self.s.b, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == SUB_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self.s.a, c, v = self._sub8(self.s.a, immediate)
            self._flags(self.s.a, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == SUB_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self.s.b, c, v = self._sub8(self.s.b, immediate)
            self._flags(self.s.b, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == AND_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self.s.a &= immediate
            self._flags(self.s.a)
            self.s.dbus = self.s.tmp
        elif opcode == AND_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self.s.b &= immediate
            self._flags(self.s.b)
            self.s.dbus = self.s.tmp
        elif opcode == OR_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self.s.a |= immediate
            self._flags(self.s.a)
            self.s.dbus = self.s.tmp
        elif opcode == OR_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self.s.b |= immediate
            self._flags(self.s.b)
            self.s.dbus = self.s.tmp
        elif opcode == XOR_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self.s.a ^= immediate
            self._flags(self.s.a)
            self.s.dbus = self.s.tmp
        elif opcode == XOR_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self.s.b ^= immediate
            self._flags(self.s.b)
            self.s.dbus = self.s.tmp
        elif opcode == CMP_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            result, c, v = self._sub8(self.s.a, immediate)
            self._flags(result, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == CMP_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            result, c, v = self._sub8(self.s.b, immediate)
            self._flags(result, c, v)
            self.s.dbus = self.s.tmp
        elif opcode == TEST_A_IMM:
            self.s.tmp = self.s.b
            immediate = self._fetch8()
            self._flags(self.s.a & immediate)
            self.s.dbus = self.s.tmp
        elif opcode == TEST_B_IMM:
            self.s.tmp = self.s.a
            immediate = self._fetch8()
            self._flags(self.s.b & immediate)
            self.s.dbus = self.s.tmp

        # Saltos — os dois bytes são sempre consumidos.
        elif opcode == JMP_ABS:
            self.s.pc = self._fetch16()
        elif opcode in {JZ_ABS, JNZ_ABS, JC_ABS, JNC_ABS, JN_ABS, JP_ABS, JV_ABS, JNV_ABS}:
            target = self._fetch16()
            take = {
                JZ_ABS: self.s.z == 1,
                JNZ_ABS: self.s.z == 0,
                JC_ABS: self.s.c == 1,
                JNC_ABS: self.s.c == 0,
                JN_ABS: self.s.n == 1,
                JP_ABS: self.s.n == 0,
                JV_ABS: self.s.v == 1,
                JNV_ABS: self.s.v == 0,
            }[opcode]
            if take:
                self.s.pc = target

        # Stack/CALL/RET
        elif opcode == CALL_ABS:
            target = self._fetch16()
            return_address = self.s.pc
            self._push8((return_address >> 8) & 0xFF)  # high primeiro
            self._push8(return_address & 0xFF)         # low no topo
            self.s.pc = target
        elif opcode == RET:
            low = self._pop8()
            high = self._pop8()
            self.s.addr = low | (high << 8)
            self.s.pc = self.s.addr
        elif opcode == PUSH_A:
            self._push8(self.s.a)
        elif opcode == PUSH_B:
            self._push8(self.s.b)
        elif opcode == POP_A:
            self.s.a = self._pop8()
        elif opcode == POP_B:
            self.s.b = self._pop8()
        elif opcode == LDSP_ABS:
            self.s.sp = self._fetch16()

        cycles = CYCLES[opcode]
        self.s.cycles += cycles
        self.s.instructions += 1
        self.last_text, _ = self.disassemble(self.last_pc)
        return cycles

    def disassemble(self, address: int) -> tuple[str, int]:
        address &= 0xFFFF
        op = self.bus.peek8(address)
        name = OP_NAMES.get(op, f"DB ${op:02X}")
        if op in IMM_OPS:
            value = self.bus.peek8(address + 1)
            return f"{name}${value:02X}", 2
        if op in ABS_OPS:
            low = self.bus.peek8(address + 1)
            high = self.bus.peek8(address + 2)
            target = low | (high << 8)
            return f"{name} ${target:04X}", 3
        if op == STI:
            low = self.bus.peek8(address + 1)
            high = self.bus.peek8(address + 2)
            value = self.bus.peek8(address + 3)
            target = low | (high << 8)
            return f"STI ${target:04X}, #${value:02X}", 4
        return name, 1


# =============================================================================
# BIOS demonstrativa embutida
# =============================================================================


def build_demo_bios() -> bytes:
    """BIOS mínima que reproduz o boot físico do WALL-8.

    0000h contém apenas o stub inicial executado enquanto o overlay está ativo.
    O stub salta para 8000h, que é a janela fixa da BIOS. Já em 8000h, o código
    desliga o overlay e libera a RAM em 0000h..7FFFh.
    """
    image = bytearray([0xFF] * EPROM_27C512_SIZE)

    # Stub físico no início da 27C512.
    image[0x0000:0x0003] = bytes([JMP_ABS, 0x00, 0x80])

    code = bytearray()
    labels: dict[str, int] = {}
    patches: list[tuple[int, str]] = []

    def emit(*values: int) -> None:
        code.extend(v & 0xFF for v in values)

    def label(name: str) -> None:
        labels[name] = BIOS_START + len(code)

    def jump(opcode: int, name: str) -> None:
        emit(opcode, 0, 0)
        patches.append((len(code) - 2, name))

    # Agora o PC já está na janela fixa 8000h..9FFFh.
    emit(LDA_IMM, 0x01)
    emit(STA_ABS, CPU_CFG & 0xFF, CPU_CFG >> 8)  # desliga overlay
    emit(LDSP_ABS, 0xFF, 0x7F)
    emit(STI, VIDEO_BASE & 0xFF, VIDEO_BASE >> 8, 0x0C)

    banner = (
        "WALL-8 EMULATOR\r\n"
        "BIOS demonstrativa ativa\r\n"
        "Digite no terminal:\r\n> "
    )
    for ch in banner.encode("ascii"):
        emit(LDA_IMM, ch)
        emit(STA_ABS, VIDEO_BASE & 0xFF, VIDEO_BASE >> 8)

    label("poll")
    # KEY_READY está em TIMER_STATUS bit 7.
    emit(LDA_ABS, TIMER_STATUS & 0xFF, TIMER_STATUS >> 8)
    emit(SHL_A)                       # bit 7 antigo vai para C
    jump(JNC_ABS, "poll")
    # A leitura de KEY_DATA gera /KEY_RD e limpa somente KEY_READY.
    emit(LDA_ABS, KEY_BASE & 0xFF, KEY_BASE >> 8)
    emit(STA_ABS, VIDEO_BASE & 0xFF, VIDEO_BASE >> 8)
    jump(JMP_ABS, "poll")

    for patch_offset, name in patches:
        target = labels[name]
        code[patch_offset] = target & 0xFF
        code[patch_offset + 1] = (target >> 8) & 0xFF

    if len(code) > BIOS_WINDOW_SIZE:
        raise AssertionError("BIOS demo excedeu a janela fixa de 8 KiB")

    image[BIOS_START:BIOS_START + len(code)] = code
    return bytes(image)


# =============================================================================
# Interface gráfica
# =============================================================================


class Wall8App:
    SPEEDS = {
        "1 kHz": 1_000,
        "10 kHz": 10_000,
        "100 kHz": 100_000,
        "1 MHz": 1_000_000,
        "4 MHz": 4_000_000,
    }

    def __init__(self, bus: Wall8Bus, cpu: Wall8CPU) -> None:
        import tkinter as tk
        import tkinter.font as tkfont
        from tkinter import filedialog, messagebox, simpledialog, ttk

        self.tk = tk
        self.tkfont = tkfont
        self.ttk = ttk
        self.filedialog = filedialog
        self.messagebox = messagebox
        self.simpledialog = simpledialog

        self.bus = bus
        self.cpu = cpu
        self.running = False
        self._last_tick = time.perf_counter()
        self._last_rate_time = self._last_tick
        self._last_rate_cycles = 0
        self._actual_hz = 0.0
        self._frame_counter = 0
        self.custom_clock_hz = 1_000_000
        self._cycle_credit = 0.0
        self._last_ui_time = self._last_tick
        self.keyboard_capture_active = False
        self.bios_dialog_dir: Optional[Path] = None
        self.cart_dialog_dir: Optional[Path] = None

        self.root = tk.Tk()
        self.root.title("WALL-8 Emulator")
        self.root.minsize(1250, 760)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self._build_ui()
        self._update_ui(force=True)
        self.root.after_idle(self._fit_window_to_fixed_video)
        self.root.after(10, self._tick)

    def _build_ui(self) -> None:
        tk = self.tk
        ttk = self.ttk

        toolbar = ttk.Frame(self.root, padding=6)
        toolbar.pack(fill="x")

        ttk.Button(toolbar, text="Carregar BIOS", command=self.load_bios).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Carregar Cart", command=self.load_cart).pack(side="left", padx=2)
        ttk.Button(toolbar, text="Salvar Cart", command=self.save_cart).pack(side="left", padx=2)
        ttk.Separator(toolbar, orient="vertical").pack(side="left", fill="y", padx=6)
        ttk.Button(toolbar, text="Reset", command=self.reset).pack(side="left", padx=2)
        self.run_button = ttk.Button(toolbar, text="Run", command=self.toggle_run)
        self.run_button.pack(side="left", padx=2)
        ttk.Button(toolbar, text="Step", command=self.step_once).pack(side="left", padx=2)

        ttk.Label(toolbar, text="Clock:").pack(side="left", padx=(16, 4))
        self.speed_var = tk.StringVar(value="1 MHz")
        speed = ttk.Combobox(
            toolbar,
            textvariable=self.speed_var,
            values=(*self.SPEEDS, "Personalizado"),
            width=12,
            state="readonly",
        )
        speed.pack(side="left")
        self.custom_clock_var = tk.StringVar(value="1000000")
        self.custom_clock_entry = ttk.Entry(
            toolbar, textvariable=self.custom_clock_var, width=9
        )
        self.custom_clock_entry.pack(side="left", padx=(4, 2))
        self.custom_clock_unit_var = tk.StringVar(value="Hz")
        custom_clock_unit = ttk.Combobox(
            toolbar,
            textvariable=self.custom_clock_unit_var,
            values=("Hz", "kHz", "MHz"),
            width=5,
            state="readonly",
        )
        custom_clock_unit.pack(side="left")
        custom_clock_unit.bind("<<ComboboxSelected>>", self._use_custom_clock)
        self.custom_clock_entry.bind("<Return>", self._use_custom_clock)
        self.custom_clock_entry.bind("<FocusIn>", self._use_custom_clock)
        self.custom_clock_entry.bind("<FocusOut>", self._use_custom_clock)

        ttk.Label(toolbar, text="Resolução:").pack(side="left", padx=(14, 4))
        self.video_resolution_var = tk.StringVar(value="Texto 40×30")
        video_resolution = ttk.Combobox(
            toolbar,
            textvariable=self.video_resolution_var,
            values=("Texto 40×30", "GFX 320×240", "GFX 160×120"),
            width=14,
            state="readonly",
        )
        video_resolution.pack(side="left")
        video_resolution.bind(
            "<<ComboboxSelected>>",
            self._set_video_resolution,
        )

        # Zoom exclusivamente inteiro: replica cada pixel lógico sem alterar
        # a resolução 640×480 nem reagir ao redimensionamento da janela.
        ttk.Label(toolbar, text="Zoom de pixels:").pack(
            side="left",
            padx=(14, 4),
        )
        self.video_pixel_scale_var = tk.StringVar(value="1×")
        video_pixel_scale = ttk.Combobox(
            toolbar,
            textvariable=self.video_pixel_scale_var,
            values=("1×", "2×", "4×"),
            width=4,
            state="readonly",
        )
        video_pixel_scale.pack(side="left")
        video_pixel_scale.bind(
            "<<ComboboxSelected>>",
            self._set_video_pixel_scale,
        )
        ttk.Separator(toolbar, orient="vertical").pack(side="left", fill="y", padx=8)
        self.cart_connected_var = tk.BooleanVar(value=self.bus.cart_connected)
        ttk.Checkbutton(
            toolbar,
            text="Cartucho conectado",
            variable=self.cart_connected_var,
            command=self._set_device_connections,
        ).pack(side="left", padx=2)
        self.video_connected_var = tk.BooleanVar(value=self.bus.video_connected)
        ttk.Checkbutton(
            toolbar,
            text="Vídeo conectado",
            variable=self.video_connected_var,
            command=self._set_device_connections,
        ).pack(side="left", padx=2)
        self.keyboard_connected_var = tk.BooleanVar(value=self.bus.keyboard_connected)
        ttk.Checkbutton(
            toolbar,
            text="Teclado conectado",
            variable=self.keyboard_connected_var,
            command=self._set_device_connections,
        ).pack(side="left", padx=2)

        self.status_var = tk.StringVar(value="Pronto")
        ttk.Label(toolbar, textvariable=self.status_var).pack(side="right", padx=8)

        main = ttk.Panedwindow(self.root, orient="horizontal")
        main.pack(fill="both", expand=True, padx=6, pady=(0, 6))

        left = ttk.Frame(main)
        right = ttk.Frame(main)
        main.add(left, weight=3)
        main.add(right, weight=2)

        self.terminal_frame = ttk.LabelFrame(
            left,
            text="Modo Texto 40×30 — saída física 640×480 — 4:3",
            padding=6,
        )
        terminal_frame = self.terminal_frame
        terminal_frame.pack(anchor="nw")

        # Fonte raster fixa: cada célula continua sendo sempre 8×8 pixels,
        # independentemente do tamanho da janela principal.
        self.video_font = self.tkfont.Font(
            # Fonte raster do Windows: no tamanho lógico 8 ela usa uma matriz
            # 6×8 dentro da célula 8×8, como terminais reais, em vez do glifo
            # muito estreito do Consolas que parecia inserir espaços.
            family="Terminal",
            size=-16,
        )
        self.video_pixel_scale = 1

        self.terminal = tk.Canvas(
            terminal_frame,
            width=640,
            height=480,
            bg="#071007",
            borderwidth=0,
            highlightthickness=0,
            takefocus=False,
        )
        # A superfície do host não tem scrollbar nem histórico próprio.
        # Ela sempre representa exatamente os 640x480 pixels lógicos atuais.
        # O próprio Canvas é toda a área preta: não há contêiner elástico,
        # letterbox ou margem interna que possa crescer com a janela.
        self.terminal.pack()
        self.terminal.bind("<Button-1>", self._focus_terminal)

        # Captura no nível da janela inteira. Isso evita depender do foco interno
        # de um tk.Text, que varia entre Windows/Linux e entre versões do Tk.
        self.root.bind_all("<KeyPress>", self._on_key_press, add="+")
        self.root.bind_all("<KeyRelease>", self._on_key_release, add="+")
        self.root.bind_all("<Button-1>", self._update_keyboard_capture, add="+")
        self.root.bind("<Tab>", self._on_console_tab, add="+")
        self.root.bind("<ISO_Left_Tab>", self._on_console_tab, add="+")
        self.root.bind("<F11>", self._toggle_fullscreen, add="+")
        self.root.bind("<Escape>", self._leave_fullscreen, add="+")

        io_frame = ttk.LabelFrame(left, text="I/O / teclado", padding=6)
        io_frame.pack(fill="x", pady=(6, 0))
        self.io_var = tk.StringVar()
        ttk.Label(
            io_frame,
            textvariable=self.io_var,
            font=("Consolas", 10),
            justify="left",
        ).pack(anchor="w")

        mem = ttk.LabelFrame(left, text="Memória ao redor do PC", padding=6)
        mem.pack(fill="both", expand=True, pady=(6, 0))
        self.mem_text = tk.Text(
            mem, height=10, font=("Consolas", 10), state="disabled", wrap="none"
        )
        self.mem_text.pack(fill="both", expand=True)
        self.mem_text.tag_configure(
            "pc_byte",
            background="#ffe08a",
            foreground="#000000",
            relief="solid",
            borderwidth=1,
        )
        self.mem_text.tag_configure("separator", foreground="#8a8a8a")
        self.mem_text.tag_configure(
            "pc_address", font=("Consolas", 10, "bold")
        )

        top_right = ttk.Frame(right)
        top_right.pack(fill="x")

        regs = ttk.LabelFrame(top_right, text="Registradores", padding=8)
        regs.pack(side="left", fill="both", expand=True)
        self.reg_var = tk.StringVar()
        ttk.Label(
            regs,
            textvariable=self.reg_var,
            font=("Consolas", 12),
            justify="left",
        ).pack(anchor="w")

        self.cfg_inline_var = tk.StringVar()
        ttk.Separator(regs, orient="horizontal").pack(fill="x", pady=(6, 4))
        ttk.Label(
            regs,
            textvariable=self.cfg_inline_var,
            font=("Consolas", 9),
            justify="left",
        ).pack(anchor="w")

        display_frame = ttk.LabelFrame(
            top_right,
            text="Display 4 × 7 segmentos",
            padding=6,
        )
        display_frame.pack(side="left", fill="both", padx=(6, 0))

        self.display_canvas = tk.Canvas(
            display_frame,
            width=246,
            height=112,
            bg="#180707",
            highlightthickness=1,
            highlightbackground="#5a2929",
        )
        self.display_canvas.pack(fill="x")
        self.display_canvas.bind(
            "<Configure>",
            lambda _event: self._draw_seven_segment_display(),
        )

        self.display_meta_var = tk.StringVar()
        ttk.Label(
            display_frame,
            textvariable=self.display_meta_var,
            font=("Consolas", 9),
            justify="center",
            anchor="center",
        ).pack(fill="x", pady=(4, 0))

        host_key_frame = ttk.LabelFrame(
            right,
            text="Teclado do PC — leitura bruta antes da conversão",
            padding=6,
        )
        host_key_frame.pack(fill="x", pady=(6, 0))
        self.host_key_raw_var = tk.StringVar(
            value="Evento: nenhum | keysym: — | char: — | keycode: —"
        )
        ttk.Label(
            host_key_frame,
            textvariable=self.host_key_raw_var,
            font=("Consolas", 10),
            justify="left",
        ).pack(anchor="w")

        self.wall_key_var = tk.StringVar(
            value="WALL-8: DATA=$00 READY=0  barramento $F000=$00"
        )
        ttk.Label(
            host_key_frame,
            textvariable=self.wall_key_var,
            font=("Consolas", 11, "bold"),
            justify="left",
        ).pack(anchor="w", pady=(3, 0))

        flags = ttk.LabelFrame(right, text="Flags / execução", padding=8)
        flags.pack(fill="x", pady=(6, 0))
        self.exec_var = tk.StringVar()
        ttk.Label(flags, textvariable=self.exec_var, font=("Consolas", 10), justify="left").pack(anchor="w")

        dis = ttk.LabelFrame(right, text="Próximas instruções", padding=6)
        dis.pack(fill="both", expand=True, pady=(6, 0))
        self.dis_text = tk.Text(dis, height=10, font=("Consolas", 10), state="disabled", wrap="none")
        self.dis_text.pack(fill="both", expand=True)

        # F5, F10 e Ctrl+R são tratados em _on_key junto do teclado global.

    def load_bios(self) -> None:
        options = {
            "title": "Selecione a BIOS/EPROM",
            "filetypes": [("Binário", "*.bin *.rom *.img"), ("Todos", "*.*")],
        }
        if self.bios_dialog_dir is not None:
            options["initialdir"] = str(self.bios_dialog_dir)
        path = self.filedialog.askopenfilename(**options)
        if not path:
            return
        try:
            self.bios_dialog_dir = Path(path).parent
            self.bus.load_bios_file(path)
            self.reset(start=False)
            self.status_var.set(
                f"BIOS: {Path(path).name} — {self.bus.bios_load_mode}"
            )
        except Exception as exc:
            self.messagebox.showerror("Erro ao carregar BIOS", str(exc))

    def load_cart(self) -> None:
        options = {
            "title": "Selecione o cartucho",
            "filetypes": [("Binário", "*.bin *.rom *.img"), ("Todos", "*.*")],
        }
        if self.cart_dialog_dir is not None:
            options["initialdir"] = str(self.cart_dialog_dir)
        path = self.filedialog.askopenfilename(**options)
        if not path:
            return
        try:
            self.cart_dialog_dir = Path(path).parent
            self.bus.load_cart_file(path)
            self.cart_connected_var.set(True)
            self.status_var.set(f"Cartucho: {Path(path).name}")
        except Exception as exc:
            self.messagebox.showerror("Erro ao carregar cartucho", str(exc))

    def save_cart(self) -> None:
        options = {
            "title": "Salvar imagem do cartucho",
            "defaultextension": ".bin",
            "filetypes": [("Binário", "*.bin"), ("Todos", "*.*")],
        }
        if self.cart_dialog_dir is not None:
            options["initialdir"] = str(self.cart_dialog_dir)
        path = self.filedialog.asksaveasfilename(**options)
        if not path:
            return
        try:
            self.cart_dialog_dir = Path(path).parent
            self.bus.save_cart_file(path)
            self.status_var.set(f"Cartucho salvo: {Path(path).name}")
        except Exception as exc:
            self.messagebox.showerror("Erro ao salvar cartucho", str(exc))

    def eject_cart(self) -> None:
        self.bus.eject_cart()
        self.status_var.set("Cartucho ejetado")

    def _use_custom_clock(self, _event=None) -> None:
        self.speed_var.set("Personalizado")
        raw = self.custom_clock_var.get().strip().replace(",", ".")
        multiplier = {"Hz": 1, "kHz": 1_000, "MHz": 1_000_000}[
            self.custom_clock_unit_var.get()
        ]
        try:
            value = float(raw) * multiplier
            if not 1 <= value <= 100_000_000:
                raise ValueError
            self.custom_clock_hz = int(value)
            self.status_var.set(f"Clock personalizado: {self.custom_clock_hz:,} Hz")
        except ValueError:
            self.status_var.set("Clock inválido; informe de 1 Hz a 100 MHz")

    def _selected_clock_hz(self) -> int:
        if self.speed_var.get() == "Personalizado":
            return self.custom_clock_hz
        return self.SPEEDS[self.speed_var.get()]

    def _set_device_connections(self) -> None:
        self.bus.cart_connected = self.cart_connected_var.get()
        self.bus.video_connected = self.video_connected_var.get()
        self.bus.keyboard_connected = self.keyboard_connected_var.get()
        self.status_var.set(
            f"Cartucho {'conectado' if self.bus.cart_connected else 'removido'}; "
            f"vídeo {'conectado' if self.bus.video_connected else 'removido'}; "
            f"teclado {'conectado' if self.bus.keyboard_connected else 'removido'}"
        )
        self._update_ui(force=True)

    def reset(self, start: bool = True) -> None:
        self.running = False
        self.bus.reset(clear_ram=True)
        self.cpu.reset()
        self._cycle_credit = 0.0
        self.running = start
        self.run_button.configure(text="Stop" if start else "Run")
        self._last_tick = time.perf_counter()
        self._update_ui(force=True)
        self.root.focus_force()

    def toggle_run(self) -> None:
        if self.cpu.s.halted:
            self.status_var.set("CPU em HLT; use Reset")
            return
        self.running = not self.running
        self.run_button.configure(text="Stop" if self.running else "Run")
        self._cycle_credit = 0.0
        self._last_tick = time.perf_counter()

    def step_once(self) -> None:
        self.running = False
        self.run_button.configure(text="Run")
        try:
            self.cpu.step()
        except Exception as exc:
            self._handle_cpu_error(exc)
        self._update_ui(force=True)

    def _handle_cpu_error(self, exc: Exception) -> None:
        self.running = False
        self.run_button.configure(text="Run")
        self.status_var.set(str(exc))
        self.messagebox.showerror("CPU parada", str(exc))

    def _focus_terminal(self, _event=None) -> str:
        # O evento de teclado é capturado globalmente dentro desta janela.
        # Forçar foco no toplevel resolve casos em que o tk.Text desabilitado
        # não recebe foco no Windows.
        self.root.focus_force()
        self.keyboard_capture_active = True
        self.status_var.set("Teclado WALL-8 ativo — digite em qualquer ponto da janela")
        return "break"

    def _update_keyboard_capture(self, event) -> None:
        """Captura teclas do WALL-8 somente depois de clicar no console."""
        self.keyboard_capture_active = event.widget is self.terminal
        if not self.keyboard_capture_active:
            self.bus.keyboard.release_all()

    def _on_console_tab(self, event) -> Optional[str]:
        """Impede a navegação do Tk e entrega Tab ao teclado do WALL-8."""
        if not self.keyboard_capture_active:
            return None
        if not self.bus.keyboard_connected:
            self.status_var.set("Teclado removido; evento não enviado ao WALL-8")
            return "break"

        accepted = self.bus.keyboard.key_down(
            0x09,
            keysym=str(event.keysym),
            char="\t",
            keycode=event.keycode,
        )
        if accepted:
            self.status_var.set("FF SET: 'Tab' → $F000=$09, $F300.7=1")
        self._update_ui(force=True)
        return "break"

    # Códigos próximos de ASCII/ANSI:
    # - caracteres imprimíveis usam o próprio byte ASCII/Latin-1;
    # - controles comuns usam seus códigos ASCII;
    # - teclas sem código ASCII ocupam a faixa estendida 80h..9Fh.
    _WALL_SPECIAL_KEYS = {
        "BackSpace": 0x08,
        "Tab": 0x09,
        "Return": 0x0D,
        "KP_Enter": 0x0D,
        "Escape": 0x1B,
        "space": 0x20,
        "Delete": 0x7F,

        "Up": 0x80,
        "Down": 0x81,
        "Left": 0x82,
        "Right": 0x83,
        "Insert": 0x84,
        "Home": 0x85,
        "End": 0x86,
        "Prior": 0x87,       # Page Up
        "Next": 0x88,        # Page Down

        "F1": 0x90,
        "F2": 0x91,
        "F3": 0x92,
        "F4": 0x93,
        "F5": 0x94,
        "F6": 0x95,
        "F7": 0x96,
        "F8": 0x97,
        "F9": 0x98,
        "F10": 0x99,
        "F11": 0x9A,
        "F12": 0x9B,

        # "Shift_L": 0xA0,
        # "Shift_R": 0xA0,
        # "Control_L": 0xA1,
        # "Control_R": 0xA1,
        # "Alt_L": 0xA2,
        # "Alt_R": 0xA2,
        # "Caps_Lock": 0xA3,
        # "Num_Lock": 0xA4,
    }

    def _host_key_raw_text(self, event, event_name: str) -> str:
        char = event.char
        if char == "":
            char_repr = "—"
            char_ord = "—"
        else:
            escaped = char.encode("unicode_escape").decode("ascii")
            char_repr = repr(escaped)
            char_ord = f"0x{ord(char):02X}" if len(char) == 1 else "—"

        return (
            f"Evento: {event_name} | keysym: {event.keysym!r} | "
            f"char: {char_repr} ({char_ord}) | keycode: {event.keycode} | "
            f"state: 0x{event.state:04X}"
        )

    def _translate_host_key(self, event) -> Optional[int]:
        keysym = str(event.keysym)

        if keysym in self._WALL_SPECIAL_KEYS:
            return self._WALL_SPECIAL_KEYS[keysym]

        char = event.char
        if not char:
            return None

        # Usa o caractere produzido pelo sistema operacional. Isso preserva
        # Shift, Caps Lock, símbolos e caracteres Latin-1 de um byte.
        value = ord(char)
        if 0x20 <= value <= 0xFF:
            return value

        return None

    def _on_key_press(self, event) -> Optional[str]:
        # Atalhos do emulador agora exigem Ctrl para não roubar F5/F10
        # do teclado do WALL-8.
        ctrl = bool(event.state & 0x0004)
        if ctrl and event.keysym == "F5":
            self.toggle_run()
            return "break"
        if ctrl and event.keysym == "F10":
            self.step_once()
            return "break"
        if ctrl and str(event.keysym).lower() == "r":
            self.reset()
            return "break"

        if not self.keyboard_capture_active:
            return None

        if not self.bus.keyboard_connected:
            self.status_var.set("Teclado removido; evento não enviado ao WALL-8")
            return "break"

        self.host_key_raw_var.set(self._host_key_raw_text(event, "KEY DOWN"))

        code = self._translate_host_key(event)
        if code is not None:
            accepted = self.bus.keyboard.key_down(
                code,
                keysym=str(event.keysym),
                char=event.char,
                keycode=event.keycode,
            )
            if accepted:
                self.status_var.set(
                    f"FF SET: {event.keysym!r} → $F000=${code:02X}, $F300.7=1"
                )
            else:
                self.status_var.set(
                    f"Auto-repeat ignorado: {event.keysym!r}"
                )
        else:
            self.status_var.set(
                f"PC detectou {event.keysym!r}; sem código WALL-8 definido"
            )

        self._update_ui(force=True)
        return "break"

    def _on_key_release(self, event) -> Optional[str]:
        if not self.keyboard_capture_active:
            return None
        self.host_key_raw_var.set(self._host_key_raw_text(event, "KEY UP"))

        # A soltura apenas libera a tecla física. DATA continua latched e
        # KEY_READY só é alterado pelo SET da tecla ou pelo RESET de /KEY_RD.
        self.bus.keyboard.key_up(
            keysym=str(event.keysym),
            char=event.char,
            keycode=event.keycode,
        )
        self.status_var.set(
            f"KeyUp {event.keysym!r}: DATA mantido; READY não alterado"
        )
        self._update_ui(force=True)
        return "break"

    def _tick(self) -> None:
        now = time.perf_counter()
        dt = min(0.1, max(0.0, now - self._last_tick))
        self._last_tick = now

        self.bus.timer.update()

        if self.running and not self.cpu.s.halted:
            try:
                selected = self._selected_clock_hz()
                self._cycle_credit += selected * dt
                instructions = 0
                while self._cycle_credit > 0 and instructions < 50_000 and not self.cpu.s.halted:
                    self._cycle_credit -= self.cpu.step()
                    instructions += 1
            except Exception as exc:
                self._handle_cpu_error(exc)

        if self.cpu.s.halted:
            self.running = False
            self.run_button.configure(text="Run")

        if now - self._last_rate_time >= 1.0:
            elapsed = now - self._last_rate_time
            delta = self.cpu.s.cycles - self._last_rate_cycles
            self._actual_hz = delta / elapsed
            self._last_rate_cycles = self.cpu.s.cycles
            self._last_rate_time = now

        self._frame_counter += 1
        if now - self._last_ui_time >= 0.05:
            self._last_ui_time = now
            self._update_ui()

        self.root.after(10, self._tick)

    VIDEO_MODES = {
        "Texto 40×30": (320, 240, 40, 30),
        "GFX 320×240": (320, 240, 320, 240),
        "GFX 160×120": (160, 120, 160, 120),
    }

    def _set_video_resolution(self, _event=None) -> None:
        logical_width, logical_height, columns, rows = self.VIDEO_MODES[
            self.video_resolution_var.get()
        ]
        self.bus.video.set_geometry(columns, rows)
        self.terminal_frame.configure(
            text=f"Modo {self.video_resolution_var.get()} — saída física 640×480 — 4:3"
        )
        self._configure_video_canvas()

    def _configure_video_canvas(self) -> None:
        logical_width, logical_height, _columns, _rows = self.VIDEO_MODES[
            self.video_resolution_var.get()
        ]
        scale = self.video_pixel_scale
        self.video_font.configure(size=-(16 * scale))
        self.terminal.configure(
            width=640 * scale,
            height=480 * scale,
        )
        self.bus.video.dirty = True
        self.root.after_idle(self._fit_window_to_fixed_video)

    def _set_video_pixel_scale(self, _event=None) -> None:
        """Aplica zoom inteiro e fixo, sem mudar a resolução emulada."""
        scale = {"1×": 1, "2×": 2, "4×": 4}.get(
            self.video_pixel_scale_var.get(),
            1,
        )
        self.video_pixel_scale = scale
        self._configure_video_canvas()

    def _toggle_fullscreen(self, _event=None) -> str:
        enabled = not bool(self.root.attributes("-fullscreen"))
        self.root.attributes("-fullscreen", enabled)
        self.root.after_idle(self._update_terminal, True)
        return "break"

    def _leave_fullscreen(self, _event=None) -> None:
        if self.root.attributes("-fullscreen"):
            self.root.attributes("-fullscreen", False)

    def _fit_window_to_fixed_video(self) -> None:
        """Garante que os 80×60 caracteres inteiros estejam sempre visíveis."""
        self.root.update_idletasks()
        if self.root.attributes("-fullscreen"):
            self._update_terminal(force=True)
            return
        required_width = max(1250, self.root.winfo_reqwidth())
        required_height = max(760, self.root.winfo_reqheight())
        self.root.minsize(required_width, required_height)

        width = max(self.root.winfo_width(), required_width)
        height = max(self.root.winfo_height(), required_height)
        self.root.geometry(f"{width}x{height}")
        self.root.update_idletasks()
        self._update_terminal(force=True)

    def _set_text(self, widget, text: str) -> None:
        widget.configure(state="normal")
        widget.delete("1.0", "end")
        widget.insert("1.0", text)
        widget.configure(state="disabled")

    def _update_terminal(self, force: bool = False) -> None:
        command_to_mode = {
            VideoDevice.MODE_TEXT: "Texto 40×30",
            VideoDevice.MODE_GFX_320: "GFX 320×240",
            VideoDevice.MODE_GFX_160: "GFX 160×120",
        }
        expected_mode = command_to_mode.get(self.bus.video.mode)
        if expected_mode and self.video_resolution_var.get() != expected_mode:
            # A BIOS também pode selecionar o modo escrevendo $10/$11/$12 em
            # VIDEO_CMD. Mantém o seletor e o Canvas sincronizados com ela.
            self.video_resolution_var.set(expected_mode)
            logical_width, logical_height, columns, rows = self.VIDEO_MODES[
                expected_mode
            ]
            self.terminal_frame.configure(
                text=f"Modo {expected_mode} — saída física 640×480 — 4:3"
            )
            self._configure_video_canvas()

        if not self.bus.video.dirty and not force:
            return

        # Não existe scrollback no Tkinter. A BIOS é responsável por escolher
        # quais linhas devem estar na superfície e redesenhá-las pela GPU.
        canvas = self.terminal
        canvas.delete("all")
        if self.bus.video.mode != VideoDevice.MODE_TEXT:
            logical_width = self.bus.video.logical_width
            logical_height = self.bus.video.logical_height
            image = self.tk.PhotoImage(width=logical_width, height=logical_height)
            on, off = "#67ff67", "#071007"
            rows = []
            stride = self.bus.video.bytes_per_line
            for y in range(logical_height):
                line = self.bus.video.vram[y * stride:(y + 1) * stride]
                colors = []
                for value in line:
                    colors.extend(on if value & (0x80 >> bit) else off
                                  for bit in range(8))
                rows.append("{" + " ".join(colors) + "}")
            image.put(" ".join(rows))
            physical_scale = 2 if self.bus.video.mode == VideoDevice.MODE_GFX_320 else 4
            self._video_image = image.zoom(physical_scale * self.video_pixel_scale)
            canvas.create_image(0, 0, image=self._video_image, anchor="nw")
            self.bus.video.dirty = False
            return

        cell = 16 * self.video_pixel_scale
        first_row_offset = 0

        # Cada caractere ocupa uma célula lógica quadrada de 8×8. As posições
        # cobrem exatamente a grade selecionada, sem padding ou área ociosa.
        for row_index, row in enumerate(self.bus.video.cells):
            # Apenas a primeira linha recebe a folga visual do topo. Deslocar
            # toda a grade faria a última linha ultrapassar a resolução por
            # dois pixels lógicos (por exemplo, 242 em uma tela de 240).
            y = (row_index + 0.5) * cell
            if row_index == 0:
                y += first_row_offset
            for column_index, char in enumerate(row):
                if char != " ":
                    canvas.create_text(
                        (column_index + 0.5) * cell,
                        y,
                        text=char,
                        font=self.video_font,
                        fill="#67ff67",
                        anchor="center",
                    )

        if self.bus.video.cursor_visible:
            x0 = self.bus.video.x * cell
            y0 = self.bus.video.y * cell
            if self.bus.video.y == 0:
                y0 += first_row_offset
            canvas.create_rectangle(
                x0,
                y0,
                x0 + cell,
                y0 + cell,
                fill="#67ff67",
                outline="",
            )
            char = self.bus.video.cells[self.bus.video.y][self.bus.video.x]
            if char != " ":
                canvas.create_text(
                    x0 + cell / 2,
                    y0 + cell / 2,
                    text=char,
                    font=self.video_font,
                    fill="#071007",
                    anchor="center",
                )

        self.bus.video.dirty = False

    # Tabelas idênticas às usadas pelo gerador 7Seg.py.
    #
    # Bits de saída da 27C512:
    # D0=A, D1=B, D2=C, D3=D, D4=E, D5=F, D6=G, D7=DP.
    _DISPLAY_SEG_HEX = {
        0x0: 0x3F,  # 0
        0x1: 0x06,  # 1
        0x2: 0x5B,  # 2
        0x3: 0x4F,  # 3
        0x4: 0x66,  # 4
        0x5: 0x6D,  # 5
        0x6: 0x7D,  # 6
        0x7: 0x07,  # 7
        0x8: 0x7F,  # 8
        0x9: 0x6F,  # 9
        0xA: 0x77,  # A
        0xB: 0x7C,  # b
        0xC: 0x39,  # C
        0xD: 0x5E,  # d
        0xE: 0x79,  # E
        0xF: 0x71,  # F
    }

    _DISPLAY_SEG_CHAR = {
        0x0: 0x00,  # espaço
        0x1: 0x77,  # A
        0x2: 0x7C,  # b
        0x3: 0x39,  # C
        0x4: 0x5E,  # d
        0x5: 0x79,  # E
        0x6: 0x71,  # F
        0x7: 0x76,  # H
        0x8: 0x38,  # L
        0x9: 0x3F,  # O
        0xA: 0x73,  # P
        0xB: 0x50,  # r
        0xC: 0x78,  # t
        0xD: 0x3E,  # U
        0xE: 0x40,  # -
        0xF: 0x08,  # _
    }

    _DISPLAY_CHAR_NAMES = {
        0x0: " ",
        0x1: "A",
        0x2: "b",
        0x3: "C",
        0x4: "d",
        0x5: "E",
        0x6: "F",
        0x7: "H",
        0x8: "L",
        0x9: "O",
        0xA: "P",
        0xB: "r",
        0xC: "t",
        0xD: "U",
        0xE: "-",
        0xF: "_",
    }

    def _display_nibbles(self) -> list[int]:
        """Retorna os quatro nibbles na ordem visual esquerda -> direita."""
        value = self.bus.display_value & 0xFFFF
        return [
            (value >> 12) & 0x0F,
            (value >> 8) & 0x0F,
            (value >> 4) & 0x0F,
            value & 0x0F,
        ]

    def _display_segment_bytes(self) -> tuple[list[int], str, str]:
        """Simula as duas 27C512 usadas para o display.

        Cada byte alimenta uma EEPROM:
          DISPLAY_HIGH -> dois dígitos da esquerda
          DISPLAY_LOW  -> dois dígitos da direita

        A8 escolhe nibble baixo/alto e A9 escolhe HEX/CHAR.
        """
        nibbles = self._display_nibbles()

        # /DISP_HEX é ativo em LOW:
        # PERIPH_CFG bit0 = 0 -> A9=0 -> HEX
        # PERIPH_CFG bit0 = 1 -> A9=1 -> CHAR
        char_mode = bool(self.bus.periph_cfg & 0x01)
        table = self._DISPLAY_SEG_CHAR if char_mode else self._DISPLAY_SEG_HEX

        segment_bytes = [table[nibble] for nibble in nibbles]

        if char_mode:
            rendered = "".join(self._DISPLAY_CHAR_NAMES[n] for n in nibbles)
            mode = "CHAR  /DISP_HEX=1  A9=1"
        else:
            rendered = "".join(f"{n:X}" for n in nibbles)
            mode = "HEX  /DISP_HEX=0  A9=0"

        return segment_bytes, rendered, mode

    def _draw_seven_segment_display(self) -> None:
        canvas = self.display_canvas
        canvas.delete("all")

        segment_bytes, rendered, mode = self._display_segment_bytes()
        active = "#ff3b30"
        inactive = "#3b1414"

        # D0..D6 correspondem diretamente aos segmentos A..G.
        segments = {
            0: ((10, 10), (42, 10)),  # A
            1: ((46, 14), (46, 43)),  # B
            2: ((46, 53), (46, 82)),  # C
            3: ((10, 86), (42, 86)),  # D
            4: ((6, 53), (6, 82)),    # E
            5: ((6, 14), (6, 43)),    # F
            6: ((10, 48), (42, 48)),  # G
        }

        spacing = 58
        digit_width = 52
        total_width = digit_width + spacing * (len(segment_bytes) - 1)

        # Centraliza os quatro dígitos horizontalmente no Canvas.
        canvas_width = max(
            canvas.winfo_width(),
            int(canvas.cget("width")),
        )
        start_x = max(0, (canvas_width - total_width) // 2)

        for index, segment_mask in enumerate(segment_bytes):
            x0 = start_x + index * spacing

            for bit, ((x1, y1), (x2, y2)) in segments.items():
                enabled = bool(segment_mask & (1 << bit))
                canvas.create_line(
                    x0 + x1,
                    y1,
                    x0 + x2,
                    y2,
                    fill=active if enabled else inactive,
                    width=7,
                    capstyle="round",
                )

            # D7: ponto decimal, caso seja usado no futuro.
            dp_enabled = bool(segment_mask & 0x80)
            canvas.create_oval(
                x0 + 45,
                82,
                x0 + 51,
                88,
                fill=active if dp_enabled else inactive,
                outline="",
            )

        masks = " ".join(f"{value:02X}" for value in segment_bytes)
        self.display_meta_var.set(
            f"$F101:$F100 = ${self.bus.display_value:04X}  →  {rendered!r}\n"
            f"{mode} | saídas ROM esquerda→direita: {masks}"
        )


    def _update_ui(self, force: bool = False) -> None:
        s = self.cpu.s
        self._update_terminal(force)

        self._draw_seven_segment_display()

        self.cfg_inline_var.set(
            f"CPU_CFG    {self.bus.cpu_cfg:08b}\n"
            f"PERIPH_CFG {self.bus.periph_cfg:08b}\n"
            f"SOUND_CFG  {self.bus.sound.config:08b}"
        )

        self.reg_var.set(
            f"A    ${s.a:02X}   B    ${s.b:02X}\n"
            f"PC   ${s.pc:04X}   SP   ${s.sp:04X}\n"
            f"PTR  ${s.ptr:04X}   MAR  ${s.mar:04X}\n"
            f"ADDR ${s.addr:04X}   TMP  ${s.tmp:02X}\n"
            f"IR   ${s.ir:02X}     DBUS ${s.dbus:02X}\n"
            f"ALU  ${s.alu:02X}"
        )

        next_text, _ = self.cpu.disassemble(s.pc)
        state = "HLT" if s.halted else ("RUN" if self.running else "PAUSE")
        self.exec_var.set(
            f"Z={s.z} C={s.c} N={s.n} V={s.v}   Estado={state}\n"
            f"Última: ${self.cpu.last_pc:04X}  {self.cpu.last_text}\n"
            f"Próxima: ${s.pc:04X}  {next_text}\n"
            f"Instruções: {s.instructions:,}\n"
            f"Microciclos: {s.cycles:,}  efetivo: {self._actual_hz:,.0f} Hz\n"
            f"Bus: {self.bus.last_access} ${self.bus.last_address:04X} = ${self.bus.last_data:02X}"
        )

        key = self.bus.keyboard.current
        key_text = "--" if key is None else f"${key:02X} '{chr(key) if 32 <= key < 127 else '.'}'"
        cart = "conectado" if self.bus.cart_connected else "ausente"
        keyboard_raw = self.bus.keyboard.read()

        raw_char = self.bus.keyboard.last_host_char
        raw_char_display = (
            repr(raw_char.encode("unicode_escape").decode("ascii"))
            if raw_char
            else "—"
        )
        self.host_key_raw_var.set(
            f"Evento: {self.bus.keyboard.last_event} | "
            f"keysym: {self.bus.keyboard.last_host_keysym or '—'!r} | "
            f"char: {raw_char_display} | "
            f"keycode: {self.bus.keyboard.last_host_keycode or '—'}"
        )
        wall_data = keyboard_raw
        status_raw = self.bus.peek8(TIMER_STATUS)
        self.wall_key_var.set(
            f"WALL-8: DATA $F000=${wall_data:02X}  "
            f"KEY_READY={(status_raw >> 7) & 1} em $F300=${status_raw:02X}  "
            f"físicas={self.bus.keyboard.pressed_count}  "
            f"repeats ignorados={self.bus.keyboard.repeat_ignored}"
        )

        self.io_var.set(
            f"SYSTEM_STATUS $F300=${status_raw:02X}  "
            f"/CARD_DETECT={(status_raw >> 4) & 1}  "
            f"/VIDEO_DETECT={(status_raw >> 5) & 1}  "
            f"/KEYBOARD_DETECT={(status_raw >> 6) & 1}\n"
            f"Cartucho: {cart}    Boot overlay: {'ON' if self.bus.boot_overlay else 'OFF'}\n"
            f"BIOS EPROM: {self.bus.bios_load_mode}\n"
            f"Cart EPROM: {self.bus.cart_load_mode}"
        )

        # Disassembly
        lines = []
        addr = s.pc
        line_height = max(1, self.tkfont.Font(font=self.dis_text["font"]).metrics("linespace"))
        visible_lines = max(10, self.dis_text.winfo_height() // line_height - 1)
        for i in range(visible_lines):
            text, length = self.cpu.disassemble(addr)
            marker = ">" if i == 0 else " "
            raw = " ".join(f"{self.bus.peek8(addr + j):02X}" for j in range(length))
            lines.append(f"{marker} ${addr:04X}: {raw:<11} {text}")
            addr = (addr + length) & 0xFFFF
        self._set_text(self.dis_text, "\n".join(lines))

        # Hex dump clássico: 16 colunas, endereços de 16 bits e byte do PC marcado.
        mem_line_height = max(
            1, self.tkfont.Font(font=self.mem_text["font"]).metrics("linespace")
        )
        memory_rows = max(4, self.mem_text.winfo_height() // mem_line_height - 3)
        rows_before_pc = memory_rows // 2
        base = ((s.pc & 0xFFF0) - rows_before_pc * 16) & 0xFFFF
        mem_lines = [
            "Offset(h) │ " + " ".join(f"{i:02X}" for i in range(16)),
            "──────────┼" + "─" * 49,
        ]
        pc_row = pc_column = 0
        for row in range(memory_rows):
            a = (base + row * 16) & 0xFFFF
            values = " ".join(f"{self.bus.peek8(a + i):02X}" for i in range(16))
            mem_lines.append(f"0x{a:04X}    │ {values}")
            distance = (s.pc - a) & 0xFFFF
            if distance < 16:
                pc_row, pc_column = row + 3, 12 + distance * 3
        self.mem_text.configure(state="normal")
        self.mem_text.delete("1.0", "end")
        self.mem_text.insert("1.0", "\n".join(mem_lines))
        self.mem_text.tag_add("separator", "1.10", "1.11")
        self.mem_text.tag_add("separator", "2.0", "2.end")
        for row in range(memory_rows):
            self.mem_text.tag_add("separator", f"{row + 3}.10", f"{row + 3}.11")
        self.mem_text.tag_add("pc_address", f"{pc_row}.0", f"{pc_row}.6")
        self.mem_text.tag_add(
            "pc_byte",
            f"{pc_row}.{pc_column}",
            f"{pc_row}.{pc_column + 2}",
        )
        self.mem_text.configure(state="disabled")

    def close(self) -> None:
        self.bus.sound.close()
        self.root.destroy()

    def run(self) -> None:
        self.root.focus_force()
        self.root.mainloop()


# =============================================================================
# Autotestes
# =============================================================================


def run_self_tests() -> None:
    bus = Wall8Bus(audio_enabled=False)
    cpu = Wall8CPU(bus)

    # ALU
    assert cpu._add8(0xFF, 0x01) == (0x00, 1, 0)
    assert cpu._add8(0x7F, 0x01) == (0x80, 0, 1)
    assert cpu._sub8(0x05, 0x03) == (0x02, 1, 0)
    assert cpu._sub8(0x03, 0x05) == (0xFE, 0, 0)
    assert cpu._sub8(0x80, 0x01) == (0x7F, 1, 1)
    assert cpu._inc8(0x7F) == (0x80, 0, 1)
    assert cpu._inc8(0xFF) == (0x00, 1, 0)
    assert cpu._dec8(0x80) == (0x7F, 1, 1)
    assert cpu._dec8(0x00) == (0xFF, 0, 0)

    # ALU imediata: resultado, flags, preservação de A/B, TMP, ciclos e
    # desmontagem. Cada caso executa uma instrução de dois bytes na RAM.
    immediate_cases = [
        # opcode, A, B, imm, A final, B final, (Z,C,N,V), TMP, texto
        (ADD_A_IMM, 0xFE, 0xA5, 0x02, 0x00, 0xA5, (1, 1, 0, 0), 0xA5, "ADD A, #$02"),
        (ADD_B_IMM, 0x35, 0x7F, 0x01, 0x35, 0x80, (0, 0, 1, 1), 0x35, "ADD B, #$01"),
        (SUB_A_IMM, 0x03, 0xA5, 0x05, 0xFE, 0xA5, (0, 0, 1, 0), 0xA5, "SUB A, #$05"),
        (SUB_B_IMM, 0x35, 0x80, 0x01, 0x35, 0x7F, (0, 1, 0, 1), 0x35, "SUB B, #$01"),
        (AND_A_IMM, 0xF0, 0xA5, 0x0F, 0x00, 0xA5, (1, 0, 0, 0), 0xA5, "AND A, #$0F"),
        (AND_B_IMM, 0x35, 0xAA, 0x0F, 0x35, 0x0A, (0, 0, 0, 0), 0x35, "AND B, #$0F"),
        (OR_A_IMM, 0x80, 0xA5, 0x01, 0x81, 0xA5, (0, 0, 1, 0), 0xA5, "OR A, #$01"),
        (OR_B_IMM, 0x35, 0x00, 0x40, 0x35, 0x40, (0, 0, 0, 0), 0x35, "OR B, #$40"),
        (XOR_A_IMM, 0xFF, 0xA5, 0xFF, 0x00, 0xA5, (1, 0, 0, 0), 0xA5, "XOR A, #$FF"),
        (XOR_B_IMM, 0x35, 0xAA, 0xFF, 0x35, 0x55, (0, 0, 0, 0), 0x35, "XOR B, #$FF"),
        (CMP_A_IMM, 0x10, 0xA5, 0x10, 0x10, 0xA5, (1, 1, 0, 0), 0xA5, "CMP A, #$10"),
        (CMP_B_IMM, 0x35, 0x00, 0x01, 0x35, 0x00, (0, 0, 1, 0), 0x35, "CMP B, #$01"),
        (TEST_A_IMM, 0x80, 0xA5, 0x80, 0x80, 0xA5, (0, 0, 1, 0), 0xA5, "TEST A, #$80"),
        (TEST_B_IMM, 0x35, 0x01, 0x80, 0x35, 0x01, (1, 0, 0, 0), 0x35, "TEST B, #$80"),
    ]

    for opcode, a, b, imm, final_a, final_b, flags, tmp, text_expected in immediate_cases:
        bus.reset(clear_ram=True)
        cpu.reset()
        bus.write8(CPU_CFG, 0x01)  # libera a RAM em 0000h
        bus.ram[0:2] = bytes([opcode, imm])
        cpu.s.a = a
        cpu.s.b = b

        decoded, size = cpu.disassemble(0x0000)
        assert decoded == text_expected and size == 2

        cycles = cpu.step()
        assert cycles == 8
        assert cpu.s.pc == 0x0002
        assert cpu.s.a == final_a and cpu.s.b == final_b
        assert (cpu.s.z, cpu.s.c, cpu.s.n, cpu.s.v) == flags
        assert cpu.s.tmp == tmp
        assert cpu.s.dbus == tmp

    # Endereçamento físico da 27C512: 0000h e 8000h podem conter bytes distintos.
    bios = bytearray([0xFF] * EPROM_27C512_SIZE)
    bios[0x0000] = 0x12
    bios[0x4000] = 0x56
    bios[0x7FFF] = 0x78
    bios[0x8000] = 0x34
    bus.load_bios_bytes(bytes(bios))
    bus.reset()
    assert bus.read8(0x0000) == 0x12
    assert bus.read8(0x4000) == 0x56
    assert bus.read8(0x7FFF) == 0x78
    assert bus.read8(0x8000) == 0x34

    bus.ram[0x0000] = 0xA5
    bus.ram[0x4000] = 0xB6
    bus.ram[0x7FFF] = 0xC7
    bus.write8(0x4000, 0x99)  # RAM deve continuar desabilitada no overlay
    assert bus.ram[0x4000] == 0xB6

    bus.write8(CPU_CFG, 0x01)
    assert bus.read8(0x0000) == 0xA5
    assert bus.read8(0x4000) == 0xB6
    assert bus.read8(0x7FFF) == 0xC7
    assert bus.read8(0x8000) == 0x34

    # CALL/RET
    bus.reset()
    cpu.reset()
    bus.ram[0:8] = bytes([LDSP_ABS, 0xFF, 0x7F, CALL_ABS, 0x08, 0x00, HLT, NOP])
    bus.ram[8:10] = bytes([RET, HLT])
    bus.write8(CPU_CFG, 0x01)  # desliga overlay para executar RAM
    cpu.step()  # SP
    cpu.step()  # CALL
    assert cpu.s.pc == 0x0008 and cpu.s.sp == 0x7FFD
    cpu.step()  # RET
    assert cpu.s.pc == 0x0006 and cpu.s.sp == 0x7FFF

    # Teclado conectado: /KEYBOARD_DETECT em F300 bit 6 fica em nivel baixo.
    assert not (bus.peek8(TIMER_STATUS) & 0x40)

    # Teclado: DATA de 8 bits em F000 e READY em F300 bit 7.
    accepted = bus.keyboard.key_down(
        0xE1,
        keysym="á",
        char="á",
        keycode=65,
    )
    assert accepted
    assert bus.peek8(KEY_BASE) == 0xE1
    assert bus.peek8(TIMER_STATUS) & 0x80
    assert bus.keyboard.ready

    # Auto-repeat antes do KeyRelease é ignorado.
    accepted = bus.keyboard.key_down(
        0xE1,
        keysym="á",
        char="á",
        keycode=65,
    )
    assert not accepted
    assert bus.keyboard.repeat_ignored == 1
    assert bus.peek8(KEY_BASE) == 0xE1

    # Ler STATUS não limpa READY.
    assert bus.read8(TIMER_STATUS) & 0x80
    assert bus.keyboard.ready

    # Ler DATA retorna os oito bits e /KEY_RD limpa apenas READY.
    assert bus.read8(KEY_BASE) == 0xE1
    assert not bus.keyboard.ready
    assert not (bus.peek8(TIMER_STATUS) & 0x80)
    assert bus.peek8(KEY_BASE) == 0xE1

    # Escrita e KeyRelease não apagam DATA.
    bus.write8(KEY_BASE, 0)
    bus.keyboard.key_up(keysym="á", char="á", keycode=65)
    assert bus.peek8(KEY_BASE) == 0xE1
    assert bus.keyboard.pressed_count == 0

    # Nova pressão volta a setar READY.
    accepted = bus.keyboard.key_down(
        0x80,
        keysym="Up",
        char="",
        keycode=38,
    )
    assert accepted
    assert bus.peek8(KEY_BASE) == 0x80
    assert bus.peek8(TIMER_STATUS) & 0x80


    # Vídeo
    bus.write8(VIDEO_BASE, ord("X"))
    assert bus.video.busy
    bus.video.advance()
    assert bus.video.cells[0][0] == "X"

    # CURSOR_END fica retido na ultima posicao: a GPU nao volta para (0,0)
    # em nenhum modo e so libera a condicao quando a CPU reposiciona
    # explicitamente X/Y, troca o modo ou conclui VIDEO_CLEAR.
    bus.write8(VIDEO_BASE + 2, 39)
    bus.write8(VIDEO_BASE + 3, 29)
    bus.write8(VIDEO_BASE, ord("Z"))
    bus.video.advance()
    assert bus.video.vram[1199] == ord("Z")
    assert (bus.video.x, bus.video.y) == (39, 29)
    assert bus.video.read_register(4) & 0x10
    bus.write8(VIDEO_BASE, ord("Y"))
    bus.video.advance()
    assert bus.video.vram[1199] == ord("Y")
    assert (bus.video.x, bus.video.y) == (39, 29)
    assert bus.video.cursor_end
    bus.write8(VIDEO_BASE + 2, 0)
    assert not bus.video.cursor_end
    assert bus.video.read_register(4) & 0x10 == 0
    bus.write8(VIDEO_BASE + 3, 0)

    # Protocolo oficial da GPU: grafico 320x240, escrita sequencial e leitura
    # assincrona sem incremento.
    bus.write8(VIDEO_BASE + 1, 0x12)
    assert not bus.video.cursor_end
    assert bus.video.read_register(4) & 0x10 == 0
    bus.write8(VIDEO_BASE + 2, 39)
    bus.write8(VIDEO_BASE + 3, 239)
    bus.write8(VIDEO_BASE, 0x81)
    assert bus.video.busy
    assert bus.video.read_register(4) & 0x01
    bus.video.advance()
    assert bus.video.vram[9599] == 0x81
    assert (bus.video.x, bus.video.y) == (39, 239)
    assert bus.video.cursor_end
    assert bus.video.read_register(4) & 0x10
    bus.write8(VIDEO_BASE + 2, 39)
    bus.write8(VIDEO_BASE + 3, 239)
    bus.write8(VIDEO_BASE + 1, 0x20)
    assert bus.video.busy
    bus.video.advance()
    assert bus.read8(VIDEO_BASE) == 0x81
    assert (bus.video.x, bus.video.y) == (39, 239)

    # 160x120 usa 20 bytes por linha, escala 4x e limpa somente 2.400 bytes.
    bus.write8(VIDEO_BASE + 1, 0x13)
    bus.write8(VIDEO_BASE + 2, 19)
    bus.write8(VIDEO_BASE + 3, 119)
    bus.write8(VIDEO_BASE, 0xAA)
    bus.video.advance()
    assert bus.video.vram[2399] == 0xAA
    assert (bus.video.x, bus.video.y) == (19, 119)
    assert bus.video.cursor_end
    assert bus.video.read_register(4) & 0x10
    bus.video.vram[2400] = 0x5A
    bus.write8(VIDEO_BASE + 1, 0x00)
    bus.video.advance()
    assert not any(bus.video.vram[:2400])
    assert bus.video.vram[2400] == 0x5A

    # Retorna ao texto para os testes da BIOS demonstrativa.
    bus.write8(VIDEO_BASE + 1, 0x11)
    bus.write8(VIDEO_BASE + 1, 0x00)
    bus.video.advance()
    assert not bus.video.cursor_end
    assert (bus.video.x, bus.video.y) == (0, 0)

    # Cart detect e escrita.
    bus.read8(KEY_BASE)  # limpa KEY_READY pendente do teste anterior
    assert bus.read8(TIMER_STATUS) & 0x10
    cart = bytearray([0xFF] * EPROM_27C512_SIZE)
    cart[CART_START] = 0x44
    cart[CART_END] = 0x55
    bus.load_cart_bytes(bytes(cart))
    assert not (bus.read8(TIMER_STATUS) & 0x10)
    assert bus.read8(CART_START) == 0x44
    assert bus.read8(CART_END) == 0x55
    bus.write8(CART_START, 0x5A)
    assert bus.read8(CART_START) == 0x5A

    # BIOS demo executa e escreve no terminal.
    bus.load_bios_bytes(build_demo_bios())
    bus.reset()
    cpu.reset()
    for _ in range(2_000):
        cpu.step()
        if "WALL-8 EMULATOR" in bus.video.text():
            break
    assert "WALL-8 EMULATOR" in bus.video.text()
    assert not bus.boot_overlay

    print("Todos os autotestes do WALL-8 passaram.")


# =============================================================================
# Main
# =============================================================================


def _parse_number(text: str) -> int:
    return int(text, 0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Emulador funcional do WALL-8")
    parser.add_argument("--bios", help="arquivo da 27C512 da BIOS, até 64 KiB")
    parser.add_argument(
        "--bios-offset", type=_parse_number, default=None,
        help="offset físico para imagem parcial da BIOS, por exemplo 0x8000",
    )
    parser.add_argument("--cart", help="arquivo da memória do cartucho, até 64 KiB")
    parser.add_argument(
        "--cart-offset", type=_parse_number, default=None,
        help="offset físico para imagem parcial do cartucho, por exemplo 0xA000",
    )
    parser.add_argument("--no-audio", action="store_true", help="desativa backend de áudio")
    parser.add_argument("--self-test", action="store_true", help="executa autotestes e encerra")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        run_self_tests()
        return 0

    bus = Wall8Bus(audio_enabled=not args.no_audio)
    cpu = Wall8CPU(bus)

    try:
        if args.bios:
            bus.load_bios_file(args.bios, args.bios_offset)
        else:
            bus.load_bios_bytes(build_demo_bios())
        if args.cart:
            bus.load_cart_file(args.cart, args.cart_offset)
        bus.reset(clear_ram=True)
        cpu.reset()

        app = Wall8App(bus, cpu)
        app.run()
        return 0
    except Exception as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 1
    finally:
        bus.sound.close()


if __name__ == "__main__":
    raise SystemExit(main())
