// ============================================================================
// reg_iic.v — I2C Controller Registers  (Template / Skeleton)
//
// Map region : 0x3000 – 0x3FFF
//
// This file is a template showing the standard region‑module structure.
// Replace the stub logic with your I2C controller implementation.
//
// Register map (relative to 0x3000):
//   0x0000  IIC_CTRL     RW   Control (enable, loopback, reset)
//   0x0001  IIC_STATUS   RO   Status (busy, ack, error)
//   0x0002  IIC_CLK_DIV  RW   SCL clock divider
//   0x0003  IIC_ADDR     RW   Slave address (7‑ or 10‑bit)
//   0x0004  IIC_DATA_TX  RW   Transmit data register
//   0x0005  IIC_DATA_RX  RO   Receive data register
//   0x0006  IIC_CMD      RW   Command trigger (START, STOP, RD, WR)
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives are compiled via the file list (do not `include here)

module reg_iic (
    // ---- Clock / Reset ----------------------------------------------------
    input                     clk,
    input                     rst_n,

    // ---- Bus Slave Interface ----------------------------------------------
    input                     cs,
    input                     we,
    input      [11:0]         addr,           // offset within region
    input      [15:0]         wdata,
    output     [15:0]         rdata,
    output                    rdy,

    // ---- I2C Hardware Interface (template) --------------------------------
    // Replace / extend with your I2C core ports
    output                    iic_enable_o,
    output                    iic_loopback_o,
    output                    iic_reset_o,
    input                     iic_busy_i,
    input                     iic_ack_err_i,
    output     [15:0]         iic_clk_div_o,
    output     [6:0]          iic_slave_addr_o,
    output     [7:0]          iic_tx_data_o,
    input      [7:0]          iic_rx_data_i,
    input                     iic_tx_done_i,
    output                    iic_start_o,
    output                    iic_stop_o,
    output                    iic_read_o,
    output                    iic_write_o
);

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    reg        [15:0]         rdata_mux;

    wire                      read_active;
    wire                      write_active;

    assign read_active  = cs & ~we;
    assign write_active = cs &  we;

    // -----------------------------------------------------------------------
    // IIC_CTRL (0x0000) : RW
    //   [0]    enable
    //   [1]    loopback
    //   [15]   soft reset
    // -----------------------------------------------------------------------
    wire [15:0] ctrl_rdata;
    wire        ctrl_we;
    reg  [15:0] ctrl_val;

    assign ctrl_we = write_active && (addr == `REG_IIC_CTRL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ctrl_val <= 16'h0000;
        else if (ctrl_we)
            ctrl_val <= wdata;
        else
            ctrl_val[15] <= 1'b0;   // reset bit self‑clears
    end

    assign ctrl_rdata = ctrl_val;

    assign iic_enable_o  = ctrl_val[0];
    assign iic_loopback_o = ctrl_val[1];
    assign iic_reset_o    = ctrl_val[15];

    // -----------------------------------------------------------------------
    // IIC_CLK_DIV (0x0002) : RW
    // -----------------------------------------------------------------------
    wire [15:0] clkdiv_rdata;
    wire        clkdiv_we;
    reg  [15:0] clkdiv_val;

    assign clkdiv_we = write_active && (addr == `REG_IIC_CLK_DIV);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clkdiv_val <= 16'h00FF;
        else if (clkdiv_we)
            clkdiv_val <= wdata;
    end

    assign clkdiv_rdata = clkdiv_val;
    assign iic_clk_div_o = clkdiv_val;

    // -----------------------------------------------------------------------
    // IIC_ADDR (0x0003) : RW
    // -----------------------------------------------------------------------
    wire [15:0] addr_rdata;
    wire        addr_we;
    reg  [15:0] addr_val;

    assign addr_we = write_active && (addr == `REG_IIC_SLV_ADDR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            addr_val <= 16'h0000;
        else if (addr_we)
            addr_val <= wdata;
    end

    assign addr_rdata = addr_val;
    assign iic_slave_addr_o = addr_val[6:0];

    // -----------------------------------------------------------------------
    // IIC_DATA_TX (0x0004) : RW
    // -----------------------------------------------------------------------
    wire [15:0] txdata_rdata;
    wire        txdata_we;
    reg  [15:0] txdata_val;

    assign txdata_we = write_active && (addr == `REG_IIC_DATA_TX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            txdata_val <= 16'h0000;
        else if (txdata_we)
            txdata_val <= wdata;
    end

    assign txdata_rdata = txdata_val;
    assign iic_tx_data_o = txdata_val[7:0];

    // -----------------------------------------------------------------------
    // IIC_CMD (0x0006) : RW — write to trigger command
    //   [0] START
    //   [1] STOP
    //   [2] READ
    //   [3] WRITE
    // -----------------------------------------------------------------------
    wire [15:0] cmd_rdata;
    wire        cmd_we;
    reg  [15:0] cmd_val;

    assign cmd_we = write_active && (addr == `REG_IIC_CMD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cmd_val <= 16'h0000;
        else
            cmd_val <= {13'h0, cmd_we ? wdata[3:0] : 4'h0};  // pulse
    end

    assign cmd_rdata = cmd_val;

    assign iic_start_o = cmd_val[0];
    assign iic_stop_o  = cmd_val[1];
    assign iic_read_o  = cmd_val[2];
    assign iic_write_o = cmd_val[3];

    // -----------------------------------------------------------------------
    // Read mux
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_IIC_CTRL      : rdata_mux = ctrl_rdata;
            `REG_IIC_STATUS    : rdata_mux = {14'b0, iic_tx_done_i, iic_busy_i};
            `REG_IIC_CLK_DIV   : rdata_mux = clkdiv_rdata;
            `REG_IIC_SLV_ADDR      : rdata_mux = addr_rdata;
            `REG_IIC_DATA_TX   : rdata_mux = txdata_rdata;
            `REG_IIC_DATA_RX   : rdata_mux = {8'b0, iic_rx_data_i};
            `REG_IIC_CMD       : rdata_mux = cmd_rdata;
            default                  : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;

endmodule
