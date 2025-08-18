module vga_frame_reader #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240,
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk_sdram,         // 133MHz SDRAM clock
    input  logic clk_vga,           // 25MHz VGA clock
    
    // SDRAM interface
    input  logic sdram_ready,       // System is ready for reading
    input  logic sdram_rx_enable,   // SDRAM provides data
    input  logic [DATA_WIDTH-1:0] sdram_data,
    output logic enable_read_mode,
    output logic [21:0] sdram_read_addr,  // CRITICAL: Added SDRAM address output
    
    // VGA timing inputs
    input  logic frame_start,
    input  logic video_on,
    input  logic [9:0] vga_x,
    input  logic [9:0] vga_y,
    
    // FIFO interface
    output logic fifo_write_enable,
    output logic [DATA_WIDTH-1:0] fifo_write_data,
    input  logic fifo_full,
    input  logic fifo_half_full,
    
    // Status
    output logic frame_ready
);

    localparam IMG_SIZE = IMG_WIDTH * IMG_HEIGHT;
    
    // Frame reading FSM
    typedef enum logic [2:0] {
        IDLE,
        WAIT_READY,
        START_READ,
        READING,
        FRAME_COMPLETE,
        WAIT_NEXT_FRAME
    } read_state_t;
    
    read_state_t state, next_state;
    
    // Pixel tracking - simplified
    logic [17:0] pixels_read_reg, pixels_read_next;
    logic reading_active;
    logic frame_start_sync, frame_start_prev;
    logic sdram_ready_latched;
    
    // Latch sdram_ready signal
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            sdram_ready_latched <= 1'b0;
        end else begin
            if (sdram_ready) begin
                sdram_ready_latched <= 1'b1;
            end
        end
    end
    
    // Synchronize frame_start to SDRAM clock domain
    logic frame_start_sync1, frame_start_sync2;
    
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            frame_start_sync1 <= 1'b0;
            frame_start_sync2 <= 1'b0;
            frame_start_prev <= 1'b0;
        end else begin
            frame_start_sync1 <= frame_start;
            frame_start_sync2 <= frame_start_sync1;
            frame_start_prev <= frame_start_sync2;
        end
    end
    
    // Edge detect for frame start
    assign frame_start_sync = frame_start_sync2 & ~frame_start_prev;
    
    // FSM next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (sdram_ready_latched) begin
                    next_state = WAIT_READY;
                end
            end
            
            WAIT_READY: begin
                if (frame_start_sync) begin
                    next_state = START_READ;
                end
            end
            
            START_READ: begin
                next_state = READING;
            end
            
            READING: begin
                if (pixels_read_reg >= IMG_SIZE - 1) begin
                    next_state = FRAME_COMPLETE;
                end
            end
            
            FRAME_COMPLETE: begin
                next_state = WAIT_NEXT_FRAME;
            end
            
            WAIT_NEXT_FRAME: begin
                if (frame_start_sync) begin
                    next_state = START_READ;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Pixel counter logic - SIMPLIFIED
    always_comb begin
        pixels_read_next = pixels_read_reg;
        
        case (state)
            IDLE, WAIT_READY, START_READ: begin
                pixels_read_next = 18'd0;
            end
            
            READING: begin
                // Only increment when SDRAM provides data and FIFO has space
                if (sdram_rx_enable && !fifo_full) begin
                    if (pixels_read_reg < IMG_SIZE - 1) begin
                        pixels_read_next = pixels_read_reg + 1;
                    end
                end
            end
            
            default: begin
                pixels_read_next = pixels_read_reg;
            end
        endcase
    end
    
    // Output logic
    always_comb begin
        enable_read_mode = 1'b0;
        reading_active = 1'b0;
        frame_ready = 1'b0;
        
        case (state)
            START_READ: begin
                enable_read_mode = 1'b1;
                reading_active = 1'b0;
                frame_ready = 1'b0;
            end
            
            READING: begin
                enable_read_mode = 1'b1;
                reading_active = 1'b1;
                frame_ready = 1'b0;
            end
            
            FRAME_COMPLETE, WAIT_NEXT_FRAME: begin
                enable_read_mode = 1'b0;
                reading_active = 1'b0;
                frame_ready = 1'b1;
            end
            
            default: begin
                enable_read_mode = 1'b0;
                reading_active = 1'b0;
                frame_ready = 1'b0;
            end
        endcase
    end
    
    // CRITICAL: Output the current pixel address to SDRAM
    assign sdram_read_addr = {4'd0, pixels_read_reg};  // Pad to 22 bits if needed
    
    // FIFO write logic - simplified, no complex line tracking
    assign fifo_write_enable = sdram_rx_enable && reading_active && !fifo_full;
    
    // Choose data source for debugging
    // Normal operation:
    assign fifo_write_data = sdram_data;
    
    // For debugging - uncomment to use test pattern instead:
    // assign fifo_write_data = {13'd0, pixels_read_reg[2:0]};  // 8-color test pattern
    
    // Registers
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixels_read_reg <= 18'd0;
        end else begin
            state <= next_state;
            pixels_read_reg <= pixels_read_next;
        end
    end

endmodule