`ifndef __REG_DEFINES_V__
`define __REG_DEFINES_V__

// ============================================================================
// reg_defines.v — Register Map Address Definitions
//
// Purpose:
//   Central address-map definition file. All region base addresses, sizes,
//   register offsets, and bit-field constants are defined here as `defines.
//   Included by any module that needs address-map awareness.
//
// Convention:
//   REG_<REGION>_<REGISTER>  for offset addresses
//   REG_<REGION>_<FIELD>_*   for bit-field position/width
//   REG_<REGION>_<FIELD>_W   for field width only
//   REG_<REGION>_<FIELD>_L   for field LSB position
//
// === How to add a new region ===
//   1. Add a REG_<NAME>_ADDR and REG_<NAME>_SIZE below
//   2. Create rtl/reg_<name>.v with standard reg_slave_intf ports
//   3. In reg_top.v: add a reg_sel_<name> decode, instantiate the module,
//      and extend the rdata mux — each addition is 3-5 lines
// ============================================================================

// ============================================================================
// Address-Space Topology
//   Total   : 0x0000 – 0xFFFF  (64 Kwords × 16 bit)
//   Regions : fixed-size, power-of-2 aligned blocks
// ============================================================================

// ----- reg_base : Version / Chip-ID / Scratch --------------------------------
//   8 Kwords  (0x0000 – 0x1FFF) → offset [12:0], decode [15:13]
`define REG_BASE_ADDR     16'h0000
`define REG_BASE_SIZE     16'h2000

// ----- reg_status : FPGA status & error counters -----------------------------
//   4 Kwords  (0x2000 – 0x2FFF) → offset [11:0], decode [15:12]
`define REG_STATUS_ADDR   16'h2000
`define REG_STATUS_SIZE   16'h1000

// ----- reg_iic : I2C controller ---------------------------------------------
//   4 Kwords  (0x3000 – 0x3FFF) → offset [11:0], decode [15:12]
`define REG_IIC_ADDR      16'h3000
`define REG_IIC_SIZE      16'h1000

// ----- reg_spi : SPI controller ---------------------------------------------
//   4 Kwords  (0x4000 – 0x4FFF) → offset [11:0], decode [15:12]
`define REG_SPI_ADDR      16'h4000
`define REG_SPI_SIZE      16'h1000

// ----- reg_ft : Factory / test ----------------------------------------------
//   4 Kwords  (0x5000 – 0x5FFF) → offset [11:0], decode [15:12]
`define REG_FT_ADDR       16'h5000
`define REG_FT_SIZE       16'h1000

// ----- reg_int : Interrupt controller ---------------------------------------
//   4 Kwords  (0x6000 – 0x6FFF) → offset [11:0], decode [15:12]
`define REG_INT_ADDR      16'h6000
`define REG_INT_SIZE      16'h1000

// ============================================================================
// reg_base Register Map  (BASE_ADDR = 0x0000)
// ============================================================================
`define REG_BASE_VER      16'h0000       // Version (RO)   [major[15:8], minor[7:0]]
`define REG_BASE_VER_MAJOR_W  8
`define REG_BASE_VER_MAJOR_L  8
`define REG_BASE_VER_MINOR_W  8
`define REG_BASE_VER_MINOR_L  0

`define REG_BASE_CHIP_ID  16'h0001       // Chip / FPGA ID (RO)

`define REG_BASE_BUILD_Y  16'h0002       // Build year  (RO)  e.g. 0x2026
`define REG_BASE_BUILD_M  16'h0003       // Build month (RO)  e.g. 0x0006
`define REG_BASE_BUILD_D  16'h0004       // Build day   (RO)  e.g. 0x0028

`define REG_BASE_GIT_SHA  16'h0005       // Git SHA short[15:0] (RO)
`define REG_BASE_GIT_SHA2 16'h0006       // Git SHA short[31:16] (RO)

`define REG_BASE_SCRATCH  16'h0010       // Scratch (RW) — free for FW use
`define REG_BASE_SCRATCH_W   16

`define REG_BASE_FEATURES 16'h0020       // Feature bitmap (RO)

// --- Demo / 教学用寄存器（展示 slice 原语的用法）-------------------------------
`define REG_BASE_CTRL     16'h0030       // 控制寄存器 —— 演示 reg_rw_wmask (RW)

// ============================================================================
// reg_status Register Map  (BASE_ADDR = 0x2000)
// ============================================================================
`define REG_STATUS_FLAGS  16'h0000       // Live status flags             (RO)
  `define REG_STATUS_FLAGS_INIT_DONE    0
  `define REG_STATUS_FLAGS_CAL_DONE     1
  `define REG_STATUS_FLAGS_ERROR        2
  `define REG_STATUS_FLAGS_WARN         3
  `define REG_STATUS_FLAGS_BUSY         4

`define REG_STATUS_ERR_CNT  16'h0010     // Cumulative error count        (RO)
`define REG_STATUS_ERR_CODE 16'h0011     // Last error code               (RO)
`define REG_STATUS_ERR_CLR  16'h0012     // Clear error log               (W1C)

`define REG_STATUS_TEMP    16'h0020      // Die temperature (approx)      (RO)
`define REG_STATUS_VCC_INT  16'h0021     // Internal core voltage         (RO)
`define REG_STATUS_VCC_AUX  16'h0022     // Auxiliary voltage             (RO)

`define REG_STATUS_UPTIME_L 16'h0030     // Uptime counter low  [15:0]    (RO)
`define REG_STATUS_UPTIME_H 16'h0031     // Uptime counter high [31:16]   (RO)

`define REG_STATUS_ERR_STICKY 16'h0040   // Error sticky counter (RC)    演示 reg_rc

// ============================================================================
// reg_int Register Map  (BASE_ADDR = 0x6000)
// ============================================================================
`define REG_INT_STATUS    16'h0000       // Pending interrupts (after mask) (RO)
`define REG_INT_ENABLE    16'h0001       // Interrupt-enable bits          (RW)
`define REG_INT_MASK      16'h0002       // Interrupt-mask bits            (RW)
`define REG_INT_CLEAR     16'h0003       // Write-1-to-clear pending       (W1C)
`define REG_INT_EDGE      16'h0004       // Edge (1) / Level (0) select    (RW)
`define REG_INT_RAW       16'h0005       // Raw interrupt source           (RO)
`define REG_INT_VECTOR    16'h0006       // Highest-prio pending source #  (RO)

`define REG_INT_EN_WID    16
`define REG_INT_MASK_WID  16

// ============================================================================
// reg_iic Register Map  (BASE_ADDR = 0x3000)
// ============================================================================
`define REG_IIC_CTRL      16'h0000       // Control                        (RW)
`define REG_IIC_STATUS    16'h0001       // Status                         (RO)
`define REG_IIC_CLK_DIV   16'h0002       // Clock divider                  (RW)
`define REG_IIC_SLV_ADDR  16'h0003       // Slave address                  (RW)
`define REG_IIC_DATA_TX   16'h0004       // Transmit data                  (RW)
`define REG_IIC_DATA_RX   16'h0005       // Receive data                   (RO)
`define REG_IIC_CMD       16'h0006       // Command trigger                (RW)

// ============================================================================
// reg_spi Register Map  (BASE_ADDR = 0x4000)
// ============================================================================
`define REG_SPI_CTRL      16'h0000       // Control                        (RW)
`define REG_SPI_STATUS    16'h0001       // Status                         (RO)
`define REG_SPI_CLK_DIV   16'h0002       // Clock divider                  (RW)
`define REG_SPI_DATA_TX   16'h0003       // Transmit data                  (RW)
`define REG_SPI_DATA_RX   16'h0004       // Receive data                   (RO)
`define REG_SPI_CS_CTRL   16'h0005       // Chip-select control            (RW)
`define REG_SPI_CMD       16'h0006       // Command trigger                (RW)

// ============================================================================
// reg_ft Register Map  (BASE_ADDR = 0x5000)
// ============================================================================
`define REG_FT_CTRL       16'h0000       // Test mode control              (RW)
`define REG_FT_STATUS     16'h0001       // Test status                    (RO)
`define REG_FT_DATA_IN    16'h0010       // Test data input                (RW)
`define REG_FT_DATA_OUT   16'h0011       // Test data output               (RO)
`define REG_FT_LOOP_CNT   16'h0020       // Loop count                     (RW)

`endif // __REG_DEFINES_V__
