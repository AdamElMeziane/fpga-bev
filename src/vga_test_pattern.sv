module vga_test_pattern (
    input  logic clk,              // 25 MHz pixel clock
    output logic hsync,
    output logic vsync,
    output logic [2:0] rgb         // {R, G, B}
);

    logic rst = 0;

    logic [9:0] x, y;
    logic [9:0] x_d, y_d;
    logic video_on, video_on_d;
    logic frame_start;

    logic [16:0] addr;
    logic [2:0] pixel;

    // VGA timing
    vga_controller ctrl (
        .clk(clk),
        .reset(rst),
        .hsync(hsync),
        .vsync(vsync),
        .x(x),
        .y(y),
        .video_on(video_on),
        .frame_start(frame_start)
    );

    // Delay coordinates by one cycle
    always_ff @(posedge clk) begin
        x_d <= x;
        y_d <= y;
        video_on_d <= video_on;
    end

    // Address calculation using delayed coordinates
    assign addr = (x_d < 320 && y_d < 240) ? (y_d * 320 + x_d) : 0;

    image_rom rom (
        .clk(clk),
        .addr(addr),
        .pixel(pixel)
    );

    // Display pixel only during visible area
    assign rgb = (x_d < 320 && y_d < 240 && video_on_d) ? pixel : 3'b000;

endmodule
