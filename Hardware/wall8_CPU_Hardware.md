# WALL-8 — Referência de Hardware e Microarquitetura

[← Voltar ao README](../README.md) · [Referência da ISA e programação](../Software/wall8_instrucoes.md) · [Esquema eletrônico](Hardware_Completo.pdf)

Este documento descreve o hardware do WALL-8 no nível necessário para compreender, montar, depurar e expandir a máquina. Ele reúne características elétricas, clocks, barramentos, registradores, memória, I/O, conectores, palavra de microcódigo e a sequência de microsteps dos 76 opcodes.

O arquivo [`Hardware_Completo.pdf`](Hardware_Completo.pdf) continua sendo a fonte visual do esquema elétrico. O [manual técnico consolidado](../WALL-8_Manual_de_Referencia_Tecnica_Rev1.1.pdf) é a referência preparada para impressão. Em caso de alteração do projeto, o esquema, o gerador de microcódigo e este documento devem receber a mesma revisão.

> **Convenção de nomes:** sinais iniciados por `/` são ativos em nível baixo. Sinais sem `/` são ativos em nível alto ou representam barramentos/campos binários normais.

## Sumário

- [1. Especificações elétricas](#1-especificações-elétricas)
- [2. Visão da microarquitetura](#2-visão-da-microarquitetura)
- [3. Clocks, HALT e reset](#3-clocks-halt-e-reset)
- [4. Barramentos e ciclos de máquina](#4-barramentos-e-ciclos-de-máquina)
- [5. Registradores e caminho de dados](#5-registradores-e-caminho-de-dados)
- [6. ALU e flags](#6-alu-e-flags)
- [7. Sistema de memória e boot](#7-sistema-de-memória-e-boot)
- [8. Arquitetura de I/O](#8-arquitetura-de-io)
- [9. Registradores de I/O](#9-registradores-de-io)
- [10. Display, LEDs e áudio](#10-display-leds-e-áudio)
- [11. Unidade de microcódigo](#11-unidade-de-microcódigo)
- [12. Microsteps dos opcodes](#12-microsteps-dos-opcodes)
- [13. Conectores e interfaces externas](#13-conectores-e-interfaces-externas)
- [14. Regras de integração e bring-up](#14-regras-de-integração-e-bring-up)
- [15. Arquivos normativos](#15-arquivos-normativos)

## 1. Especificações elétricas

### 1.1 Alimentação

O WALL-8 utiliza uma única alimentação lógica de **+5 V**, referenciada a GND. A placa não possui regulador principal: a fonte externa deve fornecer 5 V já regulados.

| Parâmetro | Valor | Observação |
|---|---:|---|
| Tensão nominal | 5,0 V | Lógica, RAM, EPROM, timers, displays e áudio |
| Faixa conservadora | 4,75 a 5,25 V | Até a caracterização da placa física |
| Referência | GND | Deve ser comum a todos os módulos |
| Fusível de entrada | 3 A | Proteção, não indicação do consumo nominal |
| Entrada | `J5` | Pino 1 GND; pino 2 +5 V através de `FU1` |

> Não aplique 9 V, 12 V ou uma bateria diretamente em `J5`. A placa espera 5 V regulados.

A entrada possui `FU1` de 3 A e diodo `1N5408` de proteção. O consumo total ainda precisa ser medido com a CPU em execução, LEDs, áudio, teclado, cartucho e GPU conectados.

### 1.2 Níveis lógicos

Os barramentos externos trabalham em níveis digitais de 5 V.

| Interface | Direção típica | Requisito |
|---|---|---|
| `EXBUS[15:0]` | CPU → módulo | Entrada compatível com lógica de 5 V |
| `DBUS[7:0]` | Bidirecional | Saída tri-state obrigatória |
| `/MEMORY_OE`, `/MEMORY_WE`, `/SEL` | CPU → módulo | Ativos em nível baixo |
| `/DETECT` | Módulo → CPU | Preferencialmente contato para GND ou open-drain/open-collector |
| `KEY_READY` | Teclado → CPU | Nível alto indica byte pronto |

Uma saída de 3,3 V não deve ser considerada automaticamente compatível com uma entrada 74HC alimentada em 5 V. Módulos de 3,3 V precisam de tradução de nível, principalmente nas entradas que podem receber 5 V da CPU.

O buffer `U117`, responsável por colocar o teclado no Data Bus, deve ser considerado **74HC541**.

### 1.3 Desacoplamento e integridade de sinal

- capacitores de 100 nF próximos aos circuitos integrados;
- capacitores de 470 µF/16 V distribuídos na alimentação;
- resistores série de 33 Ω nos seis ramos de clock;
- resistores de 68 kΩ nos barramentos para definir nível baixo em alta impedância;
- resistores de 1 kΩ e buffers dedicados nos LEDs de diagnóstico;
- GND e +5 V repetidos nos conectores de 40 vias.

Os valores ajudam na integridade de sinal, mas a placa física ainda deve ser medida com osciloscópio para verificar ringing, atraso, setup e hold, especialmente em 16 MHz.

### 1.4 Limites ainda não caracterizados

| Item | Situação atual |
|---|---|
| Corrente total | Deve ser medida após a montagem |
| Frequência máxima garantida | 16 MHz selecionável, ainda sem caracterização física completa |
| Tempos de RAM, EPROM e I/O | Não existe `WAIT`; todos devem responder dentro do microstep |
| Hot-plug e ESD | Não implementados |
| Potência e distorção do áudio | Devem ser medidas na placa física |

## 2. Visão da microarquitetura

O WALL-8 possui três barramentos principais:

| Barramento | Largura | Função |
|---|---:|---|
| `DBUS[7:0]` | 8 bits | Opcodes, operandos, dados, resultados da ALU e bytes de endereços |
| `INBUS[15:0]` | 16 bits | Movimentação interna de endereços entre `PC`, `ADDR`, `PTR`, `SP` e `MAR` |
| `EXBUS[15:0]` | 16 bits | Endereçamento de RAM, BIOS, cartucho e I/O |

Fluxo normal de um acesso:

```text
PC / ADDR / PTR / SP
          │
          ▼
Internal Address Bus
          │
          ▼
         MAR
          │
          ▼
External Address Bus ──► RAM / BIOS / CART / I/O
```

As cinco ROMs de microcódigo controlam quais fontes dirigem os barramentos e quais registradores capturam valores a cada microstep.

> Em um barramento tri-state somente uma fonte pode permanecer habilitada por vez. Habilitar simultaneamente duas saídas com valores diferentes causa contenção elétrica.

## 3. Clocks, HALT e reset

### 3.1 Clock principal

O oscilador principal utiliza:

- cristal de 16 MHz;
- portas `74HCU04`;
- condicionamento por `74HC14`;
- resistor de realimentação de 2,2 MΩ;
- resistor série de 680 Ω;
- dois capacitores de 22 pF.

Um `74HC4040` fornece divisões sucessivas e um `74HC151` seleciona o clock entregue à CPU. O código `000` é o bypass direto do cristal.

| `CLK_B2..0` | Clock | Período | `CPU_CFG` com RAM ativa |
|:---:|---:|---:|---:|
| `000` | 16 MHz | 62,5 ns | `0x01` |
| `001` | 8 MHz | 125 ns | `0x11` |
| `010` | 4 MHz | 250 ns | `0x21` |
| `011` | 2 MHz | 500 ns | `0x31` |
| `100` | 1 MHz | 1 µs | `0x41` |
| `101` | 500 kHz | 2 µs | `0x51` |
| `110` | 250 kHz | 4 µs | `0x61` |
| `111` | 125 kHz | 8 µs | `0x71` |

`CLK_B0` ocupa `CPU_CFG[4]`, `CLK_B1` ocupa `[5]` e `CLK_B2` ocupa `[6]`. Esses campos não são ativos em nível baixo.

### 3.2 Clock de debug e manual

Uma metade do `NE556` gera um clock ajustável por `RV1`. A outra metade condiciona o pulso do botão `BUT1`. O seletor `SW1` escolhe:

- `CLOCK_MAIN`;
- `CLOCK_DEBUG_AJUST`;
- `CLOCK_MANUAL`.

A faixa real do modo ajustável deve ser medida antes de ser publicada como especificação garantida.

### 3.3 Distribuição e HALT

Depois da seleção e da porta de `/HALT`, seis buffers distribuem o mesmo clock com resistores série de 33 Ω:

```text
CLOCK_PC
CLOCK_SP
CLOCK_PTR
CLOCK_ADDMAR
CLOCK_PeRA
CLOCK_RB-IR-TM-FL-ST
```

Esses sinais são ramos de fanout, não domínios de clock independentes.

`HLT` ativa `/HALT` em `T2`. Não existe interrupção nem instrução de retomada; a saída prevista é o reset físico.

### 3.4 Timers independentes

Um cristal de 32,768 kHz e um `CD4060` geram:

| Nome arquitetural | Frequência | Período real |
|---|---:|---:|
| `TIMER_1MS` | 1024 Hz | 0,9765625 ms |
| `TIMER_500MS` | 2 Hz | 500 ms |

Cada base de tempo seta um flip-flop `74HC74`. O bit permanece alto até uma escrita na página de status. Portanto, são flags retidas de evento, não contadores e nem a onda quadrada direta do divisor.

### 3.5 Hard reset

O reset utiliza `R154=100 kΩ`, `C92=10 µF`, botão `BUT2` e portas Schmitt. A constante nominal é da ordem de 1 segundo.

| Elemento | Estado após hard reset |
|---|---|
| `PC` | `0x0000` |
| Step Counter | `T0` |
| `CPU_CFG` | `0x00` |
| `PERIPH_CFG` | `0x00` |
| Boot overlay | Ativo, `/BOOT_ROM_EN=0` |
| Clock | 16 MHz, `CLK_B[2:0]=000` |
| `A`, `B`, `TMP`, `ADDR`, `MAR`, `PTR`, `SP` e flags | Indefinidos |
| `SOUND_CFG` e latches do display | Indefinidos |
| Flags dos timers | Devem ser limpas pela BIOS |

Durante o reset, `/ROM_MICRO_OE` mantém as saídas das ROMs de controle desabilitadas. A BIOS deve inicializar som, display, timers, `SP` e qualquer registrador que será utilizado.

## 4. Barramentos e ciclos de máquina

### 4.1 Data Bus

O Data Bus transporta:

- opcodes e valores imediatos;
- dados de RAM, BIOS, cartucho e I/O;
- saídas de `A`, `B`, `TMP` e ALU;
- bytes baixo e alto do `PC` durante `CALL`;
- bytes de carga de `ADDR`, `PTR` e `SP`.

### 4.2 Barramento interno de endereços

`PC`, `ADDR`, `PTR` e `SP` podem dirigir `INBUS[15:0]`. O destino mais comum é `MAR`. Em jumps e retornos, `ADDR` também alimenta a carga do `PC`.

### 4.3 Barramento externo

`MAR` dirige `EXBUS[15:0]` quando `/MAR_OUT` está ativo. Esse barramento alimenta memórias, decode e conectores externos.

### 4.4 Leitura e escrita

Uma leitura absoluta monta o endereço em dois bytes e depois acessa a memória. Exemplo de `LDA $1234`:

```text
T2  PC_OUT + MAR_LOAD
T3  MAR_OUT + MEMORY_OE + ADDR_L_LOAD + PC_INC
T4  PC_OUT + MAR_LOAD
T5  MAR_OUT + MEMORY_OE + ADDR_H_LOAD + PC_INC
T6  ADDR_OUT + MAR_LOAD
T7  MAR_OUT + MEMORY_OE + RA_LOAD
T8  STEP_RESET
```

Escritas possuem um microstep de setup antes de `/MEMORY_WE`:

```text
T7  MAR_OUT + RA_OUT
T8  MAR_OUT + RA_OUT + MEMORY_WE
```

Não existe `WAIT`. Em 16 MHz, cada microstep dura 62,5 ns e inclui os atrasos do contador, ROMs de controle, buffers, decode e setup do destino.

## 5. Registradores e caminho de dados

| Registrador | Bits | Implementação/função |
|---|---:|---|
| `A` | 8 | Acumulador; latch `74HC377`, operando da ALU |
| `B` | 8 | Segundo operando; latch `74HC377` |
| `TMP` | 8 | Temporário interno; preserva operandos em operações imediatas |
| `IR` | 8 | Opcode atual; alimenta `A0-A7` das micro-ROMs |
| `PC` | 16 | Quatro `74HC161`; incrementa, carrega e zera |
| `MAR` | 16 | Mantém o endereço apresentado ao barramento externo |
| `ADDR` | 16 | Monta endereços absolutos em formato little-endian |
| `PTR` | 16 | Contadores `74HC191`; acesso indireto e pós-incremento |
| `SP` | 16 | Contadores `74HC191`; pilha descendente |
| Flags | 4 | `Z`, `C`, `N`, `V` em latch `74HC377` |
| Step Counter | 4 | `T0-T15`; endereça as micro-ROMs |

### 5.1 Registradores visíveis ao programador

O software acessa diretamente `A`, `B`, `PTR` e `SP` por instruções. `PC` e flags afetam o fluxo, mas não existe instrução para copiá-los diretamente para `A` ou `B`.

### 5.2 Papel do TMP

`TMP` não entra diretamente na ALU. Em `ADD A, #$05`, por exemplo:

```text
T2     TMP <- B
T3/T4  B <- imediato; PC++
T5     A <- A + B; flags <- resultado
T6     B <- TMP
T7     fim
```

Assim, o registrador que não recebe o resultado termina com o valor original.

### 5.3 PTR e SP

```text
INC PTR: PTR <- PTR + 1
DEC PTR: PTR <- PTR - 1
[PTR+]:  acessa MEM[PTR] e depois incrementa PTR
PUSH:    SP <- SP - 1; MEM[SP] <- dado
POP:     dado <- MEM[SP]; SP <- SP + 1
```

`INC PTR` e `DEC PTR` não alteram flags. `PC`, `PTR` e `SP` possuem wraparound de 16 bits.

## 6. ALU e flags

### 6.1 Seleção de operandos

`ALU_AB_SWAP=0` seleciona `X=A`, `Y=B`. Quando vale 1, seleciona `X=B`, `Y=A`. O swap permite `SUB B,A`, `CMP B,A` e operações unárias sobre `B`.

### 6.2 Funções

| `MUX2..0` | `ALU_SUB` | `ALU_NOT_X` | Função |
|:---:|:---:|:---:|---|
| `000` | 0 | X | `X + Y` |
| `000` | 1 | X | `X - Y` |
| `001` | X | X | `X AND Y` |
| `010` | X | X | `X OR Y` |
| `011` | X | 0 | `X XOR Y` |
| `011` | X | 1 | `NOT X` |
| `100` | X | X | `SHR X`; `C <- X0` |
| `101` | X | X | `SHL X`; `C <- X7` |
| `110` | 0 | X | `X + 1` |
| `110` | 1 | X | `X - 1` |
| `111` | X | X | `0x00` |

Os shifts são lógicos. Não há rotação por carry nem shift aritmético.

### 6.3 Flags

| Flag | Significado |
|---|---|
| `Z` | Resultado igual a `0x00` |
| `C` | Carry na soma, *not borrow* na subtração ou bit deslocado |
| `N` | Bit 7 do resultado |
| `V` | Overflow em aritmética com sinal |

As operações de ALU gravam as quatro flags juntas. Funções lógicas, shifts e ZERO forçam `V=0`.

Após `CMP A,B`, uma comparação sem sinal usa `Z=1` para igualdade e `C=1` para `A>=B`. Em comparação com sinal, “menor que” depende de `N XOR V`, não apenas de `N`. `JP` testa somente `N=0`, portanto significa “não negativo”, incluindo zero.

## 7. Sistema de memória e boot

### 7.1 Mapa normal

| Faixa | Tamanho | Dispositivo |
|---|---:|---|
| `0x0000-0x7FFF` | 32 KiB | RAM 62256 |
| `0x8000-0x9FFF` | 8 KiB | BIOS 27C512 residente |
| `0xA000-0xEFFF` | 20 KiB | Cartucho externo |
| `0xF000-0xFFFF` | 4 KiB | I/O mapeado em memória |

### 7.2 RAM

A 62256 recebe `EXBUS[14:0]`. `/RAM_SEL`, `/MEMORY_OE` e `/MEMORY_WE` controlam a memória. O valor recomendado para uma pilha vazia é `SP $7FFF`; o primeiro `PUSH` grava em `0x7FFE`.

### 7.3 BIOS e boot overlay

A BIOS utiliza uma 27C512 de 64 KiB. Seus pinos `A0-A15` estão ligados diretamente a `EXBUS[15:0]`.

Com `/BOOT_ROM_EN=0`:

```text
0x0000-0x9FFF = janela ROM contínua de 40 KiB
RAM indisponível
```

Não existe repetição automática dos 8 KiB superiores. O endereço da CPU corresponde ao mesmo offset físico na EPROM.

Com `/BOOT_ROM_EN=1`:

```text
0x0000-0x7FFF = RAM
0x8000-0x9FFF = ROM residente
```

Para liberar a RAM, o código deve primeiro saltar para `0x8000-0x9FFF`. A instrução que grava `CPU_CFG` e a continuação precisam permanecer nessa janela de 8 KiB.

### 7.4 Cartucho

O cartucho ocupa 20 KiB de memória em `0xA000-0xEFFF`, selecionada por `/CARD_SEL`, e recebe endereço, dados, controles de memória, clock, alimentação e `/CARD_DETECT`. O conector também recebe `/CARD_IO_SEL`, ativo para a página `Y6` (`0xF600-0xF6FF`, espelhada em `0xFE00-0xFEFF`). O módulo pode implementar ROM, EEPROM, Flash, SRAM, lógica ou periféricos próprios. O WALL-8 não define registradores em `CART_IO`: os offsets e suas funções são definidos pelo hardware do cartucho e controlados pelo código da própria ROM do cartucho.

Não há MMU, proteção de escrita, proteção da pilha ou exceção de endereço. Software e hardware externo devem respeitar os limites por convenção.

## 8. Arquitetura de I/O

`/IO_SEL` cobre `0xF000-0xFFFF`. Um `74HC138` utiliza `A8`, `A9` e `A10`; `A11` não participa do subdecode e cria um espelho 0x800 bytes acima.

| CBA | Saída | Página principal | Espelho | Função |
|:---:|---|---|---|---|
| `000` | `Y0` | `0xF000-0xF0FF` | `0xF800-0xF8FF` | Teclado |
| `001` | `Y1` | `0xF100-0xF1FF` | `0xF900-0xF9FF` | Display |
| `010` | `Y2` | `0xF200-0xF2FF` | `0xFA00-0xFAFF` | Vídeo/GPU |
| `011` | `Y3` | `0xF300-0xF3FF` | `0xFB00-0xFBFF` | Status/timers |
| `100` | `Y4` | `0xF400-0xF4FF` | `0xFC00-0xFCFF` | Som |
| `101` | `Y5` | `0xF500-0xF5FF` | `0xFD00-0xFDFF` | Configuração |
| `110` | `Y6` | `0xF600-0xF6FF` | `0xFE00-0xFEFF` | CART_IO |
| `111` | `Y7` | `0xF700-0xF7FF` | `0xFF00-0xFFFF` | Reservado |

Dentro de cada página:

- teclado, status e som não decodificam offsets;
- display usa `A0`: par seleciona LOW, ímpar seleciona HIGH;
- configuração usa `A0`: par seleciona CPU, ímpar seleciona periféricos;
- vídeo decodifica `A2-A0` para os oito offsets de `0xF200-0xF207`, repetidos a cada oito bytes nas páginas `0xF2xx` e `0xFAxx`.
- `CART_IO` é encaminhado ao conector; a decodificação de `A7-A0` e o significado dos offsets pertencem ao hardware do cartucho.

## 9. Registradores de I/O

### 9.1 `KEY_DATA` — `0xF000`

Leitura de `KEYBOARD_B[7:0]`. `U117` coloca o byte no Data Bus e a mesma condição gera `/KEY_RD` para o teclado.

| Bit | Nome |
|---:|---|
| 0 | `KEYBOARD_B0` |
| 1 | `KEYBOARD_B1` |
| 2 | `KEYBOARD_B2` |
| 3 | `KEYBOARD_B3` |
| 4 | `KEYBOARD_B4` |
| 5 | `KEYBOARD_B5` |
| 6 | `KEYBOARD_B6` |
| 7 | `KEYBOARD_B7` |

O software deve verificar `/KEYBOARD_DETECT` e `KEY_READY` antes da leitura.

### 9.2 `DISPLAY_LOW/HIGH` — `0xF100/0xF101`

| Endereço | Conteúdo |
|---|---|
| `0xF100` | bits 3:0 = dígito 0; bits 7:4 = dígito 1 |
| `0xF101` | bits 3:0 = dígito 2; bits 7:4 = dígito 3 |

São registradores somente de escrita, sem readback.

### 9.3 Registradores da GPU

| Endereço | Nome | Acesso | Função |
|---|---|:---:|---|
| `0xF200` | `VIDEO_DATA` | R/W | Escrita solicita gravar um byte em X/Y; leitura devolve a última leitura de VRAM concluída. |
| `0xF201` | `VIDEO_CTRL` | W | Configuração persistente de modo, páginas, cursor, incremento e banco de caracteres; sem leitura de retorno. |
| `0xF202` | `VIDEO_X` | W | Coluna de caractere no texto ou coluna de byte nos gráficos; sem leitura de retorno. |
| `0xF203` | `VIDEO_Y` | W | Linha da próxima operação; sem leitura de retorno. |
| `0xF204` | `VIDEO_STATUS` | R | `BUSY` no bit 0 e `CURSOR_END` no bit 4; os demais bits retornam zero. |
| `0xF205` | `READ_REQ` | W | Qualquer escrita solicita ler a VRAM em X/Y; o byte escrito é ignorado. |
| `0xF206` | `CLEAR_REQ` | W | Qualquer escrita solicita CLEAR na página acessada pela CPU; o byte escrito é ignorado. |
| `0xF207` | `CURSOR_END_RESET` | W | Qualquer escrita limpa `CURSOR_END`, sem alterar X/Y; o byte escrito é ignorado. |

Os oito offsets aparecem em `0xF200-0xF207` e no espelho `0xFA00-0xFA07`. A GPU decodifica somente `A2-A0`: os mesmos offsets se repetem a cada oito bytes dentro de cada página de vídeo. A VRAM é acessada indiretamente por X/Y/DATA; não ocupa uma janela direta no espaço de memória da CPU.

#### 9.3.1 `VIDEO_CTRL` — `0xF201`

| Bit | Nome | Significado |
|---:|---|---|
| 0 | `MODE_B0` | Bit 0 da seleção de modo. |
| 1 | `MODE_B1` | Bit 1 da seleção de modo. |
| 2 | `DOUBLE_BUFFER_EN` | 0: CPU e vídeo usam a página 0. 1: vídeo usa a página frontal e CPU acessa a página oposta. |
| 3 | `DISPLAY_PAGE` | Página solicitada para exibição, 0 ou 1; a seleção é aplicada no início do `VBLANK`. |
| 4 | `CURSOR_VISIBLE` | 1 habilita o cursor piscante no texto; 0 oculta o cursor. |
| 5 | `AUTO_INCREMENT` | 1 avança X/Y após cada escrita em `VIDEO_DATA`; 0 mantém a posição. |
| 6 | `Char_Bank_14` | Bit 0 do banco de caracteres da ROM, usado no modo texto. |
| 7 | `Char_Bank_15` | Bit 1 do banco de caracteres da ROM, usado no modo texto. |

`VIDEO_CTRL` substitui todos os oito bits a cada escrita e não possui valor de reset garantido. Inicialize-o explicitamente e mantenha uma cópia em RAM para alterar campos preservando os demais. `MODE_B1:MODE_B0` = 00 seleciona texto 80 x 30; 01, gráfico 320 x 240; 10, gráfico 160 x 120; 11 não é um modo implementado. Os bits 7:6 selecionam um dos quatro bancos de caracteres da ROM.

Com `DOUBLE_BUFFER_EN`=1, a VRAM é dividida em duas páginas de 16 KiB: a CPU lê, escreve e limpa a página oposta à exibida. `DISPLAY_PAGE` é uma solicitação aplicada no `VBLANK`; `VIDEO_STATUS` não confirma a página ativa, e `BUSY` não sinaliza nem confirma essa troca. Com `DOUBLE_BUFFER_EN`=0, ambos acessam a página 0.

#### 9.3.2 `VIDEO_STATUS` — `0xF204`

| Bit | Nome | Significado |
|---:|---|---|
| 0 | `BUSY` | 1 indica leitura, escrita ou CLEAR pendente/em execução; aguarde zero antes da próxima operação. |
| 1-3 | reservado | Retornam zero; `VBLANK`, `HBLANK` e `FRAME` não são expostos à CPU. |
| 4 | `CURSOR_END` | Flag retida: o avanço automático completou a área do modo ou o CLEAR terminou. |
| 5-7 | reservado | Retornam zero. |

A GPU executa uma operação de VRAM por vez. Enquanto `BUSY`=1, o software pode consultar `VIDEO_STATUS`, mas deve aguardar `BUSY`=0 antes de alterar `VIDEO_CTRL`, `VIDEO_X`, `VIDEO_Y` ou `VIDEO_DATA` ou escrever nos offsets de solicitação e reconhecimento. `READ_REQ` e `CLEAR_REQ` são ações por escrita, não campos de `VIDEO_CTRL`.

#### 9.3.3 Coordenadas e formato dos dados

| Modo (`VIDEO_CTRL[1:0]`) | `VIDEO_X` | `VIDEO_Y` | Significado de `VIDEO_DATA` |
|---|---|---|---|
| `00`: texto 80×30 | `0-79` | `0-29` | Código de caractere; 80 bytes úteis por linha |
| `01`: gráfico 320×240 | `0-39` | `0-239` | 8 pixels por byte; 40 bytes úteis por linha |
| `10`: gráfico 160×120 | `0-19` | `0-119` | 8 pixels por byte; 20 bytes úteis por linha |

No texto, a fonte de 8×8 é repetida 2× apenas na vertical. Os modos gráficos são ampliados 2× e 4×, respectivamente. Nos bytes gráficos, o bit 0 é o pixel mais à esquerda e o bit 7 é o mais à direita.

`AUTO_INCREMENT` só afeta escritas em `VIDEO_DATA`: avança X, passa para a próxima linha e, ao completar a última linha, retorna X/Y a (0,0) e marca `CURSOR_END`. A flag não bloqueia novas escritas e permanece marcada até `CURSOR_END_RESET`, início de CLEAR ou reset geral. Escrever X/Y ou mudar o modo não limpa essa flag; a mudança de modo também não reinicializa X/Y.

#### 9.3.4 Leitura e CLEAR

Para ler a VRAM, aguarde `BUSY`=0, posicione X/Y, escreva qualquer byte em `READ_REQ`, aguarde `BUSY`=0 novamente e leia `VIDEO_DATA`. A leitura não incrementa X/Y; ler `VIDEO_DATA` sozinho não inicia uma nova leitura da VRAM.

`CLEAR_REQ` reinicia X/Y em (0,0), limpa `CURSOR_END` no início e preenche com 0x00 a área válida do modo na página acessada pela CPU, independentemente de `AUTO_INCREMENT`. Ao terminar, X/Y voltam a (0,0) e `CURSOR_END` fica marcado. No texto, o caractere 0x00 deve ser vazio em cada banco da ROM para representar a limpeza.

### 9.4 `SYSTEM_STATUS` — `0xF300`

| Bit | Nome | Significado |
|---:|---|---|
| 0 | `TIMER_1MS` | Ocorreu ao menos um tick desde a limpeza |
| 1 | `TIMER_500MS` | Ocorreu ao menos um tick desde a limpeza |
| 2 | reservado | Retorna zero |
| 3 | reservado | Retorna zero |
| 4 | `/CARD_DETECT` | 0 = cartucho presente |
| 5 | `/VIDEO_DETECT` | 0 = vídeo presente |
| 6 | `/KEYBOARD_DETECT` | 0 = teclado presente |
| 7 | `KEY_READY` | 1 = byte disponível |

Qualquer escrita na página limpa simultaneamente os dois flip-flops de timer. Os sinais de presença e teclado não são alterados.

### 9.5 `SOUND_CFG` — `0xF400`

| Bit | Nome | Função |
|---:|---|---|
| 0 | `NOISE_EN` | 1 habilita ruído; 0 desliga/reset |
| 1 | `TONE_EN` | 1 habilita tom; 0 desliga/reset |
| 2 | `TONE_B0` | Seleção de tom bit 0 |
| 3 | `TONE_B1` | Seleção de tom bit 1 |
| 4 | `TONE_B2` | Seleção de tom bit 2 |
| 5 | `NOISE_B0` | Seleção de ruído bit 0 |
| 6 | `NOISE_B1` | Seleção de ruído bit 1 |
| 7 | `NOISE_B2` | Seleção de ruído bit 2 |

`NOISE_EN` e `TONE_EN` são ativos em nível alto. O registrador é somente de escrita e cada acesso substitui os oito bits.

### 9.6 `CPU_CFG` — `0xF500`

| Bit | Nome | Reset | Função |
|---:|---|:---:|---|
| 0 | `/BOOT_ROM_EN` | 0 | 0 = ROM baixa; 1 = RAM baixa |
| 1 | reservado | 0 | Escrever 0 |
| 2 | reservado | 0 | Escrever 0 |
| 3 | reservado | 0 | Escrever 0 |
| 4 | `CLK_B0` | 0 | Clock bit 0 |
| 5 | `CLK_B1` | 0 | Clock bit 1 |
| 6 | `CLK_B2` | 0 | Clock bit 2 |
| 7 | reservado | 0 | Escrever 0 |

É somente de escrita. Para alterar um campo sem perder os demais, o software precisa manter uma cópia shadow em RAM.

### 9.7 `PERIPH_CFG` — `0xF501`

| Bit | Nome | Reset | Função |
|---:|---|:---:|---|
| 0 | `/DISP_HEX` | 0 | 0 = HEX; 1 = CHAR |
| 1 | reservado | 0 | Escrever 0 |
| 2 | `/LED_EN` | 0 | 0 = LEDs habilitados; 1 = desabilitados |
| 3-7 | reservado | 0 | Escrever 0 |

Também é somente de escrita.

## 10. Display, LEDs e áudio

### 10.1 Decodificação dos displays

Duas EPROMs 27C512 convertem os bytes dos latches em segmentos.

| Pinos da 27C512 | Origem/função |
|---|---|
| `A0-A7` | Byte de `DISPLAY_LOW` ou `DISPLAY_HIGH` |
| `A8` | `DISP_CLOCK`: 0 nibble alto/esquerdo; 1 nibble baixo/direito |
| `A9` | `/DISP_HEX`: 0 HEX; 1 CHAR |
| `A10-A15` | GND |
| `D0-D6` | Segmentos A-G, ativos em nível baixo: 0 acende; 1 apaga |
| `D7` | Ponto decimal, não utilizado e mantido em 1 |

`display_low.bin` e `display_high.bin` possuem 65.536 bytes e conteúdo idêntico. O circuito usa displays de ânodo comum, multiplexação por 555, dois `BC327` PNP, resistores de base de 1 kΩ e resistores de 330 Ω por segmento. Como os transistores PNP são acionados em nível baixo, a seleção por `DISP_CLOCK` é a inversa da versão anterior: 0 habilita os dígitos esquerdos e 1 habilita os direitos.

| Código CHAR | Símbolo | Código CHAR | Símbolo |
|:---:|:---:|:---:|:---:|
| `0` | espaço | `8` | `L` |
| `1` | `A` | `9` | `O` |
| `2` | `b` | `A` | `P` |
| `3` | `C` | `B` | `r` |
| `4` | `d` | `C` | `t` |
| `5` | `E` | `D` | `U` |
| `6` | `F` | `E` | `-` |
| `7` | `H` | `F` | `_` |

### 10.2 LEDs de diagnóstico

Os indicadores são controlados por `/LED_EN` e usam buffers e resistores de 1 kΩ para não carregar diretamente os registradores monitorados. No reset, `/LED_EN=0` e os LEDs permanecem habilitados.

### 10.3 Geração e saída de áudio

O áudio possui:

- gerador de tom e gerador de ruído baseados em `NE556`;
- dois `74HC4051` para selecionar um entre oito ajustes;
- `74HC164` com realimentação XOR para o ruído;
- mistura de tom e ruído em `AUDIO_MIX`;
- controle de nível por `RV3`;
- amplificador `TDA2822M` em ponte;
- saída de alto-falante em `J3` e saída mono duplicada em tip/ring em `J6`.

`J3` é diferencial: nenhum terminal pode ser ligado ao GND. `J6` deriva de `AUDIO_MIX` antes do estágio bridge e deve ser tratado inicialmente como saída de linha/monitoramento.

## 11. Unidade de microcódigo

### 11.1 Endereço das micro-ROMs

As cinco ROMs 27C512 recebem o mesmo endereço de 16 bits:

```text
micro_addr = opcode | (flags << 8) | (step << 12)
flags = (Z << 0) | (C << 1) | (N << 2) | (V << 3)
```

| Endereço | Origem |
|---|---|
| `A0-A7` | Opcode em `IR`, bit 0 em A0 |
| `A8` | `Z` |
| `A9` | `C` |
| `A10` | `N` |
| `A11` | `V` |
| `A12-A15` | Step Counter, `T0-T15` |

Cada combinação de opcode, flags e step seleciona uma palavra de controle de 40 bits.

### 11.2 ROM 1

| Bit | Sinal | Ativo | Função |
|---:|---|:---:|---|
| D0 | `PC_INC` | 1 | Incrementa o PC |
| D1 | `/PC_LOAD` | 0 | Carrega PC a partir do barramento interno |
| D2 | `/PC_OUT` | 0 | Coloca PC no barramento interno |
| D3 | `/MAR_LOAD` | 0 | Carrega MAR |
| D4 | `/MAR_OUT` | 0 | MAR dirige o barramento externo |
| D5 | `/IR_LOAD` | 0 | Carrega o opcode no IR |
| D6 | `/RA_LOAD` | 0 | Carrega A |
| D7 | `/RA_OUT` | 0 | A dirige o Data Bus |

### 11.3 ROM 2

| Bit | Sinal | Ativo | Função |
|---:|---|:---:|---|
| D0 | `/RB_LOAD` | 0 | Carrega B |
| D1 | `/RB_OUT` | 0 | B dirige o Data Bus |
| D2 | `/ADDR_L_LOAD` | 0 | Carrega byte baixo de ADDR |
| D3 | `/ADDR_H_LOAD` | 0 | Carrega byte alto de ADDR |
| D4 | `/ADDR_OUT` | 0 | ADDR dirige o barramento interno |
| D5 | `ALU_AB_SWAP` | 1 | Troca A/B nos operandos X/Y |
| D6 | `ALU_NOT_X` | 1 | Converte XOR em NOT X no modo 011 |
| D7 | `ALU_SUB` | 1 | Seleciona subtração/decremento |

### 11.4 ROM 3

| Bit | Sinal | Ativo | Função |
|---:|---|:---:|---|
| D0 | `ALU_MUX_0` | 1 | Seleção ALU bit 0 |
| D1 | `ALU_MUX_1` | 1 | Seleção ALU bit 1 |
| D2 | `ALU_MUX_2` | 1 | Seleção ALU bit 2 |
| D3 | `/ALU_OUT` | 0 | ALU dirige o Data Bus |
| D4 | `/MEMORY_OE` | 0 | Habilita leitura de memória/I/O |
| D5 | `/MEMORY_WE` | 0 | Habilita escrita de memória/I/O |
| D6 | `/FLAGS_LOAD` | 0 | Carrega Z/C/N/V |
| D7 | `/STEP_RESET` | 0 | Retorna o Step Counter a T0 |

### 11.5 ROM 4

| Bit | Sinal | Ativo | Função |
|---:|---|:---:|---|
| D0 | `/HALT` | 0 | Bloqueia o clock da CPU |
| D1 | `/PTR_EN` | 0 | Habilita contagem de PTR |
| D2 | `/PTR_L_LOAD` | 0 | Carrega byte baixo de PTR |
| D3 | `/PTR_H_LOAD` | 0 | Carrega byte alto de PTR |
| D4 | `/PTR_OUT` | 0 | PTR dirige o barramento interno |
| D5 | `PTR_DOWN` | 1 | Seleciona decremento de PTR |
| D6 | `/TMP_LOAD` | 0 | Carrega TMP |
| D7 | `/TMP_OUT` | 0 | TMP dirige o Data Bus |

### 11.6 ROM 5

| Bit | Sinal | Ativo | Função |
|---:|---|:---:|---|
| D0 | `/SP_EN` | 0 | Habilita contagem de SP |
| D1 | `/SP_L_LOAD` | 0 | Carrega byte baixo de SP |
| D2 | `/SP_H_LOAD` | 0 | Carrega byte alto de SP |
| D3 | `/SP_OUT` | 0 | SP dirige o barramento interno |
| D4 | `SP_DOWN` | 1 | Seleciona decremento de SP |
| D5 | `/PC_OUT_L_DATA` | 0 | Byte baixo do PC dirige o Data Bus |
| D6 | `/PC_OUT_H_DATA` | 0 | Byte alto do PC dirige o Data Bus |
| D7 | `NC` | — | Sem função |

### 11.7 Valores neutros

| ROM | Idle | Binário |
|---|---:|:---:|
| ROM 1 | `0xFE` | `11111110` |
| ROM 2 | `0x1F` | `00011111` |
| ROM 3 | `0xF8` | `11111000` |
| ROM 4 | `0xDF` | `11011111` |
| ROM 5 | `0x6F` | `01101111` |

O gerador inicia os 65.536 endereços de cada ROM com esses bytes e altera somente os bits necessários.

### 11.8 Fetch comum

Todos os 256 opcodes recebem:

```text
T0: /PC_OUT + /MAR_LOAD
T1: /MAR_OUT + /MEMORY_OE + /IR_LOAD + PC_INC
```

A execução específica começa em `T2`. Normalmente o último step ativa `/STEP_RESET`.

Opcodes não definidos executam `T0/T1`, permanecem em estado neutro de `T2` a `T15` e retornam a `T0` pelo overflow do contador. Esse comportamento não deve ser usado como parte da ISA.

## 12. Microsteps dos opcodes

As tabelas abaixo são derivadas do [`Software/Gerador_Microcodigo.py`](../Software/Gerador_Microcodigo.py). `T0` e `T1` são o fetch comum descrito acima; por isso cada linha mostra somente `T2` em diante.

### Sistema

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x00` | `NOP` | `T2`: `/STEP_RESET` |
| `0x01` | `HLT` | `T2`: `/HALT`<br>`T3`: `/HALT` |

### Load, store e movimentação

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x10` | `LDA #$xx` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MEMORY_OE` + `/RA_LOAD` + `PC_INC` + `/MAR_OUT`<br>`T4`: `/STEP_RESET` |
| `0x11` | `LDB #$xx` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MEMORY_OE` + `/RB_LOAD` + `PC_INC` + `/MAR_OUT`<br>`T4`: `/STEP_RESET` |
| `0x12` | `LDA $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `/ADDR_OUT` + `/MAR_LOAD`<br>`T7`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD`<br>`T8`: `/STEP_RESET` |
| `0x13` | `LDB $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `/ADDR_OUT` + `/MAR_LOAD`<br>`T7`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD`<br>`T8`: `/STEP_RESET` |
| `0x14` | `STA $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `/ADDR_OUT` + `/MAR_LOAD`<br>`T7`: `/MAR_OUT` + `/RA_OUT`<br>`T8`: `/MAR_OUT` + `/RA_OUT` + `/MEMORY_WE`<br>`T9`: `/STEP_RESET` |
| `0x15` | `STB $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `/ADDR_OUT` + `/MAR_LOAD`<br>`T7`: `/MAR_OUT` + `/RB_OUT`<br>`T8`: `/MAR_OUT` + `/RB_OUT` + `/MEMORY_WE`<br>`T9`: `/STEP_RESET` |
| `0x16` | `MOV A, B` | `T2`: `/RB_OUT` + `/RA_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x17` | `MOV B, A` | `T2`: `/RA_OUT` + `/RB_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x18` | `LDA [PTR]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD`<br>`T4`: `/STEP_RESET` |
| `0x19` | `LDB [PTR]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD`<br>`T4`: `/STEP_RESET` |
| `0x1A` | `STA [PTR]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/RA_OUT`<br>`T4`: `/MAR_OUT` + `/RA_OUT` + `/MEMORY_WE`<br>`T5`: `/STEP_RESET` |
| `0x1B` | `STB [PTR]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/RB_OUT`<br>`T4`: `/MAR_OUT` + `/RB_OUT` + `/MEMORY_WE`<br>`T5`: `/STEP_RESET` |
| `0x27` | `STI $addr, #$xx` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `/PC_OUT` + `/MAR_LOAD`<br>`T7`: `/MAR_OUT` + `/MEMORY_OE` + `/TMP_LOAD` + `PC_INC`<br>`T8`: `/ADDR_OUT` + `/MAR_LOAD`<br>`T9`: `/MAR_OUT` + `/TMP_OUT`<br>`T10`: `/MAR_OUT` + `/TMP_OUT` + `/MEMORY_WE`<br>`T11`: `/STEP_RESET` |

### Ponteiro PTR

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x20` | `PTR $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/PTR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/PTR_H_LOAD` + `PC_INC`<br>`T6`: `/STEP_RESET` |
| `0x21` | `INC PTR` | `T2`: `/PTR_EN`<br>`T3`: `/STEP_RESET` |
| `0x22` | `DEC PTR` | `T2`: `PTR_DOWN` + `/PTR_EN`<br>`T3`: `/STEP_RESET` |
| `0x23` | `LDA [PTR+]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD`<br>`T4`: `/PTR_EN`<br>`T5`: `/STEP_RESET` |
| `0x24` | `LDB [PTR+]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD`<br>`T4`: `/PTR_EN`<br>`T5`: `/STEP_RESET` |
| `0x25` | `STA [PTR+]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/RA_OUT`<br>`T4`: `/MAR_OUT` + `/RA_OUT` + `/MEMORY_WE`<br>`T5`: `/PTR_EN`<br>`T6`: `/STEP_RESET` |
| `0x26` | `STB [PTR+]` | `T2`: `/PTR_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/RB_OUT`<br>`T4`: `/MAR_OUT` + `/RB_OUT` + `/MEMORY_WE`<br>`T5`: `/PTR_EN`<br>`T6`: `/STEP_RESET` |

### ALU entre registradores

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x30` | `ADD A, B` | `T2`: `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x31` | `ADD B, A` | `T2`: `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x32` | `SUB A, B` | `T2`: `ALU_SUB` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x33` | `SUB B, A` | `T2`: `ALU_SUB` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x34` | `AND A, B` | `T2`: `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x35` | `AND B, A` | `T2`: `ALU_MUX_0` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x36` | `OR A, B` | `T2`: `ALU_MUX_1` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x37` | `OR B, A` | `T2`: `ALU_MUX_1` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x38` | `XOR A, B` | `T2`: `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x39` | `XOR B, A` | `T2`: `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3A` | `NOT A` | `T2`: `ALU_MUX_1` + `ALU_MUX_0` + `ALU_NOT_X` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3B` | `NOT B` | `T2`: `ALU_MUX_1` + `ALU_MUX_0` + `ALU_NOT_X` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3C` | `SHL A` | `T2`: `ALU_MUX_2` + `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3D` | `SHR A` | `T2`: `ALU_MUX_2` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3E` | `SHL B` | `T2`: `ALU_MUX_2` + `ALU_MUX_0` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x3F` | `SHR B` | `T2`: `ALU_MUX_2` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |

### Comparação, incremento e clear

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x40` | `CMP A, B` | `T2`: `ALU_SUB` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x41` | `CMP B, A` | `T2`: `ALU_SUB` + `ALU_AB_SWAP` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x42` | `INC A` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x43` | `DEC A` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `ALU_SUB` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x44` | `INC B` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x45` | `DEC B` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `ALU_SUB` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x46` | `CLR A` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |
| `0x47` | `CLR B` | `T2`: `ALU_MUX_2` + `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T3`: `/STEP_RESET` |

### Jumps, pilha e subrotinas

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x50` | `JMP $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC` + `/MAR_OUT`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC` + `/MAR_OUT`<br>`T6`: `/PC_LOAD` + `/ADDR_OUT`<br>`T7`: `/STEP_RESET` |
| `0x51` | `JZ $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [Z=1]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x52` | `JNZ $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [Z=0]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x53` | `JC $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [C=1]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x54` | `JNC $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [C=0]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x55` | `JN $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [N=1]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x56` | `JP $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [N=0]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x57` | `JV $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [V=1]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x58` | `JNV $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6` [V=0]: `/ADDR_OUT` + `/PC_LOAD`; caso contrário, estado neutro<br>`T7`: `/STEP_RESET` |
| `0x59` | `CALL $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD` + `PC_INC`<br>`T6`: `SP_DOWN` + `/SP_EN`<br>`T7`: `/SP_OUT` + `/MAR_LOAD`<br>`T8`: `/MAR_OUT` + `/PC_OUT_H_DATA`<br>`T9`: `/MAR_OUT` + `/PC_OUT_H_DATA` + `/MEMORY_WE`<br>`T10`: `SP_DOWN` + `/SP_EN`<br>`T11`: `/SP_OUT` + `/MAR_LOAD`<br>`T12`: `/MAR_OUT` + `/PC_OUT_L_DATA`<br>`T13`: `/MAR_OUT` + `/PC_OUT_L_DATA` + `/MEMORY_WE`<br>`T14`: `/ADDR_OUT` + `/PC_LOAD`<br>`T15`: `/STEP_RESET` |
| `0x5A` | `RET` | `T2`: `/SP_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_L_LOAD`<br>`T4`: `/SP_EN`<br>`T5`: `/SP_OUT` + `/MAR_LOAD`<br>`T6`: `/MAR_OUT` + `/MEMORY_OE` + `/ADDR_H_LOAD`<br>`T7`: `/SP_EN`<br>`T8`: `/ADDR_OUT` + `/PC_LOAD`<br>`T9`: `/STEP_RESET` |
| `0x5B` | `PUSH A` | `T2`: `SP_DOWN` + `/SP_EN`<br>`T3`: `/SP_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/RA_OUT`<br>`T5`: `/MAR_OUT` + `/RA_OUT` + `/MEMORY_WE`<br>`T6`: `/STEP_RESET` |
| `0x5C` | `PUSH B` | `T2`: `SP_DOWN` + `/SP_EN`<br>`T3`: `/SP_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/RB_OUT`<br>`T5`: `/MAR_OUT` + `/RB_OUT` + `/MEMORY_WE`<br>`T6`: `/STEP_RESET` |
| `0x5D` | `POP A` | `T2`: `/SP_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD`<br>`T4`: `/SP_EN`<br>`T5`: `/STEP_RESET` |
| `0x5E` | `POP B` | `T2`: `/SP_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD`<br>`T4`: `/SP_EN`<br>`T5`: `/STEP_RESET` |
| `0x5F` | `SP $addr` | `T2`: `/PC_OUT` + `/MAR_LOAD`<br>`T3`: `/MAR_OUT` + `/MEMORY_OE` + `/SP_L_LOAD` + `PC_INC`<br>`T4`: `/PC_OUT` + `/MAR_LOAD`<br>`T5`: `/MAR_OUT` + `/MEMORY_OE` + `/SP_H_LOAD` + `PC_INC`<br>`T6`: `/STEP_RESET` |

### ALU com imediato

| Opcode | Assembly | Microsteps específicos |
|---:|---|---|
| `0x60` | `ADD A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x61` | `ADD B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x62` | `SUB A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_SUB` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x63` | `SUB B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_SUB` + `ALU_AB_SWAP` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x64` | `AND A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x65` | `AND B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_0` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x66` | `OR A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_1` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x67` | `OR B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_1` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x68` | `XOR A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RA_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x69` | `XOR B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_1` + `ALU_MUX_0` + `/ALU_OUT` + `/RB_LOAD` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x6A` | `CMP A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_SUB` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x6B` | `CMP B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_SUB` + `ALU_AB_SWAP` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x6C` | `TEST A, #$xx` | `T2`: `/RB_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RB_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_0` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RB_LOAD`<br>`T7`: `/STEP_RESET` |
| `0x6D` | `TEST B, #$xx` | `T2`: `/RA_OUT` + `/TMP_LOAD`<br>`T3`: `/PC_OUT` + `/MAR_LOAD`<br>`T4`: `/MAR_OUT` + `/MEMORY_OE` + `/RA_LOAD` + `PC_INC`<br>`T5`: `ALU_MUX_0` + `/FLAGS_LOAD`<br>`T6`: `/TMP_OUT` + `/RA_LOAD`<br>`T7`: `/STEP_RESET` |


## 13. Conectores e interfaces externas

### 13.1 Teclado — J2, 16 vias

| Pino | Sinal | Pino | Sinal |
|---:|---|---:|---|
| 1 | `KEYBOARD_B0` | 2 | +5 V |
| 3 | `KEYBOARD_B1` | 4 | NC |
| 5 | `KEYBOARD_B2` | 6 | NC |
| 7 | `KEYBOARD_B3` | 8 | `/KEY_RD` |
| 9 | `KEYBOARD_B4` | 10 | `/KEYBOARD_DETECT` |
| 11 | `KEYBOARD_B5` | 12 | `KEY_READY` |
| 13 | `KEYBOARD_B6` | 14 | NC |
| 15 | `KEYBOARD_B7` | 16 | GND |

O teclado presente leva `/KEYBOARD_DETECT` ao GND. O resistor de pull-up mantém o sinal em 1 quando o módulo está ausente. `KEY_READY` deve permanecer alto enquanto o byte está estável e ser limpo após `/KEY_RD`.

### 13.2 Cartucho — J1, 2×20

| Pino | Sinal | Pino | Sinal |
|---:|---|---:|---|
| 1 | GND | 2 | +5 V |
| 3 | GND | 4 | +5 V |
| 5 | `EXBUS0` | 6 | `DBUS0` |
| 7 | `EXBUS1` | 8 | `DBUS1` |
| 9 | `EXBUS2` | 10 | `DBUS2` |
| 11 | `EXBUS3` | 12 | `DBUS3` |
| 13 | `EXBUS4` | 14 | `DBUS4` |
| 15 | `EXBUS5` | 16 | `DBUS5` |
| 17 | `EXBUS6` | 18 | `DBUS6` |
| 19 | `EXBUS7` | 20 | `DBUS7` |
| 21 | `EXBUS8` | 22 | `CLOCK_ADDMAR` |
| 23 | `EXBUS9` | 24 | `/CARD_SEL` |
| 25 | `EXBUS10` | 26 | `/MEMORY_OE` |
| 27 | `EXBUS11` | 28 | `/MEMORY_WE` |
| 29 | `EXBUS12` | 30 | `/CARD_DETECT` |
| 31 | `EXBUS13` | 32 | NC |
| 33 | `EXBUS14` | 34 | `/CARD_IO_SEL` |
| 35 | `EXBUS15` | 36 | NC |
| 37 | GND | 38 | +5 V |
| 39 | GND | 40 | +5 V |

`CLOCK_ADDMAR` é um ramo do clock da CPU. Um acesso à memória do cartucho é definido pelo endereço, `/CARD_SEL` e `/MEMORY_OE` ou `/MEMORY_WE`; um acesso ao I/O do cartucho é definido pelo endereço, `/CARD_IO_SEL` e `/MEMORY_OE` ou `/MEMORY_WE`.

### 13.3 Vídeo/GPU — J4, 2×20

| Pino | Sinal | Pino | Sinal |
|---:|---|---:|---|
| 1 | GND | 2 | +5 V |
| 3 | GND | 4 | +5 V |
| 5 | `EXBUS0` | 6 | `DBUS0` |
| 7 | `EXBUS1` | 8 | `DBUS1` |
| 9 | `EXBUS2` | 10 | `DBUS2` |
| 11 | `EXBUS3` | 12 | `DBUS3` |
| 13 | `EXBUS4` | 14 | `DBUS4` |
| 15 | `EXBUS5` | 16 | `DBUS5` |
| 17 | `EXBUS6` | 18 | `DBUS6` |
| 19 | `EXBUS7` | 20 | `DBUS7` |
| 21 | `EXBUS8` | 22 | NC |
| 23 | `EXBUS9` | 24 | `/VIDEO_SEL` |
| 25 | `EXBUS10` | 26 | `/MEMORY_OE` |
| 27 | `EXBUS11` | 28 | `/MEMORY_WE` |
| 29 | `EXBUS12` | 30 | `/VIDEO_DETECT` |
| 31 | `EXBUS13` | 32 | NC |
| 33 | `EXBUS14` | 34 | `CLOCK_PeRA` |
| 35 | `EXBUS15` | 36 | NC |
| 37 | GND | 38 | +5 V |
| 39 | GND | 40 | +5 V |

O módulo presente leva `/VIDEO_DETECT` ao GND. A GPU deve manter o Data Bus em alta impedância fora dos ciclos de leitura selecionados.

### 13.4 Alimentação — J5

| Pino | Sinal |
|---:|---|
| 1 | GND |
| 2 | Entrada +5 V através de `FU1` |

### 13.5 Alto-falante — J3

| Pino | Sinal |
|---:|---|
| 1 | Saída `OUT2` do estágio bridge |
| 2 | Saída `OUT1` do estágio bridge |

Os pinos formam um par diferencial do `TDA2822M`; nenhum deles é GND. A polaridade apenas altera a fase acústica do alto-falante.

### 13.6 Saída P2 — J6, PJ-307-5

| Pino | Função |
|---:|---|
| 1 | GND/sleeve |
| 2 | Contato comutado do canal ligado ao pino 3 |
| 3 | `AUDIO_MIX` via acoplamento e resistor de 1 kΩ |
| 4 | Contato comutado do canal ligado ao pino 5 |
| 5 | `AUDIO_MIX` via acoplamento e resistor de 1 kΩ |

O sinal mono é duplicado nos contatos de tip e ring. A saída é passiva e deve ser caracterizada antes de ser tratada como saída para fones de baixa impedância.

## 14. Regras de integração e bring-up

1. Conecte ou remova teclado, cartucho e GPU somente com a placa desligada.
2. Confirme orientação, GND e +5 V antes de energizar.
3. Toda saída ligada ao Data Bus deve permanecer em alta impedância fora do ciclo selecionado.
4. `/DETECT` informa presença, mas não implementa hot-plug.
5. Se um módulo não cumprir temporização em 16 MHz, selecione um divisor mais lento.
6. Inicie o bring-up no clock manual e acompanhe `T0`, `T1` e os sinais das micro-ROMs.
7. Teste primeiro alimentação e reset, depois clocks, fetch, registradores, ALU, memória e finalmente I/O.
8. Antes de habilitar áudio, grave `0x00` em `SOUND_CFG`.
9. Antes de usar a pilha, inicialize `SP` e confirme que a RAM está visível.
10. Use o programa de [`Checkup`](../Software/Checkup/wall8_checkup_completo_v1_guia.md) para a revisão integrada do sistema.

## 15. Arquivos normativos

| Arquivo | Papel |
|---|---|
| [`Hardware_Completo.pdf`](Hardware_Completo.pdf) | Esquema eletrônico |
| [`Software/Gerador_Microcodigo.py`](../Software/Gerador_Microcodigo.py) | Fonte normativa dos sinais e microsteps |
| [`Software/wall8.cpu`](../Software/wall8.cpu) | Codificação da ISA para o customasm |
| [`Software/wall8_instrucoes.md`](../Software/wall8_instrucoes.md) | Uso dos opcodes, ciclos e programação |
| [`Software/source_file_dispDec/7Seg.py`](../Software/source_file_dispDec/7Seg.py) | Conteúdo lógico das EPROMs dos displays |
| [`Software/wall8_placa_video.md`](../Software/wall8_placa_video.md) | Especificação detalhada da GPU |
| [`WALL-8_Manual_de_Referencia_Tecnica_Rev1.1.pdf`](../WALL-8_Manual_de_Referencia_Tecnica_Rev1.1.pdf) | Manual consolidado para consulta e impressão |

Projeto e arquitetura: **Vinicius Dias de Jesus**.

O WALL-8 utiliza o [customasm](https://github.com/hlorenzi/customasm) para definir e montar sua ISA. Agradecimentos ao autor e aos colaboradores do projeto.
