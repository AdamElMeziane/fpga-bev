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
    output logic [17:0] sdram_write_addr,  // Not used by SDRAM controller
    output logic enable_write_mode,
    output logic loading_complete
);

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        WAIT_SDRAM,
        WRITING,
        DONE
    } state_t;
    
    state_t state, next_state;
    
    // Pixel counter - tracks position in 320x240 image
    logic [17:0] pixel_count, pixel_count_next;
    
    // Total pixels to load
    localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;  // 76,800
    
    // Calculate ROM address from sequential count
    always_comb begin
        if (pixel_count < TOTAL_PIXELS) begin
            rom_addr = pixel_count;
        end else begin
            rom_addr = '0;
        end
    end
    
    // State machine logic
    always_comb begin
        next_state = state;
        pixel_count_next = pixel_count;
        enable_write_mode = 1'b0;
        pixel_data = {13'b0, rom_pixel};  // Always output current ROM pixel
        
        case (state)
            IDLE: begin
                if (start_loading && sdram_ready) begin
                    next_state = WAIT_SDRAM;
                    pixel_count_next = '0;
                end
            end
            
            WAIT_SDRAM: begin
                enable_write_mode = 1'b1;
                if (sdram_tx_enable) begin
                    next_state = WRITING;
                end
            end
            
            WRITING: begin
                enable_write_mode = 1'b1;
                if (sdram_tx_enable) begin
                    if (pixel_count >= TOTAL_PIXELS - 1) begin
                        next_state = DONE;
                    end else begin
                        pixel_count_next = pixel_count + 1;
                    end
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Dummy address output (not used by SDRAM controller)
    assign sdram_write_addr = pixel_count;
    
    // Loading complete signal
    assign loading_complete = (state == DONE);
    
    // Sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_count <= '0;
        end else begin
            state <= next_state;
            pixel_count <= pixel_count_next;
        end
    end

endmodule