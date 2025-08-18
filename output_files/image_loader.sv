module image_loader #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240,
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk,
    
    // Control signals
    input  logic start_loading,
    input  logic sdram_ready,
    input  logic sdram_tx_enable,
    
    // ROM interface
    output logic [17:0] rom_addr,
    input  logic [2:0]  rom_pixel,
    
    // SDRAM interface
    output logic [DATA_WIDTH-1:0] pixel_data,
    output logic enable_write_mode,
    output logic loading_complete
);

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        WAIT_SDRAM,
        LOAD_PIXEL,
        WAIT_WRITE,
        CHECK_DONE
    } state_t;
    
    state_t state, next_state;
    
    // Counter
    logic [17:0] pixel_counter, pixel_counter_next;
    
    // Total pixels to load
    localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    
    // State machine logic
    always_comb begin
        next_state = state;
        pixel_counter_next = pixel_counter;
        enable_write_mode = 1'b0;
        
        case (state)
            IDLE: begin
                if (start_loading && sdram_ready) begin
                    next_state = WAIT_SDRAM;
                    pixel_counter_next = '0;
                end
            end
            
            WAIT_SDRAM: begin
                // Wait for SDRAM to be ready for write
                enable_write_mode = 1'b1;
                if (sdram_tx_enable) begin
                    next_state = LOAD_PIXEL;
                end
            end
            
            LOAD_PIXEL: begin
                // Write one pixel
                enable_write_mode = 1'b1;
                if (sdram_tx_enable) begin
                    pixel_counter_next = pixel_counter + 1;
                    next_state = CHECK_DONE;
                end else begin
                    next_state = WAIT_WRITE;
                end
            end
            
            WAIT_WRITE: begin
                enable_write_mode = 1'b1;
                if (sdram_tx_enable) begin
                    pixel_counter_next = pixel_counter + 1;
                    next_state = CHECK_DONE;
                end
            end
            
            CHECK_DONE: begin
                if (pixel_counter >= TOTAL_PIXELS) begin
                    next_state = IDLE;
                end else begin
                    next_state = LOAD_PIXEL;
                end
            end
        endcase
    end
    
    // ROM address generation
    assign rom_addr = pixel_counter;
    
    // SDRAM data output - one 3-bit pixel in 16-bit word
    assign pixel_data = {13'b0, rom_pixel};
    
    // Loading complete signal
    assign loading_complete = (state == IDLE) && (pixel_counter >= TOTAL_PIXELS);
    
    // Sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_counter <= '0;
        end else begin
            state <= next_state;
            pixel_counter <= pixel_counter_next;
        end
    end

endmodule