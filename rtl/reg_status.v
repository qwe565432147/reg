// ============================================================================
// reg_status.v — FPGA Status / Monitoring Registers
//
// Map region : 0x2000 – 0x2FFF
//
// Provides read‑only access to live FPGA status:
//   • Status flags (init done, calibration, error, warning, busy)
//   • Error count & last error code
//   • Temperature / voltage monitors (if sensor hardware exists)
//   • Uptime counter (free‑running, seconds)
//
// Error‑log registers support write‑1‑to‑clear via REG_STATUS_ERR_CLR.
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives compiled via file list (do not `include here)

module reg_status (
    // ---- Clock / Reset ----------------------------------------------------
    input                     clk,
    input                     rst_n,

    // ---- Bus Slave Interface ----------------------------------------------
    input                     cs,
    input                     we,
    input      [11:0]         addr,           // offset within region (12 b)
    input      [15:0]         wdata,
    output     [15:0]         rdata,
    output                    rdy,

    // ---- Status Flags (from FPGA fabric) ----------------------------------
    input                     init_done,
    input                     cal_done,
    input                     system_error,
    input                     system_warn,
    input                     system_busy,
    input      [15:0]         error_count,    // cumulative error count
    input      [15:0]         last_error_code,
    input      [15:0]         die_temp,       // 0.1 °C / LSB, signed
    input      [15:0]         vcc_int,
    input      [15:0]         vcc_aux,

    // ---- Uptime -----------------------------------------------------------
    input      [31:0]         uptime_sec,     // free‑running seconds counter

    // ---- Output: error clear pulse ----------------------------------------
    output                    error_clr_pulse  // pulsed when host clears error
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
    // Status flags assembly
    // -----------------------------------------------------------------------
    wire [15:0] status_flags;
    assign status_flags = {
        11'b0,
        system_busy,
        system_warn,
        system_error,
        cal_done,
        init_done
    };

    // -----------------------------------------------------------------------
    // Error‑clear W1C logic
    // -----------------------------------------------------------------------
    wire        err_clr_we;
    reg         err_clr_pulse;

    assign err_clr_we = write_active && (addr == `REG_STATUS_ERR_CLR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            err_clr_pulse <= 1'b0;
        else
            err_clr_pulse <= err_clr_we && (wdata[0] == 1'b1);
    end

    assign error_clr_pulse = err_clr_pulse;

    // -----------------------------------------------------------------------
    // 演示 ⑤ reg_rc —— 读后自动清零的寄存器
    //   • 硬件检测到 system_error 上升沿 → sticky 位置 1
    //   • 软件读取 REG_STATUS_ERR_STICKY → 读到当前值
    //   • 读完后硬件自动清零（不用软件额外写一次清除）
    // -----------------------------------------------------------------------
    // 先做一个 system_error 的上升沿检测
    reg  system_error_d;
    wire system_error_rise;

    always @(posedge clk) system_error_d <= system_error;
    assign system_error_rise = system_error & ~system_error_d;

    wire        err_sticky_rd;
    wire [15:0] err_sticky_rdata;

    assign err_sticky_rd = read_active && (addr == `REG_STATUS_ERR_STICKY);

    reg_rc #(.W(16), .INIT(16'h0000)) u_err_sticky (
        .clk         (clk),
        .rst_n       (rst_n),
        .set         ({15'b0, system_error_rise}),  // 硬件事件：错误上升沿
        .read_strobe (err_sticky_rd),              // 软件读 → 自动清零
        .rdata       (err_sticky_rdata)
    );

    // -----------------------------------------------------------------------
    // Read mux — combinatorial decode
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_STATUS_FLAGS     : rdata_mux = status_flags;
            `REG_STATUS_ERR_CNT   : rdata_mux = error_count;
            `REG_STATUS_ERR_CODE  : rdata_mux = last_error_code;
            `REG_STATUS_ERR_CLR   : rdata_mux = 16'h0000;  // WO
            `REG_STATUS_TEMP      : rdata_mux = die_temp;
            `REG_STATUS_VCC_INT   : rdata_mux = vcc_int;
            `REG_STATUS_VCC_AUX   : rdata_mux = vcc_aux;
            `REG_STATUS_UPTIME_L  : rdata_mux = uptime_sec[15:0];
            `REG_STATUS_UPTIME_H  : rdata_mux = uptime_sec[31:16];
            `REG_STATUS_ERR_STICKY : rdata_mux = err_sticky_rdata;
            default                : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;

endmodule
