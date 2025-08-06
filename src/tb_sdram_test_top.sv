`timescale 1ns/1ps

module tb_sdram_test_top;

    logic clk_50MHz;
    logic reset_n;
    logic [1:0] buttons;
    logic test_pass_led;
    logic write_done_led;

    logic cs_n, ras_n, cas_n, we_n;
    logic [11:0] addr;
    logic [1:0] bank;
    logic cke;
    logic sclk;
    logic ldqm, udqm;
    wire [15:0] dq;
    logic [15:0] dq_driver;
    logic dq_drive_en;

    // Instantiate DUT
    sdram_test_top dut (
        .clk_50MHz(clk_50MHz),
        .reset_n(reset_n),
        .buttons(buttons),
        .test_pass_led(test_pass_led),
        .write_done_led(write_done_led),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .addr(addr),
        .bank(bank),
        .cke(cke),
        .sclk(sclk),
        .ldqm(ldqm),
        .udqm(udqm),
        .dq(dq)
    );

    // Clock generation
    initial clk_50MHz = 0;
    always #10 clk_50MHz = ~clk_50MHz; // 50 MHz

    // Emulate bidirectional dq
    assign dq = dq_drive_en ? dq_driver : 16'hzz;

    // Stimulus
    initial begin
        $display("Starting SDRAM top-level test...");
        reset_n = 0;
        buttons = 2'b00;
        dq_driver = 16'hzzzz;
        dq_drive_en = 0;

        #100;
        reset_n = 1;

        // Wait for init_done to go high
        wait (dut.init_done == 1);
        $display("SDRAM initialized.");

        // Trigger write
        buttons[0] = 1;
        #40;
        buttons[0] = 0;

        // Wait for write to complete
        wait (write_done_led == 0);
        $display("Write completed.");

        // Trigger read
        buttons[1] = 1;
        #40;
        buttons[1] = 0;

        // Drive dq during READ state
        wait (dut.u_rw.state == dut.u_rw.READ);
        dq_driver = 16'hCAFE;
        dq_drive_en = 1;
        #40;
        dq_drive_en = 0;
        dq_driver = 16'hzzzz;

        // Wait for COMPARE and LED latch
        #100;

        if (test_pass_led == 0)
            $display("Test Passed: Data matched.");
        else
            $display("Test Failed: LED not set.");

        $stop;
    end

endmodule
