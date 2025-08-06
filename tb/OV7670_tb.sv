module ov7670_capture_tb;

    // TB signals
    reg clk = 0;
    reg pclk = 0;
    reg rst = 1;
    reg [19:0] pixel_index = 0;

    // Clocks
    always #10 clk = ~clk;         // 50 MHz system clock (20 ns period)
    always #20.83 pclk = ~pclk;    // ~24 MHz pixel clock (41.67 ns period)

    // DUT signals
    reg vsync = 0;
    reg href = 0;
    reg [7:0] data = 8'd0;
    wire frame_done;
    wire [15:0] pixel_data;
    wire byte_toggle;
    wire pixel_valid;

    ov7670_capture dut (
        .clk(clk),
        .pclk(pclk),
        .rst(rst),
        .vsync(vsync),
        .href(href),
        .data(data),
        .frame_done(frame_done),
        .pixel_data(pixel_data),
        .byte_toggle(byte_toggle),
        .pixel_valid(pixel_valid)
    );

    // Image memory
    reg [15:0] image_data [0:307199];
    reg [15:0] captured_image [0:307199];
    integer capture_index = -1;

    // Load image data
    initial begin
        $readmemh("C:/Users/aelmezia/Desktop/PFA 1/Project/assets/image.mem", image_data);
    end

    // Reset logic
    initial begin
        #100 rst = 0;
    end

    // Camera simulation
    initial begin
        @(negedge rst);

        // VSYNC pulse to start frame
        @(posedge pclk);
        vsync = 1;
        repeat (4) @(posedge pclk);
        vsync = 0;

        // Send 480 rows
        for (integer row = 0; row < 480; row = row + 1) begin
            href = 1;
            for (integer col = 0; col < 640; col = col + 1) begin
                // Send MSB
                data = image_data[pixel_index][15:8];
                @(posedge pclk);

                // Send LSB
                data = image_data[pixel_index][7:0];
                @(posedge pclk);

                pixel_index = pixel_index + 1;
            end
            href = 0;
            repeat (10) @(posedge pclk); // small gap between lines
        end

        $display("Frame transmission complete.");
    end

    // Capture pixel when valid
    always @(posedge pclk) begin
        if (pixel_valid) begin
            capture_index = capture_index + 1;
            captured_image[capture_index] <= pixel_data;
        end
    end

    // Write captured image to file when frame is done
    always @(posedge frame_done) begin
        $writememh("C:/Users/aelmezia/Desktop/PFA 1/Project/assets/captured_output.mem", captured_image);
        $display("Captured image written to captured_output.mem");
        $finish;
    end

endmodule
