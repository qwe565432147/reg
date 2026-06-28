// ============================================================================
// cib_top.v — CIB 寄存器管理顶层
//
// 目的：
//   在一个模块中承担两个角色：
//     1. 外部总线协议适配层
//        – 对外暴露通用的类 SRAM 从接口，eSPI、SMBus、I2C、并行总线等
//          协议包装器都可以驱动此接口。
//        – 移植到新项目时，只需写一个 cib_top_<协议>.v 薄包装器，将你的
//          总线信号映射到 ext_* 端口集；CIB 层次结构中其他部分无需改动。
//     2. 区域片选译码器 & 读数据多路选择器
//        – 使用每个区域的 AMSB（地址最高有效位）实现统一译码：
//             addr[15:AMSB] == BASE_ADDR[15:AMSB]
//        – 为每个 cib_xxx 子模块生成独立的 cs_n（低电平有效的片选）
//        – 将各区域的 rdata 总线多路复用到外部接口；不存在的地址空间
//          返回 0 并拉高 bus_err
//
// 外部接口 (ext_*)：
//   类 SRAM 风格，组合逻辑读（单周期出数据），寄存写（ext_we & ext_cs_n
//   有效时在时钟上升沿捕获数据）。
//
//   用户提供的协议包装器（不在此文件中）：
//     cib_top_espi.v     – 将 eSPI 事务 → ext_*
//     cib_top_smbus.v    – 将 SMBus/I2C  → ext_*
//     cib_top_parallel.v – 直接引脚映射的并行总线 → ext_*
//     （根据需要自行添加）
//
// 内部局部总线（传递给每个子模块）：
//   信号            方向  说明
//   ─────────────────────────────────────────────
//   clk             in   与 ext_clk 相同（单时钟域）
//   rst_n           in   异步低电平复位
//   oe              出   输出使能（读选通，组合逻辑译码）
//   we              出   写使能（寄存，单周期脉冲）
//   cs_n[i]         出   片选（组合逻辑，低电平有效）
//   addr[15:0]      出   地址（组合逻辑，来自 ext_addr）
//   wdata[15:0]     出   写数据（来自 ext_wdata 寄存）
//   rdata[i][15:0]  入   每个子模块的读数据
//   rdy[i]          入   每个子模块的就绪信号
//
// 约定：
//   - 所有寄存器宽度为 16 位。
//   - 所有时序为单周期：读在同一周期返回数据（组合逻辑）；
//     写在时钟边沿捕获。
//   - 需要多周期响应的子模块（慢速 IP）将其 rdy 拉低，
//     顶层相应地将 ext_rdy 拉低。
//   - 地址空洞 → rdata = 0, bus_err 拉高。
// ============================================================================

`include "cib_reg_defines.v"

module cib_top (
    // ===== 外部总线接口 ======================================================
    // eSPI / SMBus / 并行总线 — 统一驱动此端口集。
    // 这是项目特定的协议包装器需要驱动的唯一接口。
    // ======================================================================
    input              ext_clk,            // 单时钟域
    input              ext_rst_n,          // 异步低电平复位

    // 总线事务
    input              ext_cs_n,           // 片选（低电平有效）
    input              ext_oe,             // 输出使能 / 读选通
    input              ext_we,             // 写使能
    input      [15:0]  ext_addr,           // 地址
    input      [15:0]  ext_wdata,          // 写数据

    // 总线响应
    output reg [15:0]  ext_rdata,          // 读数据
    output             ext_rdy,            // 就绪（1 = 事务完成）
    output             ext_err             // 错误（1 = 地址越界）
);

    // =========================================================================
    // 局部总线信号声明
    // =========================================================================
    wire              bus_active;          // 外部事务正在进行
    wire              bus_read;            // 读事务（oe）
    wire              bus_write;           // 写事务（we）

    // 每个子模块返回自己的 rdata/rdy
    // 区域索引 — 每新增一个 cib_xxx 实例，添加一对 wire
    wire [15:0]  rdata_base;
    wire [15:0]  rdata_board_sta;
    wire [15:0]  rdata_pwr;
    wire [15:0]  rdata_rst;
    wire [15:0]  rdata_adc_real;
    wire [15:0]  rdata_adc_his;
    wire [15:0]  rdata_adc_alm;
    wire [15:0]  rdata_int;
    wire [15:0]  rdata_iic;
    wire [15:0]  rdata_iic_agent;
    wire [15:0]  rdata_spi;
    wire [15:0]  rdata_jtag;
    wire [15:0]  rdata_fpga_load;
    wire [15:0]  rdata_mdio;
    wire [15:0]  rdata_uart;
    wire [15:0]  rdata_ms_switch;
    wire [15:0]  rdata_sfp;
    wire [15:0]  rdata_asic_misc;
    wire [15:0]  rdata_pic;
    wire [15:0]  rdata_board_ctl;
    wire [15:0]  rdata_dfx;
    wire [15:0]  rdata_ft;
    wire [15:0]  rdata_hss_sta;
    wire [15:0]  rdata_private;
    wire [15:0]  rdata_iic_complicated;
    wire [15:0]  rdata_clk_module;
    wire [15:0]  rdata_sspi;

    // 各区域就绪信号（1 = 单周期，0 = 子模块需要等待周期）
    wire         rdy_base;
    wire         rdy_board_sta;
    wire         rdy_pwr;
    wire         rdy_rst;
    wire         rdy_adc_real;
    wire         rdy_adc_his;
    wire         rdy_adc_alm;
    wire         rdy_int;
    wire         rdy_iic;
    wire         rdy_iic_agent;
    wire         rdy_spi;
    wire         rdy_jtag;
    wire         rdy_fpga_load;
    wire         rdy_mdio;
    wire         rdy_uart;
    wire         rdy_ms_switch;
    wire         rdy_sfp;
    wire         rdy_asic_misc;
    wire         rdy_pic;
    wire         rdy_board_ctl;
    wire         rdy_dfx;
    wire         rdy_ft;
    wire         rdy_hss_sta;
    wire         rdy_private;
    wire         rdy_iic_complicated;
    wire         rdy_clk_module;
    wire         rdy_sspi;

    // =========================================================================
    // 外部 → 局部总线适配
    // =========================================================================
    // bus_active 限定所有内部操作。
    // 当 ext_cs_n 无效时，所有内部选通被强制拉低。
    // =========================================================================
    assign bus_active = ~ext_cs_n;

    // 读选通 — 组合逻辑（同一周期地址 + oe → 输出数据）
    assign bus_read  = bus_active & ext_oe;

    // 写选通 — 寄存为单周期脉冲（在时钟上升沿采样）
    // （ext_we & ext_cs_n 在时钟边沿采样；we 高电平持续一个周期）
    reg  we_q;
    wire we_next;
    assign we_next  = bus_active & ext_we;
    always @(posedge ext_clk or negedge ext_rst_n) begin
        if (!ext_rst_n)
            we_q <= 1'b0;
        else
            we_q <= we_next;
    end

    // 寄存写数据（we 有效期间保持稳定）
    reg [15:0] wdata_q;
    always @(posedge ext_clk or negedge ext_rst_n) begin
        if (!ext_rst_n)
            wdata_q <= 16'h0000;
        else if (we_next)
            wdata_q <= ext_wdata;
    end

    // =========================================================================
    // 区域译码 — 基于 AMSB 的片选生成
    //
    // 每个区域有一个 AMSB（区域内偏移的最高有效位）：
    //   cs_n = 0 当 addr[15:AMSB] == BASE_ADDR[15:AMSB] && bus_active
    //   cs_n = 1 其他情况（无效）
    //
    // 当地址的（高于 AMSB 的）高位与基地址匹配时，区域被选中。
    // 只要区域是 2 的幂对齐，此方法都正确工作（cib_clk_module 除外，见下）。
    //
    // 添加新区域：添加一行 `wire` + 一行 `assign` — 共 2 行。
    // =========================================================================
    wire cs_n_base;
    wire cs_n_board_sta;
    wire cs_n_pwr;
    wire cs_n_rst;
    wire cs_n_adc_real;
    wire cs_n_adc_his;
    wire cs_n_adc_alm;
    wire cs_n_int;
    wire cs_n_iic;
    wire cs_n_iic_agent;
    wire cs_n_spi;
    wire cs_n_jtag;
    wire cs_n_fpga_load;
    wire cs_n_mdio;
    wire cs_n_uart;
    wire cs_n_ms_switch;
    wire cs_n_sfp;
    wire cs_n_asic_misc;
    wire cs_n_pic;
    wire cs_n_board_ctl;
    wire cs_n_dfx;
    wire cs_n_ft;
    wire cs_n_hss_sta;
    wire cs_n_private;
    wire cs_n_iic_complicated;
    wire cs_n_clk_module;
    wire cs_n_sspi;

    // 2 的幂对齐区域的统一译码公式：
    //   cs_n = ~bus_active | (addr[15:AMSB] !== BASE[15:AMSB])
    //
    // 综合注：所有比较共享同一个 addr[15:X] 总线；
    // 好的综合器会将共享项合并到一个查找表（LUT）中。
    assign cs_n_base           = ~bus_active | (ext_addr[15:`CIB_BASE_AMSB]          != `CIB_BASE_ADDR[15:`CIB_BASE_AMSB]);
    assign cs_n_board_sta      = ~bus_active | (ext_addr[15:`CIB_BOARD_STA_AMSB]     != `CIB_BOARD_STA_ADDR[15:`CIB_BOARD_STA_AMSB]);
    assign cs_n_pwr            = ~bus_active | (ext_addr[15:`CIB_PWR_AMSB]           != `CIB_PWR_ADDR[15:`CIB_PWR_AMSB]);
    assign cs_n_rst            = ~bus_active | (ext_addr[15:`CIB_RST_AMSB]           != `CIB_RST_ADDR[15:`CIB_RST_AMSB]);
    assign cs_n_adc_real       = ~bus_active | (ext_addr[15:`CIB_ADC_REAL_AMSB]      != `CIB_ADC_REAL_ADDR[15:`CIB_ADC_REAL_AMSB]);
    assign cs_n_adc_his        = ~bus_active | (ext_addr[15:`CIB_ADC_HIS_AMSB]       != `CIB_ADC_HIS_ADDR[15:`CIB_ADC_HIS_AMSB]);
    assign cs_n_adc_alm        = ~bus_active | (ext_addr[15:`CIB_ADC_ALM_AMSB]       != `CIB_ADC_ALM_ADDR[15:`CIB_ADC_ALM_AMSB]);
    assign cs_n_int            = ~bus_active | (ext_addr[15:`CIB_INT_AMSB]           != `CIB_INT_ADDR[15:`CIB_INT_AMSB]);
    assign cs_n_iic            = ~bus_active | (ext_addr[15:`CIB_IIC_AMSB]           != `CIB_IIC_ADDR[15:`CIB_IIC_AMSB]);
    assign cs_n_iic_agent      = ~bus_active | (ext_addr[15:`CIB_IIC_AGENT_AMSB]     != `CIB_IIC_AGENT_ADDR[15:`CIB_IIC_AGENT_AMSB]);
    assign cs_n_spi            = ~bus_active | (ext_addr[15:`CIB_SPI_AMSB]           != `CIB_SPI_ADDR[15:`CIB_SPI_AMSB]);
    assign cs_n_jtag           = ~bus_active | (ext_addr[15:`CIB_JTAG_AMSB]          != `CIB_JTAG_ADDR[15:`CIB_JTAG_AMSB]);
    assign cs_n_fpga_load      = ~bus_active | (ext_addr[15:`CIB_FPGA_LOAD_AMSB]     != `CIB_FPGA_LOAD_ADDR[15:`CIB_FPGA_LOAD_AMSB]);
    assign cs_n_mdio           = ~bus_active | (ext_addr[15:`CIB_MDIO_AMSB]          != `CIB_MDIO_ADDR[15:`CIB_MDIO_AMSB]);
    assign cs_n_uart           = ~bus_active | (ext_addr[15:`CIB_UART_AMSB]          != `CIB_UART_ADDR[15:`CIB_UART_AMSB]);
    assign cs_n_ms_switch      = ~bus_active | (ext_addr[15:`CIB_MS_SWITCH_AMSB]     != `CIB_MS_SWITCH_ADDR[15:`CIB_MS_SWITCH_AMSB]);
    assign cs_n_sfp            = ~bus_active | (ext_addr[15:`CIB_SFP_AMSB]           != `CIB_SFP_ADDR[15:`CIB_SFP_AMSB]);
    assign cs_n_asic_misc      = ~bus_active | (ext_addr[15:`CIB_ASIC_MISC_AMSB]     != `CIB_ASIC_MISC_ADDR[15:`CIB_ASIC_MISC_AMSB]);
    assign cs_n_pic            = ~bus_active | (ext_addr[15:`CIB_PIC_AMSB]           != `CIB_PIC_ADDR[15:`CIB_PIC_AMSB]);
    assign cs_n_board_ctl      = ~bus_active | (ext_addr[15:`CIB_BOARD_CTL_AMSB]     != `CIB_BOARD_CTL_ADDR[15:`CIB_BOARD_CTL_AMSB]);
    assign cs_n_dfx            = ~bus_active | (ext_addr[15:`CIB_DFX_AMSB]           != `CIB_DFX_ADDR[15:`CIB_DFX_AMSB]);
    assign cs_n_ft             = ~bus_active | (ext_addr[15:`CIB_FT_AMSB]            != `CIB_FT_ADDR[15:`CIB_FT_AMSB]);
    assign cs_n_hss_sta        = ~bus_active | (ext_addr[15:`CIB_HSS_STA_AMSB]       != `CIB_HSS_STA_ADDR[15:`CIB_HSS_STA_AMSB]);
    assign cs_n_private        = ~bus_active | (ext_addr[15:`CIB_PRIVATE_AMSB]       != `CIB_PRIVATE_ADDR[15:`CIB_PRIVATE_AMSB]);
    assign cs_n_iic_complicated = ~bus_active | (ext_addr[15:`CIB_IIC_COMPLICATED_AMSB] != `CIB_IIC_COMPLICATED_ADDR[15:`CIB_IIC_COMPLICATED_AMSB]);

    // ---- cib_clk_module（非 2 的幂大小）----
    // 大小 0x0F00，不是 2^N — 仅用 AMSB 会错误译码超出 LAST 但高位相同的地址。
    // 使用显式范围检查。
    //   有效：  0x3000 – 0x3EFF
    //   空洞：  0x3F00 – 0x3FFF（由 cib_sspi 处理）
    assign cs_n_clk_module = ~bus_active
                           | (ext_addr < `CIB_CLK_MODULE_ADDR)
                           | (ext_addr > `CIB_CLK_MODULE_LAST);

    assign cs_n_sspi           = ~bus_active | (ext_addr[15:`CIB_SSPI_AMSB]          != `CIB_SSPI_ADDR[15:`CIB_SSPI_AMSB]);

    // =========================================================================
    // 地址空洞检测
    //
    // 如果恰好一个区域选择有效，认为访问"在范围内"。
    // 如果没有区域有效（或 clk_module 的范围检查遗漏），
    // 则拉高 bus_err，rdata 返回 0。
    //
    // err 检查是组合逻辑，因此在地址译码同一周期可用。
    // =========================================================================
    wire any_selected = ~cs_n_base    | ~cs_n_board_sta  | ~cs_n_pwr
                      | ~cs_n_rst    | ~cs_n_adc_real   | ~cs_n_adc_his
                      | ~cs_n_adc_alm| ~cs_n_int        | ~cs_n_iic
                      | ~cs_n_iic_agent | ~cs_n_spi     | ~cs_n_jtag
                      | ~cs_n_fpga_load | ~cs_n_mdio    | ~cs_n_uart
                      | ~cs_n_ms_switch | ~cs_n_sfp     | ~cs_n_asic_misc
                      | ~cs_n_pic   | ~cs_n_board_ctl  | ~cs_n_dfx
                      | ~cs_n_ft    | ~cs_n_hss_sta    | ~cs_n_private
                      | ~cs_n_iic_complicated | ~cs_n_clk_module | ~cs_n_sspi;

    // ext_rdy：组合逻辑 — 总线空闲或命中有效区域时为 1。
    // 需要等待周期的子模块将其 rdy 拉低。选中区域的 rdy 为低时，
    // ext_rdy 跟随其值（外部主机插入等待周期）。
    reg [26:0] rdy_mux;  // 每个区域一个 bit（27 个区域）
    // 目前所有区域默认单周期（rdy = 1）。
    // 子模块实现后，替换为各模块的 rdy 值。
    assign ext_rdy = bus_active ? rdy_of_selected_region : 1'b1;

    // ext_err：组合逻辑
    assign ext_err = bus_active & ~any_selected;

    // =========================================================================
    // 读数据多路选择器
    //
    // 当区域被选中时（cs_n = 0），将其 rdata 路由到 ext_rdata。
    // 当没有区域被选中时（地址空洞），返回 0。
    // default 分支用于捕获空洞和仿真器的 X 传播。
    // =========================================================================
    always @(*) begin
        ext_rdata = 16'h0000;       // 默认：地址空洞 → 0
        case (1'b1)  // 优先级编码，但选择互斥
            ~cs_n_base:           ext_rdata = rdata_base;
            ~cs_n_board_sta:      ext_rdata = rdata_board_sta;
            ~cs_n_pwr:            ext_rdata = rdata_pwr;
            ~cs_n_rst:            ext_rdata = rdata_rst;
            ~cs_n_adc_real:       ext_rdata = rdata_adc_real;
            ~cs_n_adc_his:        ext_rdata = rdata_adc_his;
            ~cs_n_adc_alm:        ext_rdata = rdata_adc_alm;
            ~cs_n_int:            ext_rdata = rdata_int;
            ~cs_n_iic:            ext_rdata = rdata_iic;
            ~cs_n_iic_agent:      ext_rdata = rdata_iic_agent;
            ~cs_n_spi:            ext_rdata = rdata_spi;
            ~cs_n_jtag:           ext_rdata = rdata_jtag;
            ~cs_n_fpga_load:      ext_rdata = rdata_fpga_load;
            ~cs_n_mdio:           ext_rdata = rdata_mdio;
            ~cs_n_uart:           ext_rdata = rdata_uart;
            ~cs_n_ms_switch:      ext_rdata = rdata_ms_switch;
            ~cs_n_sfp:            ext_rdata = rdata_sfp;
            ~cs_n_asic_misc:      ext_rdata = rdata_asic_misc;
            ~cs_n_pic:            ext_rdata = rdata_pic;
            ~cs_n_board_ctl:      ext_rdata = rdata_board_ctl;
            ~cs_n_dfx:            ext_rdata = rdata_dfx;
            ~cs_n_ft:             ext_rdata = rdata_ft;
            ~cs_n_hss_sta:        ext_rdata = rdata_hss_sta;
            ~cs_n_private:        ext_rdata = rdata_private;
            ~cs_n_iic_complicated: ext_rdata = rdata_iic_complicated;
            ~cs_n_clk_module:     ext_rdata = rdata_clk_module;
            ~cs_n_sspi:           ext_rdata = rdata_sspi;
            default:              ext_rdata = 16'h0000;  // 空洞或 X 安全
        endcase
    end

    // =========================================================================
    // 就绪多路选择器 — 跟踪哪个区域的 rdy 供给 ext_rdy
    // =========================================================================
    // 与 rdata 类似的组合逻辑多路选择器。
    // 对于尚未实现的区域，将 rdy 接 1（单周期）。
    wire rdy_of_selected_region;
    always @(*) begin
        rdy_of_selected_region = 1'b1;   // 默认
        case (1'b1)
            ~cs_n_base:           rdy_of_selected_region = rdy_base;
            ~cs_n_board_sta:      rdy_of_selected_region = rdy_board_sta;
            ~cs_n_pwr:            rdy_of_selected_region = rdy_pwr;
            ~cs_n_rst:            rdy_of_selected_region = rdy_rst;
            ~cs_n_adc_real:       rdy_of_selected_region = rdy_adc_real;
            ~cs_n_adc_his:        rdy_of_selected_region = rdy_adc_his;
            ~cs_n_adc_alm:        rdy_of_selected_region = rdy_adc_alm;
            ~cs_n_int:            rdy_of_selected_region = rdy_int;
            ~cs_n_iic:            rdy_of_selected_region = rdy_iic;
            ~cs_n_iic_agent:      rdy_of_selected_region = rdy_iic_agent;
            ~cs_n_spi:            rdy_of_selected_region = rdy_spi;
            ~cs_n_jtag:           rdy_of_selected_region = rdy_jtag;
            ~cs_n_fpga_load:      rdy_of_selected_region = rdy_fpga_load;
            ~cs_n_mdio:           rdy_of_selected_region = rdy_mdio;
            ~cs_n_uart:           rdy_of_selected_region = rdy_uart;
            ~cs_n_ms_switch:      rdy_of_selected_region = rdy_ms_switch;
            ~cs_n_sfp:            rdy_of_selected_region = rdy_sfp;
            ~cs_n_asic_misc:      rdy_of_selected_region = rdy_asic_misc;
            ~cs_n_pic:            rdy_of_selected_region = rdy_pic;
            ~cs_n_board_ctl:      rdy_of_selected_region = rdy_board_ctl;
            ~cs_n_dfx:            rdy_of_selected_region = rdy_dfx;
            ~cs_n_ft:             rdy_of_selected_region = rdy_ft;
            ~cs_n_hss_sta:        rdy_of_selected_region = rdy_hss_sta;
            ~cs_n_private:        rdy_of_selected_region = rdy_private;
            ~cs_n_iic_complicated: rdy_of_selected_region = rdy_iic_complicated;
            ~cs_n_clk_module:     rdy_of_selected_region = rdy_clk_module;
            ~cs_n_sspi:           rdy_of_selected_region = rdy_sspi;
            default:              rdy_of_selected_region = 1'b1;
        endcase
    end

    // =========================================================================
    // 子模块例化
    //
    // 每个 cib_xxx 模块接收：
    //   .clk   (ext_clk)
    //   .rst_n (ext_rst_n)
    //   .cs_n  （来自上方的各自片选）
    //   .oe    (bus_read)
    //   .we    (we_q)
    //   .addr  (ext_addr — 完整 16 位；子模块使用偏移位)
    //   .wdata (wdata_q)
    //   .rdata (→ 对应 rdata wire）
    //   .rdy   (→ 对应 rdy wire）
    //
    // 注意：在此处例化你构建的区域模块。
    // 未使用的区域保持注释状态 — 它们的 cs_n 保持高电平（无效）。
    // =========================================================================

    // ---- cib_ft（工厂测试）---------------------------------------------------
    cib_ft u_cib_ft (
        .clk   (ext_clk),
        .rst_n (ext_rst_n),
        .cs_n  (cs_n_ft),
        .oe    (bus_read),
        .we    (we_q),
        .addr  (ext_addr),
        .wdata (wdata_q),
        .rdata (rdata_ft),
        .rdy   (rdy_ft),

        // 硬件测试接口（未连接模板 — 如果不用就接默认值）
        .test_mode_o     (),
        .test_loopback_o (),
        .bist_start_o    (),
        .bist_busy_i     (1'b0),
        .bist_pass_i     (1'b0),
        .bist_fail_i     (1'b0),
        .test_data_in_o  (),
        .test_data_out_i (16'h0000),
        .loop_count_o    ()
    );

    // ---- cib_base（芯片基本信息）-------------------------------------------
    /*
    cib_base u_cib_base (
        .clk   (ext_clk),
        .rst_n (ext_rst_n),
        .cs_n  (cs_n_base),
        .oe    (bus_read),
        .we    (we_q),
        .addr  (ext_addr),
        .wdata (wdata_q),
        .rdata (rdata_base),
        .rdy   (rdy_base)
    );
    */

    // ---- cib_pwr（电源管理）-----------------------------------------------
    /*
    cib_pwr u_cib_pwr (
        .clk   (ext_clk),
        .rst_n (ext_rst_n),
        .cs_n  (cs_n_pwr),
        .oe    (bus_read),
        .we    (we_q),
        .addr  (ext_addr),
        .wdata (wdata_q),
        .rdata (rdata_pwr),
        .rdy   (rdy_pwr)
    );
    */

    // +-- 在下方添加其余区域，遵循相同格式 --------------------------------+
    // | cib_board_sta, cib_rst, cib_adc_real, cib_adc_his, cib_adc_alm,      |
    // | cib_int, cib_iic, cib_iic_agent, cib_spi, cib_jtag, cib_fpga_load,   |
    // | cib_mdio, cib_uart, cib_ms_switch, cib_sfp, cib_asic_misc,           |
    // | cib_pic, cib_board_ctl, cib_dfx, cib_hss_sta, cib_private,           |
    // | cib_iic_complicated, cib_clk_module, cib_sspi                        |
    // +---------------------------------------------------------------------+

endmodule
