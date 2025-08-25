module vga_frame_reader (
    //==============================
    // System Signals
    //==============================
    input  logic        clk,         // Pixel clock (25 MHz)
    input  logic        rst_n,       // Active-low reset

    //==============================
    // VGA Timing Inputs
    //==============================
    input  logic [9:0]  x,           // Current pixel X coordinate
    input  logic [9:0]  y,           // Current pixel Y coordinate
    input  logic        video_on,    // High during visible area

    //==============================
    // SDRAM Controller Interface
    //==============================
    output logic [19:0] read_addr,   // Address to read from SDRAM
    output logic        start_read,  // Triggers SDRAM read
    input  logic [15:0] read_pixel,  // Pixel data from SDRAM
    input  logic        read_valid,  // High when read_pixel is valid

    //==============================
    // VGA Output
    //==============================
    output logic [2:0]  pixel_out    // Pixel to VGA (3-bit RGB)
);

    //==============================
    // Internal Registers
    //==============================
    logic [9:0]  x_d, y_d;         // Delayed coordinates
    logic        video_on_d;       // Delayed video_on
    logic        read_pending;     // Indicates a read is in progress

    //==============================
    // Delay VGA Coordinates
    //==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_d         <= 10'd0;
            y_d         <= 10'd0;
            video_on_d  <= 1'b0;
        end else begin
            x_d         <= x;
            y_d         <= y;
            video_on_d  <= video_on;
        end
    end

    //==============================
    // Read Trigger Logic
    //==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
        end else begin
            if (video_on && x < 320 && y < 240)
                read_pending <= 1'b1;
            else if (read_valid)
                read_pending <= 1'b0;
        end
    end

    //==============================
    // SDRAM Read Control
    //==============================
    assign read_addr   = (video_on && x < 320 && y < 240) ? (y * 320 + x) : 20'd0;
    assign start_read  = (video_on && x < 320 && y < 240);

    //==============================
    // VGA Pixel Output
    //==============================
    assign pixel_out = (video_on_d && read_valid) ? read_pixel[2:0] : 3'b000;

endmodule
