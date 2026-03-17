
# XTEA on DE2-115 with PS/2 Keyboard (HEX/ASCII) and 16x2 LCD

**What you build:** An XTEA block-cipher demo that lets you enter a 128-bit key (HEX), a 64-bit block as either **HEX (16 hex digits)** or **ASCII (8 characters)** via a **PS/2 keyboard**, and view results on the **16×2 LCD**.

## Files
- `top_xtea_ps2_lcd.v` — top-level: keyboard UI, XTEA core, LCD
- `xtea_core.v` — iterative XTEA (32 cycles)
- `ps2_keyboard.v` — PS/2 Set-2 receiver + scancode→ASCII mapping (letters, digits, space, ., ,, -, /, Enter, Backspace)
- `lcd_text.v` — 16×2 LCD controller (8-bit bus)
- `hex_ascii.v`, `hex64_to_ascii16.v` — small helpers
- `tb_xtea_core.v` — self-checking XTEA core testbench

## Build (Quartus)
1. Create project, add all `.v` files.
2. Use **DE2-115 System Builder** or a provided `.qsf` for pins named:
   - `CLOCK_50`
   - `PS2_KBCLK`, `PS2_KBDAT`
   - `LCD_ON`, `LCD_BLON`, `LCD_EN`, `LCD_RS`, `LCD_RW`, `LCD_DATA[7..0]`
3. Compile and program the FPGA.

## Use
- **K** → select Key entry (always HEX, 32 hex digits)
- **P** → select Block entry
- **M** → toggle **HEX/ASCII** mode for block (or **A** for ASCII, **H** for HEX)
- **E** → Encrypt, **D** → Decrypt (requires full key + block entered)
- **C** → clear key and block
- **Backspace** → delete last nibble (HEX) or char (ASCII)
- **Enter** is optional (ignored)

**LCD line 1** shows which field/mode you are editing and how many chars entered.  
**LCD line 2** always shows the 64‑bit block **in hex** (16 characters).

## Simulation
```
# ModelSim/Questa example
vlog xtea_core.v tb_xtea_core.v
vsim -c tb_xtea_core -do "run -all; quit"
```

## Notes
- PS/2 protocol: 11-bit frames, Set‑2 scan codes; mapping covers letters A–Z, digits, space, ., ,, -, /, Enter, Backspace.
- XTEA parameters: 64‑bit block, 128‑bit key, **32 cycles** (64 rounds), `delta=0x9E3779B9`.
