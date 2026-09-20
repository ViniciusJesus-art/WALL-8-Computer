#!/usr/bin/env python3
"""Editor e gerador da ROM de caracteres 27C512 do WALL-8.

Ligacoes de endereco da EPROM:

    A0..A7   = VRAM_LATCH_0..7 (codigo do caractere)
    A8..A10  = V_COUNT_1..3    (linha 0..7 do glifo)
    A11..A13 = GND
    A14..A15 = banco da fonte

Logo, o endereco de uma linha e:

    endereco = (banco << 14) | (linha << 8) | codigo

O bit 0 do byte de dados e o pixel esquerdo e o bit 7 e o pixel direito.
Cada glifo ocupa 8 x 8 bits. A duplicacao para 8 x 16 pertence a GPU.

Uso:

    python Gerador_ROM_Caracteres.py
    python Gerador_ROM_Caracteres.py --generate char_rom_27c512.bin
    python Gerador_ROM_Caracteres.py --self-test

A interface grafica nao requer pacotes externos: usa somente Tkinter.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path
from typing import Iterable, Optional


ROM_SIZE = 0x10000
BANK_COUNT = 4
CHAR_COUNT = 256
ROWS_PER_GLYPH = 8
ACCESSIBLE_BYTES_PER_BANK = CHAR_COUNT * ROWS_PER_GLYPH
DEFAULT_OUTPUT_NAME = "char_rom_27c512.bin"


def rom_address(bank: int, character: int, row: int) -> int:
    """Monta A0..A15 exatamente como no esquema eletrico da GPU."""
    if not 0 <= bank < BANK_COUNT:
        raise ValueError("Banco deve estar entre 0 e 3")
    if not 0 <= character < CHAR_COUNT:
        raise ValueError("Codigo deve estar entre 0x00 e 0xFF")
    if not 0 <= row < ROWS_PER_GLYPH:
        raise ValueError("Linha deve estar entre 0 e 7")
    return (bank << 14) | (row << 8) | character


def reverse_byte(value: int) -> int:
    """Inverte a ordem dos bits de um byte."""
    value &= 0xFF
    value = ((value & 0x55) << 1) | ((value >> 1) & 0x55)
    value = ((value & 0x33) << 2) | ((value >> 2) & 0x33)
    return ((value << 4) | (value >> 4)) & 0xFF


# Fonte IBM 8x8 de dominio publico, faixa U+0020..U+007F.
# A tabela original ja usa o bit 0 como pixel esquerdo, igual ao WALL-8.
# As duas colunas externas sao apagadas para manter margem entre celulas.
# Origem: https://github.com/dhepper/font8x8 (font8x8_basic.h)
_BASIC_LATIN_LSB_ROWS = bytes.fromhex(
    # 20..2F
    "0000000000000000 183c3c1818001800 3636000000000000 "
    "36367f367f363600 0c3e031e301f0c00 006333180c666300 "
    "1c361c6e3b336e00 0606030000000000 180c0606060c1800 "
    "060c1818180c0600 00663cff3c660000 000c0c3f0c0c0000 "
    "00000000000c0c06 0000003f00000000 00000000000c0c00 "
    "6030180c06030100 "
    # 30..3F
    "3e63737b6f673e00 0c0e0c0c0c0c3f00 1e33301c06333f00 "
    "1e33301c30331e00 383c36337f307800 3f031f3030331e00 "
    "1c06031f33331e00 3f3330180c0c0c00 1e33331e33331e00 "
    "1e33333e30180e00 000c0c00000c0c00 000c0c00000c0c06 "
    "180c0603060c1800 00003f00003f0000 060c1830180c0600 "
    "1e3330180c000c00 "
    # 40..4F
    "3e637b7b7b031e00 0c1e33333f333300 3f66663e66663f00 "
    "3c66030303663c00 1f36666666361f00 7f46161e16467f00 "
    "7f46161e16060f00 3c66030373667c00 3333333f33333300 "
    "1e0c0c0c0c0c1e00 7830303033331e00 6766361e36666700 "
    "0f06060646667f00 63777f7f6b636300 63676f7b73636300 "
    "1c36636363361c00 "
    # 50..5F
    "3f66663e06060f00 1e3333333b1e3800 3f66663e36666700 "
    "1e33070e38331e00 3f2d0c0c0c0c1e00 3333333333333f00 "
    "33333333331e0c00 6363636b7f776300 6363361c1c366300 "
    "3333331e0c0c1e00 7f6331184c667f00 1e06060606061e00 "
    "03060c1830604000 1e18181818181e00 081c366300000000 "
    "00000000000000ff "
    # 60..6F
    "0c0c180000000000 00001e303e336e00 0706063e66663b00 "
    "00001e3303331e00 3830303e33336e00 00001e333f031e00 "
    "1c36060f06060f00 00006e33333e301f 0706366e66666700 "
    "0c000e0c0c0c1e00 300030303033331e 070666361e366700 "
    "0e0c0c0c0c0c1e00 0000337f7f6b6300 00001f3333333300 "
    "00001e3333331e00 "
    # 70..7F
    "00003b66663e060f 00006e33333e3078 00003b6e66060f00 "
    "00003e031e301f00 080c3e0c0c2c1800 0000333333336e00 "
    "00003333331e0c00 0000636b7f7f3600 000063361c366300 "
    "00003333333e301f 00003f190c263f00 380c0c070c0c3800 "
    "1818180018181800 070c0c380c0c0700 6e3b000000000000 "
    "0000000000000000"
)


# Glifos que ja existem nos fontes dos cartuchos do WALL-8. Eles prevalecem
# sobre a tabela IBM para manter a identidade visual que o projeto ja usa.
_PROJECT_GLYPHS: dict[int, tuple[int, ...]] = {
    ord("0"): (0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0x00),
    ord("1"): (0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00),
    ord("2"): (0x3C, 0x66, 0x06, 0x0C, 0x30, 0x60, 0x7E, 0x00),
    ord("3"): (0x3C, 0x66, 0x06, 0x1C, 0x06, 0x66, 0x3C, 0x00),
    ord("4"): (0x0C, 0x1C, 0x3C, 0x6C, 0x7E, 0x0C, 0x0C, 0x00),
    ord("5"): (0x7E, 0x60, 0x7C, 0x06, 0x06, 0x66, 0x3C, 0x00),
    ord("6"): (0x1C, 0x30, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0x00),
    ord("7"): (0x7E, 0x66, 0x06, 0x0C, 0x18, 0x18, 0x18, 0x00),
    ord("8"): (0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0x00),
    ord("9"): (0x3C, 0x66, 0x66, 0x3E, 0x06, 0x0C, 0x38, 0x00),
    ord("A"): (0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00),
    ord("C"): (0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00),
    ord("E"): (0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00),
    ord("G"): (0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0x00),
    ord("I"): (0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00),
    ord("K"): (0x66, 0x6C, 0x78, 0x70, 0x78, 0x6C, 0x66, 0x00),
    ord("L"): (0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00),
    ord("M"): (0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0x00),
    ord("N"): (0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00),
    ord("O"): (0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00),
    ord("P"): (0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x00),
    ord("R"): (0x7C, 0x66, 0x66, 0x7C, 0x78, 0x6C, 0x66, 0x00),
    ord("S"): (0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00),
    ord("U"): (0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00),
    ord("V"): (0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x00),
    ord("W"): (0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00),
    ord("Y"): (0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x00),
}


def default_glyphs() -> dict[int, tuple[int, ...]]:
    """Retorna o mapa inicial do banco 00 na convencao D0 = esquerda."""
    result: dict[int, tuple[int, ...]] = {}
    for code in range(0x20, 0x80):
        offset = (code - 0x20) * ROWS_PER_GLYPH
        source = _BASIC_LATIN_LSB_ROWS[offset:offset + ROWS_PER_GLYPH]
        # Margens laterais fazem parte da celula; nao alteram 640 x 480.
        result[code] = tuple(row & 0x7E for row in source)
    for code, rows in _PROJECT_GLYPHS.items():
        # Os glifos historicos dos cartuchos foram escritos com D7 a esquerda.
        # Invertemos seus bytes para preservar a mesma aparencia visual.
        result[code] = tuple(reverse_byte(row) & 0x7E for row in rows)
    return result


class CharacterRom:
    """Modelo da imagem completa de uma EPROM 27C512."""

    def __init__(self, data: Optional[bytes | bytearray] = None) -> None:
        if data is None:
            self.data = bytearray([0xFF]) * ROM_SIZE
        else:
            if len(data) != ROM_SIZE:
                raise ValueError(
                    f"A imagem deve ter exatamente {ROM_SIZE} bytes; "
                    f"recebidos {len(data)}"
                )
            self.data = bytearray(data)

    @classmethod
    def blank(cls) -> "CharacterRom":
        rom = cls()
        # Somente os enderecos possiveis com A11..A13 em GND sao limpos.
        for bank in range(BANK_COUNT):
            for row in range(ROWS_PER_GLYPH):
                start = rom_address(bank, 0, row)
                rom.data[start:start + CHAR_COUNT] = bytes(CHAR_COUNT)
        return rom

    @classmethod
    def with_default_font(cls) -> "CharacterRom":
        rom = cls.blank()
        for code, rows in default_glyphs().items():
            rom.set_glyph(0, code, rows)
        return rom

    @classmethod
    def load(cls, path: Path) -> "CharacterRom":
        return cls(path.read_bytes())

    def save(self, path: Path) -> None:
        path.write_bytes(self.data)

    def get_glyph(self, bank: int, character: int) -> tuple[int, ...]:
        return tuple(
            self.data[rom_address(bank, character, row)]
            for row in range(ROWS_PER_GLYPH)
        )

    def set_glyph(
        self, bank: int, character: int, rows: Iterable[int]
    ) -> None:
        values = tuple(rows)
        if len(values) != ROWS_PER_GLYPH:
            raise ValueError("Um glifo precisa ter exatamente oito linhas")
        for row, value in enumerate(values):
            if not 0 <= value <= 0xFF:
                raise ValueError("Cada linha do glifo deve ser um byte")
            self.data[rom_address(bank, character, row)] = value


def printable_name(code: int) -> str:
    if 0x20 <= code <= 0x7E:
        if code == 0x20:
            return "ESPACO"
        return repr(chr(code))
    return "nao imprimivel"


class CharacterRomEditor:
    GRID_CELL = 42
    GRID_MARGIN_X = 42
    GRID_MARGIN_Y = 30
    PALETTE_CELL = 24
    PALETTE_MARGIN = 24

    COLOR_OFF = "#101711"
    COLOR_ON = "#59ff72"
    COLOR_GRID = "#426149"
    COLOR_SELECT = "#ffd45a"
    COLOR_BG = "#071007"

    def __init__(self, root, input_path: Optional[Path] = None) -> None:
        import tkinter as tk
        from tkinter import ttk

        self.tk = tk
        self.ttk = ttk
        self.root = root
        self.rom = CharacterRom.with_default_font()
        self.path: Optional[Path] = None
        self.bank = 0
        self.character = ord("A")
        self.clipboard_glyph: Optional[tuple[int, ...]] = None
        self.dirty = False
        self.drag_value: Optional[bool] = None
        self.pixel_items: list[list[int]] = []

        root.title("WALL-8 - Editor da ROM de caracteres 27C512")
        root.minsize(980, 690)
        root.protocol("WM_DELETE_WINDOW", self.close)

        self.bank_var = tk.StringVar(value=self._bank_label(0))
        self.code_var = tk.StringVar(value=f"{self.character:02X}")
        self.bytes_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Fonte padrao carregada no banco 00")
        self.character_info_var = tk.StringVar()
        self.addresses_var = tk.StringVar()

        self._build_menu()
        self._build_layout()
        self._redraw_palette()
        self._refresh_editor()

        if input_path is not None:
            self._load_path(input_path)

    @staticmethod
    def _bank_label(bank: int) -> str:
        return f"Banco {bank} - A15:A14 = {bank:02b}"

    def _build_menu(self) -> None:
        tk = self.tk
        menu = tk.Menu(self.root)
        file_menu = tk.Menu(menu, tearoff=False)
        file_menu.add_command(label="Nova ROM com fonte padrao", command=self.new_default)
        file_menu.add_command(label="Nova ROM vazia", command=self.new_blank)
        file_menu.add_separator()
        file_menu.add_command(label="Abrir .bin...", command=self.open_file, accelerator="Ctrl+O")
        file_menu.add_command(label="Salvar", command=self.save, accelerator="Ctrl+S")
        file_menu.add_command(label="Salvar como...", command=self.save_as)
        file_menu.add_separator()
        file_menu.add_command(label="Sair", command=self.close)
        menu.add_cascade(label="Arquivo", menu=file_menu)

        edit_menu = tk.Menu(menu, tearoff=False)
        edit_menu.add_command(label="Copiar glifo", command=self.copy_glyph, accelerator="Ctrl+C")
        edit_menu.add_command(label="Colar glifo", command=self.paste_glyph, accelerator="Ctrl+V")
        edit_menu.add_command(label="Limpar glifo", command=self.clear_glyph)
        edit_menu.add_command(label="Inverter glifo", command=self.invert_glyph)
        edit_menu.add_separator()
        edit_menu.add_command(label="Deslocar para esquerda", command=lambda: self.shift_glyph("left"))
        edit_menu.add_command(label="Deslocar para direita", command=lambda: self.shift_glyph("right"))
        edit_menu.add_command(label="Deslocar para cima", command=lambda: self.shift_glyph("up"))
        edit_menu.add_command(label="Deslocar para baixo", command=lambda: self.shift_glyph("down"))
        menu.add_cascade(label="Editar", menu=edit_menu)

        help_menu = tk.Menu(menu, tearoff=False)
        help_menu.add_command(label="Mapa de enderecos", command=self.show_address_help)
        help_menu.add_command(label="Como usar", command=self.show_usage_help)
        menu.add_cascade(label="Ajuda", menu=help_menu)
        self.root.configure(menu=menu)

        self.root.bind("<Control-o>", lambda _event: self.open_file())
        self.root.bind("<Control-s>", lambda _event: self.save())
        self.root.bind("<Control-c>", lambda _event: self.copy_glyph())
        self.root.bind("<Control-v>", lambda _event: self.paste_glyph())
        self.root.bind("<Left>", lambda _event: self.select_character((self.character - 1) & 0xFF))
        self.root.bind("<Right>", lambda _event: self.select_character((self.character + 1) & 0xFF))

    def _build_layout(self) -> None:
        tk = self.tk
        ttk = self.ttk

        top = ttk.Frame(self.root, padding=(10, 8))
        top.pack(fill="x")

        ttk.Label(top, text="Banco:").pack(side="left")
        bank_box = ttk.Combobox(
            top,
            textvariable=self.bank_var,
            values=[self._bank_label(i) for i in range(BANK_COUNT)],
            width=25,
            state="readonly",
        )
        bank_box.pack(side="left", padx=(5, 18))
        bank_box.bind("<<ComboboxSelected>>", self._bank_changed)

        ttk.Label(top, text="Codigo hexadecimal:").pack(side="left")
        code_entry = ttk.Entry(top, textvariable=self.code_var, width=6)
        code_entry.pack(side="left", padx=5)
        code_entry.bind("<Return>", self._code_entered)
        ttk.Button(top, text="Ir", command=self._code_entered, width=5).pack(side="left")
        ttk.Button(top, text="◀", command=lambda: self.select_character((self.character - 1) & 0xFF), width=4).pack(side="left", padx=(12, 2))
        ttk.Button(top, text="▶", command=lambda: self.select_character((self.character + 1) & 0xFF), width=4).pack(side="left")
        ttk.Label(top, textvariable=self.character_info_var).pack(side="left", padx=14)

        body = ttk.Panedwindow(self.root, orient="horizontal")
        body.pack(fill="both", expand=True, padx=10, pady=(0, 8))

        palette_frame = ttk.LabelFrame(body, text="Mapa de caracteres - clique para selecionar", padding=7)
        editor_frame = ttk.LabelFrame(body, text="Editor do glifo 8 x 8", padding=8)
        body.add(palette_frame, weight=3)
        body.add(editor_frame, weight=2)

        palette_size = self.PALETTE_MARGIN + 16 * self.PALETTE_CELL + 2
        self.palette = tk.Canvas(
            palette_frame,
            width=palette_size,
            height=palette_size,
            background=self.COLOR_BG,
            highlightthickness=0,
        )
        self.palette.pack(fill="both", expand=True)
        self.palette.bind("<Button-1>", self._palette_clicked)
        self.palette.bind("<Motion>", self._palette_motion)
        self.palette.bind("<Leave>", lambda _event: self.status_var.set(""))

        grid_width = self.GRID_MARGIN_X + 8 * self.GRID_CELL + 2
        grid_height = self.GRID_MARGIN_Y + 8 * self.GRID_CELL + 2
        self.grid = tk.Canvas(
            editor_frame,
            width=grid_width,
            height=grid_height,
            background=self.COLOR_BG,
            highlightthickness=0,
        )
        self.grid.pack(anchor="center")
        self._create_grid()
        self.grid.bind("<Button-1>", self._grid_press)
        self.grid.bind("<B1-Motion>", self._grid_drag)
        self.grid.bind("<ButtonRelease-1>", lambda _event: setattr(self, "drag_value", None))
        self.grid.bind("<Button-3>", self._grid_erase)
        self.grid.bind("<B3-Motion>", self._grid_erase)

        byte_row = ttk.Frame(editor_frame)
        byte_row.pack(fill="x", pady=(8, 3))
        ttk.Label(byte_row, text="8 bytes:").pack(side="left")
        byte_entry = ttk.Entry(byte_row, textvariable=self.bytes_var)
        byte_entry.pack(side="left", fill="x", expand=True, padx=6)
        byte_entry.bind("<Return>", self.apply_bytes)
        ttk.Button(byte_row, text="Aplicar", command=self.apply_bytes).pack(side="left")

        tools = ttk.Frame(editor_frame)
        tools.pack(fill="x", pady=4)
        for text, command in (
            ("Copiar", self.copy_glyph),
            ("Colar", self.paste_glyph),
            ("Limpar", self.clear_glyph),
            ("Inverter", self.invert_glyph),
            ("←", lambda: self.shift_glyph("left")),
            ("→", lambda: self.shift_glyph("right")),
            ("↑", lambda: self.shift_glyph("up")),
            ("↓", lambda: self.shift_glyph("down")),
        ):
            ttk.Button(tools, text=text, command=command).pack(side="left", padx=2)

        lower = ttk.Frame(editor_frame)
        lower.pack(fill="both", expand=True, pady=(5, 0))
        preview_box = ttk.LabelFrame(lower, text="Previa fisica 8 x 16", padding=5)
        preview_box.pack(side="left", fill="y")
        self.preview = tk.Canvas(
            preview_box, width=82, height=162, background=self.COLOR_BG, highlightthickness=0
        )
        self.preview.pack()

        address_box = ttk.LabelFrame(lower, text="Enderecos na 27C512", padding=6)
        address_box.pack(side="left", fill="both", expand=True, padx=(8, 0))
        ttk.Label(address_box, textvariable=self.addresses_var, font=("TkFixedFont", 9), justify="left").pack(anchor="nw")

        status = ttk.Label(self.root, textvariable=self.status_var, relief="sunken", anchor="w", padding=(6, 3))
        status.pack(fill="x", side="bottom")

    def _create_grid(self) -> None:
        self.pixel_items.clear()
        for column in range(8):
            self.grid.create_text(
                self.GRID_MARGIN_X + column * self.GRID_CELL + self.GRID_CELL / 2,
                self.GRID_MARGIN_Y / 2,
                text=str(column),
                fill="#b7cab9",
            )
        for row in range(8):
            self.grid.create_text(
                self.GRID_MARGIN_X / 2,
                self.GRID_MARGIN_Y + row * self.GRID_CELL + self.GRID_CELL / 2,
                text=str(row),
                fill="#b7cab9",
            )
            item_row = []
            for column in range(8):
                x0 = self.GRID_MARGIN_X + column * self.GRID_CELL
                y0 = self.GRID_MARGIN_Y + row * self.GRID_CELL
                item_row.append(
                    self.grid.create_rectangle(
                        x0,
                        y0,
                        x0 + self.GRID_CELL,
                        y0 + self.GRID_CELL,
                        fill=self.COLOR_OFF,
                        outline=self.COLOR_GRID,
                        width=1,
                    )
                )
            self.pixel_items.append(item_row)

    def _redraw_palette(self) -> None:
        self.palette.delete("all")
        margin = self.PALETTE_MARGIN
        cell = self.PALETTE_CELL
        glyph_scale = 2
        glyph_offset = (cell - 8 * glyph_scale) // 2

        for value in range(16):
            label = f"{value:X}"
            self.palette.create_text(
                margin + value * cell + cell / 2,
                margin / 2,
                text=label,
                fill="#b7cab9",
            )
            self.palette.create_text(
                margin / 2,
                margin + value * cell + cell / 2,
                text=label,
                fill="#b7cab9",
            )

        for code in range(CHAR_COUNT):
            palette_row, palette_column = divmod(code, 16)
            x0 = margin + palette_column * cell
            y0 = margin + palette_row * cell
            selected = code == self.character
            self.palette.create_rectangle(
                x0,
                y0,
                x0 + cell,
                y0 + cell,
                outline=self.COLOR_SELECT if selected else "#263c2b",
                width=2 if selected else 1,
            )
            for glyph_row, value in enumerate(self.rom.get_glyph(self.bank, code)):
                for column in range(8):
                    if value & (1 << column):
                        px = x0 + glyph_offset + column * glyph_scale
                        py = y0 + glyph_offset + glyph_row * glyph_scale
                        self.palette.create_rectangle(
                            px,
                            py,
                            px + glyph_scale,
                            py + glyph_scale,
                            fill=self.COLOR_ON,
                            outline="",
                        )

    def _refresh_editor(self, redraw_palette: bool = False) -> None:
        rows = self.rom.get_glyph(self.bank, self.character)
        for row, value in enumerate(rows):
            for column in range(8):
                color = self.COLOR_ON if value & (1 << column) else self.COLOR_OFF
                self.grid.itemconfigure(self.pixel_items[row][column], fill=color)

        self.code_var.set(f"{self.character:02X}")
        self.bytes_var.set(" ".join(f"{value:02X}" for value in rows))
        self.character_info_var.set(
            f"${self.character:02X}  {printable_name(self.character)}"
        )
        address_lines = []
        for row, value in enumerate(rows):
            address = rom_address(self.bank, self.character, row)
            address_lines.append(
                f"linha {row}:  ${address:04X} = ${value:02X}  {value:08b}"
            )
        self.addresses_var.set("\n".join(address_lines))
        self._redraw_preview(rows)
        if redraw_palette:
            self._redraw_palette()

    def _redraw_preview(self, rows: Iterable[int]) -> None:
        self.preview.delete("all")
        scale = 10
        for logical_row, value in enumerate(rows):
            for repetition in range(2):
                physical_row = logical_row * 2 + repetition
                for column in range(8):
                    if value & (1 << column):
                        x0 = column * scale + 1
                        y0 = physical_row * scale + 1
                        self.preview.create_rectangle(
                            x0,
                            y0,
                            x0 + scale,
                            y0 + scale,
                            fill=self.COLOR_ON,
                            outline="",
                        )

    def _palette_position(self, event) -> Optional[int]:
        column = int((event.x - self.PALETTE_MARGIN) // self.PALETTE_CELL)
        row = int((event.y - self.PALETTE_MARGIN) // self.PALETTE_CELL)
        if 0 <= column < 16 and 0 <= row < 16:
            return row * 16 + column
        return None

    def _palette_clicked(self, event) -> None:
        code = self._palette_position(event)
        if code is not None:
            self.select_character(code)

    def _palette_motion(self, event) -> None:
        code = self._palette_position(event)
        if code is not None:
            self.status_var.set(
                f"Banco {self.bank}, codigo ${code:02X}: {printable_name(code)}"
            )

    def _grid_position(self, event) -> Optional[tuple[int, int]]:
        column = int((event.x - self.GRID_MARGIN_X) // self.GRID_CELL)
        row = int((event.y - self.GRID_MARGIN_Y) // self.GRID_CELL)
        if 0 <= column < 8 and 0 <= row < 8:
            return row, column
        return None

    def _grid_press(self, event) -> None:
        position = self._grid_position(event)
        if position is None:
            return
        row, column = position
        value = self.rom.get_glyph(self.bank, self.character)[row]
        self.drag_value = not bool(value & (1 << column))
        self._set_pixel(row, column, self.drag_value)

    def _grid_drag(self, event) -> None:
        position = self._grid_position(event)
        if position is not None and self.drag_value is not None:
            self._set_pixel(position[0], position[1], self.drag_value)

    def _grid_erase(self, event) -> None:
        position = self._grid_position(event)
        if position is not None:
            self._set_pixel(position[0], position[1], False)

    def _set_pixel(self, row: int, column: int, enabled: bool) -> None:
        rows = list(self.rom.get_glyph(self.bank, self.character))
        mask = 1 << column
        new_value = (rows[row] | mask) if enabled else (rows[row] & ~mask)
        if new_value == rows[row]:
            return
        rows[row] = new_value
        self.rom.set_glyph(self.bank, self.character, rows)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def _bank_changed(self, _event=None) -> None:
        try:
            self.bank = [self._bank_label(i) for i in range(BANK_COUNT)].index(
                self.bank_var.get()
            )
        except ValueError:
            self.bank = 0
            self.bank_var.set(self._bank_label(0))
        self._redraw_palette()
        self._refresh_editor()
        self.status_var.set(f"Selecionado {self._bank_label(self.bank)}")

    def _code_entered(self, _event=None) -> None:
        from tkinter import messagebox

        text = self.code_var.get().strip()
        try:
            if text.startswith("$"):
                value = int(text[1:], 16)
            elif text.lower().startswith("0x"):
                value = int(text, 16)
            else:
                value = int(text, 16)
            if not 0 <= value <= 0xFF:
                raise ValueError
        except ValueError:
            messagebox.showerror("Codigo invalido", "Digite um valor hexadecimal de 00 ate FF.")
            self.code_var.set(f"{self.character:02X}")
            return
        self.select_character(value)

    def select_character(self, code: int) -> None:
        self.character = code & 0xFF
        self._redraw_palette()
        self._refresh_editor()

    def apply_bytes(self, _event=None) -> None:
        from tkinter import messagebox

        text = self.bytes_var.get().replace(",", " ").replace("$", "")
        try:
            rows = tuple(int(part, 16) for part in text.split())
            if len(rows) != 8 or any(not 0 <= value <= 0xFF for value in rows):
                raise ValueError
        except ValueError:
            messagebox.showerror(
                "Bytes invalidos",
                "Informe exatamente oito bytes hexadecimais, por exemplo:\n"
                "7E 60 60 7C 60 60 7E 00",
            )
            self._refresh_editor()
            return
        self.rom.set_glyph(self.bank, self.character, rows)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def copy_glyph(self) -> None:
        self.clipboard_glyph = self.rom.get_glyph(self.bank, self.character)
        self.status_var.set(
            f"Glifo ${self.character:02X} do banco {self.bank} copiado"
        )

    def paste_glyph(self) -> None:
        if self.clipboard_glyph is None:
            self.status_var.set("Nenhum glifo foi copiado ainda")
            return
        self.rom.set_glyph(self.bank, self.character, self.clipboard_glyph)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def clear_glyph(self) -> None:
        self.rom.set_glyph(self.bank, self.character, (0,) * 8)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def invert_glyph(self) -> None:
        rows = tuple(value ^ 0xFF for value in self.rom.get_glyph(self.bank, self.character))
        self.rom.set_glyph(self.bank, self.character, rows)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def shift_glyph(self, direction: str) -> None:
        rows = list(self.rom.get_glyph(self.bank, self.character))
        if direction == "left":
            rows = [(value >> 1) for value in rows]
        elif direction == "right":
            rows = [((value << 1) & 0xFF) for value in rows]
        elif direction == "up":
            rows = rows[1:] + [0]
        elif direction == "down":
            rows = [0] + rows[:-1]
        else:
            raise ValueError(direction)
        self.rom.set_glyph(self.bank, self.character, rows)
        self._mark_dirty()
        self._refresh_editor(redraw_palette=True)

    def _mark_dirty(self) -> None:
        self.dirty = True
        self._update_title()

    def _update_title(self) -> None:
        name = self.path.name if self.path else "nova ROM"
        marker = " *" if self.dirty else ""
        self.root.title(f"WALL-8 - Editor ROM 27C512 - {name}{marker}")

    def _confirm_discard(self) -> bool:
        from tkinter import messagebox

        if not self.dirty:
            return True
        answer = messagebox.askyesnocancel(
            "Alteracoes nao salvas",
            "Deseja salvar as alteracoes antes de continuar?",
        )
        if answer is None:
            return False
        if answer:
            return self.save()
        return True

    def new_default(self) -> None:
        if not self._confirm_discard():
            return
        self.rom = CharacterRom.with_default_font()
        self.path = None
        self.dirty = True
        self.bank = 0
        self.bank_var.set(self._bank_label(0))
        self._redraw_palette()
        self._refresh_editor()
        self._update_title()
        self.status_var.set("Nova ROM com fonte ASCII criada no banco 00")

    def new_blank(self) -> None:
        if not self._confirm_discard():
            return
        self.rom = CharacterRom.blank()
        self.path = None
        self.dirty = True
        self._redraw_palette()
        self._refresh_editor()
        self._update_title()
        self.status_var.set("Nova ROM vazia criada")

    def open_file(self) -> None:
        from tkinter import filedialog

        if not self._confirm_discard():
            return
        filename = filedialog.askopenfilename(
            title="Abrir imagem da ROM de caracteres",
            filetypes=(("Imagem binaria", "*.bin"), ("Todos os arquivos", "*.*")),
        )
        if filename:
            self._load_path(Path(filename))

    def _load_path(self, path: Path) -> None:
        from tkinter import messagebox

        try:
            self.rom = CharacterRom.load(path)
        except (OSError, ValueError) as error:
            messagebox.showerror("Erro ao abrir", str(error))
            return
        self.path = path
        self.dirty = False
        self._redraw_palette()
        self._refresh_editor()
        self._update_title()
        self.status_var.set(f"Carregado: {path} ({ROM_SIZE} bytes)")

    def save(self) -> bool:
        if self.path is None:
            return self.save_as()
        return self._save_path(self.path)

    def save_as(self) -> bool:
        from tkinter import filedialog

        filename = filedialog.asksaveasfilename(
            title="Salvar imagem da ROM de caracteres",
            defaultextension=".bin",
            initialfile=self.path.name if self.path else DEFAULT_OUTPUT_NAME,
            filetypes=(("Imagem binaria", "*.bin"), ("Todos os arquivos", "*.*")),
        )
        if not filename:
            return False
        return self._save_path(Path(filename))

    def _save_path(self, path: Path) -> bool:
        from tkinter import messagebox

        try:
            self.rom.save(path)
        except OSError as error:
            messagebox.showerror("Erro ao salvar", str(error))
            return False
        self.path = path
        self.dirty = False
        self._update_title()
        self.status_var.set(f"Salvo: {path} ({ROM_SIZE} bytes)")
        return True

    def close(self) -> None:
        if self._confirm_discard():
            self.root.destroy()

    def show_address_help(self) -> None:
        from tkinter import messagebox

        messagebox.showinfo(
            "Mapa de enderecos",
            "A0..A7   = codigo do caractere (VRAM_LATCH)\n"
            "A8..A10  = linha 0..7 (V_COUNT_1..3)\n"
            "A11..A13 = 000 (GND)\n"
            "A14..A15 = banco\n\n"
            "endereco = (banco << 14) | (linha << 8) | codigo\n\n"
            "D0 e o pixel esquerdo; D7 e o pixel direito.",
        )

    def show_usage_help(self) -> None:
        from tkinter import messagebox

        messagebox.showinfo(
            "Como usar",
            "Selecione o banco e o codigo no mapa 16 x 16.\n"
            "Clique em um pixel para alterna-lo. Arraste para desenhar.\n"
            "Use o botao direito para apagar pixels.\n"
            "Os oito bytes tambem podem ser digitados diretamente.\n"
            "Copiar/Colar permite repetir um glifo em outro codigo ou banco.\n\n"
            "A previa 8 x 16 mostra a duplicacao vertical feita pela GPU.\n"
            "O arquivo salvo sempre possui 65.536 bytes.",
        )


def run_self_test() -> None:
    assert len(_BASIC_LATIN_LSB_ROWS) == 96 * 8
    assert rom_address(0, 0x00, 0) == 0x0000
    assert rom_address(0, 0x45, 0) == 0x0045
    assert rom_address(0, 0x45, 7) == 0x0745
    assert rom_address(1, 0x45, 0) == 0x4045
    assert rom_address(2, 0x45, 0) == 0x8045
    assert rom_address(3, 0xFF, 7) == 0xC7FF

    rom = CharacterRom.with_default_font()
    assert len(rom.data) == ROM_SIZE
    assert rom.get_glyph(0, ord("E")) == (
        0x7E, 0x06, 0x06, 0x3E, 0x06, 0x06, 0x7E, 0x00
    )
    assert rom.get_glyph(1, ord("E")) == (0,) * 8
    assert rom.data[0x0800] == 0xFF  # A11=1: endereco nunca selecionado

    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / DEFAULT_OUTPUT_NAME
        rom.save(output)
        loaded = CharacterRom.load(output)
        assert loaded.data == rom.data
        assert output.stat().st_size == ROM_SIZE

    print("Self-test OK: enderecamento, fonte padrao e arquivo de 65536 bytes")


def parse_arguments(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--generate",
        metavar="ARQUIVO",
        type=Path,
        help="gera a ROM padrao sem abrir a interface grafica",
    )
    parser.add_argument(
        "--input",
        metavar="ARQUIVO",
        type=Path,
        help="abre uma ROM existente ao iniciar a interface",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="valida o enderecamento e o formato da ROM",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_arguments(argv)
    if args.self_test:
        run_self_test()
        return 0
    if args.generate is not None:
        rom = CharacterRom.with_default_font()
        rom.save(args.generate)
        print(f"ROM gerada: {args.generate} ({ROM_SIZE} bytes)")
        return 0

    try:
        import tkinter as tk

        root = tk.Tk()
    except Exception as error:
        print(f"Nao foi possivel iniciar o Tkinter: {error}", file=sys.stderr)
        return 1

    CharacterRomEditor(root, args.input)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
