module vga_test_top (
    input  logic clk_50MHz,
    output logic vga_hsync,
    output logic vga_vsync,
    output logic [4:0] vga_red,
    output logic [5:0] vga_green,
    output logic [4:0] vga_blue
);

    // Generate 25 MHz clock from 50 MHz input
    logic clk_25MHz;
    logic clk_div = 0;

    always_ff @(posedge clk_50MHz)
        clk_div <= ~clk_div;

    assign clk_25MHz = clk_div;

    // 3-bit RGB output from image pattern
    logic [2:0] rgb;

    // Instantiate the image-based VGA pattern generator
    vga_test_pattern pattern (
        .clk(clk_25MHz),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .rgb(rgb)
    );

    // Map 3-bit RGB to MSBs of VGA output
    assign vga_red[0]   = rgb[2];
    assign vga_green[0] = rgb[1];
    assign vga_blue[0]  = rgb[0];

    // Tie unused bits to 0
    assign vga_red[4:1]   = 4'b0;
    assign vga_green[5:1] = 5'b0;
    assign vga_blue[4:1]  = 4'b0;

endmodule
