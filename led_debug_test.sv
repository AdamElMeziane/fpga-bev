// Simple LED test to debug what's actually connected
// This will help us figure out which LEDs are real vs floating

module led_debug_test (
    input  logic        clk_50MHz,
    input  logic        reset_n,
    input  logic        start_button,
    
    output logic [3:0]  status_leds,
    
    // VGA outputs (minimal to avoid issues)
    output logic [0:0]  vga_red,
    output logic [0:0]  vga_green,
    output logic [0:0]  vga_blue,
    output logic        vga_hsync,
    output logic        vga_vsync
);

    // Simple counter for blinking
    logic [25:0] counter;
    logic button_sync1, button_sync2, button_pressed;
    logic button_state;
    
    always_ff @(posedge clk_50MHz or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 26'd0;
            button_sync1 <= 1'b0;
            button_sync2 <= 1'b0;
            button_state <= 1'b0;
        end else begin
            counter <= counter + 1;
            
            // Synchronize button
            button_sync1 <= start_button;
            button_sync2 <= button_sync1;
            
            // Toggle state on button press
            if (button_sync2 && !button_sync1) begin // falling edge
                button_state <= ~button_state;
            end
        end
    end
    
    // LED test patterns for ACTIVE-LOW LEDs
    assign status_leds[0] = ~counter[23];             // Slow blink (~6Hz)
    assign status_leds[1] = ~counter[22];             // Medium blink (~12Hz)  
    assign status_leds[2] = ~button_state;            // Button toggle state (OFF when pressed)
    assign status_leds[3] = ~start_button;            // Direct button input (OFF when pressed)
    
    // Minimal VGA (black screen)
    assign vga_red = 1'b0;
    assign vga_green = 1'b0;
    assign vga_blue = 1'b0;
    assign vga_hsync = 1'b1;
    assign vga_vsync = 1'b1;

endmodule