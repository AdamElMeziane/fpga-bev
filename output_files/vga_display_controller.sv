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

    // Image display logic with pixel doubling for 320x240 -> 640x480
    logic in_image_area;
    logic need_new_pixel;
    logic [15:0] current_pixel_data;
    logic [15:0] next_pixel_data;
    
    // Track the source pixel position (what we're reading from FIFO)
    logic [8:0] source_x;  // 0-319
    logic [7:0] source_y;  // 0-239
    
    // Calculate source pixel position (divide display position by 2)
    assign source_x = x[9:1];  // x / 2 (for 320 width)
    assign source_y = y[8:1];  // y / 2 (for 240 height)
    
    // We're displaying in the full 640x480 area with pixel doubling
    assign in_image_area = (x < 640) && (y < 480);
    
    // We need a new pixel when:
    // - We're at the start of a new 2x2 block (both x[0] and y[0] are 0)
    // - AND we're in the display area
    // - AND the source position is within the image bounds
    assign need_new_pixel = (x[0] == 1'b0) && (y[0] == 1'b0) && 
                           in_image_area && 
                           (source_x < IMG_WIDTH) && (source_y < IMG_HEIGHT);
    
    // Read FIFO when we need new pixel data
    assign fifo_read_enable = need_new_pixel && video_on && !fifo_empty;
    
    // Capture FIFO data when available
    always_ff @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            current_pixel_data <= 16'd0;
            next_pixel_data <= 16'd0;
        end else begin
            // If we read from FIFO, capture the data
            if (fifo_read_enable) begin
                next_pixel_data <= fifo_data;
            end
            
            // Update current pixel at the start of each 2x2 block
            if (need_new_pixel) begin
                current_pixel_data <= next_pixel_data;
            end
            
            // Clear data when we leave the image area
            if (!in_image_area || (source_x >= IMG_WIDTH) || (source_y >= IMG_HEIGHT)) begin
                current_pixel_data <= 16'd0;
            end
        end
    end
    
    // RGB output - display the same pixel for each 2x2 block
    always_ff @(posedge clk_vga or negedge rst_n) begin
        if (!rst_n) begin
            rgb <= 3'b000;
        end else begin
            if (in_image_area && video_on && 
                (source_x < IMG_WIDTH) && (source_y < IMG_HEIGHT)) begin
                // Display current pixel data for the entire 2x2 block
                rgb <= current_pixel_data[2:0];
            end else begin
                rgb <= 3'b000;  // Black outside image area
            end
        end
    end

endmodule