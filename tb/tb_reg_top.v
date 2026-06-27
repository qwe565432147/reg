// ============================================================================
// tb_reg_top.v — Register Map Testbench
//
// Tests:
//   1. Reset state — all registers read their initial / default values
//   2. reg_base — version, chip_id, build date, scratch RW
//   3. reg_status — flag reads, error‑clear pulse
//   4. reg_int   — enable → fire → status → clear, vector priority
//   5. reg_iic / reg_spi / reg_ft — basic read/write smoke test
//   6. bus_err   — access to unmapped hole returns error
// ============================================================================

`timescale 1ns / 1ps

`include "../rtl/reg_defines.v"
// reg_top and all sub-modules are compiled via the file list (do not `include)

module tb_reg_top;

    // =======================================================================
    // Clock & Reset
    // =======================================================================
    reg                     clk;
    reg                     rst_n;

    always #5 clk = ~clk;   // 100 MHz

    // =======================================================================
    // Bus Interface
    // =======================================================================
    reg      [15:0]         bus_addr;
    reg      [15:0]         bus_wdata;
    reg                     bus_req;
    reg                     bus_we;
    wire     [15:0]         bus_rdata;
    wire                    bus_rdy;
    wire                    bus_err;

    // =======================================================================
    // Interrupt
    // =======================================================================
    wire                    irq;
    reg      [15:0]         intr_sources;

    // =======================================================================
    // reg_base
    // =======================================================================
    reg      [7:0]          ver_major;
    reg      [7:0]          ver_minor;
    reg      [15:0]         chip_id;
    reg      [15:0]         build_year;
    reg      [7:0]          build_month;
    reg      [7:0]          build_day;
    reg      [31:0]         git_sha;
    reg      [15:0]         features;
    wire     [15:0]         scratch;

    // =======================================================================
    // reg_status
    // =======================================================================
    reg                     init_done;
    reg                     cal_done;
    reg                     system_error;
    reg                     system_warn;
    reg                     system_busy;
    reg      [15:0]         error_count;
    reg      [15:0]         last_error_code;
    reg      [15:0]         die_temp;
    reg      [15:0]         vcc_int;
    reg      [15:0]         vcc_aux;
    reg      [31:0]         uptime_sec;
    wire                    error_clr_pulse;

    // =======================================================================
    // reg_iic
    // =======================================================================
    wire                    iic_enable;
    wire                    iic_loopback;
    wire                    iic_reset;
    wire                    iic_busy;
    wire                    iic_ack_err;
    wire     [15:0]         iic_clk_div;
    wire     [6:0]          iic_slave_addr;
    wire     [7:0]          iic_tx_data;
    wire     [7:0]          iic_rx_data;
    wire                    iic_tx_done;
    wire                    iic_start;
    wire                    iic_stop;
    wire                    iic_read;
    wire                    iic_write;

    // =======================================================================
    // reg_spi
    // =======================================================================
    wire                    spi_enable;
    wire     [1:0]          spi_mode;
    wire                    spi_loopback;
    wire                    spi_busy;
    wire     [15:0]         spi_clk_div;
    wire     [15:0]         spi_tx_data;
    wire     [15:0]         spi_rx_data;
    wire     [7:0]          spi_cs_ctrl;
    wire                    spi_start;

    // =======================================================================
    // reg_ft
    // =======================================================================
    wire                    test_mode;
    wire                    test_loopback;
    wire                    bist_start;
    wire                    bist_busy;
    wire                    bist_pass;
    wire                    bist_fail;
    wire     [15:0]         test_data_in;
    wire     [15:0]         test_data_out;
    wire     [15:0]         loop_count;

    // =======================================================================
    // DUT
    // =======================================================================
    reg_top u_dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .bus_addr         (bus_addr),
        .bus_wdata        (bus_wdata),
        .bus_req          (bus_req),
        .bus_we           (bus_we),
        .bus_rdata        (bus_rdata),
        .bus_rdy          (bus_rdy),
        .bus_err          (bus_err),

        .irq              (irq),
        .intr_sources     (intr_sources),

        .ver_major        (ver_major),
        .ver_minor        (ver_minor),
        .chip_id          (chip_id),
        .build_year       (build_year),
        .build_month      (build_month),
        .build_day        (build_day),
        .git_sha          (git_sha),
        .features         (features),
        .scratch          (scratch),

        .init_done        (init_done),
        .cal_done         (cal_done),
        .system_error     (system_error),
        .system_warn      (system_warn),
        .system_busy      (system_busy),
        .error_count      (error_count),
        .last_error_code  (last_error_code),
        .die_temp         (die_temp),
        .vcc_int          (vcc_int),
        .vcc_aux          (vcc_aux),
        .uptime_sec       (uptime_sec),
        .error_clr_pulse  (error_clr_pulse),

        .iic_enable       (iic_enable),
        .iic_loopback     (iic_loopback),
        .iic_reset        (iic_reset),
        .iic_busy         (iic_busy),
        .iic_ack_err      (iic_ack_err),
        .iic_clk_div      (iic_clk_div),
        .iic_slave_addr   (iic_slave_addr),
        .iic_tx_data      (iic_tx_data),
        .iic_rx_data      (iic_rx_data),
        .iic_tx_done      (iic_tx_done),
        .iic_start        (iic_start),
        .iic_stop         (iic_stop),
        .iic_read         (iic_read),
        .iic_write        (iic_write),

        .spi_enable       (spi_enable),
        .spi_mode         (spi_mode),
        .spi_loopback     (spi_loopback),
        .spi_busy         (spi_busy),
        .spi_clk_div      (spi_clk_div),
        .spi_tx_data      (spi_tx_data),
        .spi_rx_data      (spi_rx_data),
        .spi_cs_ctrl      (spi_cs_ctrl),
        .spi_start        (spi_start),

        .test_mode        (test_mode),
        .test_loopback    (test_loopback),
        .bist_start       (bist_start),
        .bist_busy        (bist_busy),
        .bist_pass        (bist_pass),
        .bist_fail        (bist_fail),
        .test_data_in     (test_data_in),
        .test_data_out    (test_data_out),
        .loop_count       (loop_count)
    );

    // =======================================================================
    // Helper tasks
    // =======================================================================
    integer error_count_tb;
    reg [15:0] rd;

    // Single‑cycle write
    task reg_write;
        input [15:0] addr;
        input [15:0] data;
        begin
            @(posedge clk);
            bus_req   <= 1'b1;
            bus_we    <= 1'b1;
            bus_addr  <= addr;
            bus_wdata <= data;
            @(posedge clk);
            bus_req   <= 1'b0;
            bus_we    <= 1'b0;
        end
    endtask

    // Single‑cycle read (rdata valid combo, sample after posedge)
    task reg_read;
        input  [15:0] addr;
        output [15:0] data;
        begin
            @(posedge clk);
            bus_req  <= 1'b1;
            bus_we   <= 1'b0;
            bus_addr <= addr;
            @(posedge clk);
            bus_req <= 1'b0;
            data = bus_rdata;   // sampled after clock edge (rdata is combo)
        end
    endtask

    // Read with result check
    task reg_read_check;
        input [15:0] addr;
        input [15:0] expected;
        begin
            reg_read(addr, rd);
            if (rd !== expected) begin
                $display("FAIL: addr=0x%04X  expected=0x%04X  got=0x%04X",
                         addr, expected, rd);
                error_count_tb <= error_count_tb + 1;
            end else begin
                $display("PASS: addr=0x%04X = 0x%04X", addr, rd);
            end
        end
    endtask

    // =======================================================================
    // Test sequence
    // =======================================================================

    initial begin
        // ---- Initialise ---------------------------------------------------
        clk  = 0;
        rst_n = 0;

        bus_addr     = 16'h0000;
        bus_wdata    = 16'h0000;
        bus_req      = 1'b0;
        bus_we       = 1'b0;
        intr_sources = 16'h0000;

        ver_major    = 8'hA1;
        ver_minor    = 8'h01;
        chip_id      = 16'hFA51;
        build_year   = 16'h07E6;     // 2026
        build_month  = 8'h06;
        build_day    = 8'h1C;
        git_sha      = 32'hDEADBEEF;
        features     = 16'h0003;

        init_done     = 1'b0;
        cal_done      = 1'b0;
        system_error  = 1'b0;
        system_warn   = 1'b0;
        system_busy   = 1'b0;
        error_count   = 16'h0000;
        last_error_code = 16'h0000;
        die_temp      = 16'h0258;     // 60.0 °C
        vcc_int       = 16'h0A00;     // 1.0 V (scaled)
        vcc_aux       = 16'h0B00;     // 1.1 V (scaled)
        uptime_sec    = 32'h00000000;

        error_count_tb = 0;

        // ---- Reset --------------------------------------------------------
        #20 rst_n = 1;
        #10;

        $display("");
        $display("==========================================================");
        $display("Register Map Testbench Started");
        $display("==========================================================");
        $display("");

        // ===================================================================
        // Test 1: Reset values
        // ===================================================================
        $display("--- Test 1: Reset / Initial Values ---");
        reg_read_check(`REG_BASE_VER,     {ver_major, ver_minor});
        reg_read_check(`REG_BASE_CHIP_ID, chip_id);
        reg_read_check(`REG_BASE_BUILD_Y, build_year);

        // ===================================================================
        // Test 2: Scratch RW
        // ===================================================================
        $display("");
        $display("--- Test 2: Scratch Read-Write ---");
        reg_write(`REG_BASE_SCRATCH, 16'hA5A5);
        reg_read_check(`REG_BASE_SCRATCH, 16'hA5A5);

        reg_write(`REG_BASE_SCRATCH, 16'h5A5A);
        reg_read_check(`REG_BASE_SCRATCH, 16'h5A5A);

        // ===================================================================
        // Test 3: Status flags
        // ===================================================================
        $display("");
        $display("--- Test 3: Status Flags ---");
        init_done = 1'b1; cal_done = 1'b1;
        #10;
        // REG_STATUS_FLAGS at full address 0x2000
        reg_read_check(`REG_STATUS_ADDR + `REG_STATUS_FLAGS,
                       {11'b0, system_busy, system_warn, system_error, cal_done, init_done});

        // ===================================================================
        // Test 4: Error clear pulse
        // ===================================================================
        $display("");
        $display("--- Test 4: Error Clear W1C ---");
        reg_write(`REG_STATUS_ADDR + `REG_STATUS_ERR_CLR, 16'h0001);
        #10;
        if (error_clr_pulse !== 1'b1) begin
            $display("FAIL: error_clr_pulse not asserted");
            error_count_tb <= error_count_tb + 1;
        end else begin
            $display("PASS: error_clr_pulse = 1");
        end

        // ===================================================================
        // Test 4.5: reg_rw_wmask 演示 —— 带位掩码的控制寄存器
        //   ctrl 地址 0x0030, wmask = 0x0003（只允许改 bit[0] 和 bit[1]）
        //   验证写 0xFF → 只改低 2 位，高位不变
        // ===================================================================
        $display("");
        $display("--- Test 4.5: reg_rw_wmask (带位掩码) ---");
        // wmask=0x0003 → 软件只能修改 bit[1:0]，bit[15:2] 永远是 0（只读）
        reg_write(`REG_BASE_CTRL, 16'h00FF);
        reg_read_check(`REG_BASE_CTRL, 16'h0003);   // 0xFF 写入，wmask 只让 bit[1:0] 通过

        reg_write(`REG_BASE_CTRL, 16'h0002);
        reg_read_check(`REG_BASE_CTRL, 16'h0002);   // 只写 bit[1]，bit[0] 被清 0

        reg_write(`REG_BASE_CTRL, 16'h0001);
        reg_read_check(`REG_BASE_CTRL, 16'h0001);   // 只写 bit[0]

        // ===================================================================
        // Test 4.6: reg_ro 演示 —— 只读寄存器（features 地址 0x0020）
        // ===================================================================
        $display("");
        $display("--- Test 4.6: reg_ro (只读) ---");
        reg_read_check(`REG_BASE_FEATURES, features);   // 读 features = 0x0003

        // ===================================================================
        // Test 4.7: reg_rsvd 演示 —— 保留地址读 0
        //   地址 0x0008（在 base 区域的空洞中）
        // ===================================================================
        $display("");
        $display("--- Test 4.7: reg_rsvd (保留地址) ---");
        reg_read_check(16'h0008, 16'h0000);

        // ===================================================================
        // Test 5: Interrupt controller
        // ===================================================================
        $display("");
        $display("--- Test 5: Interrupt Controller ---");

        // Enable all interrupt sources
        reg_write(`REG_INT_ADDR + `REG_INT_ENABLE, 16'hFFFF);
        reg_read_check(`REG_INT_ADDR + `REG_INT_ENABLE, 16'hFFFF);

        // Fire interrupt source #3
        #10;
        intr_sources = 16'h0008;   // bit 3

        // Wait for synchronisation (3 cycles: sync_ff0 → sync_ff1 → raw_int)
        #30;

        // Read RAW, STATUS and VECTOR while source is still active
        reg_read_check(`REG_INT_ADDR + `REG_INT_RAW,    16'h0008);   // combinatorial from sync_ff1
        reg_read_check(`REG_INT_ADDR + `REG_INT_STATUS, 16'h0008);   // latched pending & enabled
        reg_read_check(`REG_INT_ADDR + `REG_INT_VECTOR, 16'h0003);   // source index 3

        // De-assert source
        intr_sources = 16'h0000;

        if (irq !== 1'b1) begin
            $display("FAIL: irq not asserted after interrupt");
            error_count_tb <= error_count_tb + 1;
        end else begin
            $display("PASS: irq = 1 after interrupt");
        end

        // Clear the interrupt
        reg_write(`REG_INT_ADDR + `REG_INT_CLEAR, 16'h0008);
        #10;
        reg_read_check(`REG_INT_ADDR + `REG_INT_STATUS, 16'h0000);

        if (irq !== 1'b0) begin
            $display("FAIL: irq still asserted after clear");
            error_count_tb <= error_count_tb + 1;
        end else begin
            $display("PASS: irq = 0 after clear");
        end

        // ===================================================================
        // Test 6: Interrupt vector priority (lowest bit = highest priority)
        // ===================================================================
        $display("");
        $display("--- Test 6: Interrupt Vector Priority ---");
        intr_sources = 16'h8001;   // bits 0 and 15
        #30;                         // wait for sync
        reg_read_check(`REG_INT_ADDR + `REG_INT_STATUS, 16'h8001);
        reg_read_check(`REG_INT_ADDR + `REG_INT_VECTOR, 16'h0000);   // bit 0 has priority
        intr_sources = 16'h0000;
        #10;

        // ===================================================================
        // Test 6.5: reg_rc 演示 —— 读后自动清零
        //   err_sticky 在 0x2040，捕获 system_error 的上升沿
        //   第一次读 → 0x0001（捕捉到错误），第二次读 → 0x0000（自动清掉）
        // ===================================================================
        $display("");
        $display("--- Test 6.5: reg_rc (读后自动清零) ---");
        system_error = 1'b0;
        #10;
        system_error = 1'b1;           // 拉高 system_error → 产生上升沿
        #20;
        reg_read_check(`REG_STATUS_ADDR + `REG_STATUS_ERR_STICKY, 16'h0001);  // 捕捉到了
        reg_read_check(`REG_STATUS_ADDR + `REG_STATUS_ERR_STICKY, 16'h0000);  // 自动清零
        system_error = 1'b0;
        #10;

        // ===================================================================
        // Test 7: reg_iic read/write
        // ===================================================================
        $display("");
        $display("--- Test 7: I2C Template ---");
        reg_write(`REG_IIC_ADDR + `REG_IIC_CTRL, 16'h0003);   // enable + loopback
        reg_read_check(`REG_IIC_ADDR + `REG_IIC_CTRL, 16'h0003);

        reg_write(`REG_IIC_ADDR + `REG_IIC_CLK_DIV, 16'h00FF);
        reg_read_check(`REG_IIC_ADDR + `REG_IIC_CLK_DIV, 16'h00FF);

        // ===================================================================
        // Test 8: reg_spi read/write
        // ===================================================================
        $display("");
        $display("--- Test 8: SPI Template ---");
        reg_write(`REG_SPI_ADDR + `REG_SPI_CTRL, 16'h0001);
        reg_read_check(`REG_SPI_ADDR + `REG_SPI_CTRL, 16'h0001);

        reg_write(`REG_SPI_ADDR + `REG_SPI_CLK_DIV, 16'h0010);
        reg_read_check(`REG_SPI_ADDR + `REG_SPI_CLK_DIV, 16'h0010);

        // ===================================================================
        // Test 9: reg_ft read/write
        // ===================================================================
        $display("");
        $display("--- Test 9: Factory Test Template ---");
        reg_write(`REG_FT_ADDR + `REG_FT_CTRL, 16'h0001);
        reg_read_check(`REG_FT_ADDR + `REG_FT_CTRL, 16'h0001);

        reg_write(`REG_FT_ADDR + `REG_FT_DATA_IN, 16'hABCD);
        reg_read_check(`REG_FT_ADDR + `REG_FT_DATA_IN, 16'hABCD);

        // ===================================================================
        // Test 10: Bus error on unmapped address
        // ===================================================================
        $display("");
        $display("--- Test 10: Unmapped Address Error ---");
        reg_read(16'h7000, rd);     // 0x7000 is a hole
        if (bus_err !== 1'b1) begin
            $display("FAIL: bus_err not asserted for unmapped addr 0x7000");
            error_count_tb <= error_count_tb + 1;
        end else begin
            $display("PASS: bus_err = 1 for addr=0x7000");
        end

        reg_read(16'h8000, rd);     // 0x8000 is also unmapped
        if (bus_err !== 1'b1) begin
            $display("FAIL: bus_err not asserted for unmapped addr 0x8000");
            error_count_tb <= error_count_tb + 1;
        end else begin
            $display("PASS: bus_err = 1 for addr=0x8000");
        end

        // ===================================================================
        // Summary
        // ===================================================================
        #20;
        $display("");
        $display("==========================================================");
        if (error_count_tb == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED — %0d error(s)", error_count_tb);
        end
        $display("==========================================================");
        $finish;
    end

    // =======================================================================
    // Waveform dump (for tools that support it)
    // =======================================================================
    initial begin
        $dumpfile("tb_reg_top.vcd");
        $dumpvars(0, tb_reg_top);
    end

endmodule
