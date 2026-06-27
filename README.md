# reg — FPGA 寄存器管理架构（纯 Verilog）

> 你不懂寄存器 map 怎么设计？这个项目就是给你看的。
> 用乐高积木的方式搭寄存器，每种"访问行为"封装成一块积木。

---

## 这个项目是干什么的？

FPGA 芯片内部有很多**寄存器**——每个寄存器就是一个 16 位的存储单元，CPU 可以读写它们来控制硬件、读取状态。

这 65536 个寄存器按功能分成不同区域：

```
地址范围          区域名       大小    用途
──────────────────────────────────────────────
0x0000 ~ 0x1FFF  reg_base     8K     版本信息、芯片ID、Scratch
0x2000 ~ 0x2FFF  reg_status   4K     FPGA 运行状态、温度、错误计数
0x3000 ~ 0x3FFF  reg_iic      4K     I2C 控制器
0x4000 ~ 0x4FFF  reg_spi      4K     SPI 控制器
0x5000 ~ 0x5FFF  reg_ft       4K     工厂测试
0x6000 ~ 0x6FFF  reg_int      4K     中断控制器
0x7000 ~ 0xFFFF  (保留)       36K    给你扩展用
```

**这个项目把"寄存器管理"这件事做成了标准化的架构**，你拿来就能用，想加寄存器就加。

---

## 你只需要懂这 3 个概念

### ① 地址译码 —— 怎么找到对应的寄存器

16 位地址（0x0000 ~ 0xFFFF）分成两部分：

```
地址 0x2500 的二进制：0010  0101 0000 0000
                      │    └──────┬──────┘
                      │            └─ 区域内偏移（哪条寄存器）
                      └─ 区域选择（哪个模块）
```

每个区域在 `reg_defines.v` 里用 **AMSB** 定义分界线：

```verilog
`define REG_BASE_ADDR   16'h0000     // 基地址
`define REG_BASE_SIZE   16'h2000     // 大小 = 8K
`define REG_BASE_AMSB   13           // 分界线：bit[15:13] 选区域
                                     //         bit[12:0]  区域内偏移
```

`reg_top.v` 里的译码器自动用 AMSB 做判断：

```verilog
// 通用公式：地址的高位 == 基地址的高位？
wire reg_sel_base = (bus_addr[15:`REG_BASE_AMSB] == 基地址[15:`REG_BASE_AMSB]);
// 实际展开：bus_addr[15:13] == 16'h0000[15:13] → bus_addr[15:13] == 3'b000
```

> 详细图解 → [docs/addressing_explained.md](docs/addressing_explained.md)

### ② 寄存器原语 —— 7 种"积木"

每种寄存器访问行为封装成一个模块，放在 `reg_slice.v` 里：

| 积木 | 干什么用 | 真实代码在哪用 |
|------|---------|--------------|
| **reg_rw** | 软件读写，硬件读（配参数用） | `reg_base.v` scratch、`reg_int.v` enable/mask/edge |
| **reg_rw_wmask** | 带掩码的读写（只改某些位） | `reg_base.v` ctrl 寄存器 |
| **reg_ro** | 硬件驱动，软件只读（状态用） | `reg_base.v` features 寄存器 |
| **reg_w1c** | 硬件置位，软件写 1 清零（中断用） | `reg_int.v` pending 寄存器 |
| **reg_rc** | 硬件置位，软件读后自动清零 | `reg_status.v` 错误粘滞位 |
| **reg_rsvd** | 保留地址，读 0 忽略写 | `reg_base.v` 地址空洞 |
| **reg_pulse** | 电平转 1 周期脉冲 | `reg_spi.v` 启动脉冲 |

> 手把手教程 → [docs/reg_slice_guide.md](docs/reg_slice_guide.md)

### ③ 总线协议 —— CPU 怎么和寄存器说话

| 操作 | 一句话 |
|------|--------|
| **读** | 给地址 → 同一周期数据就出来（组合逻辑读） |
| **写** | 给地址+数据 → 下一个时钟沿写入（寄存写） |
| **错误** | 给了不存在的地址 → `bus_err=1` |

---

## 文件结构和零基础路线图

```
reg/
├── rtl/                    ← RTL 源码（你最终综合到 FPGA 里的）
│   ├── reg_defines.v       ← 地址映射定义（改这个文件分配地址）
│   ├── reg_slice.v         ← 7 种寄存器原语（不用改）
│   ├── reg_top.v           ← 顶层：译码器 + 数据选择器（基本不用改）
│   ├── reg_base.v          ← 区域：版本信息（含 rw/ro/wmask/rsvd 示例）
│   ├── reg_status.v        ← 区域：状态监控（含 rc 示例）
│   ├── reg_int.v           ← 区域：中断控制器（含 rw/w1c 示例）
│   ├── reg_iic.v           ← 区域：I2C 模板（给你填空的）
│   ├── reg_spi.v           ← 区域：SPI 模板（含 pulse 示例）
│   └── reg_ft.v            ← 区域：工厂测试模板
├── tb/
│   └── tb_reg_top.v        ← 测试文件（31 个测试点）
├── sim/
│   ├── reg_top.f           ← 文件清单
│   └── run_sim.tcl         ← ModelSim 运行脚本
└── docs/
    ├── reg_slice_guide.md  ← 寄存器原语手把手教程 ← **从这里开始**
    └── addressing_explained.md ← 地址译码原理
```

**学习路线**：
1. 先读 `docs/reg_slice_guide.md` → 搞懂 7 种积木
2. 再读 `docs/addressing_explained.md` → 搞懂地址怎么分区
3. 打开 `sim/` 跑仿真 → 看 31 个测试怎么通过
4. 改 `reg_base.v` 加个自己的寄存器 → 动手试

---

## 怎么跑仿真

### 方法 1：ModelSim / Questa（推荐）

```bash
cd sim
vsim -do run_sim.tcl
```

### 方法 2：命令行编译检查

```bash
vlog -sv -f sim/reg_top.f
```

### 你会看到

```
# ALL TESTS PASSED
#   ✓ 复位初值
#   ✓ Scratch 读写
#   ✓ 状态标志
#   ✓ 写1清零脉冲
#   ✓ 中断流程（enable → fire → status → clear）
#   ✓ 中断优先级
#   ✓ reg_rw_wmask 带掩码读写
#   ✓ reg_ro 只读
#   ✓ reg_rsvd 保留地址
#   ✓ reg_rc 读后自动清零
#   ✓ I2C/SPI/FT 模板
#   ✓ 地址错误检测
```

---

## 如何扩展

### 加一个寄存器到已有区域（比如 reg_base）

改 2 处，共 4 行：

```verilog
// ① reg_defines.v —— 定地址
`define REG_BASE_MY_REG  16'h0031

// ② reg_base.v —— 实例化 + 加 read mux 项
reg_rw #(.W(16), .INIT(16'h0000)) u_my_reg (
    .clk(clk), .rst_n(rst_n),
    .load(write_active && (addr == `REG_BASE_MY_REG)),
    .wdata(wdata), .rdata(my_reg_rdata)
);
// 在 read mux 的 case 里加一行：
// `REG_BASE_MY_REG : rdata_mux = my_reg_rdata;
```

### 加一个全新区域

改 4 处：

| # | 文件 | 加什么 |
|---|------|--------|
| 1 | `reg_defines.v` | `REG_XXX_ADDR`、`REG_XXX_SIZE`、`REG_XXX_AMSB` |
| 2 | `rtl/reg_xxx.v` | 新建模块，用标准 `cs/we/addr/wdata/rdata/rdy` 端口 |
| 3 | `reg_top.v` | 加译码线 + 实例化 + rdata mux 项 |
| 4 | `sim/reg_top.f` | 加文件路径 |

---

## 设计原则（小白版）

1. **纯 Verilog** — 不用 SystemVerilog，所有综合器都支持
2. **一个时钟** — 所有寄存器同一个 `clk`、同一个 `rst_n`，不搞复杂
3. **配置 ≠ 逻辑** — 地址映射在 `reg_defines.v`，RTL 逻辑在各自模块，改地址不改代码
4. **防备所有可能** — 每个 case 都有 default，不存在的地址读 0 返回 `bus_err`
