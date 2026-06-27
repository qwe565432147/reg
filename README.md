# FPGA Register Management Architecture (纯 Verilog)

## 概述 | Overview

一套完整的、纯 Verilog 实现的逻辑寄存器管理架构。提供 16-bit 位宽、64K 字地址空间的分区寄存器映射管理。专为 FPGA 设计，强调**优雅、复用性、健壮性、扩展性**。

```
地址空间:  0x0000 ────────────────────────────── 0xFFFF
                  │ 64 Kwords × 16 bit          │
                  └──────────────────────────────┘

分区布局:
  0x0000 ┌─────────────────────────┐
          │  reg_base               │  8K  — 版本/ID/Scratch
  0x1FFF ├─────────────────────────┤
  0x2000 │  reg_status             │  4K  — FPGA 状态/监控
  0x2FFF ├─────────────────────────┤
  0x3000 │  reg_iic                │  4K  — I2C 控制器
  0x3FFF ├─────────────────────────┤
  0x4000 │  reg_spi                │  4K  — SPI 控制器
  0x4FFF ├─────────────────────────┤
  0x5000 │  reg_ft                 │  4K  — 工厂测试/自检
  0x5FFF ├─────────────────────────┤
  0x6000 │  reg_int                │  4K  — 中断控制器
  0x6FFF ├─────────────────────────┤
  0x7000 │  (保留 / 未来扩展)       │  36K
  0xFFFF └─────────────────────────┘
```

## 文件结构 | File Structure

```
reg/
├── README.md              ← 本文档
├── rtl/                   ← RTL 源码
│   ├── reg_defines.v      ← 地址映射宏定义（中央配置文件）
│   ├── reg_slice.v        ← 寄存器原语单元（RW/RO/W1C/RC/RSVD）
│   ├── reg_base.v         ← 基础版本信息寄存器
│   ├── reg_status.v       ← FPGA 状态监控寄存器
│   ├── reg_iic.v          ← I2C 控制器寄存器（模板）
│   ├── reg_spi.v          ← SPI 控制器寄存器（模板）
│   ├── reg_ft.v           ← 工厂测试寄存器（模板）
│   ├── reg_int.v          ← 中断控制器寄存器
│   └── reg_top.v          ← 顶层集成（译码器 + 选择器 + 仲裁）
├── tb/
│   └── tb_reg_top.v       ← 功能验证 Testbench
└── sim/
    ├── reg_top.f          ← 文件清单（仿真/综合用）
    └── run_sim.tcl        ← ModelSim/Quest 运行脚本
```

## 核心特性 | Key Features

### 1. 优雅的切片化设计
- **`reg_slice.v`** — 提供 6 种寄存器原语，每种封装一种访问行为：
  - `reg_rw` — 读写
  - `reg_rw_wmask` — 带位写掩码的读写
  - `reg_ro` — 只读（组合逻辑直通）
  - `reg_w1c` — 写 1 清零
  - `reg_rc` — 读后自动清零（粘滞位）
  - `reg_rsvd` — 保留地址（读 0，忽略写）
- 所有原语共享统一的时钟/复位/加载接口，确保全局一致性。

### 2. 模块化的区域架构
每个区域（`reg_base`、`reg_status`、`reg_int` 等）是独立的 Verilog 模块，具有**标准化接口**：

```verilog
module reg_xxx (
    input              clk, rst_n,
    input              cs,           // 片选（由顶层译码）
    input              we,           // 写使能
    input  [11:0]      addr,         // 区域内偏移地址
    input  [15:0]      wdata,        // 写数据
    output [15:0]      rdata,        // 读数据
    output             rdy,          // 就绪
    // ... 区域特定的硬件接口
);
```

### 3. 参数化与可配置性
- 所有寄存器默认值、位宽通过参数控制
- 地址映射集中在 `reg_defines.v`，修改映射无需动 RTL 逻辑
- 顶层译码器采用纯组合逻辑，单周期读写

### 4. 总线协议
**单周期读写**，无等待状态：

| 操作 | 时序 |
|------|------|
| 读   | `bus_req=1, bus_we=0` → `bus_rdata` 同周期有效（组合逻辑）|
| 写   | `bus_req=1, bus_we=1` → 下个时钟沿寄存器更新 |
| 错误 | `bus_err=1` 当地址不映射任何区域 |

### 5. 中断控制器 (`reg_int`)
- 16 个中断源，支持边沿/电平触发（逐位配置）
- 标准寄存器组：STATUS / ENABLE / MASK / CLEAR / EDGE / RAW / VECTOR
- 优先级编码器（bit 0 最高）
- 两级同步器处理异步中断输入

## 如何扩展 | How to Extend

### 添加新寄存器到已有区域
在区域模块中新增实例和 case 项即可，例如 `reg_base.v` 中添加：

```verilog
// 1. 在 reg_defines.v 中定义偏移
`define REG_BASE_MY_REG  16'h0030

// 2. 在 reg_base.v 中实例化寄存器
reg_rw #(.W(16), .INIT(16'h0000)) u_my_reg (
    .clk(clk), .rst_n(rst_n),
    .load(write_active && (addr == `REG_BASE_MY_REG[12:0])),
    .wdata(wdata), .rdata(my_reg_rdata)
);

// 3. 在 read mux 中添加 case
`REG_BASE_MY_REG[12:0]: rdata_mux = my_reg_rdata;
```

### 添加全新区域
**只需改 4 处，每处 1-3 行：**

| 步骤 | 文件 | 操作 |
|------|------|------|
| 1 | `reg_defines.v` | 定义 `REG_XXX_ADDR`、`REG_XXX_SIZE`、`REG_XXX_AMSB` |
| 2 | `rtl/reg_xxx.v` | 新建模块，使用标准 `cs/we/addr/wdata/rdata/rdy` 接口 |
| 3 | `reg_top.v` | 添加 `reg_sel_xxx` 译码、实例化模块、扩展 rdata mux |
| 4 | `sim/reg_top.f` | 添加新文件路径 |

## 寄存器原语详解 | Register Primitive Reference

| 模块 | 访问类型 | 描述 | 硬件接口 |
|------|----------|------|----------|
| `reg_rw`      | R/W   | 软件读写，硬件读 | `load`, `wdata` → `rdata` |
| `reg_rw_wmask`| R/W   | 带位写掩码的读写 | `load`, `wdata`, `wmask` |
| `reg_ro`      | RO    | 硬件驱动，软件只读 | `din` → `rdata`（组合逻辑） |
| `reg_w1c`     | W1C   | 硬件置位，软件写1清零 | `set`, `load`, `wdata` |
| `reg_rc`      | RC    | 硬件置位，读后自动清零 | `set`, `read_strobe` |
| `reg_rsvd`    | -     | 保留地址，读0忽略写 | 无 |
| `reg_pulse`   | -     | 边沿 → 单周期脉冲 | `din` → `dout` |

## 仿真验证 | Simulation

### ModelSim / Questa
```bash
cd sim
vsim -do run_sim.tcl
```

### Vivado
```tcl
add_files -fileset sim_1 -of [get_filesets sim_1] {rtl/reg_defines.v rtl/reg_slice.v ...}
```

### Verilator
```bash
verilator -f sim/reg_top.f --top reg_top --cc    # 仅编译检查
```

## 测试点 | Testbench Coverage

| # | 测试项 | 验证内容 |
|---|--------|----------|
| 1 | 复位初值 | 所有 RO 寄存器读取默认值 |
| 2 | Scratch RW | 写 → 回读一致性 |
| 3 | Status 标志 | 标志位映射正确性 |
| 4 | Error Clear W1C | error_clr_pulse 脉冲生成 |
| 5 | 中断基本流程 | enable → fire → status → clear |
| 6 | 中断优先级 | bit 0 优先于 bit 15 |
| 7-9 | I2C/SPI/FT 模板 | 基本读写验证 |
| 10 | 地址错误 | 空洞地址返回 bus_err |

## 设计哲学 | Design Philosophy

1. **纯 Verilog** — 不使用 SystemVerilog 特性，最大兼容性（Vivado、Quartus、Yosys、Verilator、ModelSim）
2. **单时钟域** — 所有寄存器在同一个 `clk` / `rst_n` 域下，简化时序约束
3. **组合读 + 寄存写** — 读路径零等待，写路径寄存（最简时序，适合 ~100-150 MHz FPGA）
4. **配置与逻辑分离** — 地址映射在 `reg_defines.v`，RTL 逻辑在各自模块，改配置不改逻辑
5. **Include-based** — 使用 `` `include `` 而非文件列表依赖，仿真和综合工具均支持
6. **防御性解码** — 所有 case 带 `default`，未映射地址返回 `bus_err` 和读 0

## 新手入门

**强烈建议先读这份手把手教程：[docs/reg_slice_guide.md](docs/reg_slice_guide.md)**

它从零开始讲解：
- 寄存器在软硬件交互中的三种角色
- 每个 `reg_slice.v` 原语的**为什么、怎么用、内部原理**
- 带对比（手写 vs 用 slice）和动手练习
