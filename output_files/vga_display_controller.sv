module vga_display_controller #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240
)(
    input  logic clk_vga,         // 25MHz VGA pixel clock
    input  logic rst_n,
    
    // VGA timing outputs
    output logic hsync,
    output logic vsync,
    output logic video_on,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic frame_start,
    
    // FIFO interface
    output logic fifo_read_enable,
    input  logic [15:0] fifo_data,
    input  logic fifo_empty,
    input  logic fifo_half_full,
    
    // VGA RGB output
    output logic [2:0] rgb
);

    // VGA 640x480 @ 60Hz timing parameters
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    
    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    // VGA timing counters
    logic [9:0] h_count, v_count;
    
    // VGA timing generation
    always_ff @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end
    
    // VGA signal generation
    assign x = h_count;
    assign y = v_count;
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign hsync = ~((h_count >= H_VISIBLE + H_FRONT) && 
                     (h_count < H_VISIBLE + H_FRONT + H_SYNC));
    assign vsync = ~((v_count >= V_VISIBLE + V_FRONT) && 
                     (v_count < V_VISIBLE + V_FRONT + V_SYNC));
    assign frame_start = (h_count == 0) && (v_count == 0);

    // Image display logic with proper pixel doubling for 320x240 -> 640x480
    logic in_image_area;
    logic need_new_pixel;
    logic fifo_was_read;  // Track if we read from FIFO last cycle
    logic [15:0] current_pixel_data;  // Store the current pixel data
    logic pixel_valid;  // Track if we have valid pixel data
    
    // We're in the image area if we're in the top-left 320x240 region
    // But since we're displaying at 640x480, we need to double pixels
    // So image area is actually the top-left 640x480 region (doubled)
    assign in_image_area = (x < (IMG_WIDTH * 2)) && (y < (IMG_HEIGHT * 2));
    
    // We need a new pixel from FIFO when:
    // - We're at an even X and even Y position (start of a 2x2 block)
    // - We're in the image area
    // - We don't have valid data
    assign need_new_pixel = (x[0] == 1'b0) && (y[0] == 1'b0) && 
                           in_image_area && !pixel_valid;
    
    // Read FIFO when we need new pixel data
    assign fifo_read_enable = need_new_pixel && video_on && !fifo_empty;
    
    // Track FIFO read and pixel data
    always_ff @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            fifo_was_read <= 1'b0;
            current_pixel_data <= 16'd0;
            pixel_valid <= 1'b0;
        end else begin
            // Track if we initiated a read
            fifo_was_read <= fifo_read_enable;
            
            // If we read from FIFO last cycle, capture the data
            if (fifo_was_read) begin
                current_pixel_data <= fifo_data;
                pixel_valid <= 1'b1;
            end
            
            // Invalidate pixel when we leave the 2x2 block
            // This happens when both x[0] and y[0] are 1 and we're about to move to next block
            if ((x[0] == 1'b1) && (y[0] == 1'b1) && in_image_area) begin
                // About to move to next 2x2 block
                if (x < (IMG_WIDTH * 2 - 1)) begin
                    // Still more pixels in this line
                    pixel_valid <= 1'b0;
                end else if (y[0] == 1'b1 && x >= (IMG_WIDTH * 2 - 1)) begin
                    // End of doubled line, moving to next source line
                    pixel_valid <= 1'b0;
                end
            end
            
            // Also invalidate at start of frame or when leaving image area
            if (frame_start || !in_image_area) begin
                pixel_valid <= 1'b0;
            end
        end
    end
    
    // RGB output - use stored pixel data for the 2x2 block
    always_ff @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            rgb <= 3'b000;
        end else begin
            if (in_image_area && pixel_valid && video_on) begin
                rgb <= current_pixel_data[2:0];  // Use the stored pixel data
            end else begin
                rgb <= 3'b000;  // Black outside image area or when no valid data
            end
        end
    end

endmodule