module multi_camera_capture #(
    parameter IMG_WIDTH = 640,
    parameter IMG_HEIGHT = 480
)(
    input  logic        clk,
    input  logic        rst,
    input  logic [3:0]  pclk,
    input  logic [3:0]  vsync,
    input  logic [3:0]  href,
    input  wire  [7:0]  data [3:0],

    output logic [15:0] pixel_data [3:0],
    output logic        pixel_valid [3:0],
    output logic        frame_done [3:0]
);

    logic byte_toggle [3:0];

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : camera_blocks
            ov7670_capture cam_inst (
                .clk(clk),
                .rst(rst),
                .pclk(pclk[i]),
                .vsync(vsync[i]),
                .href(href[i]),
                .data(data[i]),
                .frame_done(frame_done[i]),
                .pixel_data(pixel_data[i]),
                .byte_toggle(byte_toggle[i]),
                .pixel_valid(pixel_valid[i])
            );
        end
    endgenerate

endmodule
