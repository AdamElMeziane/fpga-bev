module image_loader (
    //==============================
    // System Signals
    //==============================
    input  logic        clk,       // System clock
    input  logic        rst_n,     // Active-low reset

    //==============================
    // Control Interface
    //==============================
    input  logic        start,     // Start loading image
    output logic        done,      // Asserted when loading is complete

    //==============================
    // ROM Interface
    //==============================
    output logic [16:0] rom_addr,  // Address to read from image ROM
    input  logic [2:0]  rom_pixel, // 3-bit pixel data from ROM

    //==============================
    // SDRAM Controller Interface
    //==============================
    output logic        start_write,   // Triggers SDRAM write
    output logic [15:0] pixel_data,    // Pixel data to write (zero-extended)
    output logic        pixel_valid,   // Indicates valid pixel data
    input  logic        write_ready    // SDRAM ready to accept write
);

//==============================
// Internal Types & States
//==============================

// FSM States
typedef enum logic [1:0] {
    IDLE,        // Wait for start signal
    LOAD,        // Load pixel from ROM and request SDRAM write
    WAIT_WRITE,  // Wait for SDRAM to accept the write
    DONE         // All pixels written
} state_t;

//==============================
// Internal Registers
//==============================
state_t       state, next_state;   // FSM state registers
logic [16:0]  addr_counter;        // ROM address counter (0 to 76799)

//==============================
// FSM Sequential Logic
//==============================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        addr_counter  <= 17'd0;
    end else begin
        state <= next_state;

        // Address counter increments only during LOAD → WAIT_WRITE
        if (state == WAIT_WRITE && write_ready) begin
            addr_counter <= addr_counter + 1;
        end
    end
end

//==============================
// FSM Combinational Logic
//==============================
always_comb begin
    // Default to hold state
    next_state = state;

    case (state)
        IDLE: begin
            if (start)
                next_state = LOAD;
        end

        LOAD: begin
            // Wait for SDRAM to be ready before writing
            if (write_ready)
                next_state = WAIT_WRITE;
        end

        WAIT_WRITE: begin
            // Move to DONE after last pixel
            if (addr_counter == 17'd76799)
                next_state = DONE;
            else
                next_state = LOAD;
        end

        DONE: begin
            // Stay in DONE until reset
            next_state = DONE;
        end
    endcase
end

//==============================
// Output Logic
//==============================

// ROM address is driven by the internal counter
assign rom_addr = addr_counter;

// Zero-extend 3-bit pixel to 16-bit word
assign pixel_data = {13'b0, rom_pixel};

// Asserted when valid pixel is being sent to SDRAM
assign pixel_valid = (state == LOAD);

// Triggers SDRAM write (same as pixel_valid in this case)
assign start_write = (state == LOAD);

// Asserted when all pixels have been written
assign done = (state == DONE);

endmodule