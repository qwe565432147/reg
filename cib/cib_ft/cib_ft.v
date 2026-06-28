// ============================================================================
// cib_ft.v — 工厂测试寄存器模块
//
// 地址区域 : 0x1C00 – 0x1CFF  (512 字, AMSB = 8)
//
// 本模块是所有 cib_xxx 寄存器模块的模板：
//   1. 包含全局 + 局部地址定义文件
//   2. 声明标准局部总线从接口
//   3. 根据区域内偏移译码寄存器
//   4. 例化 reg_slice 原语（每个寄存器一个）
//   5. 从寄存器值驱动硬件接口信号
//   6. 多路选择读数据
//
// 寄存器映射（相对于 CIB_FT_ADDR = 0x1C00）：
//   偏移  名称                        类型  说明
//   ──────────────────────────────────────────────────────────────
//   0x00   REG_CLK_MODULE_FOD_CTRL     RW   时钟频偏检测控制
//   0x01   REG_CLK_MODULE_FREQ_ACT_H   RO   频率实际值高16位
//   0x02   REG_CLK_MODULE_FREQ_ACT_L   RW   频率实际值低16位
//   0x03   REG_CLK_MODULE_FREQ_MAX_H   RO   频率最大值高16位
//   0x04   REG_CLK_MODULE_FREQ_MAX_L   RW   频率最大值低16位
//   0x05   REG_CLK_MODULE_FREQ_MIN_H   RO   频率最小值高16位
//   0x06   REG_CLK_MODULE_FREQ_MIN_L   RW   频率最小值低16位
//   0x07   （保留）
//   0x08   REG_LGC_RSRC_CHK_RESULT     RO   资源自检结果
//
//   注意：REG_CLK_MODULE_* 命名来自原始的时钟模块测试寄存器。
//   新增 FT 专用寄存器应使用 REG_FT_* 前缀。
// ============================================================================

`include "cib_reg_defines.v"
`include "cib_ft_reg_def.v"

module cib_ft (
    // ---- 时钟 / 复位 -------------------------------------------------------
    input                     clk,
    input                     rst_n,

    // ---- 局部总线从接口（所有 cib_xxx 统一）---------------------------------
    // 这是本模块看到的唯一接口 — cib_top 负责外部协议转换和区域片选译码。
    input                     cs_n,           // 片选（低电平有效）
    input                     oe,             // 输出使能（读选通）
    input                     we,             // 写使能（单周期脉冲）
    input      [15:0]         addr,           // 完整 16 位地址
    input      [15:0]         wdata,          // 写数据
    output reg [15:0]         rdata,          // 读数据
    output                    rdy,            // 就绪（1 = 单周期）

    // ---- 测试硬件接口 ------------------------------------------------------
    // 这些信号连接到 FPGA 中的实际测试链 / BIST 逻辑。
    output                    test_mode_o,    // 进入测试模式
    output                    test_loopback_o,// 使能数据环回
    output                    bist_start_o,   // 启动内置自测试
    input                     bist_busy_i,    // BIST 进行中
    input                     bist_pass_i,    // BIST 通过
    input                     bist_fail_i,    // BIST 失败
    output     [15:0]         test_data_in_o, // 测试激励数据
    input      [15:0]         test_data_out_i,// 测试捕获数据
    output     [15:0]         loop_count_o    // 环回迭代计数
);

    // =========================================================================
    // 事务限定信号
    // =========================================================================
    wire cs_active   = ~cs_n;              // 片选有效
    wire read_active = cs_active & oe;     // 读是组合逻辑
    wire write_active= cs_active & we;     // 写是单周期脉冲

    // 区域内地址偏移：CIB_FT_AMSB = 8 → addr[7:0]
    wire [7:0] offset = addr[`CIB_FT_AMSB-1:0];

    // =========================================================================
    // 各寄存器选择线
    // =========================================================================
    // 每个寄存器有自己的选择线（后面再与 write_active/read_active 相与）。
    // `REG_*` 值在 cib_ft_reg_def.v 中定义为全 16 位绝对地址 —
    // 因为 cs_n 已限定区域，我们只比较低位。
    wire reg_fod_ctrl     = cs_active & (offset == `REG_CLK_MODULE_FOD_CTRL[`CIB_FT_AMSB-1:0]);
    wire reg_freq_act_h   = cs_active & (offset == `REG_CLK_MODULE_FREQ_ACT_H[`CIB_FT_AMSB-1:0]);
    wire reg_freq_act_l   = cs_active & (offset == `REG_CLK_MODULE_FREQ_ACT_L[`CIB_FT_AMSB-1:0]);
    wire reg_freq_max_h   = cs_active & (offset == `REG_CLK_MODULE_FREQ_MAX_H[`CIB_FT_AMSB-1:0]);
    wire reg_freq_max_l   = cs_active & (offset == `REG_CLK_MODULE_FREQ_MAX_L[`CIB_FT_AMSB-1:0]);
    wire reg_freq_min_h   = cs_active & (offset == `REG_CLK_MODULE_FREQ_MIN_H[`CIB_FT_AMSB-1:0]);
    wire reg_freq_min_l   = cs_active & (offset == `REG_CLK_MODULE_FREQ_MIN_L[`CIB_FT_AMSB-1:0]);
    wire reg_rsrc_chk     = cs_active & (offset == `REG_LGC_RSRC_CHK_RESULT[`CIB_FT_AMSB-1:0]);

    // =========================================================================
    // 寄存器例化
    //
    // 每个寄存器使用一个 reg_slice 原语（来自 cib_reg_slice.v）。
    // 选择与访问行为匹配的原语：
    //   reg_rw         – 读写              （如控制寄存器）
    //   reg_ro         – 只读              （如状态/捕获）
    //   reg_w1c        – 写1清零           （如中断/粘滞位）
    //   reg_rc         – 读后自动清零       （如一次性状态）
    //   reg_rw_wmask   – 带掩码读写         （如共享控制）
    //   reg_rsvd       – 保留地址空洞       （读0，忽略写）
    // =========================================================================

    // ---- REG_CLK_MODULE_FOD_CTRL (0x00, RW) --------------------------------
    // 时钟频偏检测控制寄存器。
    //   bit[0]   – test_mode    （进入工厂测试模式）
    //   bit[1]   – test_loopback（使能数据环回路径）
    //   bit[2]   – bist_start   （脉冲启动 BIST）
    //   bit[15:3] – 保留
    wire [15:0] fod_ctrl_rdata;
    reg_rw #(
        .W    (16),
        .INIT (16'h0000)
    ) u_fod_ctrl (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (write_active & reg_fod_ctrl),
        .wdata (wdata),
        .rdata (fod_ctrl_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_ACT_H (0x01, RO) ------------------------------
    // 频率实际值，高 16 位。
    // 由硬件驱动（本模板中使用 test_data_out_i）。
    wire [15:0] freq_act_h_rdata;
    reg_ro #(
        .W (16)
    ) u_freq_act_h (
        .din   (test_data_out_i),
        .rdata (freq_act_h_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_ACT_L (0x02, RW) ------------------------------
    // 频率实际值，低 16 位。
    // 软件可写入用于测试注入；同时驱动 test_data_in_o。
    wire [15:0] freq_act_l_rdata;
    reg_rw #(
        .W    (16),
        .INIT (16'h0000)
    ) u_freq_act_l (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (write_active & reg_freq_act_l),
        .wdata (wdata),
        .rdata (freq_act_l_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_MAX_H (0x03, RO) ------------------------------
    // 最大记录频率，高 16 位（硬件捕获）。
    wire [15:0] freq_max_h_rdata;
    reg_ro #(
        .W (16)
    ) u_freq_max_h (
        .din   (test_data_out_i),
        .rdata (freq_max_h_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_MAX_L (0x04, RW) ------------------------------
    // 最大记录频率，低 16 位。
    wire [15:0] freq_max_l_rdata;
    reg_rw #(
        .W    (16),
        .INIT (16'h0000)
    ) u_freq_max_l (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (write_active & reg_freq_max_l),
        .wdata (wdata),
        .rdata (freq_max_l_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_MIN_H (0x05, RO) ------------------------------
    // 最小记录频率，高 16 位（硬件捕获）。
    wire [15:0] freq_min_h_rdata;
    reg_ro #(
        .W (16)
    ) u_freq_min_h (
        .din   (test_data_out_i),
        .rdata (freq_min_h_rdata)
    );

    // ---- REG_CLK_MODULE_FREQ_MIN_L (0x06, RW) ------------------------------
    // 最小记录频率，低 16 位。
    // 同时驱动 loop_count_o 用于环回测试。
    wire [15:0] freq_min_l_rdata;
    reg_rw #(
        .W    (16),
        .INIT (16'h0000)
    ) u_freq_min_l (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (write_active & reg_freq_min_l),
        .wdata (wdata),
        .rdata (freq_min_l_rdata)
    );

    // ---- 偏移 0x07：保留空洞（示例）----------------------------------------
    // 未使用的地址 — reg_rsvd 读 0，忽略写。
    // 保留这个占位符演示如何填充空洞。
    wire [15:0] rsvd_07_rdata;
    reg_rsvd #(
        .W (16)
    ) u_rsvd_07 (
        .rdata (rsvd_07_rdata)
    );

    // ---- REG_LGC_RSRC_CHK_RESULT (0x08, RO) -------------------------------
    // 资源自检结果寄存器。
    //   bit[0]   – bist_pass_i   （1 = 测试通过）
    //   bit[1]   – bist_fail_i   （1 = 测试失败）
    //   bit[2]   – bist_busy_i   （1 = 测试进行中）
    //   bit[15:3] – 保留
    wire [15:0] rsrc_chk_rdata;
    reg_ro #(
        .W (16)
    ) u_rsrc_chk (
        .din   ({13'h0000, bist_busy_i, bist_fail_i, bist_pass_i}),
        .rdata (rsrc_chk_rdata)
    );

    // =========================================================================
    // 读数据多路选择器
    //
    // 组合逻辑 mux：read_active 有效时，将选中寄存器的 rdata 路由到输出。
    // 默认（空洞或空闲）→ 0。
    // =========================================================================
    always @(*) begin
        rdata = 16'h0000;       // 安全默认值
        if (read_active) begin
            case (1'b1)
                reg_fod_ctrl:   rdata = fod_ctrl_rdata;
                reg_freq_act_h: rdata = freq_act_h_rdata;
                reg_freq_act_l: rdata = freq_act_l_rdata;
                reg_freq_max_h: rdata = freq_max_h_rdata;
                reg_freq_max_l: rdata = freq_max_l_rdata;
                reg_freq_min_h: rdata = freq_min_h_rdata;
                reg_freq_min_l: rdata = freq_min_l_rdata;
                reg_rsrc_chk:   rdata = rsrc_chk_rdata;
                // 偏移 0x07（保留）由 default 分支覆盖 → 0
                default:        rdata = 16'h0000;
            endcase
        end
    end

    // =========================================================================
    // 就绪信号 — 本模块所有寄存器均为单周期
    // =========================================================================
    // 接 1：组合逻辑读 + 寄存写（1 周期）。
    // 如果本模块将来包含多周期 IP（如 FIFO 或需要等待状态的 I2C 控制器），
    // 请替换为合适的 rdy 生成逻辑。
    assign rdy = cs_active;     // 选中时即就绪（单周期）

    // =========================================================================
    // 硬件接口输出
    // =========================================================================
    assign test_mode_o     = fod_ctrl_rdata[0];
    assign test_loopback_o = fod_ctrl_rdata[1];
    assign bist_start_o    = fod_ctrl_rdata[2];
    assign test_data_in_o  = freq_act_l_rdata;
    assign loop_count_o    = freq_min_l_rdata;

endmodule
