module vga_frame_reader #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240,
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk_sdram,         // 143MHz SDRAM clock
    input  logic clk_vga,           // 25MHz VGA clock
    
    // SDRAM interface
    input  logic sdram_ready,       // System is ready for reading
    input  logic sdram_rx_enable,   // SDRAM provides data
    input  logic [DATA_WIDTH-1:0] sdram_data,
    output logic enable_read_mode,
    output logic [17:0] sdram_read_addr,  // Not used by SDRAM controller
    
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

    localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 76,800
    
    // Frame reading FSM
    typedef enum logic [2:0] {
        IDLE,
        WAIT_READY,
        READING,
        WAIT_FRAME
    } read_state_t;
    
    read_state_t state, next_state;
    
    // Pixel counter
    logic [17:0] pixel_count, pixel_count_next;
    logic sdram_ready_latched;
    
    // Frame synchronization
    logic frame_start_sync1, frame_start_sync2, frame_start_prev;
    logic frame_start_edge;
    
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
    assign frame_start_edge = frame_start_sync2 & ~frame_start_prev;
    
    // FSM next state logic
    always_comb begin
        next_state = state;
        pixel_count_next = pixel_count;
        
        case (state)
            IDLE: begin
                if (sdram_ready_latched) begin
                    next_state = WAIT_READY;
                end
                pixel_count_next = '0;
            end
            
            WAIT_READY: begin
                if (frame_start_edge) begin
                    next_state = READING;
                    pixel_count_next = '0;
                end
            end
            
            READING: begin
                // Continuously read, wrapping at frame boundary
                if (sdram_rx_enable && !fifo_full) begin
                    if (pixel_count >= TOTAL_PIXELS - 1) begin
                        pixel_count_next = '0;  // Wrap to start
                    end else begin
                        pixel_count_next = pixel_count + 1;
                    end
                end
            end
            
            WAIT_FRAME: begin
                if (frame_start_edge) begin
                    next_state = READING;
                    pixel_count_next = '0;
                end
            end
        endcase
    end
    
    // Output control
    always_comb begin
        enable_read_mode = 1'b0;
        fifo_write_enable = 1'b0;
        fifo_write_data = sdram_data;
        frame_ready = 1'b0;
        
        case (state)
            READING: begin
                enable_read_mode = !fifo_full;
                fifo_write_enable = sdram_rx_enable && !fifo_full;
                frame_ready = (pixel_count > 0);
            end
            
            WAIT_FRAME: begin
                frame_ready = 1'b1;
            end
        endcase
    end
    
    // Dummy address output (not used by SDRAM controller)
    assign sdram_read_addr = pixel_count;
    
    // State registers
    always_ff @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_count <= '0;
        end else begin
            state <= next_state;
            pixel_count <= pixel_count_next;
        end
    end

endmodule