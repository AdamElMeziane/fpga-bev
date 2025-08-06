module rom_to_sdram_writer (
    input  logic        clk,
    input  logic        init_done,
    input  logic [2:0]  pixel_data,
    output logic        done,

    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  ba,
    output logic        cke,
    output logic [15:0] dq_out,
    output logic        dq_oe,

    output logic [16:0] pixel_index  // for ROM access
);

    // Image dimensions
    localparam int IMG_WIDTH  = 320;
    localparam int IMG_HEIGHT = 240;
    localparam int IMG_SIZE   = IMG_WIDTH * IMG_HEIGHT;

    // SDRAM timing parameters (in cycles @ 133 MHz = 7.5ns)
    localparam int tRCD  = 3;   // 20ns / 7.5ns = 2.67 -> 3
    localparam int tDPL  = 2;   // Data-in to Precharge = 2 CLK
    localparam int tRP   = 3;   // 20ns / 7.5ns = 2.67 -> 3
    localparam int tDAL  = tDPL + tRP; // 5 cycles total

    // FSM states
    typedef enum logic [3:0] {
        IDLE,
        ACTIVATE,
        WAIT_TRCD,
        WRITE,
        WAIT_TDAL,
        PRECHARGE,
        WAIT_TRP,
        NEXT_PIXEL,
        DONE_STATE
    } state_t;

    state_t state;
    logic [3:0] wait_counter;
    logic [19:0] sdram_addr;  // Extended to 20 bits for proper mapping
    logic [15:0] padded_pixel;

    assign padded_pixel = {13'b0, pixel_data};  // pad 3-bit RGB to 16-bit
    assign cke = 1;
    assign dq_out = padded_pixel;
    assign dq_oe = (state == WRITE);

    // Address mapping for 4M x 16 SDRAM (1M x 16 x 4 banks)
    // Total addressable: 4M locations = 22 bits, but we only use 20 bits
    // [19:18] = bank (2 bits for 4 banks)
    // [17:6]  = row  (12 bits for 4096 rows)  
    // [5:0]   = col  (6 bits for 64 columns, but SDRAM has more)
    wire [1:0]  bank_addr = sdram_addr[19:18];
    wire [11:0] row_addr  = sdram_addr[17:6];
    wire [5:0]  col_addr  = sdram_addr[5:0];

    // Sequential logic
    always_ff @(posedge clk) begin
        if (!init_done) begin
            state        <= IDLE;
            pixel_index  <= 0;
            sdram_addr   <= 0;
            wait_counter <= 0;
            done         <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (pixel_index < IMG_SIZE) begin
                        state <= ACTIVATE;
                    end else begin
                        state <= DONE_STATE;
                    end
                end

                ACTIVATE: begin
                    state        <= WAIT_TRCD;
                    wait_counter <= 0;
                end

                WAIT_TRCD: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tRCD - 1)
                        state <= WRITE;
                end

                WRITE: begin
                    state        <= WAIT_TDAL;
                    wait_counter <= 0;
                end

                WAIT_TDAL: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tDAL - 1)
                        state <= PRECHARGE;
                end

                PRECHARGE: begin
                    state        <= WAIT_TRP;
                    wait_counter <= 0;
                end

                WAIT_TRP: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tRP - 1)
                        state <= NEXT_PIXEL;
                end

                NEXT_PIXEL: begin
                    pixel_index <= pixel_index + 1;
                    sdram_addr  <= sdram_addr + 1;
                    state       <= IDLE;  // Go back to check if done
                end

                DONE_STATE: begin
                    done <= 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // SDRAM command generation
    always_comb begin
        // Default: NOP
        cs_n  = 1;
        ras_n = 1;
        cas_n = 1;
        we_n  = 1;
        addr  = 12'd0;
        ba    = 2'b00;

        case (state)
            ACTIVATE: begin
                cs_n  = 0;
                ras_n = 0;
                cas_n = 1;
                we_n  = 1;
                addr  = row_addr;    // Row address
                ba    = bank_addr;   // Bank address
            end

            WRITE: begin
                cs_n  = 0;
                ras_n = 1;
                cas_n = 0;
                we_n  = 0;
                addr  = {6'b0, col_addr};  // Column address (pad to 12 bits)
                ba    = bank_addr;         // Bank address
            end

            PRECHARGE: begin
                cs_n      = 0;
                ras_n     = 0;
                cas_n     = 1;
                we_n      = 0;
                addr[10]  = 1;  // A10 = 1 → precharge all banks
                ba        = 2'b00;
            end

            default: begin
                // NOP - all signals already set above
            end
        endcase
    end

endmodule