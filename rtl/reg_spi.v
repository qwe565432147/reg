// ============================================================================
// reg_spi.v — SPI Controller Registers  (Template / Skeleton)
//
// Map region : 0x4000 – 0x4FFF
//
// Register map (relative to 0x4000):
//   0x0000  SPI_CTRL      RW   Control (enable, mode, loopback)
//   0x0001  SPI_STATUS    RO   Status (busy, tx_empty, rx_full, error)
//   0x0002  SPI_CLK_DIV   RW   SCK clock divider
//   0x0003  SPI_DATA_TX   RW   Transmit data register
//   0x0004  SPI_DATA_RX   RO   Receive data register
//   0x0005  SPI_CS_CTRL   RW   Chip‑select control
//   0x0006  SPI_CMD       RW   Command trigger
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives compiled via file list (do not `include here)

module reg_spi (
    // ---- Clock / Reset ----------------------------------------------------
    input                     clk,
    input                     rst_n,

    // ---- Bus Slave Interface ----------------------------------------------
    input                     cs,
    input                     we,
    input      [11:0]         addr,
    input      [15:0]         wdata,
    output     [15:0]         rdata,
    output                    rdy,

    // ---- SPI Hardware Interface (template) --------------------------------
    output                    spi_enable_o,
    output     [1:0]          spi_mode_o,         // 00:CPOL0/CPHA0, ...
    output                    spi_loopback_o,
    input                     spi_busy_i,
    output     [15:0]         spi_clk_div_o,
    output     [15:0]         spi_tx_data_o,
    input      [15:0]         spi_rx_data_i,
    output     [7:0]          spi_cs_ctrl_o,      // CS lines control
    output                    spi_start_o
);

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    reg        [15:0]         rdata_mux;
    wire                      write_active;

    assign write_active = cs & we;

    // -----------------------------------------------------------------------
    // SPI_CTRL (0x0000) : RW
    // -----------------------------------------------------------------------
    wire [15:0] ctrl_rdata;
    wire        ctrl_we;
    reg  [15:0] ctrl_val;

    assign ctrl_we = write_active && (addr == `REG_SPI_CTRL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ctrl_val <= 16'h0000;
        else if (ctrl_we)
            ctrl_val <= wdata;
    end

    assign ctrl_rdata = ctrl_val;

    assign spi_enable_o  = ctrl_val[0];
    assign spi_mode_o    = ctrl_val[2:1];
    assign spi_loopback_o = ctrl_val[3];

    // -----------------------------------------------------------------------
    // SPI_CLK_DIV (0x0002) : RW
    // -----------------------------------------------------------------------
    wire [15:0] clkdiv_rdata;
    wire        clkdiv_we;
    reg  [15:0] clkdiv_val;

    assign clkdiv_we = write_active && (addr == `REG_SPI_CLK_DIV);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clkdiv_val <= 16'h0008;
        else if (clkdiv_we)
            clkdiv_val <= wdata;
    end

    assign clkdiv_rdata = clkdiv_val;
    assign spi_clk_div_o = clkdiv_val;

    // -----------------------------------------------------------------------
    // SPI_DATA_TX (0x0003) : RW
    // -----------------------------------------------------------------------
    wire [15:0] txdata_rdata;
    wire        txdata_we;
    reg  [15:0] txdata_val;

    assign txdata_we = write_active && (addr == `REG_SPI_DATA_TX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            txdata_val <= 16'h0000;
        else if (txdata_we)
            txdata_val <= wdata;
    end

    assign txdata_rdata = txdata_val;
    assign spi_tx_data_o = txdata_val;

    // -----------------------------------------------------------------------
    // SPI_CS_CTRL (0x0005) : RW
    // -----------------------------------------------------------------------
    wire [15:0] csctrl_rdata;
    wire        csctrl_we;
    reg  [15:0] csctrl_val;

    assign csctrl_we = write_active && (addr == `REG_SPI_CS_CTRL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            csctrl_val <= 16'h0001;     // CS0 active
        else if (csctrl_we)
            csctrl_val <= wdata;
    end

    assign csctrl_rdata = csctrl_val;
    assign spi_cs_ctrl_o = csctrl_val[7:0];

    // -----------------------------------------------------------------------
    // SPI_CMD (0x0006) : RW — write to trigger
    // -----------------------------------------------------------------------
    wire [15:0] cmd_rdata;
    wire        cmd_we;

    reg_pulse #(.W(1)) u_start_pulse (
        .clk   (clk),
        .rst_n (rst_n),
        .din   (cmd_we && wdata[0]),
        .dout  (spi_start_o)
    );

    assign cmd_we = write_active && (addr == `REG_SPI_CMD);
    assign cmd_rdata = 16'h0000;

    // -----------------------------------------------------------------------
    // Read mux
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_SPI_CTRL        : rdata_mux = ctrl_rdata;
            `REG_SPI_STATUS      : rdata_mux = {15'b0, spi_busy_i};
            `REG_SPI_CLK_DIV     : rdata_mux = clkdiv_rdata;
            `REG_SPI_DATA_TX     : rdata_mux = txdata_rdata;
            `REG_SPI_DATA_RX     : rdata_mux = spi_rx_data_i;
            `REG_SPI_CS_CTRL     : rdata_mux = csctrl_rdata;
            `REG_SPI_CMD         : rdata_mux = cmd_rdata;
            default                 : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;

endmodule
