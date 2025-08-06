module vga_display_top (
    input clk_25mhz, 
    input rst,
    output logic hsync,
    output logic vsync,
    output logic [4:0] red,
    output logic [5:0] green,
    output logic [4:0] blue
);

// internal signals
logic [9:0] x, y;
logic video_on;

// instantiationS
vga_controller vga_ctrl (
    .clk(clk_25mhz),
    .rst(rst),
    .hsync(hsync),
    .vsync(vsync),
    .x(x),
    .y(y),
    .video_on(video_on)
);

vga_test_pattern pat (
    .x(x),
    .y(y),
    .video_on(video_on),
    .red(red),
    .green(green),
    .blue(blue)
);

endmodule