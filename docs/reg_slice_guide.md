# reg_slice.v 手把手教程 —— 寄存器原语从入门到精通

> 适用人群：会基本 Verilog 语法（module、always、assign），但不清楚"寄存器管理"怎么设计的开发者。
>
> 学习目标：彻底搞懂每个原语模块**为什么存在**、**怎么用**、**内部原理**。

---

## 目录

1. [前置知识：寄存器的三种角色](#1-前置知识寄存器的三种角色)
2. [reg_rw —— 读写寄存器](#2-reg_rw--读写寄存器)
3. [reg_ro —— 只读寄存器](#3-reg_ro--只读寄存器)
4. [reg_rw_wmask —— 带位掩码的读写寄存器](#4-reg_rw_wmask--带位掩码的读写寄存器)
5. [reg_w1c —— 写1清零寄存器](#5-reg_w1c--写1清零寄存器)
6. [reg_rc —— 读后自动清零寄存器](#6-reg_rc--读后自动清零寄存器)
7. [reg_rsvd —— 保留地址占位](#7-reg_rsvd--保留地址占位)
8. [reg_pulse —— 边沿转脉冲](#8-reg_pulse--边沿转脉冲)
9. [总结：什么时候用哪个](#9-总结什么时候用哪个)

---

## 1. 前置知识：寄存器的三种角色

在一个寄存器管理架构里，每个寄存器都同时连接**软件（CPU）**和**硬件（FPGA逻辑）**。但交互方向可以分三种：

```
        软件（CPU）             硬件（FPGA逻辑）
            │                        │
            │  ① 写配置值   ──────►  │  控制寄存器 (RW)
            │                        │
            │  ② 读取状态   ◄──────  │  状态寄存器 (RO)
            │                        │
            │  ③ 写"清0"    ──────►  │  事件寄存器 (W1C/RC)
            │     读取状态  ◄──────  │
            │                        │
```

| 角色 | 软件做什么 | 硬件做什么 | 典型用途 |
|------|-----------|-----------|---------|
| **控制** | 写入配置值 | 读取并使用该值 | 分频系数、使能开关、模式选择 |
| **状态** | 读取当前值 | 硬件驱动该值 | 温度读数、错误码、忙标志 |
| **事件** | 读取后清除（或写1清除） | 硬件置位标志位 | 中断状态、错误事件、完成标志 |

**reg_slice.v 里的每个模块对应一种交互模式。** 不需要在一个 always 块里同时处理"软件写"和"硬件置位"，每个原语只做一件事。

---

## 2. reg_rw —— 读写寄存器

### 2.1 为什么要它？

这是最简单的寄存器：**软件写入一个值，硬件读到这个值。** 用来配参数。

比如 I2C 的分频系数 `IIC_CLK_DIV`：
1. 软件计算出分频值，写入寄存器
2. I2C 硬件模块读取分频值，产生 SCL 时钟

### 2.2 端口图

```
         ┌─────────────┐
  clk ──►             │
 rst_n ─►             │
         │   reg_rw    │
  load ─►             ├──── rdata
 wdata ─►             │
         └─────────────┘
```

### 2.3 参数

| 参数 | 默认值 | 含义 |
|------|--------|------|
| `W` | 16 | 寄存器位宽 |
| `INIT` | 全0 | 复位后的初始值 |

### 2.4 内部原理

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rdata <= INIT;          // 复位 → 回到初始值
    else if (load)
        rdata <= wdata;         // load 有效 → 写入新值
    // 否则保持不动
end
```

- **`rst_n` 有效**：`rdata = INIT`（比如 16'h0000）
- **`load = 1`**：`rdata = wdata`（软件写进来了）
- **`load = 0`**：`rdata` 保持原值

### 2.5 使用实例

在 `reg_base.v` 里的 Scratch 寄存器：

```verilog
// ① 产生 load 信号——当地址匹配且是写操作时
assign scratch_we = write_active && (addr == `REG_BASE_SCRATCH);

// ② 实例化 reg_rw
reg_rw #(.W(16), .INIT(16'h0000)) u_scratch (
    .clk   (clk),
    .rst_n (rst_n),
    .load  (scratch_we),        // ← 只有这一条控制线
    .wdata (wdata),             // ← 总线写数据
    .rdata (scratch_rdata)      // ← 给 read mux 用
);
```

### 2.6 不用 slice 的手写版本（对比）

```verilog
// ❌ 每写一个寄存器都要重复这个 always
reg [15:0] scratch_val;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        scratch_val <= 16'h0000;
    else if (scratch_we)
        scratch_val <= wdata;
end

assign scratch_rdata = scratch_val;
```

6 行 vs 2 行。10 个寄存器就是 60 行 vs 20 行。

---

## 3. reg_ro —— 只读寄存器

### 3.1 为什么要它？

**硬件驱动一个值，软件被动读取。** 软件不能修改它。

比如芯片版本号、温度读数、当前状态标志。

### 3.2 端口图

```
         ┌─────────────┐
  din ──►   reg_ro     ├──── rdata
         └─────────────┘
```

**没有 clk，没有 rst_n。** 纯组合逻辑——`rdata` 和 `din` 永远是同一根线。

### 3.3 内部原理

```verilog
assign rdata = din;
```

一字不差，就是一条连线。

### 3.4 那为什么还要包一层 module？

- **语义清晰**：看到 `reg_ro` 就知道"这是个只读寄存器"
- **接口统一**：和 `reg_rw` 一样有 `rdata` 输出，read mux 里统一处理
- **方便改**：哪天想改成 flop 输出（加一拍延迟），不用改调用方

### 3.5 使用实例

```verilog
wire [15:0] version_val;
assign version_val = {ver_major, ver_minor};

// 实例化 RO（其实直接用 wire assign 也可以）
reg_ro #(.W(16)) u_version (
    .din   (version_val),
    .rdata (ver_rdata)
);
```

实际在代码里，`reg_base.v` 直接用了 wire assign（没实例化 reg_ro），因为版本号就 3 行，没必要。**这就是灵活性——slice 是元件库，你可以用也可以不用。**

---

## 4. reg_rw_wmask —— 带位掩码的读写寄存器

### 4.1 为什么要它？

普通 `reg_rw` 是**整字写入**——软件写 16'hA5A5，所有 16 位都变成 A5A5。

但有时候软件只应该改某些位。比如一个控制寄存器：

```
位 [15:8]  保留（软件不能写）
位 [7]     软复位
位 [6:1]   保留
位 [0]     使能
```

如果软件用 `reg_rw`，写 0x0001 会使能，但下次写 0x0081 想把复位拉高时，使能位被意外清掉了。

`reg_rw_wmask` 解决这个问题：**软件可以指定"这次只写 bit 0 和 bit 7，其他位不变"。**

### 4.2 端口图

```
         ┌────────────────┐
  clk ──►                │
 rst_n ─►                │
         │ reg_rw_wmask   │
  load ─►                ├──── rdata
 wdata ─►                │
 wmask ─►                │
         └────────────────┘
```

多了一个 `wmask` 端口：**`wmask[i] = 1` 表示这一位要更新，=0 表示保持原值。**

### 4.3 内部原理

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rdata <= INIT;
    else if (load)
        rdata <= (wdata & wmask) | (rdata & ~wmask);
end
```

核心一行：`(wdata & wmask) | (rdata & ~wmask)`

- `wdata & wmask` ：取出 wdata 中 wmask=1 的位
- `rdata & ~wmask` ：保留 rdata 中 wmask=0 的位
- 两者 OR 起来 → 部分更新

### 4.4 使用实例

```verilog
// 软件只允许改 bit[0]（使能）和 bit[7]（复位）
assign wmask_val = 16'h0081;

reg_rw_wmask #(.W(16), .INIT(16'h0000)) u_ctrl (
    .clk  (clk),
    .rst_n(rst_n),
    .load (ctrl_we),
    .wdata(wdata),
    .wmask(wmask_val),
    .rdata(ctrl_rdata)
);
```

### 4.5 什么时候用？

| 场景 | 用 reg_rw | 用 reg_rw_wmask |
|------|-----------|----------------|
| 整个寄存器只控制一件事 | ✓ | - |
| 寄存器里多个字段，软件每次都知道完整值 | ✓ | - |
| 寄存器里混了保留位/只读位 | - | ✓ |
| 多个软件模块写同一寄存器不同位 | - | ✓ |

---

## 5. reg_w1c —— 写1清零寄存器

### 5.1 为什么要它？

这是嵌入式中最常用的寄存器类型之一。

场景：硬件检测到一个事件（比如 DMA 传输完成），把某个标志位置 1。软件读到后，**写 1 来清除这个标志**。

为什么不用普通 RW？
- 如果软件写 0 来清除：硬件又在同一周期置位了怎么办？冲突。
- W1C 保证：**软件写 0 不影响当前值**，只有写 1 才清除。硬件置位优先级 > 软件清除。

### 5.2 端口图

```
         ┌─────────────┐
  clk ──►             │
 rst_n ─►             │
         │  reg_w1c    │
  load ─►             ├──── rdata
 wdata ─►             │
   set ─►             │
         └─────────────┘
```

新端口 `set`：**硬件置位信号**——`set[i]=1` 时，对应位变成 1（不管之前是什么值）。

### 5.3 内部原理

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rdata <= INIT;
    else begin
        rdata <= rdata | set;              // ① 硬件置位（优先级最高）
        if (load)
            rdata <= (rdata | set) & ~wdata;  // ② 软件写1清零
    end
end
```

**优先级**：硬件置位 > 软件写1 > 保持

- **① 硬件置位**：`rdata | set` — set 的每一位强制变成 1
- **② 软件清除**：如果 `load=1`，`(rdata | set) & ~wdata` — wdata 里为 1 的位被清成 0

关键设计：**如果在同一周期硬件 set=1 且软件 wdata=1（要清除这一位），①先置位→②再清除，结果是 0。** 软件清除胜出，但硬件也不会丢失事件（因为事件通常保持多周期）。

### 5.4 使用实例

在 `reg_int.v` 里的中断 pending 寄存器：

```verilog
reg_w1c #(.W(16), .INIT(16'h0000)) u_pending (
    .clk  (clk),
    .rst_n(rst_n),
    .load (pending_we),        // 写 INT_CLEAR 时有效
    .wdata(wdata),             // 写 1 的位被清除
    .set  (raw_int),           // 硬件中断源置位
    .rdata(pending_rdata)
);
```

### 5.5 不用 slice 的"容易错"版本

```verilog
// ❌ 错误：忘记了 set 的优先级
always @(posedge clk)
    if (load & wdata[0]) pending[0] <= 1'b0;
    else if (set[0])      pending[0] <= 1'b1;

// 同一周期 set 和 clear 同时来 → 因为 else if 优先级，clear 被 set 覆盖了！
// 但实际上应该清除
```

```verilog
// ❌ 错误：写 0 也把位改了
always @(posedge clk)
    if (load) pending <= pending & ~wdata;  // wdata=0 会清掉所有位！

// W1C 的约定是只有写 1 才清除，写 0 不影响
```

**用 slice 就不会犯这些错。**

---

## 6. reg_rc —— 读后自动清零寄存器

### 6.1 为什么要它？

W1C 需要软件"先读状态，再写 1 清除"，需要两步。`reg_rc` 更激进：**软件读一次，读完自动清除**。

适用场景：一些不太关键的状态信息，比如"发生了多少次错误"。软件每隔一段时间读一次，读到的就是"从上一次读到现在发生的次数"，不需要额外写清除。

### 6.2 端口图

```
         ┌──────────────┐
  clk ──►              │
 rst_n ─►              │
         │   reg_rc     │
   set ─►              ├──── rdata
  read_ ─►             │
  strobe               │
         └──────────────┘
```

- `set`：硬件置位（同 W1C）
- `read_strobe`：读脉冲（1 周期高电平）——告诉寄存器"软件正在读你，读完清空"

### 6.3 内部原理

```verilog
reg [W-1:0] val;        // 内部存储

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        val   <= INIT;
        rdata <= INIT;
    end else begin
        val <= val | set;              // 硬件事件累加
        rdata <= val;                  // 寄存器输出 = val（上一个周期的）
        if (read_strobe)
            val <= {W{1'b0}};          // 读完立即清零
    end
end
```

注意：**`rdata` 输出的是读之前的 `val`**，然后 `val` 才清零。所以软件读到的是"清零之前的值"。

### 6.4 使用实例

```verilog
// 错误计数：硬件每检测到一个错误，set[0] 拉高 1 周期
// 软件每隔 1 秒读一次，读完后自动归零
reg_rc #(.W(16), .INIT(16'h0000)) u_err_cnt (
    .clk  (clk),
    .rst_n(rst_n),
    .set  (error_event),
    .read_strobe(read_active && (addr == REG_ERR_CNT)),
    .rdata(err_cnt_rdata)
);
```

### 6.5 reg_w1c vs reg_rc 选哪个？

| | reg_w1c | reg_rc |
|--|---------|--------|
| 清除方式 | 软件写 1 到特定位 | 软件读，读后自动清除 |
| 软件步骤 | 读状态 → 写 1 清除 | 读状态（一次完成） |
| 控制粒度 | 可逐位清除 | 整字清除（读整个寄存器） |
| 适合场景 | 中断状态（需要精确控制清除哪个源） | 计数器、统计信息（不关键的状态） |

---

## 7. reg_rsvd —— 保留地址占位

### 7.1 为什么要它？

地址空间里有些区域是"保留"的——现在没用，但将来可能会用。如果不处理，这些地址读出来可能是 X（不确定值），或者综合时会优化掉。`reg_rsvd` 明确告诉工具：**这个地址读 0，写忽略**。

### 7.2 内部原理

```verilog
assign rdata = {W{1'b0}};
```

就是这么简单。纯组合逻辑，读永远返回 0。

### 7.3 使用实例 —— 在 reg_base.v 中填充地址空洞

`reg_base` 区域的地址 `0x0008~0x000F` 是未使用的空洞（介于 GIT_SHA2 和 SCRATCH 之间），用 `reg_rsvd` 占位：

```verilog
// reg_base.v 中实例化（不给端口连线，rdata 固定 0）
reg_rsvd #(.W(16)) u_rsvd_0008 ();
```

这行代码的作用：
- 综合时告诉工具：这个地址是**故意**不用的，不是忘了写
- 读 `0x0008` 返回确定值 `0x0000`，而不是 X（未知态）
- 将来想在这个地址加真正的寄存器时，把 `reg_rsvd` 替换成 `reg_rw` 即可

### 7.4 在 read mux 里的作用

read mux 的 case 语句不需要为 rsvd 加专门项——default 已经返回 0。rsvd 实例只是"文档化的占位符"，不是功能必须的。

---

## 8. reg_pulse —— 边沿转脉冲

### 8.1 为什么要它？

很多硬件控制信号是**脉冲**（高电平只持续 1 个时钟周期），但来自软件的写信号是**电平**（可能持续多个周期）。`reg_pulse` 把一个电平变化转成一个周期的脉冲。

典型场景：软件写 SPI_CMD 寄存器来触发一次 SPI 传输。软件写 1 到 cmd 位，硬件只应该看到 1 周期的高电平，然后自动拉低。如果用普通寄存器，软件写 1 后，硬件一直看到 1。

### 8.2 端口图

```
         ┌──────────────┐
  clk ──►              │
 rst_n ─►  reg_pulse   │
         │              │
  din ──►              ├──── dout
         └──────────────┘
```

- `din`：输入信号（电平变化）
- `dout`：输出脉冲（只在 `din` 从 0→1 的下一周期输出 1 周期高电平）

### 8.3 内部原理

```verilog
reg [W-1:0] din_d;     // 延迟一拍

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        din_d <= {W{1'b0}};
    else
        din_d <= din;
end

assign dout = din & ~din_d;  // 上升沿检测
```

原理：`din_d` 是 `din` 延迟 1 周期的值。`din & ~din_d` 在 `din` 从 0 变 1 的那一周期为高，之后为低。

### 8.4 使用实例

在 `reg_spi.v` 里：

```verilog
// 软件写 SPI_CMD 寄存器 → 产生 1 周期脉冲 → 触发 SPI 传输
wire start_pulse;

reg_pulse #(.W(1)) u_start_pulse (
    .clk  (clk),
    .rst_n(rst_n),
    .din  (cmd_we && wdata[0]),   // 写 CMD 且 bit0=1
    .dout (spi_start_o)           // 输出 1 周期脉冲
);
```

### 8.5 不用 pulse 的替代做法

```verilog
// ❌ 毛刺风险：组合逻辑直接输出
assign spi_start = cmd_we && wdata[0];  // 如果 cmd_we 或 wdata 中间变化，会有毛刺

// ✅ 用 pulse：寄存输出，干净
```

---

## 9. 总结：什么时候用哪个

### 速查表

| 你的场景 | 用哪个原语 | 原因 |
|---------|-----------|------|
| 软件写一个配置值，硬件使用 | `reg_rw` | 最简单，整字读写 |
| 软件只能改寄存器的某些位 | `reg_rw_wmask` | 带位掩码，不改的位不动 |
| 硬件驱动一个值，软件只能读 | `reg_ro` 或直接 wire | 纯组合逻辑直通 |
| 硬件置位事件，软件写1清除 | `reg_w1c` | 硬件 set 优先级高于 clear |
| 硬件累加计数，软件读后自动清 | `reg_rc` | 读操作本身隐式清零 |
| 地址空洞，读0写忽略 | `reg_rsvd` | 明确占位，防 X 态 |
| 电平→脉冲转换 | `reg_pulse` | 边沿检测，输出 1 周期脉冲 |

### 代码量对比（10 个 RW 寄存器）

| 方式 | 代码行数 | 一致性 | 改复位方式的工作量 |
|------|---------|--------|-------------------|
| 手写 always | ~70 行 | ❌ 每个人风格不同 | 改 10 个 always 块 |
| 用 `reg_rw` 实例化 | ~25 行 | ✅ 全部一致 | 改 reg_slice.v 一处 |

### 架构图总览

```
                    reg_slice.v 元件库
                    ┌────────────────────┐
                    │  reg_rw            │  ← 读写
                    │  reg_rw_wmask      │  ← 带掩码读写
        实例化       │  reg_ro            │  ← 只读
    ───────────────► │  reg_w1c           │  ← 写1清零
                     │  reg_rc            │  ← 读后自动清
                     │  reg_rsvd          │  ← 保留占位
                     │  reg_pulse         │  ← 边沿→脉冲
                     └────────────────────┘
                              │
                              ▼
                    ┌────────────────────────────────────┐
                    │  reg_base.v      reg_rw  (scratch) │
                    │                   reg_rw_wmask(ctrl)│
                    │                   reg_ro  (features)│
                    │                   reg_rsvd(reserved)│
                    ├────────────────────────────────────┤
                    │  reg_status.v    reg_rc  (err_sticky)│
                    ├────────────────────────────────────┤
                    │  reg_int.v       reg_rw ×3         │
                    │                   reg_w1c (pending) │
                    ├────────────────────────────────────┤
                    │  reg_spi.v       reg_pulse(start)   │
                    ├────────────────────────────────────┤
                    │  reg_iic.v / reg_ft.v  (模板)       │
                    └────────────────────────────────────┘
```

---

### 动手练习

如果你想亲自试试：

1. **在 reg_base.v 添加一个新的 RW 寄存器**（地址 0x0031）：
   ```verilog
   // ① 先在 reg_defines.v 中定义
   `define REG_BASE_MY_REG  16'h0031

   // ② 在 reg_base.v 中实例化
   reg_rw #(.W(8), .INIT(8'h42)) u_my_reg (
       .clk(clk), .rst_n(rst_n),
       .load(write_active && (addr == `REG_BASE_MY_REG)),
       .wdata(wdata[7:0]),
       .rdata(my_reg_rdata)
   );
   ```
   然后在 read mux 里加一行 `REG_BASE_MY_REG : rdata_mux = my_reg_rdata;`

2. **把 reg_status.v 的 error_clear 换成 reg_w1c**：
   当前 reg_status.v 里手写了一个 error clear 逻辑。试试用 `reg_w1c` 替代。
