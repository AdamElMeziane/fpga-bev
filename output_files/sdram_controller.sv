// HY57V641620ETP-7 SDR SDRAM Controller (143 MHz)
// - CL = 3, BL = 8, Sequential
// - Auto-precharge on every READ/WRITE (A10=1)
// - Writes the 320x240 (76800) words image once, then reads cyclically
// - Simple streaming interface: one word per clk when enable_* is asserted
//
// External data is 16-bit. One pixel per word (you pack 3-bit RGB in [2:0]).
//
// NOTE: If you want "single write" mode (write burst=single), set MRS_A9=1
// and adjust the write path to issue one WRITE per word (no burst). This
// version keeps A9=0 (burst write) so writes stream naturally 8 words/burst.

module sdram_controller #(
    parameter integer DATA_WIDTH = 16,

    // Image geometry (must match your ROM/FIFO use)
    parameter integer IMG_COLS   = 512,   // columns per SDR row used
    parameter integer IMG_ROWS   = 240,   // 76800 / 256 = 300 rows

    // Clock derived timing (143 MHz -> 7 ns)
    parameter integer T_RP_CYC   = 3,     // tRP >= 20 ns -> 3 cycles
    parameter integer T_RCD_CYC  = 3,     // tRCD >= 20 ns -> 3 cycles
    parameter integer T_RFC_CYC  = 9,     // tRFC >= 63 ns -> 9 cycles
    parameter integer T_MRD_CYC  = 2,     // tMRD >= 2 cycles
    parameter integer CL         = 3,     // CAS Latency cycles

    // Refresh interval (approx). 7.8us / 7ns ≈ 1115
    parameter integer REF_INT_CYC = 1115,

    // Burst length (fixed)
    parameter integer BL          = 8     // BL=8
)(
    input  logic rst_n,
    input  logic clk,

    // Control interface
    input  logic start,                   // begin init
    input  logic enable_write_mode,       // external "we want to write now"
    input  logic enable_read_mode,        // external "we want to read now"
    input  logic [DATA_WIDTH-1:0] incoming_data, // write data from upstream
    output logic [DATA_WIDTH-1:0] outgoing_data, // read data to downstream
    output logic enable_transmitter,      // request for write data (valid each clk)
    output logic enable_receiver,         // read data valid each clk
    output logic sdram_init_done,

    // SDRAM physical interface (HY57V641620ETP-7)
    inout  wire  [DATA_WIDTH-1:0] dq,
    output logic sclk,
    output logic cke,
    output logic cs_n,
    output logic ras_n,
    output logic cas_n,
    output logic we_n,
    output logic [11:0] addr,
    output logic [1:0]  bank,
    output logic udqm,
    output logic ldqm
);

    // --------------------------------------------------------------------
    // Command encodings (ras, cas, we)
    // --------------------------------------------------------------------
    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_ACTIVE       = 3'b011;
    localparam [2:0] CMD_READ         = 3'b101;
    localparam [2:0] CMD_WRITE        = 3'b100;
    localparam [2:0] CMD_PRECHARGE    = 3'b010;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
    localparam [2:0] CMD_MRS          = 3'b000;
    localparam [2:0] CMD_BURST_STOP   = 3'b110;

    // --------------------------------------------------------------------
    // Mode Register (A[11:0]): BL=8 (A2..A0=011), BT=0 (A3=0),
    // CL=3 (A6..A4=011), A7=0, A8=0, A9=0 (burst write), A10=0, A11=0
    // --------------------------------------------------------------------
    localparam [11:0] MRS_VALUE = {
        1'b0,       // A11 (reserved)
        1'b0,       // A10 (AP not set in MRS; AP is per command)
        1'b0,       // A9  (0 = burst write, 1 = single write)
        1'b0,       // A8  (test = 0)
        3'b011,     // A6..A4 = CL=3
        1'b0,       // A3 = burst type = sequential
        3'b011      // A2..A0 = BL=8
    };

    // --------------------------------------------------------------------
    // Simple address/use model: bank 0 only
    // row: 0..IMG_ROWS-1, col: 0..IMG_COLS-1 (8-beat steps)
    // --------------------------------------------------------------------
    logic [11:0] row_wr, row_rd;
    logic [8:0]  col_wr, col_rd;   // 8-bit covers 0..511
    logic [2:0]  bl_cnt;           // 0..7 beats per burst

    // State machine
    typedef enum logic [4:0] {
        ST_RESET          = 5'd0,
        ST_WAIT_START     = 5'd1,
        ST_PWRUP_NOP      = 5'd2,
        ST_PRECHARGE_ALL  = 5'd3,
        ST_tRP_WAIT       = 5'd4,
        ST_AR1            = 5'd5,
        ST_tRFC1          = 5'd6,
        ST_AR2            = 5'd7,
        ST_tRFC2          = 5'd8,
        ST_MRS            = 5'd9,
        ST_tMRD           = 5'd10,
        ST_IDLE           = 5'd11,
        ST_REFRESH_PRE    = 5'd12,
        ST_REFRESH_tRP    = 5'd13,
        ST_REFRESH_AR     = 5'd14,
        ST_REFRESH_tRFC   = 5'd15,
        // Operations
        ST_ACT_WR         = 5'd16,
        ST_tRCD_WR        = 5'd17,
        ST_WRITE_CMD      = 5'd18,
        ST_WRITE_BURST    = 5'd19,
        ST_tRP_AFTER_WR   = 5'd20,

        ST_ACT_RD         = 5'd21,
        ST_tRCD_RD        = 5'd22,
        ST_READ_CMD       = 5'd23,
        ST_READ_LAT       = 5'd24,
        ST_READ_BURST     = 5'd25,
        ST_tRP_AFTER_RD   = 5'd26
    } state_t;

    state_t state, nstate;

    // Timers/counters
    logic [15:0] timer;
    logic [15:0] refresh_cnt;

    // Command/address regs to outputs
    logic [2:0]  cmd;
    logic [11:0] addr_r;
    logic [1:0]  bank_r;

    // DQ tristate control
    logic dq_oe;
    assign dq = dq_oe ? incoming_data : 'z;

    // Outputs
    assign sclk = clk;
    assign cke  = 1'b1;
    assign cs_n = 1'b0;
    assign {ras_n, cas_n, we_n} = cmd;
    assign addr = addr_r;
    assign bank = bank_r;
    assign udqm = 1'b0;
    assign ldqm = 1'b0;

    // Data valid flags
    logic rx_valid;
    assign enable_receiver = rx_valid;
    assign outgoing_data   = rx_valid ? dq : '0;

    // Write request to upstream
    logic tx_req;
    assign enable_transmitter = tx_req;

    // Init done flag
    logic init_done;
    assign sdram_init_done = init_done;

    // Helper flags
    wire want_write = enable_write_mode && !init_done ? 1'b0 : enable_write_mode;
    wire want_read  = enable_read_mode  && init_done;

    // Refresh time
    wire do_refresh = (refresh_cnt >= REF_INT_CYC);

    // Row/col advance helpers (wraps inside image)
    function automatic [8:0] next_col(input [8:0] c);
        next_col = (c + BL >= IMG_COLS) ? 9'd0 : (c + BL[8:0]);
    endfunction

    function automatic [11:0] next_row(input [11:0] r);
        next_row = (r == IMG_ROWS-1) ? 12'd0 : (r + 12'd1);
    endfunction

    // Sequential
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_RESET;
            timer        <= '0;
            refresh_cnt  <= '0;
            cmd          <= CMD_NOP;
            addr_r       <= 12'd0;
            bank_r       <= 2'b00;
            dq_oe        <= 1'b0;
            rx_valid     <= 1'b0;
            tx_req       <= 1'b0;
            init_done    <= 1'b0;
            row_wr       <= 12'd0;
            row_rd       <= 12'd0;
            col_wr       <= 9'd0;
            col_rd       <= 9'd0;
            bl_cnt       <= 3'd0;
        end else begin
            state <= nstate;

            // Default outputs each cycle
            cmd      <= CMD_NOP;
            addr_r   <= 12'd0;
            bank_r   <= 2'b00;
            dq_oe    <= 1'b0;
            rx_valid <= 1'b0;
            tx_req   <= 1'b0;

            // Timer and refresh counter
            if (state != nstate) begin
                timer <= 16'd0;
            end else begin
                timer <= timer + 16'd1;
            end

            if (state == ST_IDLE) begin
                refresh_cnt <= do_refresh ? 16'd0 : (refresh_cnt + 16'd1);
            end else if (state == ST_REFRESH_tRFC) begin
                // hold refresh_cnt cleared through refresh
                refresh_cnt <= 16'd0;
            end

            // FSM actions
            unique case (state)
                // ----------------------------------------------------------
                ST_RESET: begin
                    // after reset go wait for start
                end

                ST_WAIT_START: begin
                    // wait for 'start' from top
                end

                ST_PWRUP_NOP: begin
                    // 200us power-up NOPs: re-use a big timer at top if you want.
                    // For brevity we don't burn 200us here; assume PLL and power-up handled,
                    // or stretch this state externally before asserting 'start'.
                end

                ST_PRECHARGE_ALL: begin
                    cmd        <= CMD_PRECHARGE;
                    // A10=1 => precharge ALL banks
                    addr_r[10] <= 1'b1;
                end

                ST_tRP_WAIT: begin
                    // wait tRP cycles
                end

                ST_AR1: begin
                    cmd <= CMD_AUTO_REFRESH;
                end

                ST_tRFC1: begin
                    // wait tRFC
                end

                ST_AR2: begin
                    cmd <= CMD_AUTO_REFRESH;
                end

                ST_tRFC2: begin
                    // wait tRFC
                end

                ST_MRS: begin
                    cmd    <= CMD_MRS;
                    addr_r <= MRS_VALUE;
                end

                ST_tMRD: begin
                    // wait tMRD
                end

                ST_IDLE: begin
                    if (!init_done) init_done <= 1'b1;
                    // no op; decisions in combinational
                end

                // ------------------ WRITE path ---------------------------
                ST_ACT_WR: begin
                    cmd    <= CMD_ACTIVE;
                    addr_r <= row_wr;     // Row address
                end

                ST_tRCD_WR: begin
                    // wait tRCD
                end

                ST_WRITE_CMD: begin
                    cmd         <= CMD_WRITE;
                    // Column addr + auto-precharge
                    addr_r[8:0] <= col_wr;
                    addr_r[10]  <= 1'b1; // A10=1 => autoprecharge
                    // Start burst: request data beats
                    tx_req      <= 1'b1;
                    dq_oe       <= 1'b1; // drive DQ for first beat
                    bl_cnt      <= 3'd0;
                end

                ST_WRITE_BURST: begin
                    // stream BL cycles; request one word/clk
                    tx_req <= 1'b1;
                    dq_oe  <= 1'b1;
                    bl_cnt <= bl_cnt + 3'd1;
                    if (bl_cnt == (BL-1)) begin
                        // end of burst -> next column or next row
                        if (col_wr + BL >= IMG_COLS) begin
                            col_wr <= 9'd0;
                            row_wr <= next_row(row_wr);
                        end else begin
                            col_wr <= col_wr + BL[6:0];
                        end
                    end
                end

                ST_tRP_AFTER_WR: begin
                    // wait tRP before next ACTIVE (AP closes row internally)
                end

                // ------------------- READ path ---------------------------
                ST_ACT_RD: begin
                    cmd    <= CMD_ACTIVE;
                    addr_r <= row_rd;
                end

                ST_tRCD_RD: begin
                    // wait tRCD
                end

                ST_READ_CMD: begin
                    cmd         <= CMD_READ;
                    addr_r[8:0] <= col_rd;
                    addr_r[10]  <= 1'b1; // autoprecharge
                    bl_cnt      <= 3'd0;
                end

                ST_READ_LAT: begin
                    // wait CL cycles; then data appears
                end

                ST_READ_BURST: begin
                    // present BL beats
                    rx_valid <= 1'b1;
                    bl_cnt   <= bl_cnt + 3'd1;
                    if (bl_cnt == (BL-1)) begin
                        if (col_rd + BL >= IMG_COLS) begin
                            col_rd <= 9'd0;
                            row_rd <= next_row(row_rd);
                        end else begin
                            col_rd <= col_rd + BL[6:0];
                        end
                    end
                end

                ST_tRP_AFTER_RD: begin
                    // wait tRP before next ACTIVE
                end

                default: ;
            endcase
        end
    end

    // Next-state logic
    always_comb begin
        nstate = state;

        unique case (state)
            ST_RESET:         nstate = ST_WAIT_START;
            ST_WAIT_START:    nstate = start ? ST_PRECHARGE_ALL : ST_WAIT_START;

            ST_PWRUP_NOP:     nstate = (timer >= 16'd28571) ? ST_PRECHARGE_ALL : ST_PWRUP_NOP; // ~200us/7ns

            ST_PRECHARGE_ALL: nstate = ST_tRP_WAIT;
            ST_tRP_WAIT:      nstate = (timer >= T_RP_CYC-1) ? ST_AR1 : ST_tRP_WAIT;

            ST_AR1:           nstate = ST_tRFC1;
            ST_tRFC1:         nstate = (timer >= T_RFC_CYC-1) ? ST_AR2 : ST_tRFC1;

            ST_AR2:           nstate = ST_tRFC2;
            ST_tRFC2:         nstate = (timer >= T_RFC_CYC-1) ? ST_MRS : ST_tRFC2;

            ST_MRS:           nstate = ST_tMRD;
            ST_tMRD:          nstate = (timer >= T_MRD_CYC-1) ? ST_IDLE : ST_tMRD;

            ST_IDLE: begin
                if (do_refresh) begin
                    nstate = ST_REFRESH_PRE;
                end else if (want_write && (row_wr < IMG_ROWS)) begin
                    // Still building the image: write path
                    nstate = ST_ACT_WR;
                end else if (want_read) begin
                    // Read continuously, wrap inside image
                    nstate = ST_ACT_RD;
                end else begin
                    nstate = ST_IDLE;
                end
            end

            // Refresh sequence: PRECH ALL -> tRP -> AR -> tRFC -> IDLE
            ST_REFRESH_PRE:   nstate = ST_REFRESH_tRP;
            ST_REFRESH_tRP:   nstate = (timer >= T_RP_CYC-1)  ? ST_REFRESH_AR   : ST_REFRESH_tRP;
            ST_REFRESH_AR:    nstate = ST_REFRESH_tRFC;
            ST_REFRESH_tRFC:  nstate = (timer >= T_RFC_CYC-1) ? ST_IDLE         : ST_REFRESH_tRFC;

            // Write path
            ST_ACT_WR:        nstate = ST_tRCD_WR;
            ST_tRCD_WR:       nstate = (timer >= T_RCD_CYC-1) ? ST_WRITE_CMD    : ST_tRCD_WR;
            ST_WRITE_CMD:     nstate = ST_WRITE_BURST;
            ST_WRITE_BURST:   nstate = (bl_cnt == (BL-1))      ? ST_tRP_AFTER_WR : ST_WRITE_BURST;
            ST_tRP_AFTER_WR:  nstate = (timer >= T_RP_CYC-1)   ? ST_IDLE         : ST_tRP_AFTER_WR;

            // Read path
            ST_ACT_RD:        nstate = ST_tRCD_RD;
            ST_tRCD_RD:       nstate = (timer >= T_RCD_CYC-1) ? ST_READ_CMD     : ST_tRCD_RD;
            ST_READ_CMD:      nstate = ST_READ_LAT;
            ST_READ_LAT:      nstate = (timer >= CL-1)        ? ST_READ_BURST   : ST_READ_LAT;
            ST_READ_BURST:    nstate = (bl_cnt == (BL-1))     ? ST_tRP_AFTER_RD : ST_READ_BURST;
            ST_tRP_AFTER_RD:  nstate = (timer >= T_RP_CYC-1)  ? ST_IDLE         : ST_tRP_AFTER_RD;

            default:          nstate = ST_RESET;
        endcase
    end

endmodule
