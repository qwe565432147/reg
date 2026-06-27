// ============================================================================
// reg_top.v — Top‑Level Register Map Integration
//
// Implements a 16‑bit register management architecture with partitioned
// address regions.  The top module provides:
//
//   1. Single‑cycle bus slave interface (read / write)
//   2. Address decoder — maps upper address bits to region chip‑selects
//   3. Read‑data mux — gathers region read data onto a single bus_rdata
//   4. Error generation — bus_err asserted on access to unmapped address
//   5. Interrupt aggregation — combines all region interrupts
//
// Bus Protocol (single‑cycle, no wait states):
//   Read  : bus_req=1, bus_we=0, bus_addr=<addr>
//           → bus_rdata valid the SAME cycle (combinatorial decode)
//   Write : bus_req=1, bus_we=1, bus_addr=<addr>, bus_wdata=<data>
//           → registered at the next rising clock edge
//   rdy   : always 1 (single‑cycle)
//   err   : combinatorial, asserted when addr does not fall in any region
//
// === Adding a new region ===
//   In this file, four things need to change (each is 1-3 lines):
//     1. Add `include for the new module header
//     2. Add a reg_sel_<name> wire in the decoder section
//     3. Instantiate the region module
//     4. Add one case item to the rdata mux
// ============================================================================

`include "reg_defines.v"
// Sub-modules (reg_base, reg_status, reg_iic, reg_spi, reg_ft, reg_int)
// are compiled via the file list, NOT `included.
// reg_slice primitives are also compiled via the file list.

module reg_top (
    // =======================================================================
    // Clock & Reset
    // =======================================================================
    input                     clk,
    input                     rst_n,

    // =======================================================================
    // Bus Slave Interface  (single‑cycle, combinatorial read)
    // =======================================================================
    input      [15:0]         bus_addr,       // word address
    input      [15:0]         bus_wdata,      // write data
    input                     bus_req,        // request strobe
    input                     bus_we,         // 1 = write, 0 = read
    output reg [15:0]         bus_rdata,      // read data
    output                    bus_rdy,        // ready (always 1)
    output                    bus_err,        // unmapped address error

    // =======================================================================
    // Interrupt
    // =======================================================================
    output                    irq,            // combined interrupt to CPU
    input      [15:0]         intr_sources,   // 16 interrupt sources

    // =======================================================================
    // reg_base — Version / ID / Scratch
    // =======================================================================
    input      [7:0]          ver_major,
    input      [7:0]          ver_minor,
    input      [15:0]         chip_id,
    input      [15:0]         build_year,
    input      [7:0]          build_month,
    input      [7:0]          build_day,
    input      [31:0]         git_sha,
    input      [15:0]         features,
    output     [15:0]         scratch,

    // =======================================================================
    // reg_status — FPGA Status & Monitoring
    // =======================================================================
    input                     init_done,
    input                     cal_done,
    input                     system_error,
    input                     system_warn,
    input                     system_busy,
    input      [15:0]         error_count,
    input      [15:0]         last_error_code,
    input      [15:0]         die_temp,
    input      [15:0]         vcc_int,
    input      [15:0]         vcc_aux,
    input      [31:0]         uptime_sec,
    output                    error_clr_pulse,

    // =======================================================================
    // reg_iic — I2C Hardware Interface
    // =======================================================================
    output                    iic_enable,
    output                    iic_loopback,
    output                    iic_reset,
    input                     iic_busy,
    input                     iic_ack_err,
    output     [15:0]         iic_clk_div,
    output     [6:0]          iic_slave_addr,
    output     [7:0]          iic_tx_data,
    input      [7:0]          iic_rx_data,
    input                     iic_tx_done,
    output                    iic_start,
    output                    iic_stop,
    output                    iic_read,
    output                    iic_write,

    // =======================================================================
    // reg_spi — SPI Hardware Interface
    // =======================================================================
    output                    spi_enable,
    output     [1:0]          spi_mode,
    output                    spi_loopback,
    input                     spi_busy,
    output     [15:0]         spi_clk_div,
    output     [15:0]         spi_tx_data,
    input      [15:0]         spi_rx_data,
    output     [7:0]          spi_cs_ctrl,
    output                    spi_start,

    // =======================================================================
    // reg_ft — Factory Test Interface
    // =======================================================================
    output                    test_mode,
    output                    test_loopback,
    output                    bist_start,
    input                     bist_busy,
    input                     bist_pass,
    input                     bist_fail,
    output     [15:0]         test_data_in,
    input      [15:0]         test_data_out,
    output     [15:0]         loop_count
);

    // =======================================================================
    // Address Decoder
    //
    //   每个区域用 _AMSB 定义译码边界。通用公式：
    //     reg_sel_xxx = (bus_addr[15:AMSB] == REG_XXX_ADDR[15:AMSB])
    //
    //   这样改 REG_XXX_ADDR 或重新分配区域时，译码器自动跟随，无需手改。
    //
    //   Reg.      AMSB  addr[15:AMSB]  base[15:AMSB]
    //   ───────  ────  ─────────────  ─────────────
    //   base       13   [15:13] 3bit   3'b000         0x0000
    //   status     12   [15:12] 4bit   4'b0010         0x2000
    //   iic        12   [15:12] 4bit   4'b0011         0x3000
    //   spi        12   [15:12] 4bit   4'b0100         0x4000
    //   ft         12   [15:12] 4bit   4'b0101         0x5000
    //   int        12   [15:12] 4bit   4'b0110         0x6000
    //   (hole)     12   [15:12] 4bit   4'b0111         ← 保留
    //   (hole)     15   [15]    1bit   1'b1            ← 未来大块
    // =======================================================================

    // -- Decode compare values (wire wrappers, Verilog不允许对常量做位选) -------
    wire [15:0] dec_base_addr   = `REG_BASE_ADDR;
    wire [15:0] dec_status_addr = `REG_STATUS_ADDR;
    wire [15:0] dec_iic_addr    = `REG_IIC_ADDR;
    wire [15:0] dec_spi_addr    = `REG_SPI_ADDR;
    wire [15:0] dec_ft_addr     = `REG_FT_ADDR;
    wire [15:0] dec_int_addr    = `REG_INT_ADDR;

    // -- Select lines (combinatorial, AMSB‑driven) --------------------------
    wire  reg_sel_base   = (bus_addr[15:`REG_BASE_AMSB]   == dec_base_addr[15:`REG_BASE_AMSB]);
    wire  reg_sel_status = (bus_addr[15:`REG_STATUS_AMSB] == dec_status_addr[15:`REG_STATUS_AMSB]);
    wire  reg_sel_iic    = (bus_addr[15:`REG_IIC_AMSB]    == dec_iic_addr[15:`REG_IIC_AMSB]);
    wire  reg_sel_spi    = (bus_addr[15:`REG_SPI_AMSB]    == dec_spi_addr[15:`REG_SPI_AMSB]);
    wire  reg_sel_ft     = (bus_addr[15:`REG_FT_AMSB]    == dec_ft_addr[15:`REG_FT_AMSB]);
    wire  reg_sel_int    = (bus_addr[15:`REG_INT_AMSB]    == dec_int_addr[15:`REG_INT_AMSB]);

    // -- Any region selected? ------------------------------------------------
    wire  reg_sel_any    = reg_sel_base  | reg_sel_status |
                           reg_sel_iic   | reg_sel_spi    |
                           reg_sel_ft    | reg_sel_int;

    assign bus_rdy = bus_req;           // single‑cycle, always ready
    assign bus_err = bus_req & ~reg_sel_any;  // error on unmapped access

    // -- Offset addresses for each region (lower bits) -----------------------
    wire [12:0] base_addr   = bus_addr[12:0];
    wire [11:0] status_addr = bus_addr[11:0];
    wire [11:0] iic_addr    = bus_addr[11:0];
    wire [11:0] spi_addr    = bus_addr[11:0];
    wire [11:0] ft_addr     = bus_addr[11:0];
    wire [11:0] int_addr    = bus_addr[11:0];

    // =======================================================================
    // Region Module Instantiations
    // =======================================================================

    // ----- reg_base : Version / ID / Scratch --------------------------------
    wire [15:0] base_rdata;
    wire        base_rdy;

    reg_base u_reg_base (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (reg_sel_base & bus_req),
        .we           (bus_we),
        .addr         (base_addr),
        .wdata        (bus_wdata),
        .rdata        (base_rdata),
        .rdy          (base_rdy),
        .ver_major    (ver_major),
        .ver_minor    (ver_minor),
        .chip_id      (chip_id),
        .build_year   (build_year),
        .build_month  (build_month),
        .build_day    (build_day),
        .git_sha      (git_sha),
        .features     (features),
        .scratch      (scratch)
    );

    // ----- reg_status : FPGA Status ----------------------------------------
    wire [15:0] status_rdata;
    wire        status_rdy;

    reg_status u_reg_status (
        .clk             (clk),
        .rst_n           (rst_n),
        .cs              (reg_sel_status & bus_req),
        .we              (bus_we),
        .addr            (status_addr),
        .wdata           (bus_wdata),
        .rdata           (status_rdata),
        .rdy             (status_rdy),
        .init_done       (init_done),
        .cal_done        (cal_done),
        .system_error    (system_error),
        .system_warn     (system_warn),
        .system_busy     (system_busy),
        .error_count     (error_count),
        .last_error_code (last_error_code),
        .die_temp        (die_temp),
        .vcc_int         (vcc_int),
        .vcc_aux         (vcc_aux),
        .uptime_sec      (uptime_sec),
        .error_clr_pulse (error_clr_pulse)
    );

    // ----- reg_iic : I2C Controller ----------------------------------------
    wire [15:0] iic_rdata;
    wire        iic_rdy;

    reg_iic u_reg_iic (
        .clk            (clk),
        .rst_n          (rst_n),
        .cs             (reg_sel_iic & bus_req),
        .we             (bus_we),
        .addr           (iic_addr),
        .wdata          (bus_wdata),
        .rdata          (iic_rdata),
        .rdy            (iic_rdy),
        .iic_enable_o   (iic_enable),
        .iic_loopback_o (iic_loopback),
        .iic_reset_o    (iic_reset),
        .iic_busy_i     (iic_busy),
        .iic_ack_err_i  (iic_ack_err),
        .iic_clk_div_o  (iic_clk_div),
        .iic_slave_addr_o(iic_slave_addr),
        .iic_tx_data_o  (iic_tx_data),
        .iic_rx_data_i  (iic_rx_data),
        .iic_tx_done_i  (iic_tx_done),
        .iic_start_o    (iic_start),
        .iic_stop_o     (iic_stop),
        .iic_read_o     (iic_read),
        .iic_write_o    (iic_write)
    );

    // ----- reg_spi : SPI Controller ----------------------------------------
    wire [15:0] spi_rdata;
    wire        spi_rdy;

    reg_spi u_reg_spi (
        .clk             (clk),
        .rst_n           (rst_n),
        .cs              (reg_sel_spi & bus_req),
        .we              (bus_we),
        .addr            (spi_addr),
        .wdata           (bus_wdata),
        .rdata           (spi_rdata),
        .rdy             (spi_rdy),
        .spi_enable_o    (spi_enable),
        .spi_mode_o      (spi_mode),
        .spi_loopback_o  (spi_loopback),
        .spi_busy_i      (spi_busy),
        .spi_clk_div_o   (spi_clk_div),
        .spi_tx_data_o   (spi_tx_data),
        .spi_rx_data_i   (spi_rx_data),
        .spi_cs_ctrl_o   (spi_cs_ctrl),
        .spi_start_o     (spi_start)
    );

    // ----- reg_ft : Factory Test -------------------------------------------
    wire [15:0] ft_rdata;
    wire        ft_rdy;

    reg_ft u_reg_ft (
        .clk             (clk),
        .rst_n           (rst_n),
        .cs              (reg_sel_ft & bus_req),
        .we              (bus_we),
        .addr            (ft_addr),
        .wdata           (bus_wdata),
        .rdata           (ft_rdata),
        .rdy             (ft_rdy),
        .test_mode_o     (test_mode),
        .test_loopback_o (test_loopback),
        .bist_start_o    (bist_start),
        .bist_busy_i     (bist_busy),
        .bist_pass_i     (bist_pass),
        .bist_fail_i     (bist_fail),
        .test_data_in_o  (test_data_in),
        .test_data_out_i (test_data_out),
        .loop_count_o    (loop_count)
    );

    // ----- reg_int : Interrupt Controller ----------------------------------
    wire [15:0] int_rdata;
    wire        int_rdy;

    reg_int u_reg_int (
        .clk            (clk),
        .rst_n          (rst_n),
        .cs             (reg_sel_int & bus_req),
        .we             (bus_we),
        .addr           (int_addr),
        .wdata          (bus_wdata),
        .rdata          (int_rdata),
        .rdy            (int_rdy),
        .intr_sources   (intr_sources),
        .irq_o          (irq)
    );

    // =======================================================================
    // Read‑Data Mux  (combinatorial, priority encoded)
    //
    //   bus_rdata is flopped at the end of mux for clean timing.
    // =======================================================================
    always @(*) begin
        case (1'b1)
            reg_sel_base   : bus_rdata = base_rdata;
            reg_sel_status : bus_rdata = status_rdata;
            reg_sel_iic    : bus_rdata = iic_rdata;
            reg_sel_spi    : bus_rdata = spi_rdata;
            reg_sel_ft     : bus_rdata = ft_rdata;
            reg_sel_int    : bus_rdata = int_rdata;
            default        : bus_rdata = 16'h0000;
        endcase
    end

endmodule
