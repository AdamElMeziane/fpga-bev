module button_led_test_top (
    input  logic        clk_50MHz,
    input  logic [1:0]  buttons,
    output logic        test_pass_led,
    output logic        write_done_led
);

    logic [1:0] btn_sync;
    logic [1:0] btn_prev;
    logic [1:0] toggle;

    // Simple button edge detection (rising edge)
    always_ff @(posedge clk_50MHz) begin
        btn_sync <= buttons;
        btn_prev <= btn_sync;

        if (btn_sync[0] && !btn_prev[0])
            toggle[0] <= ~toggle[0];

        if (btn_sync[1] && !btn_prev[1])
            toggle[1] <= ~toggle[1];
    end

    // Active-low LEDs
    assign test_pass_led = 0;  // LED2 on when toggle[0] is 1
    assign write_done_led = ~toggle[1];  // LED3 on when toggle[1] is 1

endmodule
