module ov7670_capture (
    input wire clk,
    input wire rst,
    input wire pclk,
    input wire vsync,
    input wire href,
    input wire [7:0] data,
    output reg frame_done,
    output reg [15:0] pixel_data,
    output reg byte_toggle,
    output reg pixel_valid
);

reg [19:0] pixel_count;

always @(posedge pclk or posedge rst) begin
    if (rst) begin
        pixel_data   <= 0;
        byte_toggle  <= 0;
        pixel_count  <= 0;
        frame_done   <= 0;
        pixel_valid  <= 0;
    end else if (!vsync && href) begin
        if (!byte_toggle) begin
            pixel_data[15:8] <= data; // MSB
            pixel_valid <= 0;
        end else begin
            pixel_data[7:0] <= data;  // LSB
            pixel_count <= pixel_count + 1;
            pixel_valid <= 1;
        end
        byte_toggle <= ~byte_toggle;
    end else begin
        byte_toggle <= 0;
        pixel_valid <= 0;
        if (!vsync && pixel_count == 307200) begin
            frame_done <= 1;
            pixel_count <= 0;
        end else begin
            frame_done <= 0;
        end
    end
end

endmodule
