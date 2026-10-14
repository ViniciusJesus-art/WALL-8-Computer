# ============================================================
# Gera EEPROMs para display HEX/CHAR do Wall-8
#
# Endereçamento da EEPROM:
#
# A0-A7 = byte de entrada
#
# A8    = seleção do dígito
#         0 = dígito da esquerda -> nibble alto
#         1 = dígito da direita  -> nibble baixo
#
# A9    = modo
#         0 = HEX
#         1 = CHAR
#
# A10-A15 = GND
#
# Saída:
# D0-D6 = segmentos A-G (ativos em nível baixo)
# D7    = DP / não usado (mantido em nível alto)
#
# Arquivos gerados:
# display_low.bin  -> EEPROM do byte LOW
# display_high.bin -> EEPROM do byte HIGH
#
# Observação:
# Os dois arquivos são iguais.
# A diferença é qual byte você liga em A0-A7 de cada EEPROM.
# ============================================================


# ============================================================
# Tabela de segmentos
#
# Display ânodo comum:
# 0 = segmento aceso
# 1 = segmento apagado
#
# D0 = segmento A
# D1 = segmento B
# D2 = segmento C
# D3 = segmento D
# D4 = segmento E
# D5 = segmento F
# D6 = segmento G
# D7 = ponto decimal
# ============================================================

SEG_HEX = {
    0x0: 0xC0,  # 0
    0x1: 0xF9,  # 1
    0x2: 0xA4,  # 2
    0x3: 0xB0,  # 3
    0x4: 0x99,  # 4
    0x5: 0x92,  # 5
    0x6: 0x82,  # 6
    0x7: 0xF8,  # 7
    0x8: 0x80,  # 8
    0x9: 0x90,  # 9
    0xA: 0x88,  # A
    0xB: 0x83,  # b
    0xC: 0xC6,  # C
    0xD: 0xA1,  # d
    0xE: 0x86,  # E
    0xF: 0x8E,  # F
}

BLANK = 0xFF


# ============================================================
# Tabela de caracteres para modo CHAR
#
# Cada nibble vira um caractere.
#
# Sugestão de códigos:
#
# 0 = espaço/apagado
# 1 = A
# 2 = b
# 3 = C
# 4 = d
# 5 = E
# 6 = F
# 7 = H
# 8 = L
# 9 = O
# A = P
# B = r
# C = t
# D = U
# E = -
# F = _
# ============================================================

CHAR_SEG = {
    0x0: BLANK, # espaço
    0x1: 0x88,  # A
    0x2: 0x83,  # b
    0x3: 0xC6,  # C
    0x4: 0xA1,  # d
    0x5: 0x86,  # E
    0x6: 0x8E,  # F
    0x7: 0x89,  # H
    0x8: 0xC7,  # L
    0x9: 0xC0,  # O
    0xA: 0x8C,  # P
    0xB: 0xAF,  # r
    0xC: 0x87,  # t
    0xD: 0xC1,  # U
    0xE: 0xBF,  # -
    0xF: 0xF7,  # _
}

EEPROM_SIZE = 65536  # 27C512 = 64 KiB


def pega_nibble(valor, digito_sel):
    """
    valor      = A0-A7
    digito_sel = A8

    digito_sel = 0 -> nibble alto   -> dígito da esquerda
    digito_sel = 1 -> nibble baixo  -> dígito da direita
    """

    if digito_sel == 0:
        return (valor >> 4) & 0x0F
    else:
        return valor & 0x0F


def gera_byte_saida(valor, digito_sel, modo):
    """
    valor      = A0-A7
    digito_sel = A8
    modo       = A9

    modo = 0 -> HEX
    modo = 1 -> CHAR
    """

    nibble = pega_nibble(valor, digito_sel)

    # Modo HEX normal
    if modo == 0:
        return SEG_HEX[nibble]

    # Modo CHAR
    else:
        return CHAR_SEG[nibble]


def gerar_arquivo(nome_arquivo):
    memoria = bytearray([BLANK] * EEPROM_SIZE)

    for endereco in range(EEPROM_SIZE):
        valor = endereco & 0xFF
        digito_sel = (endereco >> 8) & 0x01
        modo = (endereco >> 9) & 0x01

        memoria[endereco] = gera_byte_saida(
            valor=valor,
            digito_sel=digito_sel,
            modo=modo
        )

    with open(nome_arquivo, "wb") as arquivo:
        arquivo.write(memoria)

    print(f"Arquivo gerado: {nome_arquivo}")
    print(f"Tamanho: {len(memoria)} bytes")


gerar_arquivo("display_low.bin")
gerar_arquivo("display_high.bin")

print("Concluído.")
