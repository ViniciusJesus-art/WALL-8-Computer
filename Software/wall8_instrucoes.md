# WALL-8 — Referência da ISA

[← Voltar para a apresentação do WALL-8](../README.md) · [Referência de hardware e microarquitetura](../Hardware/wall8_CPU_Hardware.md)

Esta é a referência prática dos **76 opcodes** definidos na revisão atual de [`wall8.cpu`](wall8.cpu).

O documento mostra a sintaxe aceita pelo montador, os bytes produzidos, a quantidade de ciclos, o efeito de cada instrução e as alterações visíveis em flags e registradores. A apresentação do projeto está no [`README.md`](../README.md); os sinais elétricos, bits das ROMs e microsteps estão em [`Hardware/wall8_CPU_Hardware.md`](../Hardware/wall8_CPU_Hardware.md).

## Sumário

- [Convenções](#convenções)
- [Montagem e formato binário](#montagem-e-formato-binário)
- [Modelo de programação](#modelo-de-programação)
- [1. Sistema e controle](#1-sistema-e-controle)
- [2. Load, store e movimentação](#2-load-store-e-movimentação)
- [3. Ponteiro PTR](#3-ponteiro-ptr)
- [4. ALU entre registradores](#4-alu-entre-registradores)
- [5. Comparação, incremento e clear](#5-comparação-incremento-e-clear)
- [6. Jumps, pilha e subrotinas](#6-jumps-pilha-e-subrotinas)
- [7. ALU com valor imediato](#7-alu-com-valor-imediato)
- [Exemplos rápidos](#exemplos-rápidos)
- [Programando os periféricos](#programando-os-periféricos)
- [Exemplos completos](#exemplos-completos)
- [Organização da BIOS](#organização-da-bios)
- [Créditos](#créditos)

## Convenções

| Forma | Significado |
|---|---|
| `A` | Registrador A / acumulador |
| `B` | Registrador B |
| `#$xx` | Valor imediato de 8 bits |
| `$addr` | Endereço absoluto de 16 bits |
| `[PTR]` | Memória no endereço guardado em PTR |
| `[PTR+]` | Acessa MEM[PTR] e incrementa PTR depois |
| `LL HH` | Endereço little-endian: byte baixo e depois byte alto |

Exemplo:

```asm
LDA $1234
```

Bytes:

```text
12 34 12
```

A coluna `Atualiza flags` indica se a instrução grava um novo estado em `Z`, `C`, `N` e `V`. A coluna `Altera registradores A/B` considera somente o estado final visível de A e B; alterações internas temporárias do microcódigo não contam.

Os endereços de 16 bits sempre são emitidos em **little-endian**. Assim, `LL` é o byte baixo e `HH` é o byte alto.

As contagens da coluna `Ciclos` incluem o fetch comum do opcode e o microstep que encerra a instrução. Um ciclo corresponde a um período do clock selecionado em `CPU_CFG`.

## Montagem e formato binário

O arquivo `wall8.cpu` utiliza a sintaxe do [customasm](https://github.com/hlorenzi/customasm). Um programa deve incluir a definição da arquitetura antes das instruções:

```asm
#include "wall8.cpu"

LDA #$55
STA $0100
HLT
```

Exemplo de montagem para uma imagem binária simples:

```bash
customasm programa.asm -f binary -o programa.bin
```

Os valores imediatos possuem 8 bits. Endereços absolutos, `PTR` e `SP` possuem 16 bits. Valores fora dessas larguras devem ser tratados como erro de programação, e não truncados manualmente sem verificar o resultado.

## Modelo de programação

### Registradores disponíveis

| Registrador | Uso pelo software |
|---|---|
| `A` | Acumulador, primeiro argumento e valor de retorno sugerido |
| `B` | Segundo operando e temporário |
| `PTR` | Ponteiro de 16 bits para acesso indireto |
| `SP` | Ponteiro da pilha |
| `PC` | Controlado por fetch, jumps, `CALL` e `RET` |
| `Z`, `C`, `N`, `V` | Flags usadas pelos jumps condicionais |

Não existem instruções para mover diretamente `PC`, `SP`, `PTR` ou o registrador de flags para `A` ou `B`. Quando o programa precisa conservar um desses estados, deve usar uma variável em RAM ou uma convenção própria.

### Pilha e chamadas

A pilha cresce em direção aos endereços menores. A inicialização recomendada é:

```asm
SP $7FFF
```

O primeiro `PUSH` grava em `0x7FFE`. `CALL` e `RET` preservam somente o endereço de retorno; não salvam `A`, `B`, `PTR` ou flags.

Convenção inicial recomendada:

- `A`: primeiro argumento e valor de retorno;
- `B`: segundo argumento ou temporário;
- `PTR`: a rotina deve informar se o altera;
- `SP`: deve sair da subrotina com o mesmo valor de entrada;
- flags: considere sempre destruídas por qualquer operação da ALU.

### Flags e comparações

| Flag | Uso |
|---|---|
| `Z` | Resultado zero |
| `C` | Carry; em subtração e `CMP`, 1 significa ausência de borrow |
| `N` | Bit 7 do resultado |
| `V` | Overflow com sinal |

Após `CMP A,B`:

- `Z=1` indica igualdade;
- em valores sem sinal, `C=1` indica `A>=B`;
- em valores com sinal, “menor que” depende de `N XOR V`;
- `JP` testa somente `N=0`, incluindo o resultado zero.

`CMP` e `TEST` alteram as flags, mas preservam os operandos.

### Polling e ausência de interrupções

O WALL-8 não possui interrupções. Timers, teclado e GPU devem ser consultados por polling. Rotinas demoradas devem retornar ao laço principal com frequência para não perder responsividade.

### Registradores somente de escrita

`SOUND_CFG`, `CPU_CFG` e `PERIPH_CFG` não possuem readback. Se um programa precisar alterar apenas um campo, deve manter uma cópia shadow em RAM:

```asm
CPU_CFG_SHADOW = $0200

; Estado inicial conhecido: RAM ativa e clock de 16 MHz.
STI CPU_CFG_SHADOW, #$01

; Mantém RAM ativa e muda o clock para 1 MHz.
LDA CPU_CFG_SHADOW
AND A, #$01
OR A, #$40
STA CPU_CFG_SHADOW
STA $F500
```

---

## 1. Sistema e controle

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x00` | `NOP` | `00` | 3 | Não executa operação e inicia o próximo fetch. | NÃO | NÃO | `NOP` |
| `0x01` | `HLT` | `01` | 3 | Para a CPU até ocorrer reset. | NÃO | NÃO | `HLT` |

## 2. Load, store e movimentação

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x10` | `LDA #$xx` | `10 xx` | 5 | Carrega um valor imediato de 8 bits em A. | NÃO | **SIM** | `LDA #$55` |
| `0x11` | `LDB #$xx` | `11 xx` | 5 | Carrega um valor imediato de 8 bits em B. | NÃO | **SIM** | `LDB #$0A` |
| `0x12` | `LDA $addr` | `12 LL HH` | 9 | Lê a memória no endereço absoluto e grava em A. | NÃO | **SIM** | `LDA $F300` |
| `0x13` | `LDB $addr` | `13 LL HH` | 9 | Lê a memória no endereço absoluto e grava em B. | NÃO | **SIM** | `LDB $2000` |
| `0x14` | `STA $addr` | `14 LL HH` | 10 | Grava A no endereço absoluto. | NÃO | NÃO | `STA $F100` |
| `0x15` | `STB $addr` | `15 LL HH` | 10 | Grava B no endereço absoluto. | NÃO | NÃO | `STB $0100` |
| `0x16` | `MOV A, B` | `16` | 4 | Copia o valor de B para A. | NÃO | **SIM** | `MOV A, B` |
| `0x17` | `MOV B, A` | `17` | 4 | Copia o valor de A para B. | NÃO | **SIM** | `MOV B, A` |
| `0x18` | `LDA [PTR]` | `18` | 5 | Lê o byte apontado por PTR e grava em A. | NÃO | **SIM** | `PTR $8000`<br>`LDA [PTR]` |
| `0x19` | `LDB [PTR]` | `19` | 5 | Lê o byte apontado por PTR e grava em B. | NÃO | **SIM** | `PTR $8000`<br>`LDB [PTR]` |
| `0x1A` | `STA [PTR]` | `1A` | 6 | Grava A no endereço apontado por PTR. | NÃO | NÃO | `PTR $0200`<br>`STA [PTR]` |
| `0x1B` | `STB [PTR]` | `1B` | 6 | Grava B no endereço apontado por PTR. | NÃO | NÃO | `PTR $0200`<br>`STB [PTR]` |
| `0x27` | `STI $addr, #$xx` | `27 LL HH xx` | 12 | Grava um valor imediato diretamente na memória. | NÃO | NÃO | `STI $F400, #$12` |

## 3. Ponteiro PTR

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x20` | `PTR $addr` | `20 LL HH` | 7 | Carrega um endereço de 16 bits em PTR. | NÃO | NÃO | `PTR $8000` |
| `0x21` | `INC PTR` | `21` | 4 | Incrementa PTR em 1. | NÃO | NÃO | `INC PTR` |
| `0x22` | `DEC PTR` | `22` | 4 | Decrementa PTR em 1. | NÃO | NÃO | `DEC PTR` |
| `0x23` | `LDA [PTR+]` | `23` | 6 | Lê MEM[PTR] para A e depois incrementa PTR. | NÃO | **SIM** | `LDA [PTR+]` |
| `0x24` | `LDB [PTR+]` | `24` | 6 | Lê MEM[PTR] para B e depois incrementa PTR. | NÃO | **SIM** | `LDB [PTR+]` |
| `0x25` | `STA [PTR+]` | `25` | 7 | Grava A em MEM[PTR] e depois incrementa PTR. | NÃO | NÃO | `STA [PTR+]` |
| `0x26` | `STB [PTR+]` | `26` | 7 | Grava B em MEM[PTR] e depois incrementa PTR. | NÃO | NÃO | `STB [PTR+]` |

## 4. ALU entre registradores

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x30` | `ADD A, B` | `30` | 4 | Soma B a A e grava o resultado em A. | **SIM** | **SIM** | `ADD A, B` |
| `0x31` | `ADD B, A` | `31` | 4 | Soma A a B e grava o resultado em B. | **SIM** | **SIM** | `ADD B, A` |
| `0x32` | `SUB A, B` | `32` | 4 | Subtrai B de A e grava o resultado em A. | **SIM** | **SIM** | `SUB A, B` |
| `0x33` | `SUB B, A` | `33` | 4 | Subtrai A de B e grava o resultado em B. | **SIM** | **SIM** | `SUB B, A` |
| `0x34` | `AND A, B` | `34` | 4 | Executa A AND B e grava o resultado em A. | **SIM** | **SIM** | `AND A, B` |
| `0x35` | `AND B, A` | `35` | 4 | Executa B AND A e grava o resultado em B. | **SIM** | **SIM** | `AND B, A` |
| `0x36` | `OR A, B` | `36` | 4 | Executa A OR B e grava o resultado em A. | **SIM** | **SIM** | `OR A, B` |
| `0x37` | `OR B, A` | `37` | 4 | Executa B OR A e grava o resultado em B. | **SIM** | **SIM** | `OR B, A` |
| `0x38` | `XOR A, B` | `38` | 4 | Executa A XOR B e grava o resultado em A. | **SIM** | **SIM** | `XOR A, B` |
| `0x39` | `XOR B, A` | `39` | 4 | Executa B XOR A e grava o resultado em B. | **SIM** | **SIM** | `XOR B, A` |
| `0x3A` | `NOT A` | `3A` | 4 | Inverte todos os bits de A. | **SIM** | **SIM** | `NOT A` |
| `0x3B` | `NOT B` | `3B` | 4 | Inverte todos os bits de B. | **SIM** | **SIM** | `NOT B` |
| `0x3C` | `SHL A` | `3C` | 4 | Desloca A um bit para a esquerda. | **SIM** | **SIM** | `SHL A` |
| `0x3D` | `SHR A` | `3D` | 4 | Desloca A um bit para a direita. | **SIM** | **SIM** | `SHR A` |
| `0x3E` | `SHL B` | `3E` | 4 | Desloca B um bit para a esquerda. | **SIM** | **SIM** | `SHL B` |
| `0x3F` | `SHR B` | `3F` | 4 | Desloca B um bit para a direita. | **SIM** | **SIM** | `SHR B` |

## 5. Comparação, incremento e clear

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x40` | `CMP A, B` | `40` | 4 | Compara A com B usando o resultado de A − B. | **SIM** | NÃO | `CMP A, B`<br>`JZ IGUAIS` |
| `0x41` | `CMP B, A` | `41` | 4 | Compara B com A usando o resultado de B − A. | **SIM** | NÃO | `CMP B, A`<br>`JN MENOR` |
| `0x42` | `INC A` | `42` | 4 | Incrementa A em 1. | **SIM** | **SIM** | `INC A` |
| `0x43` | `DEC A` | `43` | 4 | Decrementa A em 1. | **SIM** | **SIM** | `DEC A` |
| `0x44` | `INC B` | `44` | 4 | Incrementa B em 1. | **SIM** | **SIM** | `INC B` |
| `0x45` | `DEC B` | `45` | 4 | Decrementa B em 1. | **SIM** | **SIM** | `DEC B` |
| `0x46` | `CLR A` | `46` | 4 | Carrega 0x00 em A. | **SIM** | **SIM** | `CLR A` |
| `0x47` | `CLR B` | `47` | 4 | Carrega 0x00 em B. | **SIM** | **SIM** | `CLR B` |

## 6. Jumps, pilha e subrotinas

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x50` | `JMP $addr` | `50 LL HH` | 8 | Salta incondicionalmente para o endereço. | NÃO | NÃO | `JMP LOOP` |
| `0x51` | `JZ $addr` | `51 LL HH` | 8 | Salta quando Z = 1. | NÃO | NÃO | `CMP A, #$00`<br>`JZ ZERO` |
| `0x52` | `JNZ $addr` | `52 LL HH` | 8 | Salta quando Z = 0. | NÃO | NÃO | `TEST A, #$80`<br>`JNZ BIT_LIGADO` |
| `0x53` | `JC $addr` | `53 LL HH` | 8 | Salta quando C = 1. | NÃO | NÃO | `ADD A, B`<br>`JC CARRY` |
| `0x54` | `JNC $addr` | `54 LL HH` | 8 | Salta quando C = 0. | NÃO | NÃO | `ADD A, B`<br>`JNC SEM_CARRY` |
| `0x55` | `JN $addr` | `55 LL HH` | 8 | Salta quando N = 1. | NÃO | NÃO | `CMP A, B`<br>`JN NEGATIVO` |
| `0x56` | `JP $addr` | `56 LL HH` | 8 | Salta quando N = 0. | NÃO | NÃO | `CMP A, B`<br>`JP NAO_NEGATIVO` |
| `0x57` | `JV $addr` | `57 LL HH` | 8 | Salta quando V = 1. | NÃO | NÃO | `ADD A, B`<br>`JV OVERFLOW` |
| `0x58` | `JNV $addr` | `58 LL HH` | 8 | Salta quando V = 0. | NÃO | NÃO | `ADD A, B`<br>`JNV SEM_OVERFLOW` |
| `0x59` | `CALL $addr` | `59 LL HH` | 16 | Empilha o endereço de retorno e chama uma subrotina. | NÃO | NÃO | `CALL DESENHA_TELA` |
| `0x5A` | `RET` | `5A` | 10 | Retorna ao endereço salvo pelo CALL. | NÃO | NÃO | `MINHA_ROTINA:`<br>`    INC A`<br>`    RET` |
| `0x5B` | `PUSH A` | `5B` | 7 | Salva A na pilha. | NÃO | NÃO | `PUSH A` |
| `0x5C` | `PUSH B` | `5C` | 7 | Salva B na pilha. | NÃO | NÃO | `PUSH B` |
| `0x5D` | `POP A` | `5D` | 6 | Recupera da pilha um valor para A. | NÃO | **SIM** | `POP A` |
| `0x5E` | `POP B` | `5E` | 6 | Recupera da pilha um valor para B. | NÃO | **SIM** | `POP B` |
| `0x5F` | `SP $addr` | `5F LL HH` | 7 | Inicializa o Stack Pointer com um endereço de 16 bits. | NÃO | NÃO | `SP $7FFF` |

## 7. ALU com valor imediato

| Opcode | Assembly | Bytes | Ciclos | O que faz | Atualiza flags | Altera registradores A/B | Exemplo de uso |
|---:|---|---|---:|---|:---:|:---:|---|
| `0x60` | `ADD A, #$xx` | `60 xx` | 8 | Soma o valor imediato a A. | **SIM** | **SIM** | `ADD A, #$05` |
| `0x61` | `ADD B, #$xx` | `61 xx` | 8 | Soma o valor imediato a B. | **SIM** | **SIM** | `ADD B, #$05` |
| `0x62` | `SUB A, #$xx` | `62 xx` | 8 | Subtrai o valor imediato de A. | **SIM** | **SIM** | `SUB A, #$01` |
| `0x63` | `SUB B, #$xx` | `63 xx` | 8 | Subtrai o valor imediato de B. | **SIM** | **SIM** | `SUB B, #$01` |
| `0x64` | `AND A, #$xx` | `64 xx` | 8 | Executa A AND valor imediato e grava o resultado em A. | **SIM** | **SIM** | `AND A, #$0F` |
| `0x65` | `AND B, #$xx` | `65 xx` | 8 | Executa B AND valor imediato e grava o resultado em B. | **SIM** | **SIM** | `AND B, #$F0` |
| `0x66` | `OR A, #$xx` | `66 xx` | 8 | Executa A OR valor imediato e grava o resultado em A. | **SIM** | **SIM** | `OR A, #$80` |
| `0x67` | `OR B, #$xx` | `67 xx` | 8 | Executa B OR valor imediato e grava o resultado em B. | **SIM** | **SIM** | `OR B, #$01` |
| `0x68` | `XOR A, #$xx` | `68 xx` | 8 | Executa A XOR valor imediato e grava o resultado em A. | **SIM** | **SIM** | `XOR A, #$FF` |
| `0x69` | `XOR B, #$xx` | `69 xx` | 8 | Executa B XOR valor imediato e grava o resultado em B. | **SIM** | **SIM** | `XOR B, #$FF` |
| `0x6A` | `CMP A, #$xx` | `6A xx` | 8 | Compara A com o valor imediato usando A − imediato. | **SIM** | NÃO | `CMP A, #$FF`<br>`JZ IGUAL` |
| `0x6B` | `CMP B, #$xx` | `6B xx` | 8 | Compara B com o valor imediato usando B − imediato. | **SIM** | NÃO | `CMP B, #$10`<br>`JNZ DIFERENTE` |
| `0x6C` | `TEST A, #$xx` | `6C xx` | 8 | Testa em A os bits selecionados pela máscara imediata. | **SIM** | NÃO | `TEST A, #$80`<br>`JNZ BIT_7_LIGADO` |
| `0x6D` | `TEST B, #$xx` | `6D xx` | 8 | Testa em B os bits selecionados pela máscara imediata. | **SIM** | NÃO | `TEST B, #$10`<br>`JZ BIT_4_DESLIGADO` |

---

## Exemplos rápidos

### Comparar A com um valor imediato

```asm
LDA #$FF
CMP A, #$FF
JZ VALOR_IGUAL
```

`CMP` não altera `A`, `B` ou o valor comparado; apenas atualiza as flags.

### Testar um bit do registrador de status

```asm
LDA $F300
TEST A, #$80
JNZ TECLA_PRONTA
```

A máscara `0x80` testa o bit 7 (`KEY_READY`) sem destruir o byte lido em `A`.

### Somar um valor sem ocupar B

```asm
LDB #$77
LDA #$10
ADD A, #$05
```

Resultado:

```text
A = 0x15
B = 0x77
```

### Percorrer bytes consecutivos

```asm
PTR $8000
LDA [PTR+]
LDB [PTR+]
```

Depois das duas leituras, `PTR` aponta para `$8002`.

### Chamar uma subrotina

```asm
SP $7FFF
LDA #$40
CALL SOMA_UM
HLT

SOMA_UM:
    INC A
    RET
```

Ao retornar, `A = 0x41`.

## Programando os periféricos

### Constantes recomendadas

```asm
KEY_DATA       = $F000
DISPLAY_LOW    = $F100
DISPLAY_HIGH   = $F101
VIDEO_DATA     = $F200
VIDEO_CMD      = $F201
VIDEO_X        = $F202
VIDEO_Y        = $F203
VIDEO_STATUS   = $F204
SYSTEM_STATUS  = $F300
SOUND_CFG      = $F400
CPU_CFG        = $F500
PERIPH_CFG     = $F501
CART_IO_BASE    = $F600
```

A página `0xF600-0xF6FF`, espelhada em `0xFE00-0xFEFF`, é encaminhada ao cartucho por `/CARD_IO_SEL`. O WALL-8 não define registradores em `CART_IO`: os offsets e suas funções são definidos pelo hardware de cada cartucho e controlados pelo código da própria ROM do cartucho.

### Timers

Os bits de timer são flags retidas. Leia o snapshot antes de limpar:

```asm
LDA SYSTEM_STATUS
TEST A, #$01
JZ SEM_TICK_1MS

; Trata TIMER_1MS.
STA SYSTEM_STATUS     ; o valor é ignorado; limpa os dois timers

SEM_TICK_1MS:
```

O timer chamado `TIMER_1MS` opera a 1024 Hz, com período de 0,9765625 ms.

### Teclado

```asm
LDA SYSTEM_STATUS
TEST A, #$40          ; /KEYBOARD_DETECT
JNZ SEM_TECLADO       ; 1 = ausente

TEST A, #$80          ; KEY_READY
JZ SEM_TECLA

LDA KEY_DATA          ; a leitura também gera /KEY_RD
```

### Display

```asm
; Modo HEX e LEDs habilitados.
STI PERIPH_CFG, #$00

; Exibe 1234 nos quatro dígitos.
STI DISPLAY_HIGH, #$12
STI DISPLAY_LOW,  #$34
```

Para selecionar CHAR mantendo os LEDs habilitados:

```asm
STI PERIPH_CFG, #$01
```

### Som

`SOUND_CFG[0]` habilita ruído, `[1]` habilita tom, `[4:2]` seleciona tom e `[7:5]` configura ruído.

```asm
; Tom habilitado, seleção 100.
STI SOUND_CFG, #$12

; Silêncio.
STI SOUND_CFG, #$00
```

### Vídeo/GPU

Antes de alterar `VIDEO_X`, `VIDEO_Y`, `VIDEO_DATA` ou iniciar um comando de VRAM, aguarde `BUSY=0`:

```asm
VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET
```

Selecionando o modo texto e escrevendo `A` na primeira célula:

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$11

CALL VIDEO_WAIT
STI VIDEO_X, #$00
STI VIDEO_Y, #$00
STI VIDEO_DATA, #$41
```

Para solicitar uma leitura de VRAM:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$05
STI VIDEO_Y, #$05
STI VIDEO_CMD, #$20
CALL VIDEO_WAIT
LDA VIDEO_DATA
```

## Exemplos completos

### Estrutura mínima, loop e HLT

```asm
#include "wall8.cpu"

LDA #$00

LOOP:
    INC A
    JMP LOOP
```

Para encerrar a execução até o próximo reset:

```asm
HLT
```

### Teste de RAM por endereço absoluto

```asm
#include "wall8.cpu"

LDA #$55
STA $000A

CLR A
LDA $000A
CMP A, #$55
JNZ ERRO_RAM

OK_RAM:
    JMP OK_RAM

ERRO_RAM:
    HLT
```

### Escrita imediata com `STI`

```asm
STI $0010, #$11
STI $0011, #$22
STI $0012, #$33
```

`STI` não altera o estado final de `A` ou `B`.

### Preenchimento sequencial com PTR

```asm
PTR $0200
LDA #$AA
STA [PTR+]
STA [PTR+]
STA [PTR+]
STA [PTR+]
```

Depois das quatro gravações, `PTR=$0204`.

### Copiar um bloco

Como existe somente um `PTR`, o exemplo mantém o destino em um endereço absoluto e incrementa manualmente apenas a origem. Para cópias maiores, a BIOS pode reservar variáveis de ponteiro em RAM e recarregar `PTR` a cada etapa.

```asm
PTR $8000
LDA [PTR+]
STA $0300

LDA [PTR+]
STA $0301
```

### Testar uma máscara sem destruir o valor

```asm
LDA SYSTEM_STATUS
TEST A, #$20          ; /VIDEO_DETECT
JZ VIDEO_PRESENTE

SEM_VIDEO:
    JMP SEM_VIDEO

VIDEO_PRESENTE:
```

O valor original permanece em `A`; somente as flags são alteradas.

### Subrotina preservando registradores

```asm
SP $7FFF

LDA #$10
LDB #$20
CALL SOMA_PRESERVA_B
HLT

SOMA_PRESERVA_B:
    PUSH B
    ADD A, B
    POP B
    RET
```

Ao retornar, `A=$30` e `B=$20`.

## Organização da BIOS

No reset, `/BOOT_ROM_EN=0` e a 27C512 responde de `0x0000` a `0x9FFF` como uma janela contínua de 40 KiB. Os offsets físicos da EPROM acompanham diretamente os endereços da CPU; não existe repetição automática dos 8 KiB superiores.

O software pode escolher entre duas organizações:

- manter o overlay ativo e usar até 40 KiB de ROM, sem RAM;
- transferir a execução para uma rotina residente em `0x8000-0x9FFF` e gravar `1` em `/BOOT_ROM_EN`, liberando a RAM em `0x0000-0x7FFF`.

O código que executa a própria liberação do overlay e a instrução seguinte devem estar na janela residente de 8 KiB. Com o seletor de clock em `000`, o valor abaixo preserva o bypass de 16 MHz:

```asm
CPU_CFG = $F500

; Esta rotina deve estar montada entre $8000 e $9FFF.
LIBERA_RAM:
    STI CPU_CFG, #$01
    JMP CONTINUA_NA_ROM

CONTINUA_NA_ROM:
    ; A RAM agora responde de $0000 a $7FFF.
```

Para iniciar a pilha no final da RAM depois da transição:

```asm
SP $7FFF
```

## Créditos

A definição da ISA e os exemplos deste documento utilizam o [customasm](https://github.com/hlorenzi/customasm), projeto de **hlorenzi**. Agradecimentos ao autor e aos colaboradores pela ferramenta e pela documentação disponibilizadas à comunidade.
