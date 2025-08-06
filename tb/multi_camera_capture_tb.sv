module multi_camera_capture_tb;

    // System clock
    logic clk = 0;
    always #10 clk = ~clk; // 50 MHz

    // Pixel clocks for 4 cameras
    logic [3:0] pclk = 4'b0000;
    always #20 pclk[0] = ~pclk[0];
    always #20 pclk[1] = ~pclk[1];
    always #20 pclk[2] = ~pclk[2];
    always #20 pclk[3] = ~pclk[3];

    // Reset
    logic rst = 1;
    initial begin
        #100 rst = 0;
    end

    // Camera signals
    logic [3:0] vsync = 0;
    logic [3:0] href = 0;
    logic [7:0] data [3:0];

    // Outputs
    logic [15:0] pixel_data [3:0];
    logic pixel_valid [3:0];
    logic frame_done [3:0];

    // Instantiate DUT
    multi_camera_capture dut (
        .clk(clk),
        .rst(rst),
        .pclk(pclk),
        .vsync(vsync),
        .href(href),
        .data(data),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .frame_done(frame_done)
    );

    // Dummy image data
    logic [15:0] dummy_image [0:639];
    initial begin
        for (int i = 0; i < 640; i++) begin
            dummy_image[i] = 16'hF800 + i;
        end
    end

    // Simulate all cameras
    initial begin
        @(negedge rst);
        for (int cam = 0; cam < 4; cam++) begin
            automatic int local_cam = cam;
            fork
                simulate_camera(local_cam);
            join_none
        end
        #1; // DELAY 
    end

    // Camera simulation task
    task automatic simulate_camera(int cam_id);
        automatic int px = 0;
        $display("Camera %0d simulation started", cam_id);

        @(posedge pclk[cam_id]);
        vsync[cam_id] = 1;
        repeat (4) @(posedge pclk[cam_id]);
        vsync[cam_id] = 0;

        for (int row = 0; row < 480; row++) begin
            href[cam_id] = 1;
            for (int col = 0; col < 640; col++) begin
                data[cam_id] = dummy_image[col][15:8]; @(posedge pclk[cam_id]);
                data[cam_id] = dummy_image[col][7:0];  @(posedge pclk[cam_id]);
            end
            href[cam_id] = 0;
            repeat (10) @(posedge pclk[cam_id]);
        end
    endtask

    // Output monitor
    always @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            if (pixel_valid[i])
                $display("Cam %0d: Pixel = %h", i, pixel_data[i]);
            if (frame_done[i])
                $display("Cam %0d: Frame done!", i);
        end
    end

endmodule
