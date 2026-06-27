// ============================================================================
// reg_ft.v — Factory / Test Registers  (Template / Skeleton)
//
// Map region : 0x5000 – 0x5FFF
//
// Provides basic test‑mode control, loopback data paths, and loop counting
// for production‑line or self‑test scenarios.
//
// Register map (relative to 0x5000):
//   0x0000  FT_CTRL         RW   Test control
//   0x0001  FT_STATUS       RO   Test status
//   0x0010  FT_DATA_IN      RW   Test data input
//   0x0011  FT_DATA_OUT     RO   Test data output
//   0x0020  FT_LOOP_CNT     RW   Loop count for BIST
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives compiled via file list (do not `include here)

module reg_ft (
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

    // ---- Test Hardware Interface (template) -------------------------------
    output                    test_mode_o,
    output                    test_loopback_o,
    output                    bist_start_o,
    input                     bist_busy_i,
    input                     bist_pass_i,
    input                     bist_fail_i,
    output     [15:0]         test_data_in_o,
    input      [15:0]         test_data_out_i,
    output     [15:0]         loop_count_o
);

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    reg        [15:0]         rdata_mux;
    wire                      write_active;

    assign write_active = cs & we;

    // -----------------------------------------------------------------------
    // FT_CTRL (0x0000) : RW
    //   [0]  test_mode
    //   [1]  loopback
    //   [2]  bist_start  (self‑clearing pulse)
    // -----------------------------------------------------------------------
    wire [15:0] ctrl_rdata;
    wire        ctrl_we;
    reg  [15:0] ctrl_val;

    assign ctrl_we = write_active && (addr == `REG_FT_CTRL);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ctrl_val <= 16'h0000;
        else if (ctrl_we)
            ctrl_val <= {13'h0, wdata[2:0]};
        else
            ctrl_val[2] <= 1'b0;   // bist_start self‑clears
    end

    assign ctrl_rdata = ctrl_val;

    assign test_mode_o    = ctrl_val[0];
    assign test_loopback_o = ctrl_val[1];
    assign bist_start_o   = ctrl_val[2];

    // -----------------------------------------------------------------------
    // FT_DATA_IN (0x0010) : RW
    // -----------------------------------------------------------------------
    wire [15:0] din_rdata;
    wire        din_we;
    reg  [15:0] din_val;

    assign din_we = write_active && (addr == `REG_FT_DATA_IN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            din_val <= 16'h0000;
        else if (din_we)
            din_val <= wdata;
    end

    assign din_rdata = din_val;
    assign test_data_in_o = din_val;

    // -----------------------------------------------------------------------
    // FT_LOOP_CNT (0x0020) : RW
    // -----------------------------------------------------------------------
    wire [15:0] loop_rdata;
    wire        loop_we;
    reg  [15:0] loop_val;

    assign loop_we = write_active && (addr == `REG_FT_LOOP_CNT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            loop_val <= 16'h0000;
        else if (loop_we)
            loop_val <= wdata;
    end

    assign loop_rdata = loop_val;
    assign loop_count_o = loop_val;

    // -----------------------------------------------------------------------
    // Read mux
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_FT_CTRL        : rdata_mux = ctrl_rdata;
            `REG_FT_STATUS      : rdata_mux = {13'b0, bist_fail_i, bist_pass_i, bist_busy_i};
            `REG_FT_DATA_IN     : rdata_mux = din_rdata;
            `REG_FT_DATA_OUT    : rdata_mux = test_data_out_i;
            `REG_FT_LOOP_CNT    : rdata_mux = loop_rdata;
            default                : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;

endmodule
