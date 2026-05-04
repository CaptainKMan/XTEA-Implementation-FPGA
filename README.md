# XTEA Encryption Engine — DE2-115 FPGA

A hardware implementation of the XTEA (eXtended Tiny Encryption Algorithm) block cipher on the Terasic DE2-115 (Cyclone IV E EP4CE115F29C7). The system accepts a 128-bit key and 64-bit plaintext via a PS/2 keyboard and displays results on the onboard 16×2 LCD.

---

## Features

- Full XTEA encrypt and decrypt in hardware — 32 cycles at 50 MHz (~640 ns per block)
- PS/2 keyboard input with Set-2 scan code decoding and full frame validation (start bit, parity, stop bit)
- HEX entry mode (16 nibbles) and ASCII entry mode (8 characters) for the plaintext block
- HD44780 LCD controller with complete initialization sequence and continuous refresh
- Power-on reset generator — no button required on boot
- Function key controls (F1–F6) so the full alphanumeric keyboard is available for data entry
- Switch-mode fallback input via DE2-115 onboard switches and pushbuttons (KEY[3] toggles modes)

---

## Hardware Requirements

| Item | Detail |
|------|--------|
| FPGA Board | Terasic DE2-115 (Cyclone IV E EP4CE115F29C7) |
| Keyboard | PS/2 keyboard (native PS/2, not USB-to-PS/2 passive adapter) |
| Software | Quartus Prime 20.1.1 Lite Edition |

---

## Repository Structure

```
XTEA-Implementation-FPGA/
├── student_xtea_ps2_ascii/
│   ├── xtea_core.v          # XTEA cipher engine (32-cycle FSM)
│   ├── ps2_keyboard.v       # PS/2 receiver + Set-2 scan code to ASCII
│   ├── lcd_text.v           # HD44780 LCD controller FSM
│   ├── hex64_to_ascii16.v   # 64-bit hex → 16 ASCII character converter
│   ├── hex_ascii.v          # Nibble ↔ ASCII conversion utilities
│   ├── top_xtea_ps2_lcd.v   # Top-level integrator
│   └── tb_xtea_core.v       # ModelSim testbench (3 encrypt/decrypt vectors)
├── XTEA_proj.qsf            # Quartus pin assignments
├── XTEA_proj.qpf            # Quartus project file
└── XTEA_proj.sdc            # Timing constraints (50 MHz clock)
```

---

## Pin Assignments

| Signal | FPGA Pin | Direction |
|--------|----------|-----------|
| CLOCK_50 | PIN_Y2 | Input |
| PS2_KBCLK | PIN_G6 | Input |
| PS2_KBDAT | PIN_H5 | Input |
| RESET_N | PIN_M23 | Input |
| LCD_ON | PIN_L5 | Output |
| LCD_EN | PIN_L4 | Output |
| LCD_RS | PIN_M2 | Output |
| LCD_RW | PIN_M1 | Output |
| LCD_DATA[0] | PIN_L3 | Output |
| LCD_DATA[1] | PIN_L1 | Output |
| LCD_DATA[2] | PIN_L2 | Output |
| LCD_DATA[3] | PIN_K7 | Output |
| LCD_DATA[4] | PIN_K1 | Output |
| LCD_DATA[5] | PIN_K2 | Output |
| LCD_DATA[6] | PIN_M3 | Output |
| LCD_DATA[7] | PIN_M5 | Output |
| SW[0..4,17] | See QSF | Input |
| KEY[0..3] | See QSF | Input |

---

## Building & Programming

1. Open `XTEA_proj.qpf` in Quartus Prime 20.1.1
2. Verify the target device is **EP4CE115F29C7** (Assignments → Device)
3. Run full compilation (Processing → Start Compilation)
4. Connect the DE2-115 via USB-Blaster, power on the board
5. Open the Programmer (Tools → Programmer), select the `.sof` from `output_files/`, click Start

---

## Simulation

Open ModelSim, set the working directory to the project root, and run:

```tcl
vlog student_xtea_ps2_ascii/xtea_core.v
vlog student_xtea_ps2_ascii/tb_xtea_core.v
vsim tb_xtea_core
run -all
```

Expected output:
```
# All XTEA tests passed.
```

---

## Usage

Power on the board with a PS/2 keyboard connected. The LCD shows `XTEA READY`.

### Controls

```
F1        - Select KEY field (128-bit key, enter 32 hex digits)
F2        - Select BLOCK field (64-bit plaintext/ciphertext)
F3        - Encrypt
F4        - Decrypt
F5        - Toggle ASCII / HEX entry mode for block field
F6        - Clear all fields
Backspace - Delete last character in current field
```

### Quick Example

1. Press **F1**, type 32 hex digits for your key (`000102030405060708090A0B0C0D0E0F00112233445566778899AABBCCDDEEFF` → abbreviated to 32 chars)
2. Press **F2**, type 16 hex digits for your plaintext block
3. Press **F3** — ciphertext appears on line 2
4. Press **F2**, type the ciphertext back in, press **F4** — original plaintext returns

---

## Design Notes

**XTEA round structure:** Each of the 32 cycles performs two Feistel half-rounds (one update to v0, one to v1), totalling 64 half-round operations per encrypt/decrypt matching the original Needham-Wheeler specification.

**PS/2 receiver:** Uses a 4-stage synchronizer (1100 falling-edge pattern) on PS2_KBCLK, counts all 11 bits including start, and validates stop bit and odd parity before accepting a frame. Break codes (0xF0 prefix) are correctly discarded.

**LCD timing:** Initialization sequence observes HD44780-required delays: 15 ms power-on, 4.1 ms post-Function-Set, 2 ms post-Clear, 100 µs between other commands. EN pulse width is 1 µs. All implemented as synchronous downcounters at 50 MHz.

**Timing:** The design operates at 50 MHz. Without an SDC file, Quartus defaults to a 1 ns target and reports timing violations — these are false; add `XTEA_proj.sdc` with `create_clock -period 20.000 [get_ports CLOCK_50]` to see the true (passing) timing result.

---

## Known Limitations

- LCD_DATA pins must be assigned with brackets in the QSF: `LCD_DATA[0]` not `LCD_DATA0`
- Passive USB-to-PS/2 adapters do not work with modern keyboards; use a native PS/2 keyboard

---
