// ============================================================================
// reg_int.v — Interrupt Controller Registers
//
// Map region : 0x6000 – 0x6FFF
//
// Implements a flexible interrupt controller with 16 interrupt sources.
// Each source can be configured as edge‑sensitive or level‑sensitive.
//
// Register map (relative to 0x6000):
//   Offset  | Name         | Access | Description
//   --------+--------------+--------+------------------------------------------
//   0x0000  | INT_STATUS   |  RO    | Pending interrupts (enabled & unmasked)
//   0x0001  | INT_ENABLE   |  RW    | Enable each source
//   0x0002  | INT_MASK     |  RW    | Mask each source (1 = masked)
//   0x0003  | INT_CLEAR    |  W1C   | Clear pending (write 1 to bit)
//   0x0004  | INT_EDGE     |  RW    | 1 = edge‑triggered, 0 = level‑triggered
//   0x0005  | INT_RAW      |  RO    | Raw interrupt source state
//   0x0006  | INT_VECTOR   |  RO    | Highest‑priority pending source index
//
// Interrupt flow:
//   1. Source asserts → raw capture (edge detect if edge‑mode)
//   2. Raw captured in pending register
//   3. Pending & Enable & ~Mask → status
//   4. Status != 0 → irq_o asserted
//   5. Software reads INT_VECTOR, services interrupt, writes INT_CLEAR
// ============================================================================

`include "reg_defines.v"
// reg_slice primitives compiled via file list (do not `include here)

module reg_int (
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

    // ---- Interrupt Sources (from FPGA fabric) -----------------------------
    input      [15:0]         intr_sources,   // 16 interrupt lines

    // ---- Interrupt Output -------------------------------------------------
    output                    irq_o           // combined interrupt to CPU
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
    // Register instances — all use reg_rw primitives from reg_slice.v
    // -----------------------------------------------------------------------

    // INT_ENABLE (0x0001) : RW
    wire [15:0] enable_rdata;
    wire        enable_we;

    reg_rw #(.W(16), .INIT(16'h0000)) u_int_enable (
        .clk  (clk),
        .rst_n(rst_n),
        .load (enable_we),
        .wdata(wdata),
        .rdata(enable_rdata)
    );
    assign enable_we = write_active && (addr == `REG_INT_ENABLE);

    // INT_MASK (0x0002) : RW
    wire [15:0] mask_rdata;
    wire        mask_we;

    reg_rw #(.W(16), .INIT(16'h0000)) u_int_mask (
        .clk  (clk),
        .rst_n(rst_n),
        .load (mask_we),
        .wdata(wdata),
        .rdata(mask_rdata)
    );
    assign mask_we = write_active && (addr == `REG_INT_MASK);

    // INT_EDGE (0x0004) : RW — edge vs level select
    wire [15:0] edge_rdata;
    wire        edge_we;

    reg_rw #(.W(16), .INIT(16'h0000)) u_int_edge (
        .clk  (clk),
        .rst_n(rst_n),
        .load (edge_we),
        .wdata(wdata),
        .rdata(edge_rdata)
    );
    assign edge_we = write_active && (addr == `REG_INT_EDGE);

    // -----------------------------------------------------------------------
    // Raw edge detection for edge‑mode sources
    // -----------------------------------------------------------------------
    wire [15:0] intr_edge;
    reg  [15:0] intr_sync;

    // Synchronise (simple 2‑stage) — assumes intr_sources is async
    reg [15:0] sync_ff0, sync_ff1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff0 <= 16'h0000;
            sync_ff1 <= 16'h0000;
        end else begin
            sync_ff0 <= intr_sources;
            sync_ff1 <= sync_ff0;
        end
    end

    // Edge detect
    reg [15:0] sync_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_ff2 <= 16'h0000;
        else
            sync_ff2 <= sync_ff1;
    end

    assign intr_edge = sync_ff1 & ~sync_ff2;   // rising edge

    // -----------------------------------------------------------------------
    // Raw interrupt value: for edge‑mode sources, use edge; for level, use synchronised
    // -----------------------------------------------------------------------
    wire [15:0] raw_int;
    assign raw_int = (sync_ff1 & ~edge_rdata) | (intr_edge & edge_rdata);

    // -----------------------------------------------------------------------
    // 演示 ④ reg_w1c —— 中断 pending 寄存器
    //   硬件 set  : raw_int（中断源来了就置位对应位）
    //   软件清除  : 写 INT_CLEAR（写 1 清除对应位）
    //   优先级    : set > w1c（同一周期又 set 又 clear → 保留 set 的值）
    // -----------------------------------------------------------------------
    wire [15:0] pending_rdata;
    wire        pending_we;

    assign pending_we = write_active && (addr == `REG_INT_CLEAR);

    reg_w1c #(.W(16), .INIT(16'h0000)) u_pending (
        .clk   (clk),
        .rst_n (rst_n),
        .load  (pending_we),         // 写 INT_CLEAR → 软件清除
        .wdata (wdata),              // wdata[i]=1 时清除 pending[i]
        .set   (raw_int),            // 硬件中断源 → 强制置位
        .rdata (pending_rdata)
    );

    // -----------------------------------------------------------------------
    // Status = pending & enable & ~mask
    // -----------------------------------------------------------------------
    wire [15:0] int_status;
    assign int_status = pending_rdata & enable_rdata & ~mask_rdata;

    // -----------------------------------------------------------------------
    // Interrupt vector — highest priority (lowest bit wins)
    // -----------------------------------------------------------------------
    wire [15:0] vector_rdata;
    reg  [3:0]  vector_idx;

    always @(*) begin
        vector_idx = 4'h0;
        if (int_status[0])  vector_idx = 4'h0;
        else if (int_status[1])  vector_idx = 4'h1;
        else if (int_status[2])  vector_idx = 4'h2;
        else if (int_status[3])  vector_idx = 4'h3;
        else if (int_status[4])  vector_idx = 4'h4;
        else if (int_status[5])  vector_idx = 4'h5;
        else if (int_status[6])  vector_idx = 4'h6;
        else if (int_status[7])  vector_idx = 4'h7;
        else if (int_status[8])  vector_idx = 4'h8;
        else if (int_status[9])  vector_idx = 4'h9;
        else if (int_status[10]) vector_idx = 4'hA;
        else if (int_status[11]) vector_idx = 4'hB;
        else if (int_status[12]) vector_idx = 4'hC;
        else if (int_status[13]) vector_idx = 4'hD;
        else if (int_status[14]) vector_idx = 4'hE;
        else if (int_status[15]) vector_idx = 4'hF;
    end

    assign vector_rdata = {12'b0, vector_idx};

    // -----------------------------------------------------------------------
    // Combined interrupt output
    // -----------------------------------------------------------------------
    assign irq_o = (int_status != 16'h0000);

    // -----------------------------------------------------------------------
    // Read mux — combinatorial decode
    // -----------------------------------------------------------------------
    always @(*) begin
        case (addr)
            `REG_INT_STATUS   : rdata_mux = int_status;
            `REG_INT_ENABLE   : rdata_mux = enable_rdata;
            `REG_INT_MASK     : rdata_mux = mask_rdata;
            `REG_INT_CLEAR    : rdata_mux = 16'h0000;   // WO
            `REG_INT_EDGE     : rdata_mux = edge_rdata;
            `REG_INT_RAW      : rdata_mux = raw_int;
            `REG_INT_VECTOR   : rdata_mux = vector_rdata;
            default                : rdata_mux = 16'h0000;
        endcase
    end

    assign rdata = rdata_mux;
    assign rdy   = cs;

endmodule
