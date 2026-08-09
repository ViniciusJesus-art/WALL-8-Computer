# WALL-8 — Checkup completo v1.0

## Arquivos

- `wall8_checkup_completo_v1.asm`: fonte para CustomASM.
- `wall8_checkup_completo_v1.bin`: imagem de 40 KiB (`0xA000` bytes), correspondente ao `#bankdef bios`.
- SHA-256 do ASM: `9b9b4ca2cb673ceea1ae995f727989c5d4f2878033c0e3d5c21a0b91c8aaa131`
- SHA-256 do BIN: `ed1eff65d6e25f04f386f92ead6f56a0c8b52eca69a023a365a7721f41ac0f58`

## Atenção

O teste de RAM é **destrutivo** e apaga completamente `0x0000..0x7FFF`.

O firmware substitui a BIOS normal durante o checkup. Ao concluir todos os testes, ele executa `HLT`. Portanto, o resultado final esperado é a CPU parada, com:

```text
DISPLAY_HIGH = A1
DISPLAY_LOW  = 01
```

Se a CPU continuar depois do `HLT`, ela entra na rotina de falha do opcode `01`.

## Sequência executada

1. RAM completa, com padrões `00`, `FF`, `55` e `AA`.
2. Display de 7 segmentos e controle `/LED_EN`.
3. Todos os 76 opcodes.
4. Timers de 1 ms e 500 ms.
5. Vídeo texto `40x30`.
6. Vídeo gráfico `320x240`.
7. Vídeo gráfico `160x120` e animação.
8. Teclado e limpeza de `KEY_READY`.
9. Som: oito seleções de tom e oito de ruído, 500 ms por seleção.
10. Cartucho: detecção e duas leituras completas de 20 KiB para comparar checksum.
11. Resumo e teste final de `HLT`.

## Códigos no display

Durante os testes da CPU:

```text
DISPLAY_LOW  = opcode atual
DISPLAY_HIGH = 00 durante a execução
```

Em falha fatal:

```text
DISPLAY_LOW  = opcode ou identificador do teste
DISPLAY_HIGH = alterna entre valor esperado e valor obtido
```

Identificadores dos testes externos:

| LOW | Teste |
|---:|---|
| `E1` | RAM `0x0400..0x7FFF` |
| `E2` | RAM `0x0000..0x03FF` |
| `F1` | Display e LEDs |
| `F3` | Timers |
| `11` | Vídeo texto 40x30 |
| `12` | Vídeo 320x240 |
| `13` | Vídeo 160x120 |
| `F0` | Teclado |
| `F4` | Som |
| `A0` | Cartucho |
| `01` | HLT final |

## Comportamento dos periféricos opcionais

### Vídeo

O bit `$F300.5` é `/VIDEO_DETECT`:

- `0`: executa todos os testes de vídeo;
- `1`: pula vídeo sem marcar falha.

O teste segue a definição detalhada de `VIDEO_STATUS.bit4 = CURSOR_END`.

### Teclado

Há uma janela de aproximadamente 10 segundos para pressionar uma tecla.

- Se uma tecla for recebida, o firmware verifica o byte e confirma que a leitura de `KEY_DATA` limpou `KEY_READY`.
- Sem tecla, o teste fica como `SKIP`; não é uma falha fatal.

### Cartucho

O bit `$F300.4` é `/CARD_DETECT`:

- `0`: lê `0xA000..0xEFFF` duas vezes e compara os checksums;
- `1`: pula o teste.

O checkup **não chama `$A000`**, evitando executar automaticamente um programa desconhecido. O checksum confirma estabilidade de leitura e barramentos, mas não valida o conteúdo correto da ROM sem uma assinatura oficial de cartucho.

### Som

A codificação usada é a da tabela detalhada:

```text
bit0 = NOISE_EN
bit1 = TONE_EN
bits2..4 = seleção de tom
bits5..7 = seleção de ruído
```

Assim, `SOUND_CFG = 00` desliga ambos os geradores.

## Montagem

O fonte começa com:

```asm
#include "../wall8.cpu"
```

Ajuste para:

```asm
#include "wall8.cpu"
```

caso o arquivo do checkup fique na mesma pasta do `wall8.cpu`.

A imagem `.bin` incluída foi montada por um montador independente usando diretamente a tabela documentada dos 76 opcodes e executada até o `HLT` em um emulador lógico. Recomenda-se também montar o `.asm` com o seu `wall8.cpu` atual para confirmar que a definição real não divergiu da documentação.
