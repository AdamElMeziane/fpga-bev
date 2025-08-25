module top_sdram_vga_system (
    //==============================
    // System Inputs
    //==============================
    input  logic        clk_50MHz,     // Base clock input
    input  logic        start_button,  // Push-button to start image load

    //==============================
    // VGA Output
    //==============================
    output logic        vga_hsync,
    output logic        vga_vsync,
    output logic [0:0]  vga_red,
    output logic [0:0]  vga_green,
    output logic [0:0]  vga_blue,

    //==============================
    // SDRAM Interface
    //==============================
    output logic        sclk,          // SDRAM clock
    output logic        cke,
    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  bank,
    inout  wire [15:0]  dq,
    output logic        ldqm,
    output logic        udqm,

    //==============================
    // Debug LEDs
    //==============================
    output logic [3:0]  status_leds
);

//==============================
// Clock Signals
//==============================
logic clk_143MHz;   // SDRAM clock
logic clk_25MHz;    // VGA pixel clock
logic pll_locked;   // PLL lock indicator

//==============================
// PLL: Generate 143 MHz from 50 MHz
//==============================
pll_143MHz pll_inst (
    .areset(~start_button),     // Reset PLL with button (or use reset_n if preferred)
    .inclk0(clk_50MHz),         // Input clock
    .c0(clk_143MHz),            // Output clock (143 MHz)
    .locked(pll_locked)         // PLL lock status
);

//==============================
// Clock Divider: Generate 25 MHz from 50 MHz
//==============================
logic clk_div;
always_ff @(posedge clk_50MHz)
    clk_div <= ~clk_div;

assign clk_25MHz = clk_div;

//==============================
// Assign SDRAM clock output
//==============================
assign sclk = clk_143MHz;

//==============================
// Reset Synchronizers
//==============================

// SDRAM domain reset (clk_143MHz)
logic reset_sync_143_stage1, reset_sync_143;
always_ff @(posedge clk_143MHz or negedge start_button) begin
    if (!start_button) begin
        reset_sync_143_stage1 <= 1'b0;
        reset_sync_143        <= 1'b0;
    end else begin
        reset_sync_143_stage1 <= 1'b1;
        reset_sync_143        <= reset_sync_143_stage1;
    end
end

// VGA domain reset (clk_25MHz)
logic reset_sync_25_stage1, reset_sync_25;
always_ff @(posedge clk_25MHz or negedge start_button) begin
    if (!start_button) begin
        reset_sync_25_stage1 <= 1'b0;
        reset_sync_25        <= 1'b0;
    end else begin
        reset_sync_25_stage1 <= 1'b1;
        reset_sync_25        <= reset_sync_25_stage1;
    end
end

//==============================
// VGA Timing Generator
//==============================
logic [9:0] x, y;
logic       video_on;
logic       frame_start;

vga_display_controller vga_timing (
    .clk(clk_25MHz),
    .rst_n(reset_sync_25),
    .hsync(vga_hsync),
    .vsync(vga_vsync),
    .video_on(video_on),
    .x(x),
    .y(y),
    .frame_start(frame_start)
);

//==============================
// SDRAM to VGA Frame Reader
//==============================
logic [19:0] read_addr;
logic        start_read;
logic [15:0] read_pixel;
logic        read_valid;
logic [2:0]  pixel_rgb;

vga_frame_reader reader (
    .clk(clk_25MHz),
    .rst_n(reset_sync_25),
    .x(x),
    .y(y),
    .video_on(video_on),
    .read_addr(read_addr),
    .start_read(start_read),
    .read_pixel(read_pixel),
    .read_valid(read_valid),
    .pixel_out(pixel_rgb)
);

// VGA RGB output mapping
assign vga_red[0]   = pixel_rgb[2];
assign vga_green[0] = pixel_rgb[1];
assign vga_blue[0]  = pixel_rgb[0];

//==============================
// SDRAM Controller
//==============================
logic        start_write;
logic [15:0] pixel_data;
logic        pixel_valid;
logic        write_ready;

sdram_controller sdram_ctrl (
    // System
    .clk_143MHz(clk_143MHz),
    .rst_n(reset_sync_143),

    // Write interface (from image_loader)
    .start_write(start_write),
    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .write_ready(write_ready),

    // Read interface (from vga_frame_reader)
    .start_read(start_read),
    .read_addr(read_addr),
    .read_pixel(read_pixel),
    .read_valid(read_valid),

    // SDRAM physical interface
    .sdram_clk(sclk),
    .sdram_cke(cke),
    .sdram_cs_n(cs_n),
    .sdram_ras_n(ras_n),
    .sdram_cas_n(cas_n),
    .sdram_we_n(we_n),
    .sdram_ba(bank),
    .sdram_addr(addr),
    .sdram_dq(dq),
    .sdram_ldqm(ldqm),
    .sdram_udqm(udqm)
);

//==============================
// Image ROM
//==============================
logic [16:0] rom_addr;
logic [2:0]  rom_pixel;

image_rom rom (
    .clk(clk_143MHz),
    .addr(rom_addr),
    .pixel(rom_pixel)
);

//==============================
// Image Loader (ROM → SDRAM)
//==============================
logic        loader_start;
logic        loader_done;

image_loader loader (
    .clk(clk_143MHz),
    .rst_n(reset_sync_143),
    .start(loader_start),
    .done(loader_done),

    // ROM interface
    .rom_addr(rom_addr),
    .rom_pixel(rom_pixel),

    // SDRAM write interface
    .start_write(start_write),
    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .write_ready(write_ready)
);

//==============================
// Main FSM States
//==============================
typedef enum logic [1:0] {
    INIT,
    WRITE,
    READ
} system_state_t;

system_state_t state;

always_ff @(posedge clk_143MHz or negedge reset_sync_143) begin
    if (!reset_sync_143) begin
        state <= INIT;
    end else begin
        case (state)
            INIT: begin
                if (pll_locked)
                    state <= WRITE;
            end

            WRITE: begin
                if (loader_done)
                    state <= READ;
            end

            READ: begin
                // Remain in READ forever
                state <= READ;
            end

            default: state <= INIT;
        endcase
    end
end

assign loader_start = (state == WRITE);
assign status_leds  = {1'b0, state}; // Optional: show state on LEDs

endmodule