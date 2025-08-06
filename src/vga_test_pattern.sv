module vga_test_pattern (
    input  logic clk,              // 25 MHz pixel clock
    output logic hsync,
    output logic vsync,
    output logic [2:0] rgb         // {R, G, B}
);

    logic rst = 0;

    logic [9:0] x, y;
    logic video_on;

    logic [17:0] addr;
    logic [2:0] pixel;

    // VGA timing
    vga_controller ctrl (
        .clk(clk),
        .reset(rst),
        .hsync(hsync),
        .vsync(vsync),
        .x(x),
        .y(y),
        .video_on(video_on)
    );

    // Address calculation for 320×240 image
    assign addr = (x < 320 && y < 240) ? (y * 320 + x) : 0;

    image_rom rom (
        .clk(clk),
        .addr(addr),
        .pixel(pixel)
    );

    assign rgb = (x < 320 && y < 240 && video_on) ? pixel : 3'b000;

endmodule
