# 地址译码原理 —— 总线地址是怎么找到寄存器的？

> 你看到 `REG_BASE_AMSB` 不知道干啥用，很正常——它确实没被代码用到。下面把这个概念彻底讲清楚。

---

## 1. 问题：16 位地址 → 多个区域

地址总线是 16 位宽（0x0000 ~ 0xFFFF），表示 65536 个不同的地址。但我们不想把所有寄存器塞在一个大模块里，而是**按功能分成多个区域**：

```
地址空间         谁的地盘
0x0000 ~ 0x1FFF  reg_base     ← 版本/ID
0x2000 ~ 0x2FFF  reg_status   ← 状态监控
0x3000 ~ 0x3FFF  reg_iic      ← I2C
...等等
```

硬件收到一个地址（比如 0x2500）时，需要快速判断：**这属于哪个区域？**

## 2. 核心思路：用高位地址做"门牌号"

因为每个区域的大小是 **2 的整数次幂**（4K = 4096 = 2¹²），地址天然可以拆成两部分：

```
   15  14  13  12 │ 11  10   9   8   7   6   5   4   3   2   1   0
  ────────────────┼───────────────────────────────────────────────
   区域选择位      │     区域内偏移地址（哪条寄存器）
```

- **高位**（左边）→ 用于判断是哪个区域
- **低位**（右边）→ 用于在该区域内选中具体的寄存器

### 具体计算

`reg_base` 的大小是 8K（0x0000 ~ 0x1FFF）：
- 8K = 8192 = 2¹³ → 需要 **13 根地址线** 来寻址这 8K 个位置
- 所以低位使用 `addr[12:0]`（13 bit）
- 高位使用 `addr[15:13]`（3 bit）来区分区域

`reg_status` 的大小是 4K（0x2000 ~ 0x2FFF）：
- 4K = 4096 = 2¹² → 需要 **12 根地址线** 来寻址这 4K 个位置
- 所以低位使用 `addr[11:0]`（12 bit）
- 高位使用 `addr[15:12]`（4 bit）来区分区域

## 3. 图解：地址 0x2500 的旅程

```
CPU 发出地址：0x2500
二进制：        0010  0101 0000 0000
                │││└──────────────────
         判断区域用的高位          │
                              区域内偏移

第 1 步：看 addr[15:12] = 4'b0010
         查到 reg_status 的基地址就是 0x2000（二进制 0010_0000_...）
         → 匹配！选中 reg_status

第 2 步：把 addr[11:0] = 12'h500 传给 reg_status
         reg_status 内部看偏移 0x500 → 发现是"未定义地址" → 返回 0
```

## 4. 代码里怎么写的

在 `reg_top.v` 里的译码器：

```verilog
// 用 addr[15:12] 来判断是哪个 4K 区域
wire  reg_sel_base   = (bus_addr[15:13] == 3'b000);   // 8K 区域，用 3 bit
wire  reg_sel_status = (bus_addr[15:12] == 4'b0010);  // 4K 区域，用 4 bit
wire  reg_sel_iic    = (bus_addr[15:12] == 4'b0011);
wire  reg_sel_spi    = (bus_addr[15:12] == 4'b0100);
wire  reg_sel_ft     = (bus_addr[15:12] == 4'b0101);
wire  reg_sel_int    = (bus_addr[15:12] == 4'b0110);
```

- `bus_addr[15:13]` — 取高位 3 bit（`reg_base` 独占这 3 bit 的全部组合）
- `bus_addr[15:12]` — 取高位 4 bit（其他区域各占一种组合）

### 为什么 reg_base 用 3 bit，其他的用 4 bit？

因为 reg_base 的**大小不一样**：
- reg_base 占 8K 地址 → 需要 13 bit 的偏移 → 还剩 3 bit（16−13=3）用于区域选择
- 其他区域占 4K → 需要 12 bit 的偏移 → 还剩 4 bit（16−12=4）用于区域选择

## 5. AMSB 到底是什么？

**AMSB = Address Most Significant Bit**（地址的最高有效位）

```
`define REG_BASE_AMSB   13   表示 reg_base 的地址偏移使用 [12:0]
                              区域选择使用 [15:13]（最高位是 bit 13）
`define REG_STATUS_AMSB 12   表示 reg_status 的地址偏移使用 [11:0]
                              区域选择使用 [15:12]（最高位是 bit 12）
```

理解方式：从 bit `AMSB` 开始往上是区域选择位，往下是区域内偏移位。

```
  15  14  13  12  11  10  ...  0
  ───────────  ─────────────────
   区域选择      区域内偏移
   ↑              ↑
   AMSB 往上的位   AMSB-1 往下的位
```

### 为什么你在代码里看到它且正在被用？

AMSB 驱动 `reg_top.v` 的译码器：

```verilog
// reg_defines.v 中定义
`define REG_BASE_ADDR   16'h0000
`define REG_BASE_AMSB   13

// reg_top.v 中使用 —— AMSB 决定用哪几位地址做区域判断
wire [15:0] dec_base_addr = `REG_BASE_ADDR;

// 通用公式：地址的高位 == 基地址的高位？
wire reg_sel_base = (bus_addr[15:`REG_BASE_AMSB] == dec_base_addr[15:`REG_BASE_AMSB]);
//                  bus_addr[15:13]              16'h0000[15:13] = 3'b000
// 结果：基地址0x0000的高3位是000，bus_addr高3位也是000 → 匹配！选中 reg_base
```

改了 `REG_BASE_ADDR` 或 `REG_BASE_AMSB`，译码器**自动适配**，不需要碰 `reg_top.v` 的判断逻辑。

## 6. 如果我想加一个 4K 的新区域，怎么算？

假设要在 0x7000 ~ 0x7FFF 加 `reg_xxx`：

```
1. 区域大小 = 4K = 2¹² → 偏移用 12 bit → AMSB = 12
2. 0x7000 的二进制 = 0111_0000_0000_0000
   └─┬─┘
   addr[15:12] = 4'b0111
3. 在 reg_defines.v 里加定义：
   `define REG_XXX_ADDR   16'h7000
   `define REG_XXX_SIZE   16'h1000
   `define REG_XXX_AMSB   12
4. 在 reg_top.v 里加一行译码（AMSB 自动驱动）：
   wire [15:0] dec_xxx_addr = `REG_XXX_ADDR;
   wire reg_sel_xxx = (bus_addr[15:`REG_XXX_AMSB] == dec_xxx_addr[15:`REG_XXX_AMSB]);
   //                   bus_addr[15:12]                 16'h7000[15:12] = 4'b0111
```

这就是 AMSB 的好处：**改地址只需改 reg_defines.v 一处**，译码器里的公式是通用的。

## 总结

| 概念 | 含义 | 例子 |
|------|------|------|
| 高位地址 | 区域选择 | `addr[15:12]` |
| 低位地址 | 区域内偏移 | `addr[11:0]` |
| AMSB | 高位和低位的分界点 | `REG_STATUS_AMSB = 12` |
| 区域大小 | 决定了 AMSB 的值 | 4K→AMSB=12, 8K→AMSB=13 |

**所有 `_AMSB` 宏在代码里未被使用**，它们是设计阶段的"注释"而非功能代码。
