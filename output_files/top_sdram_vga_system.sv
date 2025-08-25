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
    pll_133Mhz pll_inst (  // Module name unchanged but outputs 143MHz
        .areset(~reset_n),
        .inclk0(clk_50MHz),
        .c0(clk_133),          // Actually 143MHz for -7 speed grade
        .locked(pll_locked)
    );

    // Generate 25MHz VGA clock
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
    
    always_ff @(posedge clk_133 or negedge reset_sync_133) begin
        if (!reset_sync_133) begin
            start_sync1 <= 1'b1;
            start_sync2 <= 1'b1;
            start_sync3 <= 1'b1;
        end else begin
            start_sync1 <= start_button;
            start_sync2 <= start_sync1;
            start_sync3 <= start_sync2;
        end
    end
    
    // Generate single pulse on button press
    assign button_pressed_pulse = !start_sync2 && start_sync3;

    //========================================================================
    // System State Machine
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
    logic loader_loading_complete;
    
    always_ff @(posedge clk_133 or negedge reset_sync_133) begin
        if (!reset_sync_133) begin
            sys_state <= SYS_WAIT_INIT;
        end else begin
            sys_state <= sys_next_state;
        end
    end
    
    always_comb begin
        sys_next_state = sys_state;
        case (sys_state)
            SYS_WAIT_INIT: begin
                if (sdram_init_done) begin
                    sys_next_state = SYS_WAIT_BUTTON;
                end
            end
            
            SYS_WAIT_BUTTON: begin
                if (button_pressed_pulse) begin
                    sys_next_state = SYS_LOADING;
                end
            end
            
            SYS_LOADING: begin
                if (loader_loading_complete) begin
                    sys_next_state = SYS_DISPLAYING;
                end
            end
            
            SYS_DISPLAYING: begin
                // Stay here - continuously display
            end
            
            SYS_ERROR: begin
                // Stay in error state
            end
        endcase
    end

    //========================================================================
    // Image ROM
    //========================================================================
    logic [17:0] rom_addr;
    logic [2:0] rom_pixel;
    
    image_rom img_rom (
        .clk(clk_133),
        .addr(rom_addr),
        .pixel(rom_pixel)
    );

    //========================================================================
    // SDRAM Controller (using original without wrapper for now)
    //========================================================================
    logic sdram_start;
    logic sdram_enable_write_mode, sdram_enable_read_mode;
    logic [15:0] sdram_incoming_data, sdram_outgoing_data;
    logic sdram_enable_transmitter, sdram_enable_receiver;

    // Start SDRAM when PLL is locked
    assign sdram_start = pll_locked;

    // Use the controller from document 8 (already in your files)
    // It expects sequential access and manages its own addressing
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
        .sdram_init_done(sdram_init_done),
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
    logic loader_start;
    logic [17:0] loader_sdram_addr;  // Address from loader (ignored by SDRAM controller)
    logic loader_write_enable;
    logic [15:0] loader_write_data;
    
    assign loader_start = (sys_state == SYS_LOADING);

    image_loader #(
        .IMG_WIDTH(320),
        .IMG_HEIGHT(240),
        .DATA_WIDTH(16)
    ) img_loader (
        .rst_n(reset_sync_133),
        .clk(clk_133),
        .start_loading(loader_start),
        .sdram_ready(sdram_init_done),
        .sdram_tx_enable(sdram_enable_transmitter),
        .rom_addr(rom_addr),
        .rom_pixel(rom_pixel),
        .pixel_data(loader_write_data),
        .sdram_write_addr(loader_sdram_addr),  // Connected but ignored by SDRAM
        .enable_write_mode(loader_write_enable),
        .loading_complete(loader_loading_complete)
    );

    //========================================================================
    // VGA Display Controller
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
    // FIFO Buffer (Clock Domain Crossing) - 16-bit throughout
    //========================================================================
    logic fifo_write_enable;
    logic [15:0] fifo_write_data;
    logic fifo_full;

    fifo_buffer #(
        .ADDR_WIDTH(11),    // 2048 entries
        .DATA_WIDTH(16)     // 16-bit data throughout
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
    logic reader_enable_read;
    logic [17:0] reader_sdram_addr;  // Address from reader (ignored by SDRAM)
    logic reader_frame_ready;
    logic reader_start;
    
    assign reader_start = (sys_state == SYS_DISPLAYING);

    vga_frame_reader #(
        .IMG_WIDTH(320),
        .IMG_HEIGHT(240),
        .DATA_WIDTH(16)
    ) frame_reader (
        .rst_n(reset_sync_133),
        .clk_sdram(clk_133),
        .clk_vga(clk_25),
        .sdram_ready(reader_start),
        .sdram_rx_enable(sdram_enable_receiver),
        .sdram_data(sdram_outgoing_data),
        .enable_read_mode(reader_enable_read),
        .sdram_read_addr(reader_sdram_addr),  // Connected but ignored by SDRAM
        .frame_start(vga_frame_start),
        .video_on(vga_video_on),  // FIXED: Added missing connection
        .vga_x(vga_x),            // FIXED: Added missing connection
        .vga_y(vga_y),            // FIXED: Added missing connection
        .fifo_write_enable(fifo_write_enable),
        .fifo_write_data(fifo_write_data),
        .fifo_full(fifo_full),
        .fifo_half_full(fifo_half_full),
        .frame_ready(reader_frame_ready)
    );

    //========================================================================
    // SDRAM Access Control
    //========================================================================
    always_comb begin
        // Control which module accesses SDRAM
        sdram_enable_write_mode = 1'b0;
        sdram_enable_read_mode = 1'b0;
        sdram_incoming_data = 16'd0;
        
        case (sys_state)
            SYS_LOADING: begin
                sdram_enable_write_mode = loader_write_enable;
                sdram_incoming_data = loader_write_data;
            end
            
            SYS_DISPLAYING: begin
                sdram_enable_read_mode = reader_enable_read;
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
    // Status LEDs for Debugging
    //========================================================================
    always_comb begin
        case (sys_state)
            SYS_WAIT_INIT:   status_leds = 4'b1110;  // LED0 on
            SYS_WAIT_BUTTON: status_leds = 4'b1101;  // LED1 on
            SYS_LOADING:     status_leds = 4'b1011;  // LED2 on
            SYS_DISPLAYING:  status_leds = 4'b0111;  // LED3 on
            SYS_ERROR:       status_leds = 4'b0000;  // All on
            default:         status_leds = 4'b1111;  // All off
        endcase
    end

endmodule