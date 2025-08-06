module sdram_to_vga_reader (
    input  logic        clk_sdram,    // 133MHz
    input  logic        clk_vga,      // 25MHz
    input  logic        reset_n,
    input  logic        video_on,
    input  logic [9:0]  x,
    input  logic [9:0]  y,
    input  logic        frame_start,

    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  ba,
    output logic        cke,
    input  logic [15:0] dq,
    output logic        dq_oe,

    output logic [2:0]  rgb
);

    localparam IMG_WIDTH = 320;
    localparam IMG_HEIGHT = 240;
    
    // SDRAM timing parameters
    localparam int tRCD = 3;  // 20ns / 7.5ns
    localparam int tCAS = 3;  // CAS latency = 3
    localparam int tRP  = 3;  // 20ns / 7.5ns

    typedef enum logic [3:0] {
        IDLE,
        WAIT_REQUEST,
        ACTIVATE,
        WAIT_TRCD,
        READ,
        WAIT_CAS,
        CAPTURE,
        PRECHARGE,
        WAIT_TRP,
        NEXT_PIXEL
    } state_t;

    state_t state;
    logic [3:0] wait_counter;
    logic [19:0] sdram_addr;  // 20-bit address matching writer
    logic [8:0] read_col;     // Current column being read
    logic [8:0] read_row;     // Current row being read

    // Address mapping (same as writer)
    wire [1:0]  bank_addr = sdram_addr[19:18];
    wire [11:0] row_addr  = sdram_addr[17:6];
    wire [5:0]  col_addr  = sdram_addr[5:0];

    assign dq_oe = 0;  // Always input for reader
    assign cke = 1;

    // Clock domain crossing signals
    logic request_line;           // VGA domain request
    logic request_line_sync1, request_line_sync2; // SDRAM domain
    logic line_ready;            // SDRAM domain  
    logic line_ready_sync1, line_ready_sync2;     // VGA domain
    logic [8:0] request_row;     // VGA domain
    logic [8:0] request_row_sync1, request_row_sync2; // SDRAM domain

    // Dual-port line buffer (SDRAM writes, VGA reads)
    logic [15:0] line_buffer_a [0:IMG_WIDTH-1];  // Port A: SDRAM write
    logic [15:0] line_buffer_b [0:IMG_WIDTH-1];  // Port B: VGA read
    logic buffer_select;  // 0 = VGA reads A, SDRAM writes B; 1 = opposite
    logic [8:0] write_addr;
    logic write_enable;
    logic [15:0] write_data;

    // VGA domain logic
    logic [8:0] current_line;
    logic line_requested;
    
    always_ff @(posedge clk_vga or negedge reset_n) begin
        if (!reset_n) begin
            request_line <= 0;
            line_requested <= 0;
            current_line <= 9'd511; // Invalid line to force first request
            request_row <= 0;
        end else begin
            // When we start a new line and it's within image bounds
            if (x == 0 && y < IMG_HEIGHT && y != current_line && !line_requested) begin
                request_row <= y[8:0];
                request_line <= 1;
                line_requested <= 1;
                current_line <= y[8:0];
            end
            
            // Clear request after it's been acknowledged
            if (request_line && line_ready_sync2) begin
                request_line <= 0;
                line_requested <= 0;
            end
        end
    end

    // Synchronizers: VGA to SDRAM domain
    always_ff @(posedge clk_sdram or negedge reset_n) begin
        if (!reset_n) begin
            request_line_sync1 <= 0;
            request_line_sync2 <= 0;
            request_row_sync1 <= 0;
            request_row_sync2 <= 0;
        end else begin
            request_line_sync1 <= request_line;
            request_line_sync2 <= request_line_sync1;
            request_row_sync1 <= request_row;
            request_row_sync2 <= request_row_sync1;
        end
    end

    // Synchronizers: SDRAM to VGA domain  
    always_ff @(posedge clk_vga or negedge reset_n) begin
        if (!reset_n) begin
            line_ready_sync1 <= 0;
            line_ready_sync2 <= 0;
        end else begin
            line_ready_sync1 <= line_ready;
            line_ready_sync2 <= line_ready_sync1;
        end
    end

    // SDRAM read FSM
    always_ff @(posedge clk_sdram or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            wait_counter <= 0;
            sdram_addr <= 0;
            read_col <= 0;
            read_row <= 0;
            line_ready <= 0;
            buffer_select <= 0;
            write_addr <= 0;
            write_enable <= 0;
            write_data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    line_ready <= 0;
                    write_enable <= 0;
                    if (request_line_sync2) begin
                        read_row <= request_row_sync2;
                        read_col <= 0;
                        sdram_addr <= {2'b00, request_row_sync2, 3'b000, 6'b000000}; // Start of row
                        write_addr <= 0;
                        buffer_select <= ~buffer_select; // Switch buffers
                        state <= ACTIVATE;
                    end
                end

                ACTIVATE: begin
                    state <= WAIT_TRCD;
                    wait_counter <= 0;
                end

                WAIT_TRCD: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tRCD - 1)
                        state <= READ;
                end

                READ: begin
                    state <= WAIT_CAS;
                    wait_counter <= 0;
                end

                WAIT_CAS: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tCAS - 1)
                        state <= CAPTURE;
                end

                CAPTURE: begin
                    // Store the read data
                    write_data <= dq;
                    write_enable <= 1;
                    write_addr <= read_col;
                    
                    read_col <= read_col + 1;
                    sdram_addr <= sdram_addr + 1;
                    
                    if (read_col >= IMG_WIDTH - 1) begin
                        state <= PRECHARGE;
                    end else begin
                        state <= PRECHARGE; // Need to precharge between each read
                    end
                end

                PRECHARGE: begin
                    write_enable <= 0;
                    state <= WAIT_TRP;
                    wait_counter <= 0;
                end

                WAIT_TRP: begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter >= tRP - 1) begin
                        if (read_col >= IMG_WIDTH) begin
                            line_ready <= 1;
                            state <= IDLE;
                        end else begin
                            state <= ACTIVATE; // Read next pixel
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Dual-port line buffer write (SDRAM domain)
    always_ff @(posedge clk_sdram) begin
        if (write_enable) begin
            if (buffer_select) begin
                line_buffer_b[write_addr] <= write_data;
            end else begin
                line_buffer_a[write_addr] <= write_data;
            end
        end
    end

    // SDRAM command generation
    always_comb begin
        cs_n  = 1;
        ras_n = 1;
        cas_n = 1;
        we_n  = 1;
        addr  = 12'd0;
        ba    = 2'b00;

        case (state)
            ACTIVATE: begin
                cs_n  = 0; ras_n = 0; cas_n = 1; we_n = 1;
                addr  = row_addr;
                ba    = bank_addr;
            end

            READ: begin
                cs_n  = 0; ras_n = 1; cas_n = 0; we_n = 1;
                addr  = {6'b0, col_addr};
                ba    = bank_addr;
            end

            PRECHARGE: begin
                cs_n      = 0;
                ras_n     = 0;
                cas_n     = 1;
                we_n      = 0;
                addr[10]  = 1; // precharge all banks
            end
        endcase
    end

    // VGA pixel output (VGA domain)
    logic [15:0] pixel_data;
    
    always_ff @(posedge clk_vga) begin
        if (video_on && x < IMG_WIDTH && y < IMG_HEIGHT) begin
            // Read from the buffer not currently being written
            if (buffer_select) begin
                pixel_data <= line_buffer_a[x];
            end else begin
                pixel_data <= line_buffer_b[x];
            end
            rgb <= pixel_data[2:0]; // Extract 3-bit RGB
        end else begin
            rgb <= 3'b000;
        end
    end

endmodule