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
    localparam FIFO_SIZE = 2048;  // Match your FIFO size
    
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
    
    // Pixel and line tracking
    logic [17:0] pixels_read_reg, pixels_read_next;
    logic [9:0] current_line, current_line_next;
    logic [9:0] pixels_in_line, pixels_in_line_next;
    logic reading_active;
    logic frame_start_sync, frame_start_prev;
    logic sdram_ready_latched;
    
    // Track VGA consumption (synchronized to SDRAM clock)
    logic [9:0] vga_y_sync1, vga_y_sync2;
    logic [9:0] last_vga_line;
    logic vga_needs_data;
    
    // Synchronize VGA Y position to SDRAM clock
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            vga_y_sync1 <= 10'd0;
            vga_y_sync2 <= 10'd0;
            last_vga_line <= 10'd0;
        end else begin
            vga_y_sync1 <= vga_y;
            vga_y_sync2 <= vga_y_sync1;
            // Track when VGA moves to a new line
            if (vga_y_sync2 != last_vga_line && vga_y_sync2 < IMG_HEIGHT) begin
                last_vga_line <= vga_y_sync2;
            end
        end
    end
    
    // Calculate if VGA needs more data (don't get too far ahead)
    // We want to stay at most 2-3 lines ahead of VGA
    assign vga_needs_data = (current_line <= last_vga_line + 3);
    
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
    
    // Pixel and line counter logic
    always_comb begin
        pixels_read_next = pixels_read_reg;
        current_line_next = current_line;
        pixels_in_line_next = pixels_in_line;
        
        case (state)
            IDLE, WAIT_READY, START_READ: begin
                pixels_read_next = 18'd0;
                current_line_next = 10'd0;
                pixels_in_line_next = 10'd0;
            end
            
            READING: begin
                // Only write when:
                // 1. SDRAM has data
                // 2. FIFO has space (preferably at least one line worth)
                // 3. VGA needs more data (not too far ahead)
                if (sdram_rx_enable && !fifo_full && vga_needs_data) begin
                    if (pixels_read_reg < IMG_SIZE - 1) begin
                        pixels_read_next = pixels_read_reg + 1;
                        
                        // Track line position
                        if (pixels_in_line == IMG_WIDTH - 1) begin
                            pixels_in_line_next = 10'd0;
                            current_line_next = current_line + 1;
                        end else begin
                            pixels_in_line_next = pixels_in_line + 1;
                        end
                    end
                end
            end
            
            default: begin
                pixels_read_next = pixels_read_reg;
                current_line_next = current_line;
                pixels_in_line_next = pixels_in_line;
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
    
    // FIFO write logic - only write valid data when not too far ahead
    assign fifo_write_enable = sdram_rx_enable && reading_active && 
                              !fifo_full && vga_needs_data;
    assign fifo_write_data = sdram_data;
    
    // Registers
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixels_read_reg <= 18'd0;
            current_line <= 10'd0;
            pixels_in_line <= 10'd0;
        end else begin
            state <= next_state;
            pixels_read_reg <= pixels_read_next;
            current_line <= current_line_next;
            pixels_in_line <= pixels_in_line_next;
        end
    end

endmodule