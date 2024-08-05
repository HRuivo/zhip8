# zhip8
Chip-8 Emulator in Zig and SDL2.

## Status
![CHIP-8 Operations](https://github.com/HRuivo/zhip8/actions/workflows/main.yml/badge.svg)

## Installation

### From Source

Building Zhip8 from source is done with zig build.

```bash
git clone https://github.com/HRuivo/zhip8
cd zhip8
zig build
```

### Running

Run with a ROM to be loading into memory.

```bash
zig build run -- <ROM_NAME>
zig build run -- TETRIS
```
### TODO

- Error handling
- Stack Overflow handling
- Graphics Abstraction Layer
- Input handling
- Testing
