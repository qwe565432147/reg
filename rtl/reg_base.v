// ============================================================================
// reg_base.v — Base / Version Information Registers
//
// Map region : 0x0000 – 0x1FFF
//
// Provides:
//   • Version register (major / minor)
//   • Chip / FPGA unique ID
//   • Build date (year / month / day)
//   • Git SHA (64 bit, two registers)
//   • Scratch register for firmware scratch pad
//   • Feature bitmap
//
// Interface:
//   All registers use the standard reg_slave_intf (see reg_top.v).
//   The module is purely register‑based — no ongoing hardware logic.
//   RO registers are parameter‑driven at elaboration time.
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives compiled via file list (do not `include here)

module reg_base (
    // ---- Clock / Reset ----------------------------------------------------
    input                     clk,
    input                     rst_n,

    // ---- Bus Slave Interface ----------------------------------------------
    input                     cs,             // chip select (decoded by top)
    input                     we,             // 1 = write, 0 = read
    input      [12:0]         addr,           // offset within region (13 b)
    input      [15:0]         wdata,          // write data
    output     [15:0]         rdata,          // read data
    output                    rdy,            // ready (always 1)

    // ---- Version / ID Parameters (connect at instantiation) ---------------
    input      [7:0]          ver_major,      // version major
    input      [7:0]          ver_minor,      // version minor
    input      [15:0]         chip_id,        // chip / FPGA ID
    input      [15:0]         build_year,     // e.g. 0x07E6 (2026)
    input      [7:0]          build_month,    // e.g. 0x06
    input      [7:0]          build_day,      // e.g. 0x1C
    input      [31:0]         git_sha,        // git SHA short
    input      [15:0]         features,       // feature bitmap

    // ---- Hardware Interface -----------------------------------------------
    output reg [15:0]         scratch         // scratch register value
);

    // -----------------------------------------------------------------------
    // Internal wires
    // -----------------------------------------------------------------------
    reg        [15:0]         rdata_mux;
    wire                      read_active;
    wire                      write_active;

    // -----------------------------------------------------------------------
    // Decode helpers
    // -----------------------------------------------------------------------
    assign read_active  = cs & ~we;
    assign write_active = cs &  we;

    // -----------------------------------------------------------------------
    // Register field instantiations
    // -----------------------------------------------------------------------

    // -- REG_BASE_VER (0x0000) : RO — version
    wire [15:0] ver_val;
    assign ver_val = {ver_major, ver_minor};

    // -- REG_BASE_CHIP_ID (0x0001) : RO — chip / FPGA ID
    // -- REG_BASE_BUILD_Y  (0x0002) : RO — build year
    // -- REG_BASE_BUILD_M  (0x0003) : RO — build month
    // -- REG_BASE_BUILD_D  (0x0004) : RO — build day
    // -- REG_BASE_GIT_SHA  (0x0005) : RO — git SHA [15:0]
    // -- REG_BASE_GIT_SHA2 (0x0006) : RO — git SHA [31:16]

    // -- REG_BASE_SCRATCH (0x0010) : RW — scratch
    wire        scratch_we;
    wire [15:0] scratch_rdata;
    reg_rw #(.W(16), .INIT(16'h0000)) u_scratch (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (scratch_we),
        .wdata (wdata),
        .rdata (scratch_rdata)
    );

    assign scratch_we = write_active && (addr == `REG_BASE_SCRATCH);

    // scratch output = register value (driven by reg_rw above)
    assign scratch = scratch_rdata;

    // -----------------------------------------------------------------------
    // 演示 ① reg_ro —— 把 features 封装为只读寄存器模块
    // reg_ro 只是组合逻辑直通（assign rdata = din），但模块化后接口统一
    // -----------------------------------------------------------------------
    wire [15:0] features_rdata;
    reg_ro #(.W(16)) u_features (
        .din   (features),
        .rdata (features_rdata)
    );

    // -----------------------------------------------------------------------
    // 演示 ② reg_rw_wmask —— 带位掩码的控制寄存器
    // 软件写控制位时，只更新 wmask 指定的位，其他位保持不动
    //   位 [0] : feature_A 使能
    //   位 [1] : feature_B 使能
    //   位 [2] : 保留（软件不能改，wmask 恒为 0）
    //   位 [3] : 保留（软件不能改，wmask 恒为 0）
    // -----------------------------------------------------------------------
    wire        ctrl_we;
    wire [15:0] ctrl_rdata;
    wire [15:0] ctrl_wmask;
    assign ctrl_we   = write_active && (addr == `REG_BASE_CTRL);
    assign ctrl_wmask = 16'h0003;      // 只允许软件改 bit[0] 和 bit[1]

    reg_rw_wmask #(.W(16), .INIT(16'h0000)) u_ctrl (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (ctrl_we),
        .wdata (wdata),
        .wmask (ctrl_wmask),
        .rdata (ctrl_rdata)
    );

    // -----------------------------------------------------------------------
    // 演示 ③ reg_rsvd —— 用保留寄存器填充地址空洞
    // 地址 0x0007~0x000F 是未用的空洞，放 rsvd 防止读 X
    // -----------------------------------------------------------------------
    wire [15:0] rsvd_0008_rdata;
    reg_rsvd #(.W(16)) u_rsvd_0008 ();
    // 可以放多个，这里只演示一个

    // -----------------------------------------------------------------------
    // Read mux — combinatorial decode
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_BASE_VER       : rdata_mux = ver_val;
            `REG_BASE_CHIP_ID   : rdata_mux = chip_id;
            `REG_BASE_BUILD_Y   : rdata_mux = build_year;
            `REG_BASE_BUILD_M   : rdata_mux = {8'b0, build_month};
            `REG_BASE_BUILD_D   : rdata_mux = {8'b0, build_day};
            `REG_BASE_GIT_SHA   : rdata_mux = git_sha[15:0];
            `REG_BASE_GIT_SHA2  : rdata_mux = git_sha[31:16];
            `REG_BASE_SCRATCH   : rdata_mux = scratch_rdata;
            `REG_BASE_FEATURES  : rdata_mux = features_rdata;  // ← 改用 reg_ro 输出
            `REG_BASE_CTRL      : rdata_mux = ctrl_rdata;
            default             : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;    // single‑cycle response

endmodule
