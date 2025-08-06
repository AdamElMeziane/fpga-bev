// VGA Display Controller that reads from FIFO buffer
// Handles the display of image data from SDRAM via FIFO

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
    
    // VGA timing generation (exactly like your working version)
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
    
    // VGA signal generation (exactly like your working version)
    assign x = h_count;
    assign y = v_count;
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign hsync = ~((h_count >= H_VISIBLE + H_FRONT) && 
                     (h_count < H_VISIBLE + H_FRONT + H_SYNC));
    assign vsync = ~((v_count >= V_VISIBLE + V_FRONT) && 
                     (v_count < V_VISIBLE + V_FRONT + V_SYNC));
    assign frame_start = (h_count == 0) && (v_count == 0);

    // Image display logic (similar to your working ROM version)
    logic in_image_area;
    assign in_image_area = (x < IMG_WIDTH) && (y < IMG_HEIGHT);
    
    // FIFO read logic - read when we need pixel data
    assign fifo_read_enable = in_image_area && video_on && !fifo_empty;
    
    // RGB output generation (exactly like your working version)
    always_ff @(posedge clk_vga) begin
        if (in_image_area && video_on && !fifo_empty) begin
            rgb <= fifo_data[2:0];  // Extract 3-bit RGB from FIFO data
        end else begin
            rgb <= 3'b000;
        end
    end

endmodule