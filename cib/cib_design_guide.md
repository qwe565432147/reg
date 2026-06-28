# CIB 寄存器管理架构 — 从零开始详细设计文档

> **写给谁看的**：刚入职的新员工、转岗做 FPGA 开发的同事、或者任何想知道"芯片里的寄存器到底是怎么一回事"的人。  
> **需要的基础**：懂最基本的 Verilog（module、wire、reg、always），知道 "clk" 是时钟、"rst_n" 是复位。就够了。  
> **读完能干什么**：看懂 CIB 架构的所有代码，知道怎么加新的寄存器、怎么加新的功能模块、怎么把整套东西搬到另一个项目里用。

---

## 目录

1. [先搞懂三个基本概念](#1-先搞懂三个基本概念)
2. [CIB 架构长什么样](#2-cib-架构长什么样)
3. [地址译码：CPU 怎么找到你要的寄存器](#3-地址译码cpu-怎么找到你要的寄存器)
4. [寄存器原语：7 种"积木"](#4-寄存器原语7-种积木)
5. [cib_top.v：架构的"大脑"](#5-cib_topv架构的大脑)
6. [cib_ft.v：一个完整的功能模块示例](#6-cib_ftv一个完整的功能模块示例)
7. [从头加一个寄存器（实战）](#7-从头加一个寄存器实战)
8. [从头加一个新功能区域（实战）](#8-从头加一个新功能区域实战)
9. [移植到新项目：换总线协议怎么办](#9-移植到新项目换总线协议怎么办)
10. [附录：文件清单与数据流](#10-附录文件清单与数据流)

---

## 1. 先搞懂三个基本概念

### 1.1 什么是寄存器（Register）

**寄存器 = 一个 CPU 能读写的存储单元**。

想象一个控制面板：

```
            ┌──────────────────────┐
 CPU 读 ←── │  0x1C00 这个地址     │ ←── 你可以看到里面的值（读）
 CPU 写 ──→ │  里的 16 位存储单元   │ ──→ 你可以改变里面的值（写）
            └──────────────────────┘
                  │
                  ▼
            连接到芯片内部的某个功能
            （比如：让某个引脚输出高电平）
```

在 FPGA 里，每个寄存器就是一个 16 位的存储空间。CPU（或者叫"主控"）通过**地址**来找到它，通过**读/写**来操作它。

### 1.2 什么是地址映射（Address Map）

芯片里不可能只有一个寄存器 —— 可能有几百上千个。为了管理它们，我们把地址空间分成连续的块，每个块有一个固定的**地址**。

就像一栋楼：

```
地址空间 (0x0000 ~ 0x3FFF)   →   一栋 32 层的楼
每层 512 个字                →   每层 512 个房间
```

CIB 的地址空间是 **0x0000 ~ 0x3FFF**，一共 **32K（32768）个 16 位字**。

### 1.3 什么是总线协议（Bus Protocol）

CPU 和寄存器之间怎么"说话"？需要一组信号线来传输地址、数据、读写命令。这套规则就是总线协议。

常见的协议有：
- **eSPI** —— 英特尔发明的串行外设接口，现在服务器/电脑主板上很常见
- **SMBus / I2C** —— 两线制的低速总线，常用于电源管理、温度传感器
- **Parallel Bus** —— 古老的并口总线，地址线和数据线分开

**CIB 架构的精髓**：不管你用哪种外部总线，到了 CIB 内部，都转成统一的**内部局部总线**。这样你只需要在顶层做一次协议转换，下层 27 个功能模块完全不用动。

---

## 2. CIB 架构长什么样

### 2.1 三层架构

```
┌─────────────────────────────────────────────────────┐
│  第一层：外部协议适配层                                │
│  (cib_top_espi.v / cib_top_smbus.v / 你自己写的)     │
│                                                      │
│  功能：把 eSPI/SMBus/... 的信号转成 ext_* 标准接口    │
│  移植新项目时：只改这一层                              │
└──────────────────┬──────────────────────────────────┘
                   │ ext_cs_n, ext_oe, ext_we,
                   │ ext_addr, ext_wdata, ext_rdata, ...
                   ▼
┌─────────────────────────────────────────────────────┐
│  第二层：区域片选译码层                                │
│  (cib_top.v)                                         │
│                                                      │
│  功能：                                              │
│  1. ext_* → 内部局部总线转换                          │
│  2. 用 AMSB 判断地址属于哪个区域 → 拉低该区域的 cs_n   │
│  3. 把选中区域的读数据送回 ext_rdata                   │
│  4. 地址空洞检测 → 返回 bus_err                       │
└──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬─────────────┘
   │  │  │  │  │  │  │  │  │  │  │  │  │
   ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼  ▼
┌─────────────────────────────────────────────────────┐
│  第三层：功能寄存器模块                                │
│  (cib_ft / cib_base / cib_pwr / ... 每个区域一个)     │
│                                                      │
│  功能：                                              │
│  1. 内部译码：根据地址偏移找到本区域内的具体寄存器      │
│  2. 例化寄存器原语（reg_rw / reg_ro / ...）            │
│  3. 把寄存器值和硬件外设信号互相连接                    │
│  新加功能时：在这层加新的模块，不影响上面两层           │
└─────────────────────────────────────────────────────┘
```

### 2.2 关键设计思想

**"配置 ≠ 逻辑"**：
- 地址映射（哪个区域在哪个地址范围）写在 `cib_reg_defines.v` 里
- 寄存器逻辑（每个寄存器是 RW 还是 RO）写在各自功能模块里
- 改地址映射不用动 RTL 逻辑，改 RTL 逻辑不用动地址映射

**"标准接口"**：
每个 `cib_xxx` 模块都用完全相同的端口连接 `cib_top`：
```
cs_n, oe, we, addr[15:0], wdata[15:0], rdata[15:0], rdy
```
这意味着你可以像插积木一样插拔功能模块。

---

## 3. 地址译码：CPU 怎么找到你要的寄存器

### 3.1 地址的两部分

CIB 使用 16 位地址（0x0000 ~ 0x3FFF）。每一级译码只关心地址的一部分：

```
完整地址：     [15] [14] [13] [12] [11] [10] [9] [8] [7] ... [0]
                  \    \    \    \   /
                   \    \    \    \ /
                    ┌────┬────┬───┐
                    │ 区域选择    │ ← 区域译码（cib_top 做）
                    │ 高位比较    │    比较 addr[15:AMSB] 和 BASE[15:AMSB]
                    └────┬────┬───┘
                         │
                    ┌────┴────┐
                    │ 寄存器选择 │ ← 模块内部译码（cib_xxx 自己做）
                    │ 低位偏移  │    比较 addr[AMSB-1:0] 和寄存器偏移
                    └─────────┘
```

### 3.2 AMSB 是什么

**AMSB = Address Most Significant Bit**（地址最高有效位）。

每个区域定义一个 AMSB，用来指示"地址的哪一位以上用于区域选择"。

举个例子，`CIB_FT` 区域：
```
基地址：0x1C00     二进制：0001 1100 0000 0000
AMSB：  8

所以：
  addr[15:8] 用于区域选择  →  在 cib_top 里比较
  addr[7:0]  用于模块内偏移 →  在 cib_ft.v 里译码各个寄存器
```

### 3.3 一个完整的地址译码过程

假设 CPU 要读地址 `0x1C03`：

```
地址 0x1C03 = 二进制 0001 1100 0000 0011

第一步：cib_top 查看所有区域的 cs_n
  检查 CIB_FT：addr[15:8] = 0001 1100，CIB_FT_ADDR[15:8] = 0001 1100 → 匹配！
  所以 cs_n_ft = 0 （选中了 FT 区域）

第二步：cib_top 把 oe/addr/wdata 发给 cib_ft

第三步：cib_ft 收到 cs_n=0，oe=1
  计算 offset = addr[7:0] = 8'h03
  查找：offset == REG_CLK_MODULE_FREQ_MAX_H (偏移 0x03)？成立！
  返回：rdata = freq_max_h_rdata

第四步：cib_top 从 rdata_ft 拿到数据，送到 ext_rdata
```

### 3.4 为什么 AMSB 译码高效

传统写法：
```verilog
// 每个区域都要这样写，累死人
reg_sel_ft = (addr >= 16'h1C00) && (addr <= 16'h1CFF);
```

AMSB 写法：
```verilog
// 所有区域统一公式，综合出来就是一个比较器
cs_n_ft = ~bus_active | (addr[15:8] != `CIB_FT_ADDR[15:8]);
```

而且 AMSB 是根据区域大小自动推导的 —— 256 字区域 AMSB=7，512 字区域 AMSB=8，以此类推。不需要手算边界。

### 3.5 例外：cib_clk_module

`cib_clk_module` 的大小是 3840 字（0x0F00），不是 2 的幂。AMSB 方法会误译码。所以单独对它做了范围检查：

```verilog
assign cs_n_clk_module = ~bus_active
                       | (ext_addr < `CIB_CLK_MODULE_ADDR)
                       | (ext_addr > `CIB_CLK_MODULE_LAST);
```

其他 26 个区域都是 2 的幂对齐，都用统一公式。

---

## 4. 寄存器原语：7 种"积木"

所有寄存器都由 `cib_reg_slice.v` 里的 7 种原语搭建。每种原语封装了一种**读写访问行为**。

### 4.1 reg_rw — 读写寄存器

**最常用的寄存器类型**。CPU 可以随便读、随便写。

```
CPU 写 → wdata ──→ [寄存器] ──→ rdata → CPU 读
                    │
                    ▼
                 输出到硬件逻辑（控制信号）
```

**典型用途**：控制寄存器（开关、模式选择、配置参数）。

**代码示例**：
```verilog
reg_rw #(
    .W    (16),          // 宽度 16 位
    .INIT (16'h0000)     // 复位初值 0
) u_my_reg (
    .clk   (clk),
    .rst_n (rst_n),
    .load  (write_active & reg_sel),   // 写使能
    .wdata (wdata),                     // 写数据
    .rdata (my_reg_rdata)               // 读数据
);
```

### 4.2 reg_ro — 只读寄存器

**CPU 只能读，不能写**。值由硬件逻辑驱动。

```
硬件逻辑 → din ──→ [组合逻辑] ──→ rdata → CPU 读
```

**典型用途**：状态寄存器、版本号、温度读数。

**注意**：reg_ro 没有时钟、没有复位 —— 就是一根导线（`assign rdata = din`）。

### 4.3 reg_rw_wmask — 带掩码的读写寄存器

CPU 写的时候，可以指定**只修改某些位**，其他位保持不变。

```
CPU 写 → wdata ──┐
CPU 写 → wmask ──┤   [寄存器] ──→ rdata → CPU 读
                 │   只修改 wmask=1 的位
```

**典型用途**：多个 bit 分别控制不同功能，不想因为写一次就把别的 bit 冲掉。

### 4.4 reg_w1c — 写 1 清零寄存器

**硬件可以置位**（set），**CPU 写 1 来清零**。CPU 写 0 不影响。

```
硬件事件 → set ──┐
                  [寄存器] ──→ rdata → CPU 读
CPU 写1 → wdata ──┘ 清零对应位
```

优先级：硬件置位 > 软件写1清零 > 保持。

**典型用途**：中断状态寄存器。硬件检测到事件就置 1，CPU 处理后写 1 清零。

### 4.5 reg_rc — 读后自动清零寄存器

**CPU 读取这个寄存器之后，它自动变成 0**。

```
硬件置位 → set ──→ [寄存器] ──→ rdata → CPU 读
                    │             之后自动清零
                    ▼
                  值变为 0
```

**典型用途**：一次性状态标志，比如"数据准备好了"，CPU 读一次就知道。

### 4.6 reg_rsvd — 保留地址空洞

**占位用**。读返回 0，写被忽略。

**典型用途**：填充地址映射里的空洞，避免错误访问。

### 4.7 reg_pulse — 边沿转脉冲

把输入信号**上升沿**变成**一个周期宽度的脉冲**。

```
din   ──╂──┃──╂──┃──╂──  (电平变化)
dout  ────┃██┃───────     (1 周期脉冲)
```

**典型用途**：给 W1C 寄存器生成置位脉冲、触发一次性操作。

### 4.8 怎么选哪种原语

| 场景 | 用哪个 |
|------|--------|
| 软件可读可写的控制参数 | `reg_rw` |
| 软件只能读的状态值 | `reg_ro` |
| 多个控制位放在一个寄存器里，只改其中几个 | `reg_rw_wmask` |
| 硬件报事件，软件处理后写 1 清除 | `reg_w1c` |
| 硬件置位，读一次就自动清除 | `reg_rc` |
| 地址空洞、保留位 | `reg_rsvd` |
| 电平信号转脉冲 | `reg_pulse` |

---

## 5. cib_top.v：架构的"大脑"

### 5.1 它做什么

`cib_top.v` 是整个寄存器系统的**顶层模块**，负责三件事：

1. **外部总线适配**：把外部来的 `ext_cs_n / ext_oe / ext_we / ext_addr / ext_wdata` 转成内部用的 `bus_read / we_q / wdata_q`
2. **区域片选译码**：根据地址判断属于哪个区域，拉低对应区域的 `cs_n`
3. **读数据汇合**：把选中区域的 `rdata` 送到 `ext_rdata`，没选中时返回 0 并报 `ext_err`

### 5.2 外部接口说明

```
信号               方向  宽度  说明
─────────────────────────────────────────────
ext_clk             I    1    全局时钟（所有寄存器共用）
ext_rst_n           I    1    异步复位，低电平有效
ext_cs_n            I    1    片选，低电平有效（= 有事务来）
ext_oe              I    1    读使能（= CPU 要读数据）
ext_we              I    1    写使能（= CPU 要写数据）
ext_addr            I    16   地址线
ext_wdata           I    16   写数据
ext_rdata           O    16   读数据
ext_rdy             O    1    就绪（= 本周期事务已完成）
ext_err             O    1    错误（= 地址不存在）
```

**时序说明（读）**：

```
时钟  █▁█▁█▁█▁█▁█▁█▁█▁
                          
addr  ────┃  0x1C00  ┃────  (地址在 ext_cs_n 有效时给出)
                                    
cs_n  ────┃____┃────────  (低电平有效)
                                    
oe    ────┃_1__┃────────  (高电平 = 读)
                                    
rdata ────────┃ 0xABCD ┃──  (同一周期返回数据！组合逻辑)
                                    
rdy   ────────┃_1____┃───  (数据有效)
```

**时序说明（写）**：

```
时钟  █▁█▁█▁█▁█▁█▁█▁█▁
                        ▲
addr  ────┃  0x1C00  ┃┃─────
                        │
cs_n  ────┃____┃───────│───
                        │
we    ────┃_1__┃───────│─── (在时钟上升沿采样)
                        │
wdata ────┃ 0xABCD ┃───│───
                        │
                        └── 此时数据写入寄存器
```

### 5.3 片选译码逻辑

核心公式只有一行，重复 27 次：

```verilog
cs_n_xxx = ~bus_active | (addr[15:AMSB] != BASE[15:AMSB]);
```

翻译成人话：**当地址的高位（高于 AMSB 的部分）等于该区域的基地址高位时，选中该区域。**

所有 2 的幂对齐的区域都用这个公式。综合器会把所有区域的比较合并，最终每个区域只需要一个比较器。

### 5.4 地址空洞检测

如果地址不属于任何已定义区域：

```verilog
any_selected = ~cs_n_base | ~cs_n_board_sta | ... | ~cs_n_sspi;
ext_err = bus_active & ~any_selected;
```

CPU 读到不存在的地址 → `ext_err=1`，`ext_rdata=0`。

### 5.5 移植接口

`cib_top.v` 的 `ext_*` 端口是**通用类 SRAM 接口**。新项目的外部总线协议（eSPI、SMBus 等）需要一个**协议包装器**来桥接：

```
eSPI 协议 ──→ cib_top_espi.v ──→ cib_top
                                    │
SMBus 协议 ──→ cib_top_smbus.v ──┘
                                    │
Parallel 协议 ──→ cib_top_parallel.v ──┘
```

这个包装器通常只需要几十行代码，把协议侧的地址/数据/读写信号映射到 `ext_*` 端口上。

---

## 6. cib_ft.v：一个完整的功能模块示例

### 6.1 它做什么

`cib_ft` 是"工厂测试"寄存器模块，地址范围 `0x1C00 ~ 0x1CFF`（512 个字）。它实现了 8 个寄存器，用于工厂生产线的测试。

### 6.2 模块接口

```verilog
module cib_ft (
    // 时钟和复位（来自 cib_top）
    input             clk,
    input             rst_n,

    // 局部总线（来自 cib_top）
    input             cs_n,      // 片选，低有效
    input             oe,        // 读使能
    input             we,        // 写使能（单周期脉冲）
    input      [15:0] addr,      // 16位地址
    input      [15:0] wdata,     // 写数据
    output reg [15:0] rdata,     // 读数据
    output            rdy,       // 单周期就绪

    // 硬件外设信号（接到 FPGA 内部的实际测试逻辑）
    output            test_mode_o,
    output            test_loopback_o,
    output            bist_start_o,
    input             bist_busy_i,
    input             bist_pass_i,
    input             bist_fail_i,
    output     [15:0] test_data_in_o,
    input      [15:0] test_data_out_i,
    output     [15:0] loop_count_o
);
```

**重点**：局部总线部分（clk 到 rdy）是所有 cib_xxx 模块**一模一样**的接口。硬件外设部分（test_mode_o 到 loop_count_o）是每个模块**自己特有的**。

### 6.3 内部结构

```
cib_ft 内部流程：

                        ┌──────────────────┐
cs_n ──→ cs_active     │                  │
oe   ──→ read_active   │  读数据多路选择器  │
we   ──→ write_active  │  组合逻辑 case    │
addr ──→ offset[7:0]   │  根据哪个寄存器    │
                        │  被选中，输出对应  │
                        │  的 rdata        │
                        └──────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
    ┌────▼────┐          ┌────▼────┐          ┌────▼────┐
    │ FOD_CTRL│          │FREQ_ACT_│          │ 其他 5  │
    │ (reg_rw)│          │L (reg_rw)          │ 个寄存器  │
    │         │          │         │          │         │
    │bit[0]=  │          │输出→    │          │         │
    │test_mode│          │data_in_o│          │         │
    └─────────┘          └─────────┘          └─────────┘
```

### 6.4 寄存器译码

每个寄存器有一条选择线：

```verilog
wire reg_fod_ctrl = cs_active & (offset == `REG_CLK_MODULE_FOD_CTRL[7:0]);
```

- `cs_active` 确保只在本模块被选中时才工作
- 比较 `offset`（addr 的低 8 位）和寄存器偏移定义
- 译码结果是组合逻辑，不消耗寄存器

### 6.5 读数据多路选择器

```verilog
always @(*) begin
    rdata = 16'h0000;  // 默认值 = 0
    if (read_active) begin
        case (1'b1)
            reg_fod_ctrl:   rdata = fod_ctrl_rdata;
            reg_freq_act_h: rdata = freq_act_h_rdata;
            // ... 每个寄存器一行
            default:        rdata = 16'h0000;
        endcase
    end
end
```

`case (1'b1)` 是一个并联优先级编码器 —— 哪个选择线为 1 就输出对应的 rdata。所有选择线互斥（一个地址不可能同时选中两个寄存器），所以综合器会把它优化成一个普通的多路选择器。

---

## 7. 从头加一个寄存器（实战）

**场景**：在 cib_ft 模块里加一个"环回计数最大值"寄存器（FT_MAX_LOOP），地址偏移 0x09，类型 RW，复位值 0xFFFF。

### 第 1 步：在 cib_ft_reg_def.v 加偏移定义

```verilog
`define REG_FT_MAX_LOOP   16'h0009  // 环回计数最大值寄存器 (RW)
```

### 第 2 步：在 cib_ft.v 加选择线

```verilog
// 在 // Per‑Register Select Lines 区域添加：
wire reg_max_loop  = cs_active & (offset == `REG_FT_MAX_LOOP[`CIB_FT_AMSB-1:0]);
```

### 第 3 步：在 cib_ft.v 实例化寄存器

```verilog
// ---- REG_FT_MAX_LOOP (0x09, RW) ------------------------------------------
// 环回计数最大值，复位为 0xFFFF
wire [15:0] max_loop_rdata;
reg_rw #(
    .W    (16),
    .INIT (16'hFFFF)
) u_max_loop (
    .clk   (clk),
    .rst_n (rst_n),
    .load  (write_active & reg_max_loop),
    .wdata (wdata),
    .rdata (max_loop_rdata)
);
```

### 第 4 步：在 cib_ft.v 的读 mux 里加一行

```verilog
reg_max_loop:   rdata = max_loop_rdata;
```

### 共 4 步，每步 1 行，总计 4 行代码。

---

## 8. 从头加一个新功能区域（实战）

**场景**：新增一个温度传感器区域 `cib_temp`，地址范围 `0x3F00 ~ 0x3FFF`（256 字，AMSB=7），包含：
- `REG_TEMP_CTRL`（0x00，RW）—— 控制寄存器
- `REG_TEMP_VALUE`（0x01，RO）—— 温度读数

### 第 1 步：在 cib_reg_defines.v 加区域定义

```verilog
// 再往上翻，cib_sspi 是最后一个区域（0x3F00）
// 但实际上 0x3F00 已经被 cib_sspi 占了！
// 所以找个真的空闲地址，比如 0x3E00（假设还没用）
// 这里只是为了演示流程，实际地址需要重新规划……

// -------------------------------- cib_temp ----------------------------------
//  256 字  (假设某个空闲地址) → 偏移 [6:0], 译码 [15:7]
`define CIB_TEMP_ADDR            16'h????   // 替换为实际未使用的地址
`define CIB_TEMP_SIZE            16'h0080
`define CIB_TEMP_LAST            (`CIB_TEMP_ADDR + `CIB_TEMP_SIZE - 1)
`define CIB_TEMP_AMSB            7
```

### 第 2 步：创建 cib_temp/cib_temp_reg_def.v

```verilog
`ifndef __CIB_TEMP_REG_DEF_V__
`define __CIB_TEMP_REG_DEF_V__

// ============================================================================
// cib_temp 寄存器映射  (基地址 = ?????)
// ============================================================================
`define REG_TEMP_CTRL            16'h0000  // 温度传感器控制寄存器       (RW)
`define REG_TEMP_VALUE           16'h0001  // 当前温度读数寄存器         (RO)

`endif
```

### 第 3 步：创建 cib_temp/cib_temp.v

```verilog
`include "cib_reg_defines.v"
`include "cib_temp_reg_def.v"

module cib_temp (
    input              clk,
    input              rst_n,
    input              cs_n,
    input              oe,
    input              we,
    input      [15:0]  addr,
    input      [15:0]  wdata,
    output reg [15:0]  rdata,
    output             rdy,

    // ---- 温度传感器硬件接口 ----
    input      [15:0]  temp_data_i,     // 来自 ADC 的温度数据
    output             temp_enable_o    // 传感器使能
);

    wire cs_active    = ~cs_n;
    wire read_active  = cs_active & oe;
    wire write_active = cs_active & we;
    wire [6:0] offset = addr[`CIB_TEMP_AMSB-1:0];

    // 选择线
    wire reg_ctrl   = cs_active & (offset == `REG_TEMP_CTRL[6:0]);
    wire reg_value  = cs_active & (offset == `REG_TEMP_VALUE[6:0]);

    // 寄存器实例化
    wire [15:0] ctrl_rdata;
    reg_rw #(.W(16), .INIT(16'h0000)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .load(write_active & reg_ctrl),
        .wdata(wdata), .rdata(ctrl_rdata)
    );

    wire [15:0] value_rdata;
    reg_ro #(.W(16)) u_value (
        .din(temp_data_i), .rdata(value_rdata)
    );

    // 读 mux
    always @(*) begin
        rdata = 16'h0000;
        if (read_active) begin
            case (1'b1)
                reg_ctrl:  rdata = ctrl_rdata;
                reg_value: rdata = value_rdata;
                default:   rdata = 16'h0000;
            endcase
        end
    end

    assign rdy = cs_active;

    // 硬件输出
    assign temp_enable_o = ctrl_rdata[0];

endmodule
```

### 第 4 步：在 cib_top.v 加片选信号 + rdata/rdy wire + 例化

```verilog
// 在 Region Decode 区域加：
wire cs_n_temp;
assign cs_n_temp = ~bus_active | (ext_addr[15:`CIB_TEMP_AMSB] != `CIB_TEMP_ADDR[15:`CIB_TEMP_AMSB]);

// 在 rdata/rdy wire 声明区域加：
wire [15:0] rdata_temp;
wire         rdy_temp;

// 在读 mux 加：
~cs_n_temp: ext_rdata = rdata_temp;

// 在 rdy mux 加：
~cs_n_temp: rdy_of_selected_region = rdy_temp;

// 在 any_selected 加：
| ~cs_n_temp

// 在模块例化区域加：
cib_temp u_cib_temp (
    .clk(ext_clk), .rst_n(ext_rst_n),
    .cs_n(cs_n_temp), .oe(bus_read), .we(we_q),
    .addr(ext_addr), .wdata(wdata_q),
    .rdata(rdata_temp), .rdy(rdy_temp),
    .temp_data_i(...), .temp_enable_o(...)
);
```

**一共改 4 个文件，加约 20 行代码**。架构搭好后，扩展成本极低。

---

## 9. 移植到新项目：换总线协议怎么办

### 9.1 问题

假设你这套 CIB 架构之前用在 eSPI 总线的项目上，现在新项目要用 SMBus（I2C）。怎么办？

**答案是：只需要写一个新的协议包装器 `cib_top_smbus.v`，其他所有 cib_xxx 模块不改一行代码。**

### 9.2 协议包装器示例

下面是一个极简的 SMBus 包装器示意（不是完整实现，只是展示思路）：

```verilog
// cib_top_smbus.v — SMBus/I2C 转 ext_* 接口
module cib_top_smbus (
    // SMBus 接口（来自芯片引脚）
    inout              smb_clk,
    inout              smb_data,

    // CIB 寄存器系统接口
    output             reg_clk,
    output             reg_rst_n,
    // 以下信号直接接 cib_top 的 ext_* 端口
    output             ext_cs_n,
    output             ext_oe,
    output             ext_we,
    output     [15:0]  ext_addr,
    output     [15:0]  ext_wdata,
    input      [15:0]  ext_rdata,
    input              ext_rdy,
    input              ext_err
);

    // 这里的逻辑：
    // 1. 检测 SMBus 起始条件
    // 2. 解析地址字节（7 位设备地址 + 1 位 R/W）
    // 3. 如果是写：接收数据字节，拼成 16 位 → ext_wdata
    // 4. 如果是读：发送 ext_rdata 到 SMBus 上
    // 5. 等待 ext_rdy，必要时插入 SMBus 时钟拉伸

    // ... SMBus 状态机实现 ...

endmodule
```

### 9.3 移植检查清单

```
□ 写新包装器：cib_top_<新协议>.v（约 50~200 行，取决于协议复杂度）
□ 确认 ext_* 时序是否匹配（尤其读是组合逻辑返回的）
□ 如果新协议时钟频率不同，确认是否需要时钟域同步
□ 检查 ext_cs_n 的极性（大部分协议是低有效）
□ 仿真验证：先跑一遍已有测试用例
□ 其他 cib_xxx 文件 → 无需修改
```

---

## 10. 附录：文件清单与数据流

### 10.1 文件清单

```
cib/                              ← CIB 架构根目录
│
├── cib_reg_defines.v             ← 中央地址映射（27 个区域的基地址/大小/AMSB）
│                                   - 改这个文件来分配新区域的地址
│
├── cib_reg_slice.v               ← 7 种寄存器原语
│                                   - 通常不需要改
│
├── cib_top.v                     ← 顶层模块
│                                   - 协议适配 + 区域译码 + 读数据汇合
│                                   - 移植新协议时不改这个文件
│
├── cib_ft/                       ← 工厂测试模块（示例，已实现）
│   ├── cib_ft.v                  ← 模块主体 + 寄存器译码 + 硬件接口
│   └── cib_ft_reg_def.v         ← 本模块的寄存器偏移定义
│
├── cib_base/                     ← 芯片基本信息模块（待实现）
│
├── cib_pwr/                      ← 电源管理模块（待实现）
│
└── cib_xxx/                      ← 其他 24 个区域文件夹（待实现）
    ├── cib_xxx.v
    └── cib_xxx_reg_def.v
```

### 10.2 一次完整读操作的数据流

```
CPU 读地址 0x1C03
        │
        ▼
[外部总线包装器] cib_top_espi.v
  将 eSPI 事务转成 ext_cs_n=0, ext_oe=1, ext_addr=0x1C03
        │
        ▼
[cib_top.v] 区域译码
  cs_n_ft = (addr[15:8] == CIB_FT_ADDR[15:8])? 0 : 1
  结果：cs_n_ft = 0（选中 FT 区域）
        │
        ▼
[cib_top.v] 读信号传递
  bus_read=1, addr=0x1C03 传给 cib_ft
        │
        ▼
[cib_ft.v] 寄存器译码
  offset = addr[7:0] = 0x03
  reg_freq_max_h = (offset == 0x03) = 1
        │
        ▼
[cib_ft.v] 读数据 mux
  选中 freq_max_h_rdata → rdata_ft
        │
        ▼
[cib_top.v] 数据汇合 mux
  cs_n_ft=0 → ext_rdata = rdata_ft
  ext_rdy=1 → 数据有效
        │
        ▼
CPU 读到 0x1C03 的内容
```

### 10.3 一次完整写操作的数据流

```
CPU 写地址 0x1C00，数据 0x0005
        │
        ▼
[外部总线包装器] → ext_cs_n=0, ext_we=1, addr=0x1C00, wdata=0x0005
        │
        ▼
[cib_top.v]
  • 区域译码：cs_n_ft=0
  • we 在时钟边沿寄存 → we_q=1
  • wdata 寄存 → wdata_q=0x0005
        │
        ▼
[cib_ft.v]
  • write_active = cs_active & we_q = 1
  • reg_fod_ctrl = (offset==0x00) = 1
  • u_fod_ctrl 的 load=1，wdata=0x0005
        │
        ▼
[时钟上升沿]
  fod_ctrl_rdata <= 0x0005
  → test_mode_o     = bit[0] = 1
  → test_loopback_o = bit[1] = 0
  → bist_start_o    = bit[2] = 1
        │
        ▼
写入完成，FPGA 进入测试模式，BIST 启动
```

---

> **最后的话**
>
> CIB 架构的设计哲学是"一次搭好，到处复用"。地址映射和寄存器逻辑分离、标准化的内部总线、基于 AMSB 的统一译码 —— 这些设计选择都是为了让你在加新功能时只需要关心"这个寄存器是 RW 还是 RO"，而不需要重新发明一套地址译码逻辑。
>
> 如果你读完这个文档还是觉得哪里不清楚，直接看代码 —— `cib_ft.v` 是最好的教材，它麻雀虽小五脏俱全，看懂它就看懂了整个架构。
