module top_sdram_vga (
    input  logic        clk_50MHz,
    input  logic        reset_n,

    output logic [0:0]  vga_red,
    output logic [0:0]  vga_green,
    output logic [0:0]  vga_blue,
    output logic        vga_hsync,
    output logic        vga_vsync,

    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  bank,
    output logic        cke,
    inout  wire [15:0]  dq
);

    logic clk_133, clk_25, pll_locked;
    logic reset_sync_133, reset_sync_25;

    // PLL for 133MHz SDRAM clock
    pll_133Mhz pll_inst (
        .areset(~reset_n),
        .inclk0(clk_50MHz),
        .c0(clk_133),
        .locked(pll_locked)
    );

    // Clock divider for 25MHz VGA clock
    clock_divider #(.DIVIDE_BY(2)) vga_clk_gen (
        .clk_in(clk_50MHz),
        .clk_out(clk_25)
    );

    // Reset synchronizers for each clock domain
    always_ff @(posedge clk_133 or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync_133 <= 0;
        end else begin
            reset_sync_133 <= pll_locked;
        end
    end

    always_ff @(posedge clk_25 or negedge reset_n) begin
        if (!reset_n) begin
            reset_sync_25 <= 0;
        end else begin
            reset_sync_25 <= 1;
        end
    end

    // VGA controller signals
    logic [9:0] x, y;
    logic       video_on;
    logic       frame_start;

    vga_controller vga_inst (
        .clk(clk_25),
        .reset(~reset_sync_25),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .video_on(video_on),
        .x(x),
        .y(y),
        .frame_start(frame_start)
    );

    // SDRAM data bus control
    logic [15:0] dq_out_writer;
    logic        dq_oe_writer;
    logic [15:0] dq_out;
    logic        dq_oe;

    assign dq = dq_oe ? dq_out : 16'hZZZZ;

    // Main FSM states
    typedef enum logic [1:0] {
        INIT,
        WRITE,
        READ
    } main_state_t;
    
    main_state_t main_state;
    logic init_done, write_done;

    // Shared SDRAM control signals
    logic [11:0] addr_init, addr_writer, addr_reader;
    logic [1:0]  bank_init, bank_writer, bank_reader;
    logic        cs_n_init, ras_n_init, cas_n_init, we_n_init, cke_init;
    logic        cs_n_writer, ras_n_writer, cas_n_writer, we_n_writer, cke_writer;
    logic        cs_n_reader, ras_n_reader, cas_n_reader, we_n_reader, cke_reader;
    logic        dq_oe_reader;
    logic [2:0]  rgb;

    // SDRAM signal multiplexing based on main state
    always_comb begin
        case (main_state)
            INIT: begin
                addr   = addr_init;
                bank   = bank_init;
                cs_n   = cs_n_init;
                ras_n  = ras_n_init;
                cas_n  = cas_n_init;
                we_n   = we_n_init;
                cke    = cke_init;
                dq_out = 16'hZZZZ;
                dq_oe  = 0;
            end
            
            WRITE: begin
                addr   = addr_writer;
                bank   = bank_writer;
                cs_n   = cs_n_writer;
                ras_n  = ras_n_writer;
                cas_n  = cas_n_writer;
                we_n   = we_n_writer;
                cke    = cke_writer;
                dq_out = dq_out_writer;
                dq_oe  = dq_oe_writer;
            end
            
            READ: begin
                addr   = addr_reader;
                bank   = bank_reader;
                cs_n   = cs_n_reader;
                ras_n  = ras_n_reader;
                cas_n  = cas_n_reader;
                we_n   = we_n_reader;
                cke    = cke_reader;
                dq_out = 16'hZZZZ;
                dq_oe  = dq_oe_reader;
            end
            
            default: begin
                addr   = 12'd0;
                bank   = 2'b00;
                cs_n   = 1;
                ras_n  = 1;
                cas_n  = 1;
                we_n   = 1;
                cke    = 1;
                dq_out = 16'hZZZZ;
                dq_oe  = 0;
            end
        endcase
    end

    // VGA RGB output
    assign vga_red[0]   = rgb[2];
    assign vga_green[0] = rgb[1];
    assign vga_blue[0]  = rgb[0];

    // ROM instantiation
    logic [16:0] writer_pixel_index;
    logic [2:0]  pixel_data;

    image_rom rom (
        .clk(clk_133),
        .addr(writer_pixel_index),
        .pixel(pixel_data)
    );

    // SDRAM initialization FSM
    sdram_init_fsm init_fsm (
        .clk(clk_133),
        .reset_n(reset_sync_133),
        .init_done(init_done),
        .cs_n(cs_n_init),
        .ras_n(ras_n_init),
        .cas_n(cas_n_init),
        .we_n(we_n_init),
        .addr(addr_init),
        .ba(bank_init),
        .cke(cke_init)
    );

    // ROM to SDRAM writer
    rom_to_sdram_writer writer (
        .clk(clk_133),
        .init_done(init_done && (main_state == WRITE)),
        .pixel_data(pixel_data),
        .done(write_done),
        .cs_n(cs_n_writer),
        .ras_n(ras_n_writer),
        .cas_n(cas_n_writer),
        .we_n(we_n_writer),
        .addr(addr_writer),
        .ba(bank_writer),
        .cke(cke_writer),
        .dq_out(dq_out_writer),
        .dq_oe(dq_oe_writer),
        .pixel_index(writer_pixel_index)
    );

    // SDRAM to VGA reader
    sdram_to_vga_reader reader (
        .clk_sdram(clk_133),
        .clk_vga(clk_25),
        .reset_n(reset_sync_133 && reset_sync_25),
        .video_on(video_on),
        .x(x),
        .y(y),
        .frame_start(frame_start),
        .cs_n(cs_n_reader),
        .ras_n(ras_n_reader),
        .cas_n(cas_n_reader),
        .we_n(we_n_reader),
        .addr(addr_reader),
        .ba(bank_reader),
        .cke(cke_reader),
        .dq(dq),
        .dq_oe(dq_oe_reader),
        .rgb(rgb)
    );

    // Main FSM: INIT → WRITE → READ
    always_ff @(posedge clk_133 or negedge reset_sync_133) begin
        if (!reset_sync_133) begin
            main_state <= INIT;
        end else begin
            case (main_state)
                INIT: begin
                    if (init_done) begin
                        main_state <= WRITE;
                    end
                end
                
                WRITE: begin
                    if (write_done) begin
                        main_state <= READ;
                    end
                end
                
                READ: begin
                    // Stay in read mode
                end
                
                default: main_state <= INIT;
            endcase
        end
    end

endmodule