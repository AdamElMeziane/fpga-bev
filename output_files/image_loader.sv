// Image Loader - Fixed version with proper state machine
// Transfers image data from ROM to SDRAM

module image_loader #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240,
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk,
    input  logic start_loading,     // Start transferring image to SDRAM
    input  logic sdram_ready,       // Not used - kept for compatibility
    input  logic sdram_tx_enable,   // SDRAM requests data
    
    output logic [DATA_WIDTH-1:0] pixel_data,
    output logic enable_write_mode,
    output logic loading_complete
);

    localparam IMG_SIZE = IMG_WIDTH * IMG_HEIGHT;
    
    // Image loading FSM
    typedef enum logic [1:0] {
        IDLE,
        LOADING,
        COMPLETE
    } load_state_t;
    
    load_state_t state, next_state;
    
    // Pixel counter
    logic [17:0] pixel_addr_reg, pixel_addr_next;  // 18 bits for 320x240 = 76800 pixels
    logic [2:0] rom_pixel_data;
    logic start_loading_latched;
    
    // Latch the start signal
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_loading_latched <= 1'b0;
        end else begin
            if (start_loading) begin
                start_loading_latched <= 1'b1;
            end else if (state == COMPLETE) begin
                start_loading_latched <= 1'b0;
            end
        end
    end
    
    // ROM instantiation for image data
    image_rom rom (
        .clk(clk),
        .addr(pixel_addr_reg),
        .pixel(rom_pixel_data)
    );
    
    // FSM next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_loading || start_loading_latched) begin
                    next_state = LOADING;
                end
            end
            
            LOADING: begin
                if (pixel_addr_reg >= IMG_SIZE - 1) begin
                    next_state = COMPLETE;
                end
            end
            
            COMPLETE: begin
                if (!start_loading && !start_loading_latched) begin
                    next_state = IDLE;  // Ready for next load
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Address counter logic
    always_comb begin
        pixel_addr_next = pixel_addr_reg;
        case (state)
            IDLE: begin
                pixel_addr_next = 18'd0;
            end
            
            LOADING: begin
                if (sdram_tx_enable) begin
                    if (pixel_addr_reg < IMG_SIZE - 1) begin
                        pixel_addr_next = pixel_addr_reg + 1;
                    end
                end
            end
            
            COMPLETE: begin
                pixel_addr_next = 18'd0;  // Reset for next time
            end
            
            default: pixel_addr_next = 18'd0;
        endcase
    end
    
    // Output logic
    always_comb begin
        enable_write_mode = 1'b0;
        loading_complete = 1'b0;
        
        case (state)
            IDLE: begin
                enable_write_mode = 1'b0;
                loading_complete = 1'b0;
            end
            
            LOADING: begin
                enable_write_mode = 1'b1;
                loading_complete = 1'b0;
            end
            
            COMPLETE: begin
                enable_write_mode = 1'b0;
                loading_complete = 1'b1;
            end
            
            default: begin
                enable_write_mode = 1'b0;
                loading_complete = 1'b0;
            end
        endcase
    end
    
    // Pad 3-bit RGB to 16-bit data (compatible with original design)
    assign pixel_data = {13'b0, rom_pixel_data};
    
    // Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_addr_reg <= 18'd0;
        end else begin
            state <= next_state;
            pixel_addr_reg <= pixel_addr_next;
        end
    end

endmodule