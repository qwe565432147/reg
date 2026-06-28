`ifndef __CIB_REG_DEFINES_V__
`define __CIB_REG_DEFINES_V__

// ============================================================================
// cib_reg_defines.v — 寄存器地址映射定义
//
// 目的：
//   中央地址映射定义文件。所有区域基地址、大小、寄存器偏移以及位域常量
//   都在此定义为 `defines。需要了解地址映射的模块都包含此文件。
//
// 命名约定：
//   REG_<区域名>_<寄存器>    用于偏移地址
//   REG_<区域名>_<位域>_*    用于位域位置/宽度
//   REG_<区域名>_<位域>_W   仅位域宽度
//   REG_<区域名>_<位域>_L   仅位域最低位(LSB)位置
//   REG_<区域名>_LAST       区域结束地址 (基地址 + 大小 - 1)
//
// === 如何添加新区域 ===
//   1. 在下方添加 REG_<名称>_ADDR、REG_<名称>_SIZE 和 REG_<名称>_LAST
//   2. 创建 rtl/reg_<名称>.v，使用标准 reg_slave_intf 端口
//   3. 在 reg_top.v 中添加 reg_sel_<名称> 译码、实例化模块、
//      并在 rdata 多路选择器中增加一项——每次添加只需 3-5 行
// ============================================================================

// ============================================================================
// 地址空间拓扑
//   总空间  ：0x0000 – 0x3FFF  （32K字 × 16位）
//   区域    ：固定大小、2的幂对齐的块（cib_clk_module 除外）
// ============================================================================

// -------------------------------- cib_base -----------------------------------
//  512 字  (0x0000 – 0x00FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_BASE_ADDR           16'h0000
`define CIB_BASE_SIZE           16'h0100
`define CIB_BASE_LAST           (`CIB_BASE_ADDR + `CIB_BASE_SIZE - 1)
`define CIB_BASE_AMSB           8

// ------------------------------ cib_board_sta -------------------------------
//  512 字  (0x0100 – 0x01FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_BOARD_STA_ADDR      16'h0100
`define CIB_BOARD_STA_SIZE      16'h0100
`define CIB_BOARD_STA_LAST      (`CIB_BOARD_STA_ADDR + `CIB_BOARD_STA_SIZE - 1)
`define CIB_BOARD_STA_AMSB      8

// --------------------------------- cib_pwr ----------------------------------
//  256 字  (0x0200 – 0x027F) → 偏移 [6:0], 译码 [15:7]
`define CIB_PWR_ADDR            16'h0200
`define CIB_PWR_SIZE            16'h0080
`define CIB_PWR_LAST            (`CIB_PWR_ADDR + `CIB_PWR_SIZE - 1)
`define CIB_PWR_AMSB            7

// --------------------------------- cib_rst ----------------------------------
//  256 字  (0x0280 – 0x02FF) → 偏移 [6:0], 译码 [15:7]
`define CIB_RST_ADDR            16'h0280
`define CIB_RST_SIZE            16'h0080
`define CIB_RST_LAST            (`CIB_RST_ADDR + `CIB_RST_SIZE - 1)
`define CIB_RST_AMSB            7

// ------------------------------ cib_adc_real --------------------------------
//  512 字  (0x0300 – 0x03FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_ADC_REAL_ADDR       16'h0300
`define CIB_ADC_REAL_SIZE       16'h0100
`define CIB_ADC_REAL_LAST       (`CIB_ADC_REAL_ADDR + `CIB_ADC_REAL_SIZE - 1)
`define CIB_ADC_REAL_AMSB       8

// ------------------------------- cib_adc_his --------------------------------
//  512 字  (0x0400 – 0x04FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_ADC_HIS_ADDR        16'h0400
`define CIB_ADC_HIS_SIZE        16'h0100
`define CIB_ADC_HIS_LAST        (`CIB_ADC_HIS_ADDR + `CIB_ADC_HIS_SIZE - 1)
`define CIB_ADC_HIS_AMSB        8

// ------------------------------- cib_adc_alm --------------------------------
//  512 字  (0x0500 – 0x05FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_ADC_ALM_ADDR        16'h0500
`define CIB_ADC_ALM_SIZE        16'h0100
`define CIB_ADC_ALM_LAST        (`CIB_ADC_ALM_ADDR + `CIB_ADC_ALM_SIZE - 1)
`define CIB_ADC_ALM_AMSB        8

// --------------------------------- cib_int ----------------------------------
//  256 字  (0x0600 – 0x067F) → 偏移 [6:0], 译码 [15:7]
`define CIB_INT_ADDR            16'h0600
`define CIB_INT_SIZE            16'h0080
`define CIB_INT_LAST            (`CIB_INT_ADDR + `CIB_INT_SIZE - 1)
`define CIB_INT_AMSB            7

// --------------------------------- cib_iic ----------------------------------
//  512 字  (0x0680 – 0x077F) → 偏移 [7:0], 译码 [15:8]
`define CIB_IIC_ADDR            16'h0680
`define CIB_IIC_SIZE            16'h0100
`define CIB_IIC_LAST            (`CIB_IIC_ADDR + `CIB_IIC_SIZE - 1)
`define CIB_IIC_AMSB            8

// ----------------------------- cib_iic_agent --------------------------------
//  256 字  (0x0780 – 0x07FF) → 偏移 [6:0], 译码 [15:7]
`define CIB_IIC_AGENT_ADDR      16'h0780
`define CIB_IIC_AGENT_SIZE      16'h0080
`define CIB_IIC_AGENT_LAST      (`CIB_IIC_AGENT_ADDR + `CIB_IIC_AGENT_SIZE - 1)
`define CIB_IIC_AGENT_AMSB      7

// --------------------------------- cib_spi ----------------------------------
//  512 字  (0x0800 – 0x08FF) → 偏移 [7:0], 译码 [15:8]
`define CIB_SPI_ADDR            16'h0800
`define CIB_SPI_SIZE            16'h0100
`define CIB_SPI_LAST            (`CIB_SPI_ADDR + `CIB_SPI_SIZE - 1)
`define CIB_SPI_AMSB            8

// -------------------------------- cib_jtag ----------------------------------
//  256 字  (0x0900 – 0x097F) → 偏移 [6:0], 译码 [15:7]
`define CIB_JTAG_ADDR           16'h0900
`define CIB_JTAG_SIZE           16'h0080
`define CIB_JTAG_LAST           (`CIB_JTAG_ADDR + `CIB_JTAG_SIZE - 1)
`define CIB_JTAG_AMSB           7

// ----------------------------- cib_fpga_load --------------------------------
//  256 字  (0x0980 – 0x09FF) → 偏移 [6:0], 译码 [15:7]
`define CIB_FPGA_LOAD_ADDR      16'h0980
`define CIB_FPGA_LOAD_SIZE      16'h0080
`define CIB_FPGA_LOAD_LAST      (`CIB_FPGA_LOAD_ADDR + `CIB_FPGA_LOAD_SIZE - 1)
`define CIB_FPGA_LOAD_AMSB      7

// -------------------------------- cib_mdio ----------------------------------
//  256 字  (0x0A80 – 0x0B7F) → 偏移 [7:0], 译码 [15:8]
`define CIB_MDIO_ADDR           16'h0A80
`define CIB_MDIO_SIZE           16'h0100
`define CIB_MDIO_LAST           (`CIB_MDIO_ADDR + `CIB_MDIO_SIZE - 1)
`define CIB_MDIO_AMSB           8

// -------------------------------- cib_uart ----------------------------------
//  128 字  (0x0B80 – 0x0BFF) → 偏移 [6:0], 译码 [15:7]
`define CIB_UART_ADDR           16'h0B80
`define CIB_UART_SIZE           16'h0080
`define CIB_UART_LAST           (`CIB_UART_ADDR + `CIB_UART_SIZE - 1)
`define CIB_UART_AMSB           7

// ----------------------------- cib_ms_switch --------------------------------
//  512 字  (0x0C00 – 0x0CFF) → 偏移 [7:0], 译码 [15:8]
`define CIB_MS_SWITCH_ADDR      16'h0C00
`define CIB_MS_SWITCH_SIZE      16'h0100
`define CIB_MS_SWITCH_LAST      (`CIB_MS_SWITCH_ADDR + `CIB_MS_SWITCH_SIZE - 1)
`define CIB_MS_SWITCH_AMSB      8

// -------------------------------- cib_sfp -----------------------------------
//  1024 字 (0x0D00 – 0x0EFF) → 偏移 [8:0], 译码 [15:9]
`define CIB_SFP_ADDR            16'h0D00
`define CIB_SFP_SIZE            16'h0200
`define CIB_SFP_LAST            (`CIB_SFP_ADDR + `CIB_SFP_SIZE - 1)
`define CIB_SFP_AMSB            9

// ----------------------------- cib_asic_misc --------------------------------
//  512 字  (0x0F00 – 0x0FFF) → 偏移 [7:0], 译码 [15:8]
`define CIB_ASIC_MISC_ADDR      16'h0F00
`define CIB_ASIC_MISC_SIZE      16'h0100
`define CIB_ASIC_MISC_LAST      (`CIB_ASIC_MISC_ADDR + `CIB_ASIC_MISC_SIZE - 1)
`define CIB_ASIC_MISC_AMSB      8

// -------------------------------- cib_pic -----------------------------------
//  1024 字 (0x1000 – 0x11FF) → 偏移 [8:0], 译码 [15:9]
`define CIB_PIC_ADDR            16'h1000
`define CIB_PIC_SIZE            16'h0200
`define CIB_PIC_LAST            (`CIB_PIC_ADDR + `CIB_PIC_SIZE - 1)
`define CIB_PIC_AMSB            9

// ----------------------------- cib_board_ctl --------------------------------
//  1024 字 (0x1200 – 0x13FF) → 偏移 [8:0], 译码 [15:9]
`define CIB_BOARD_CTL_ADDR      16'h1200
`define CIB_BOARD_CTL_SIZE      16'h0200
`define CIB_BOARD_CTL_LAST      (`CIB_BOARD_CTL_ADDR + `CIB_BOARD_CTL_SIZE - 1)
`define CIB_BOARD_CTL_AMSB      9

// -------------------------------- cib_dfx -----------------------------------
//  4096 字 (0x1400 – 0x1BFF) → 偏移 [10:0], 译码 [15:11]
`define CIB_DFX_ADDR            16'h1400
`define CIB_DFX_SIZE            16'h0800
`define CIB_DFX_LAST            (`CIB_DFX_ADDR + `CIB_DFX_SIZE - 1)
`define CIB_DFX_AMSB            11

// -------------------------------- cib_ft ------------------------------------
//  512 字  (0x1C00 – 0x1CFF) → 偏移 [7:0], 译码 [15:8]
`define CIB_FT_ADDR             16'h1C00
`define CIB_FT_SIZE             16'h0100
`define CIB_FT_LAST             (`CIB_FT_ADDR + `CIB_FT_SIZE - 1)
`define CIB_FT_AMSB             8

// ------------------------------ cib_hss_sta ---------------------------------
//  512 字  (0x1D00 – 0x1DFF) → 偏移 [7:0], 译码 [15:8]
`define CIB_HSS_STA_ADDR        16'h1D00
`define CIB_HSS_STA_SIZE        16'h0100
`define CIB_HSS_STA_LAST        (`CIB_HSS_STA_ADDR + `CIB_HSS_STA_SIZE - 1)
`define CIB_HSS_STA_AMSB        8

// ------------------------------ cib_private --------------------------------
//  1024 字 (0x1E00 – 0x1FFF) → 偏移 [8:0], 译码 [15:9]
`define CIB_PRIVATE_ADDR        16'h1E00
`define CIB_PRIVATE_SIZE        16'h0200
`define CIB_PRIVATE_LAST        (`CIB_PRIVATE_ADDR + `CIB_PRIVATE_SIZE - 1)
`define CIB_PRIVATE_AMSB        9

// -------------------------- cib_iic_complicated ----------------------------
//  8192 字 (0x2000 – 0x2FFF) → 偏移 [11:0], 译码 [15:12]
//  复杂 I2C 控制器寄存器空间
`define CIB_IIC_COMPLICATED_ADDR 16'h2000
`define CIB_IIC_COMPLICATED_SIZE 16'h1000
`define CIB_IIC_COMPLICATED_LAST (`CIB_IIC_COMPLICATED_ADDR + `CIB_IIC_COMPLICATED_SIZE - 1)
`define CIB_IIC_COMPLICATED_AMSB 12

// ---------------------------- cib_clk_module --------------------------------
//  3840 字 (0x3000 – 0x3EFF) → 偏移 [11:0], 译码 [15:12]
//  注意：大小不是 2 的幂；使用基地址范围比较进行译码
`define CIB_CLK_MODULE_ADDR     16'h3000
`define CIB_CLK_MODULE_SIZE     16'h0F00
`define CIB_CLK_MODULE_LAST     (`CIB_CLK_MODULE_ADDR + `CIB_CLK_MODULE_SIZE - 1)
`define CIB_CLK_MODULE_AMSB     12

// ------------------------------- cib_sspi -----------------------------------
//  512 字  (0x3F00 – 0x3FFF) → 偏移 [7:0], 译码 [15:8]
`define CIB_SSPI_ADDR           16'h3F00
`define CIB_SSPI_SIZE           16'h0100
`define CIB_SSPI_LAST           (`CIB_SSPI_ADDR + `CIB_SSPI_SIZE - 1)
`define CIB_SSPI_AMSB           8

`endif // __CIB_REG_DEFINES_V__
