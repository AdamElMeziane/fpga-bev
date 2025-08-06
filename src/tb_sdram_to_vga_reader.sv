`timescale 1ns/1ps

module tb_sdram_to_vga_reader;

    logic clk_sdram = 0;
    logic clk_vga   = 0;
    always #3.75 clk_sdram = ~clk_sdram; // 133 MHz
    always #20   clk_vga   = ~clk_vga;   // 25 MHz

    logic video_on = 1;
    logic [9:0] x = 0, y = 0;
    logic frame_start = 0;

    logic cs_n, ras_n, cas_n, we_n, cke, dq_oe;
    logic [11:0] addr;
    logic [1:0]  ba;
    logic [15:0] dq;
    logic [2:0]  rgb;

    // SDRAM dummy response: return red pixel (RGB565 = 0xF800)
    always_ff @(posedge clk_sdram) begin
        if (!cs_n && ras_n && !cas_n && we_n) begin
            dq <= 16'hF800; // Red
        end
    end

    sdram_to_vga_reader dut (
        .clk_sdram(clk_sdram),
        .clk_vga(clk_vga),
        .video_on(video_on),
        .x(x),
        .y(y),
        .frame_start(frame_start),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .addr(addr),
        .ba(ba),
        .cke(cke),
        .dq(dq),
        .dq_oe(dq_oe),
        .rgb(rgb)
    );

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_sdram_to_vga_reader);

        // Trigger one frame
        #100;
        frame_start = 1;
        #10;
        frame_start = 0;

        // Simulate VGA scan
        repeat (320) begin
            #40;
            x = x + 1;
        end

        #1000;
        $finish;
    end

endmodule
