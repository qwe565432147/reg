// ============================================================================
// cib_reg_slice.v — 寄存器原语单元
//
// 目的：
//   可复用的 1/多 bit 寄存器单元，封装了所有常见的读写访问行为。
//   统一使用这些原语，确保设计中所有寄存器遵循相同的复位、时钟和访问语义。
//
// 原语类型
//   reg_rw    —  读写寄存器              (软件读写，硬件读)
//   reg_ro    —  只读寄存器              (硬件驱动，软件读取)
//   reg_w1c   —  写1清零寄存器           (硬件置位，软件清零)
//   reg_rc    —  读后自动清零 (粘滞)     (首次读返回值后清零)
//   reg_rsvd  —  保留地址空洞            (读0，忽略写)
//
// 约定
//   所有原语使用异步低电平复位 (negedge rst_n)。
//   所有原语带有参数化宽度 W 和复位初值 INIT。
//   "load/wen" 使能预期为单周期脉冲。
// ============================================================================

`include "cib_reg_defines.v"

// ============================================================================
// reg_rw — 读写寄存器
//   load   : 写使能（单周期脉冲）
//   wdata  : 写数据
//   rdata  : 读数据（= 当前寄存器值）
//   如需软硬件分控，使用 wmask 变体。
// ============================================================================
module reg_rw #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    output reg [W-1:0]         rdata
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else if (load)
            rdata <= wdata;
    end

endmodule


// ============================================================================
// reg_rw_wmask — 带掩码的读写寄存器
//   load   : 写使能
//   wdata  : 写数据
//   wmask  : 逐位写掩码（1 = 写入该位）
//   rdata  : 读数据
//   适用于 SW 只想修改某些位的场景。
// ============================================================================
module reg_rw_wmask #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    input      [W-1:0]         wmask,
    output reg [W-1:0]         rdata
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else if (load)
            rdata <= (wdata & wmask) | (rdata & ~wmask);
    end

endmodule


// ============================================================================
// reg_ro — 只读寄存器
//   din    : 硬件驱动的值
//   rdata  : 读数据（= din 组合逻辑直通）
//   无时钟、无复位 — 纯组合逻辑。
// ============================================================================
module reg_ro #(
    parameter W = 16
) (
    input      [W-1:0]         din,
    output     [W-1:0]         rdata
);

    assign rdata = din;

endmodule


// ============================================================================
// reg_w1c — 写1清零寄存器
//   set    : 硬件置位（边沿/事件）
//   load   : 软件写选通
//   wdata  : 写数据（为1的位被清零）
//   rdata  : 读数据（= 置位与清零后的当前值）
//
//   优先级（高→低）：set > w1c > 保持
//   同一周期内同时 set 和写1的位保持置位。
// ============================================================================
module reg_w1c #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    input      [W-1:0]         set,
    output reg [W-1:0]         rdata
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else begin
            rdata <= rdata | set;                       // 硬件置位
            if (load)
                rdata <= (rdata | set) & ~wdata;        // 软件写1清零
        end
    end

endmodule


// ============================================================================
// reg_rc — 读后自动清零（粘滞）寄存器
//   set          : 硬件置位
//   rdata        : 读数据（= 当前值）；读取返回值后清零
//   read_strobe  : 读选通
//
//   注意："读后清零"意味着读取动作本身清除该位。
//   本原语使用寄存读——值被采样到影子寄存器中，一个周期后清除。
//   适用于主机轮询直到收到非零值的低频状态读取。
// ============================================================================
module reg_rc #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input      [W-1:0]         set,
    input                      read_strobe,
    output reg [W-1:0]         rdata
);

    reg [W-1:0] val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val   <= INIT;
            rdata <= INIT;
        end else begin
            val <= val | set;
            rdata <= val;                           // 寄存读
            if (read_strobe)
                val <= {W{1'b0}};
        end
    end

endmodule


// ============================================================================
// reg_rsvd — 保留地址空洞
//   SW 读始终返回 0，写被静默忽略。
//   用于填充地址映射中的间隙，避免意外的译码空洞。
// ============================================================================
module reg_rsvd #(
    parameter W = 16
) (
    output [W-1:0] rdata
);

    assign rdata = {W{1'b0}};

endmodule


// ============================================================================
// reg_pulse — 边沿转脉冲转换器（用于 W1C 置位逻辑）
//   在 din 的上升沿产生一个周期脉冲。
//   如果 din 来自其他时钟域，假定已做同步处理。
// ============================================================================
module reg_pulse #(
    parameter W = 1
) (
    input              clk,
    input              rst_n,
    input  [W-1:0]     din,
    output [W-1:0]     dout
);

    reg [W-1:0] din_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            din_d <= {W{1'b0}};
        else
            din_d <= din;
    end

    assign dout = din & ~din_d;

endmodule
