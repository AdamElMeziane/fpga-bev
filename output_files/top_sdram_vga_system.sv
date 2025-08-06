// Complete SDRAM-VGA Display System - FIXED VERSION
// Proper initialization sequencing and button handling
// Displays 320x240 image from ROM via SDRAM buffering

module top_sdram_vga_system (
    input  logic        clk_50MHz,
    input  logic        reset_n,
    input  logic        start_button,      // Active-low button to start image loading

    // VGA outputs
    output logic [0:0]  vga_red,
    output logic [0:0]  vga_green,
    output logic [0:0]  vga_blue,
    output logic        vga_hsync,
    output logic        vga_vsync,

    // SDRAM interface
    inout  wire [15:0]  dq,
    output logic        sclk,
    output logic        cke,
    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  bank,
    output logic        udqm,
    output logic        ldqm,
    
    // Status LEDs (active-low for debugging)
    output logic [3:0]  status_leds
);

    // Clock generation
    logic clk_133, clk_25, pll_locked;
    logic reset_sync_133, reset_sync_25;

    // PLL for clock generation
    pll_133Mhz pll_inst (
        .areset(~reset_n),
        .inclk0(clk_50MHz),
        .c0(clk_133),          // 133MHz for SDRAM
        .locked(pll_locked)
    );

    // Generate 25MHz VGA clock (exactly like your working version)
    logic clk_div = 0;
    always_ff @(posedge clk_50MHz)
        clk_div <= ~clk_div;
    assign clk_25 = clk_div;

    // Reset synchronizers
    always_ff @(posedge clk_133 or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync_133 <= 1'b0;
        end else begin
            reset_sync_133 <= pll_locked;
        end
    end

    always_ff @(posedge clk_25 or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync_25 <= 1'b0;
        end else begin
            reset_sync_25 <= 1'b1;
        end
    end

    //========================================================================
    // Button handling with proper edge detection for active-low button
    //========================================================================
    logic start_sync1, start_sync2, start_sync3;
    logic button_pressed_pulse;
    logic button_was_pressed;
    
    always_ff @(posedge clk_133 or negedge reset_sync_133) begin
        if (!reset_sync_133) begin
            start_sync1 <= 1'b1;  // Default high (not pressed)
            start_sync2 <= 1'b1;
            start_sync3 <= 1'b1;
            button_was_pressed <= 1'b0;
        end else begin
            start_sync1 <= start_button;
            start_sync2 <= start_sync1;
            start_sync3 <= start_sync2;
            
            // Detect falling edge (button press) for active-low button
            if (!start_sync2 && start_sync3) begin
                button_was_pressed <= 1'b1;
            end else if (button_was_pressed && loader_loading_complete) begin
                button_was_pressed <= 1'b0;
            end
        end
    end
    
    // Generate single pulse on button press
    assign button_pressed_pulse = !start_sync2 && start_sync3;

    //========================================================================
    // System State Machine for proper sequencing
    //========================================================================
    typedef enum logic [2:0] {
        SYS_WAIT_INIT,
        SYS_WAIT_BUTTON,
        SYS_LOADING,
        SYS_DISPLAYING,
        SYS_ERROR
    } sys_state_t;
    
    sys_state_t sys_state, sys_next_state;
    logic sdram_init_done;
    logic [23:0] timeout_counter;
    
    always_ff @(posedge clk_133 or negedge reset_sync_133) begin
        if (!reset_sync_133) begin
            sys_state <= SYS_WAIT_INIT;
            timeout_counter <= '0;
        end else begin
            sys_state <= sys_next_state;
            
            // Timeout counter for debugging
            if (sys_state == SYS_WAIT_INIT) begin
                if (timeout_counter < 24'hFFFFFF) begin
                    timeout_counter <= timeout_counter + 1;
                end
            end else begin
                timeout_counter <= '0;
            end
        end
    end
    
    always_comb begin
        sys_next_state = sys_state;
        case (sys_state)
            SYS_WAIT_INIT: begin
                if (sdram_init_done) begin
                    sys_next_state = SYS_WAIT_BUTTON;
                end else if (timeout_counter == 24'hFFFFFF) begin
                    sys_next_state = SYS_ERROR;  // Timeout - SDRAM init failed
                end
            end
            
            SYS_WAIT_BUTTON: begin
                if (button_pressed_pulse || button_was_pressed) begin
                    sys_next_state = SYS_LOADING;
                end
            end
            
            SYS_LOADING: begin
                if (loader_loading_complete) begin
                    sys_next_state = SYS_DISPLAYING;
                end
            end
            
            SYS_DISPLAYING: begin
                // Stay here
            end
            
            SYS_ERROR: begin
                // Stay in error state
            end
        endcase
    end

    //========================================================================
    // SDRAM Controller Signals
    //========================================================================
    logic sdram_start;
    logic sdram_enable_write_mode, sdram_enable_read_mode;
    logic [15:0] sdram_incoming_data, sdram_outgoing_data;
    logic sdram_enable_transmitter, sdram_enable_receiver;

    // Start SDRAM when PLL is locked
    assign sdram_start = pll_locked;

    sdram_controller sdram_ctrl (
        .rst_n(reset_sync_133),
        .clk(clk_133),
        .start(sdram_start),
        .enable_write_mode(sdram_enable_write_mode),
        .enable_read_mode(sdram_enable_read_mode),
        .incoming_data(sdram_incoming_data),
        .outgoing_data(sdram_outgoing_data),
        .enable_transmitter(sdram_enable_transmitter),
        .enable_receiver(sdram_enable_receiver),
        .sdram_init_done(sdram_init_done),  // NEW: Get init status
        .dq(dq),
        .sclk(sclk),
        .cke(cke),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .addr(addr),
        .bank(bank),
        .udqm(udqm),
        .ldqm(ldqm)
    );

    //========================================================================
    // Image Loader (ROM to SDRAM)
    //========================================================================
    logic loader_loading_complete;
    logic loader_enable_write;
    logic loader_start;
    
    // Start loading when in LOADING state
    assign loader_start = (sys_state == SYS_LOADING);

    image_loader #(
        .IMG_WIDTH(320),
        .IMG_HEIGHT(240),
        .DATA_WIDTH(16)
    ) img_loader (
        .rst_n(reset_sync_133),
        .clk(clk_133),
        .start_loading(loader_start),
        .sdram_ready(1'b1),  // Always ready once we're in LOADING state
        .sdram_tx_enable(sdram_enable_transmitter),
        .pixel_data(sdram_incoming_data),
        .enable_write_mode(loader_enable_write),
        .loading_complete(loader_loading_complete)
    );

    //========================================================================
    // VGA Timing Generator with FIFO interface
    //========================================================================
    logic vga_video_on, vga_frame_start;
    logic [9:0] vga_x, vga_y;
    logic fifo_read_enable;
    logic [15:0] fifo_read_data;
    logic fifo_empty, fifo_half_full;
    logic [2:0] vga_rgb;

    vga_display_controller #(
        .IMG_WIDTH(320),
        .IMG_HEIGHT(240)
    ) vga_ctrl (
        .clk_vga(clk_25),
        .rst_n(reset_sync_25),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .video_on(vga_video_on),
        .x(vga_x),
        .y(vga_y),
        .frame_start(vga_frame_start),
        .fifo_read_enable(fifo_read_enable),
        .fifo_data(fifo_read_data),
        .fifo_empty(fifo_empty),
        .fifo_half_full(fifo_half_full),
        .rgb(vga_rgb)
    );

    //========================================================================
    // FIFO Buffer (Clock Domain Crossing)
    //========================================================================
    logic fifo_write_enable;
    logic [15:0] fifo_write_data;
    logic fifo_full;

    fifo_buffer #(
        .ADDR_WIDTH(9),    // 512 entries for good buffering
        .DATA_WIDTH(16)
    ) pixel_fifo (
        .rst_n(reset_sync_133 & reset_sync_25),
        .clk_write(clk_133),
        .clk_read(clk_25),
        .write_enable(fifo_write_enable),
        .write_data(fifo_write_data),
        .fifo_full(fifo_full),
        .read_enable(fifo_read_enable),
        .read_data(fifo_read_data),
        .fifo_empty(fifo_empty),
        .fifo_half_full(fifo_half_full)
    );

    //========================================================================
    // VGA Frame Reader (SDRAM to FIFO)
    //========================================================================
    logic reader_enable_read_mode;
    logic reader_frame_ready;
    logic reader_start;
    
    // Enable reading when displaying
    assign reader_start = (sys_state == SYS_DISPLAYING);

    vga_frame_reader #(
        .IMG_WIDTH(320),
        .IMG_HEIGHT(240),
        .DATA_WIDTH(16)
    ) frame_reader (
        .rst_n(reset_sync_133),
        .clk_sdram(clk_133),
        .clk_vga(clk_25),
        .sdram_ready(reader_start),  // Start reading when in DISPLAYING state
        .sdram_rx_enable(sdram_enable_receiver),
        .sdram_data(sdram_outgoing_data),
        .enable_read_mode(reader_enable_read_mode),
        .frame_start(vga_frame_start),
        .video_on(vga_video_on),
        .vga_x(vga_x),  
        .vga_y(vga_y),
        .fifo_write_enable(fifo_write_enable),
        .fifo_write_data(fifo_write_data),
        .fifo_full(fifo_full),
        .fifo_half_full(fifo_half_full),
        .frame_ready(reader_frame_ready)
    );

    //========================================================================
    // Control Logic with proper arbitration
    //========================================================================
    
    // SDRAM mode control - ensure only one mode active at a time
    always_comb begin
        sdram_enable_write_mode = 1'b0;
        sdram_enable_read_mode = 1'b0;
        
        case (sys_state)
            SYS_LOADING: begin
                sdram_enable_write_mode = loader_enable_write;
            end
            
            SYS_DISPLAYING: begin
                sdram_enable_read_mode = reader_enable_read_mode;
            end
            
            default: begin
                // No SDRAM access
            end
        endcase
    end

    //========================================================================
    // VGA Output Assignment
    //========================================================================
    assign vga_red[0]   = vga_rgb[2];
    assign vga_green[0] = vga_rgb[1];
    assign vga_blue[0]  = vga_rgb[0];

    //========================================================================
    // Status LEDs for Debugging (ACTIVE-LOW LEDs)
    //========================================================================
    always_comb begin
        case (sys_state)
            SYS_WAIT_INIT:   status_leds = 4'b1110;  // LED0 on: waiting for init
            SYS_WAIT_BUTTON: status_leds = 4'b1101;  // LED1 on: waiting for button
            SYS_LOADING:     status_leds = 4'b1011;  // LED2 on: loading
            SYS_DISPLAYING:  status_leds = 4'b0111;  // LED3 on: displaying
            SYS_ERROR:       status_leds = 4'b0000;  // All LEDs on: error
            default:         status_leds = 4'b1111;  // All LEDs off
        endcase
    end

endmodule