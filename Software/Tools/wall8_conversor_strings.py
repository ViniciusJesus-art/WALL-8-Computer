#!/usr/bin/env python3
"""
Conversor de strings para o assembler do WALL-8.

Converte:
    Texto normal -> linhas #d8 0xNN, 0xNN...
    Matriz #d8/bytes -> texto normal

Aceita na conversão inversa:
    0x41
    $41
    41h
    65          (decimal)
    #d8 0x41, 0x42, 0x00

O byte 0x00 pode ser tratado como terminador da string.
"""

from __future__ import annotations

import re
import tkinter as tk
from tkinter import messagebox, ttk


HEX_TOKEN_RE = re.compile(
    r"""
    (?:
        0x(?P<hex0>[0-9a-fA-F]{1,2})
        |
        \$(?P<hex1>[0-9a-fA-F]{1,2})
        |
        (?P<hex2>[0-9a-fA-F]{1,2})[hH]
        |
        (?P<decimal>\d{1,3})
    )
    """,
    re.VERBOSE,
)

WALL8_TEXT_COLUMNS = 80
WALL8_TEXT_ROWS = 30
WALL8_TEXT_FONT = ("Consolas", 11)


def text_to_asm(
    text: str,
    *,
    bytes_per_line: int = 16,
    append_null: bool = True,
    encoding: str = "latin-1",
) -> str:
    """Converte texto em diretivas #d8."""
    # O editor Tk usa LF para mudar de linha, enquanto o terminal WALL-8 usa CR.
    # Normalize antes de codificar para preservar o desenho mostrado na grade.
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r")
    try:
        data = bytearray(text.encode(encoding))
    except UnicodeEncodeError as exc:
        bad = text[exc.start : exc.end]
        raise ValueError(
            f"O caractere {bad!r} não cabe em um byte usando {encoding}."
        ) from exc

    if append_null and (not data or data[-1] != 0):
        data.append(0)

    lines: list[str] = []
    for start in range(0, len(data), bytes_per_line):
        chunk = data[start : start + bytes_per_line]
        values = ", ".join(f"0x{value:02X}" for value in chunk)
        lines.append(f"    #d8 {values}")

    return "\n".join(lines)


def parse_byte_matrix(source: str) -> bytes:
    """Extrai bytes de linhas #d8 ou de uma lista de valores."""
    # Remove comentários comuns antes de procurar os números.
    cleaned_lines = []
    for line in source.splitlines():
        line = line.split(";", 1)[0]
        line = line.split("//", 1)[0]
        line = re.sub(r"^\s*#d8\b", "", line, flags=re.IGNORECASE)
        cleaned_lines.append(line)

    cleaned = "\n".join(cleaned_lines)
    values: list[int] = []

    for match in HEX_TOKEN_RE.finditer(cleaned):
        if match.group("hex0") is not None:
            value = int(match.group("hex0"), 16)
        elif match.group("hex1") is not None:
            value = int(match.group("hex1"), 16)
        elif match.group("hex2") is not None:
            value = int(match.group("hex2"), 16)
        else:
            value = int(match.group("decimal"), 10)

        if not 0 <= value <= 0xFF:
            raise ValueError(f"Valor fora de 8 bits: {value}")

        values.append(value)

    if not values:
        raise ValueError("Nenhum byte foi encontrado.")

    return bytes(values)


def asm_to_text(
    source: str,
    *,
    stop_at_null: bool = True,
    encoding: str = "latin-1",
) -> str:
    """Converte uma matriz de bytes em texto."""
    data = parse_byte_matrix(source)

    if stop_at_null:
        null_index = data.find(b"\x00")
        if null_index >= 0:
            data = data[:null_index]

    text = data.decode(encoding, errors="replace")
    # CR (0x0D) e CR+LF do WALL-8 precisam virar uma quebra real no tk.Text.
    return text.replace("\r\n", "\n").replace("\r", "\n")


class Wall8StringConverter(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("WALL-8 — Conversor de Strings")
        self.geometry("1100x680")
        self.minsize(850, 520)

        self.append_null = tk.BooleanVar(value=True)
        self.stop_at_null = tk.BooleanVar(value=True)
        self.bytes_per_line = tk.IntVar(value=16)

        self._build_ui()
        self.update_idletasks()
        required_width = self.winfo_reqwidth()
        required_height = self.winfo_reqheight()
        self.geometry(f"{max(1100, required_width)}x{max(680, required_height)}")
        self.minsize(required_width, required_height)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=10)
        root.pack(fill="both", expand=True)

        options = ttk.Frame(root)
        options.pack(fill="x", pady=(0, 8))

        ttk.Label(options, text="Bytes por linha:").pack(side="left")
        ttk.Spinbox(
            options,
            from_=1,
            to=64,
            textvariable=self.bytes_per_line,
            width=5,
        ).pack(side="left", padx=(4, 14))

        ttk.Checkbutton(
            options,
            text="Adicionar 0x00 no final",
            variable=self.append_null,
        ).pack(side="left", padx=(0, 14))

        ttk.Checkbutton(
            options,
            text="Parar no primeiro 0x00 ao decodificar",
            variable=self.stop_at_null,
        ).pack(side="left")

        panes = ttk.Panedwindow(root, orient="horizontal")
        panes.pack(fill="both", expand=True)

        left = ttk.LabelFrame(
            panes,
            text="Texto normal (tela WALL-8: 80 x 30)",
            padding=6,
        )
        right = ttk.LabelFrame(panes, text="Matriz para o ASM", padding=6)
        panes.add(left, weight=0)
        panes.add(right, weight=1)

        self.text_input = tk.Text(
            left,
            width=WALL8_TEXT_COLUMNS,
            height=WALL8_TEXT_ROWS,
            wrap="char",
            font=WALL8_TEXT_FONT,
            undo=True,
        )
        # Nao permita que o gerenciador de geometria altere a grade visivel:
        # cada celula da fonte monoespacada representa uma celula da tela WALL-8.
        self.text_input.pack(anchor="nw")

        self.asm_input = tk.Text(
            right,
            wrap="none",
            font=("Consolas", 11),
            undo=True,
        )
        self.asm_input.pack(fill="both", expand=True)

        buttons = ttk.Frame(root)
        buttons.pack(fill="x", pady=(8, 0))

        ttk.Button(
            buttons,
            text="Texto → #d8",
            command=self.convert_text_to_asm,
        ).pack(side="left", padx=(0, 6))

        ttk.Button(
            buttons,
            text="#d8 → Texto",
            command=self.convert_asm_to_text,
        ).pack(side="left", padx=(0, 6))

        ttk.Button(
            buttons,
            text="Limpar tudo",
            command=self.clear_all,
        ).pack(side="left")

        ttk.Button(
            buttons,
            text="Copiar matriz",
            command=self.copy_asm,
        ).pack(side="right")

        self.status = tk.StringVar(
            value="Pronto. A codificação usada é Latin-1, um byte por caractere."
        )
        ttk.Label(root, textvariable=self.status).pack(
            fill="x",
            pady=(8, 0),
        )

    def convert_text_to_asm(self) -> None:
        try:
            text = self.text_input.get("1.0", "end-1c")
            result = text_to_asm(
                text,
                bytes_per_line=max(1, self.bytes_per_line.get()),
                append_null=self.append_null.get(),
            )
            self.asm_input.delete("1.0", "end")
            self.asm_input.insert("1.0", result)
            byte_count = len(parse_byte_matrix(result))
            self.status.set(f"Convertido para {byte_count} bytes.")
        except Exception as exc:
            messagebox.showerror("Erro na conversão", str(exc))

    def convert_asm_to_text(self) -> None:
        try:
            source = self.asm_input.get("1.0", "end-1c")
            result = asm_to_text(
                source,
                stop_at_null=self.stop_at_null.get(),
            )
            self.text_input.delete("1.0", "end")
            self.text_input.insert("1.0", result)
            self.status.set(
                f"Convertido para {len(result)} caracteres visíveis."
            )
        except Exception as exc:
            messagebox.showerror("Erro na conversão", str(exc))

    def clear_all(self) -> None:
        self.text_input.delete("1.0", "end")
        self.asm_input.delete("1.0", "end")
        self.status.set("Campos limpos.")

    def copy_asm(self) -> None:
        content = self.asm_input.get("1.0", "end-1c")
        self.clipboard_clear()
        self.clipboard_append(content)
        self.status.set("Matriz copiada para a área de transferência.")


def main() -> None:
    app = Wall8StringConverter()
    app.mainloop()


if __name__ == "__main__":
    main()
