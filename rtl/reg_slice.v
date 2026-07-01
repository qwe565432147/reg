// ============================================================================
// reg_slice.v — Register Primitive Cells
//
// Purpose:
//   Reusable 1‑ or N‑bit register cells that encapsulate every common
//   read/write access behaviour.  Using these consistently guarantees
//   that every register in the design obeys the same reset, clock,
//   and access semantics.
//
// Cell types
//   reg_rw    —  Read / Write                (software R/W, hardware read)
//   reg_ro    —  Read‑Only                   (hardware drives, software reads)
//   reg_w1c   —  Write‑1‑to‑Clear            (hardware sets, software clears)
//   reg_rc    —  Read‑to‑Clear (sticky)      (first read returns val, clears)
//   reg_rsvd  —  Reserved hole               (reads 0, ignores writes)
//
// Convention
//   All cells use asynchronous active‑low reset (negedge rst_n).
//   All cells have a parameterised width W and an INIT reset value.
//   The "load" / "wen" qualifier is expected to be a single cycle pulse.
// ============================================================================

`include "reg_defines.v"

// ============================================================================
// reg_rw — Read / Write register
//   load   : write enable (1 cycle pulse)
//   wdata  : write data
//   rdata  : read data  (= current register value)
//   For split hardware / software access use the wmask variant.
// ============================================================================
module reg_rw #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    output reg [W-1:0]         rdata
);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else if (load)
            rdata <= wdata;
    end

endmodule


// ============================================================================
// reg_rw_wmask — Read / Write register with word‑level write mask
//   load   : write enable
//   wdata  : write data
//   wmask  : per‑bit write mask (1 = write this bit)
//   rdata  : read data
//   Useful for registers where SW should only touch certain bits.
// ============================================================================
module reg_rw_wmask #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    input      [W-1:0]         wmask,
    output reg [W-1:0]         rdata
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else if (load)
            rdata <= (wdata & wmask) | (rdata & ~wmask);
    end

endmodule


// ============================================================================
// reg_ro — Read‑Only register
//   din    : value driven by hardware
//   rdata  : read data (= din combinatorial)
//   No clock, no reset — purely combinatorial.
// ============================================================================
module reg_ro #(
    parameter W = 16
) (
    input      [W-1:0]         din,
    output     [W-1:0]         rdata
);

    assign rdata = din;

endmodule


// ============================================================================
// reg_w1c — Write‑1‑to‑Clear register
//   set    : hardware sets bits (edge / event)
//   load   : software write strobe
//   wdata  : write data (bits with 1 are cleared)
//   rdata  : read data (= current value after set & clear)
//
//   Priority (highest → lowest) : set > w1c > hold
//   A bit set AND written 1 in the same cycle remains set.
// ============================================================================
module reg_w1c #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input                      load,
    input      [W-1:0]         wdata,
    input      [W-1:0]         set,
    output reg [W-1:0]         rdata
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= INIT;
        else begin
            rdata <= rdata | set;                      // hardware set
            if (load)
                rdata <= (rdata | set) & ~wdata;       // software clear
        end
    end

endmodule


// ============================================================================
// reg_rc — Read‑to‑Clear (sticky) register
//   set    : hardware sets bits
//   rdata  : read data (= current value); after read returns, value is cleared
//
//   Note: "read‑to‑clear" means the act of reading clears the bit.
//   This cell uses a registered read — the value is sampled into a shadow
//   register one cycle before clearing.  Use for infrequent status reads
//   where the host reads until it gets a non‑zero value.
// ============================================================================
module reg_rc #(
    parameter                  W    = 16,
    parameter [W-1:0]          INIT = {W{1'b0}}
) (
    input                      clk,
    input                      rst_n,
    input      [W-1:0]         set,
    input                      read_strobe,
    output reg [W-1:0]         rdata
);

    reg [W-1:0] val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val   <= INIT;
            rdata <= INIT;
        end else begin
            val <= val | set;
            rdata <= val;                       // registered read
            if (read_strobe)
                val <= {W{1'b0}};
        end
    end

endmodule


// ============================================================================
// reg_rsvd — Reserved register hole
//   Always reads 0 from SW; any write is silently ignored.
//   Use to fill gaps in the address map and avoid accidental decode holes.
// ============================================================================
module reg_rsvd #(
    parameter W = 16
) (
    output [W-1:0] rdata
);

    assign rdata = {W{1'b0}};

endmodule


// ============================================================================
// reg_pulse — Edge‑to‑pulse converter (used by W1C set logic)
//   Generates a 1‑cycle pulse on the rising edge of din.
//   Synchroniser assumed if din is from another clock domain.
// ============================================================================
module reg_pulse #(
    parameter W = 1
) (
    input              clk,
    input              rst_n,
    input  [W-1:0]     din,
    output [W-1:0]     dout
);

    reg [W-1:0] din_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            din_d <= {W{1'b0}};
        else
            din_d <= din;
    end

    assign dout = din & ~din_d;

endmodule
