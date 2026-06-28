// ============================================================================
// cib_top_espi.v — eSPI 协议转 CIB ext_* 接口示例
//
// 目的：
//   演示"外部协议包装器 + 管线寄存"的方案 B 模式。
//   将 eSPI 外围通道（Peripheral Channel）的读写事务转换为 CIB 架构的
//   ext_* 标准接口，并在转换过程中插入管线寄存。
//
// 设计要点：
//   1. 协议解码与管线寄存分两段写，清晰分离
//   2. 管线深度为 1 拍（可根据时序需求增加）
//   3. 利用 ext_rdy 信号处理回读数据的延迟对齐
//   4. 本文件只做协议转换 + 打拍，不做区域译码（那是 cib_top 的事）
//
// 移植到其他协议（SMBus、Parallel 等）时，只需替换本文件的协议解码部分，
// 管线寄存和 cib_top 例化部分可以复用同一套代码结构。
// ============================================================================

`include "cib_reg_defines.v"

module cib_top_espi (
    // ---- 时钟 / 复位 -------------------------------------------------------
    input              clk,                // 外部系统时钟
    input              rst_n,              // 异步低电平复位

    // ---- eSPI 总线接口（来自芯片引脚）----------------------------------------
    // 这是一个极简的 eSPI 模型，只展示 peripheral channel 的单字读写。
    // 完整的 eSPI 还需要处理多通道、包长度、CRC、中断等，此处略去。
    input              espi_cs_n,          // eSPI 片选（低有效）
    input              espi_clk,           // eSPI 时钟（上升沿采样）
    input              espi_mosi,          // 主机→从机数据线
    output             espi_miso,          // 从机→主机数据线
    output             espi_rdy            // eSPI 就绪

    // 注意：为保持示例简洁，这里假设 espi_clk == clk（同频）。
    // 实际项目中若 espi_clk 与系统时钟不同频，需要跨时钟域同步。
);

    // =========================================================================
    // 段一：eSPI 协议解码 → 原始 ext_* 值（组合逻辑）
    //
    // 这里把 eSPI 包解析成地址、数据、读写命令。
    // 实际项目中这里会是一个状态机，处理字节接收、地址解析、数据拼装等。
    // 本示例简化为一组组合逻辑赋值。
    // =========================================================================

    // 模拟 eSPI 解码结果（组合逻辑）
    // 真实场景中，这些来自 eSPI 移位寄存器和状态机的输出
    wire        espi_cs_active_pre;         // 解码后的事务有效
    wire        espi_oe_pre;                // 解码后的读使能（get 命令）
    wire        espi_we_pre;                // 解码后的写使能（put 命令）
    wire [15:0] espi_addr_pre;              // 解码后的地址（eSPI 地址取低 16 位）
    wire [15:0] espi_wdata_pre;             // 解码后的写数据

    // ── 此处模拟赋值，实际项目中替换为 eSPI 状态机输出 ──
    assign espi_cs_active_pre = ~espi_cs_n; // 片选有效
    assign espi_oe_pre        = 1'b0;       // （假设当前无读事务）
    assign espi_we_pre        = 1'b0;       // （假设当前无写事务）
    assign espi_addr_pre      = 16'h0000;
    assign espi_wdata_pre     = 16'h0000;

    // =========================================================================
    // 段二：管线寄存（时序逻辑）
    //
    // 将组合逻辑解码结果寄存 N 拍后再送进 cib_top。
    // 这样做的好处：
    //   1. 切断组合逻辑长路径，改善时序
    //   2. 对齐 ext_rdy 和 ext_rdata 的时序关系
    //   3. 不需要额外的打拍器模块，协议包装器自包含
    //
    // 管线深度说明：
    //   1 拍 = 地址/控制信号寄存一次，读数据从 cib_top 返回后也寄存一次
    //   如果需要更多拍，只需增加一级寄存器（通常 1~2 拍足够）
    // =========================================================================

    // ── 一级管线寄存器 ──
    reg         ext_cs_n_r1;
    reg         ext_oe_r1;
    reg         ext_we_r1;
    reg [15:0]  ext_addr_r1;
    reg [15:0]  ext_wdata_r1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_cs_n_r1  <= 1'b1;           // 片选默认无效
            ext_oe_r1    <= 1'b0;
            ext_we_r1    <= 1'b0;
            ext_addr_r1  <= 16'h0000;
            ext_wdata_r1 <= 16'h0000;
        end else begin
            ext_cs_n_r1  <= ~espi_cs_active_pre;  // 取反转化：active → cs_n
            ext_oe_r1    <= espi_oe_pre;           // 读使能透传
            ext_we_r1    <= espi_we_pre;           // 写使能透传
            ext_addr_r1  <= espi_addr_pre;         // 地址寄存
            ext_wdata_r1 <= espi_wdata_pre;        // 写数据寄存
        end
    end

    // ── 如果需要两级管线，再加一级（代码完全复用上层结构）──
    // reg         ext_cs_n_r2;
    // reg         ext_oe_r2;
    // ...
    // always @(posedge clk) begin
    //     ext_cs_n_r2  <= ext_cs_n_r1;
    //     ext_oe_r2    <= ext_oe_r1;
    //     ...
    // end
    //
    // 最后接到 cib_top 的 ext_* 时，选 r2 那级：
    //   .ext_cs_n(ext_cs_n_r2), ...

    // =========================================================================
    // cib_top 例化
    //
    // 把寄存后的控制/地址/数据信号接到 cib_top 的 ext_* 端口。
    // cib_top 完全不感知外部协议类型和管线深度 —— 它只认 ext_* 接口。
    // =========================================================================

    wire [15:0] cib_rdata;      // cib_top 返回的读数据
    wire        cib_rdy;        // cib_top 返回的就绪信号
    wire        cib_err;        // cib_top 返回的错误信号

    cib_top u_cib_top (
        .ext_clk   (clk),
        .ext_rst_n (rst_n),

        .ext_cs_n  (ext_cs_n_r1),     // 接寄存后的片选
        .ext_oe    (ext_oe_r1),       // 接寄存后的读使能
        .ext_we    (ext_we_r1),       // 接寄存后的写使能
        .ext_addr  (ext_addr_r1),     // 接寄存后的地址
        .ext_wdata (ext_wdata_r1),    // 接寄存后的写数据

        .ext_rdata (cib_rdata),       // 来自 cib_top 的读数据
        .ext_rdy   (cib_rdy),         // 来自 cib_top 的就绪
        .ext_err   (cib_err)          // 来自 cib_top 的错误
    );

    // =========================================================================
    // eSPI 回读数据寄存
    //
    // cib_top 返回的 ext_rdata / ext_rdy 是组合逻辑或仅寄存一次的。
    // 在这里再寄存一拍，让 eSPI 输出时序更干净。
    // 这也意味着从地址发出到数据返回共 2 拍延迟：
    //   第 1 拍：cib_top 内部译码
    //   第 2 拍：回读数据寄存（本模块）
    // =========================================================================

    reg         espi_miso_valid;    // 输出数据有效标志
    reg [15:0]  espi_miso_data;     // 输出数据

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            espi_miso_valid <= 1'b0;
            espi_miso_data  <= 16'h0000;
        end else begin
            espi_miso_valid <= cib_rdy;           // rdy 对齐数据
            espi_miso_data  <= cib_rdy ? cib_rdata : espi_miso_data;
        end
    end

    // MISO 输出（实际 eSPI 输出还需要串行化，此处简化）
    assign espi_miso = espi_miso_valid ? espi_miso_data[0] : 1'bz;
    assign espi_rdy  = cib_rdy;

endmodule
