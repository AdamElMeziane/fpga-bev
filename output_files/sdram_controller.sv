module sdram_controller (
    //==============================
    // System Signals
    //==============================
    input  logic        clk_143MHz,  // SDRAM clock domain
    input  logic        rst_n,       // Active-low reset

    //==============================
    // Write Interface
    input  logic        start_write,
    input  logic [15:0] pixel_data,
    input  logic        pixel_valid,
    output logic        write_ready,

    //==============================
    // Read Interface (for VGA)
    input  logic        start_read,
    input  logic [19:0] read_addr,
    output logic [15:0] read_pixel,
    output logic        read_valid,

    //==============================
    // SDRAM Physical Interface
    input logic        sdram_clk,
    output logic        sdram_cke,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    output logic [1:0]  sdram_ba,
    output logic [11:0] sdram_addr,  // Corrected to 12 bits
    inout  logic [15:0] sdram_dq,
    output logic        sdram_ldqm,
    output logic        sdram_udqm
);


// Init FSM States
typedef enum logic [2:0] {
    RESET_WAIT,      // Wait for 100 µs after power-up
    PRECHARGE_ALL,   // Precharge all banks
    LOAD_MODE,       // Load Mode Register
    AUTO_REFRESH_1,  // First Auto Refresh
    AUTO_REFRESH_2,  // Second Auto Refresh
    READY            // Initialization complete
} init_state_t;

// Write FSM States
typedef enum logic [2:0] {
    WRITE_IDLE,
    WRITE_ACTIVATE,
    WRITE_WAIT_RCD,
    WRITE_CMD,
    WRITE_WAIT_WR,
    WRITE_NEXT
} write_state_t;

// Read FSM States
typedef enum logic [2:0] {
    READ_IDLE,
    READ_ACTIVATE,
    READ_WAIT_RCD,
    READ_CMD,
    READ_WAIT_CL,
    READ_DONE
} read_state_t;


// Registers
init_state_t state, next_state;
logic [15:0] cycle_count; // Enough for 100 µs at 143 MHz (~14,300 cycles)

write_state_t write_state;
logic [2:0]   write_timer;
logic [19:0]  write_addr;
logic         writing;

read_state_t read_state;
logic [2:0]  read_timer;
logic [19:0] read_addr_latched;

// Init FSM logic
always_ff @(posedge clk_143MHz or negedge rst_n) begin
    if (!rst_n) begin
        state <= RESET_WAIT;
        cycle_count <= 0;
    end else begin
        state <= next_state;
        if (state == RESET_WAIT)
            cycle_count <= cycle_count + 1;
        else
            cycle_count <= 0;
    end
end

// Write FSM Logic
always_ff @(posedge clk_143MHz or negedge rst_n) begin
    if (!rst_n) begin
        write_state <= WRITE_IDLE;
        write_timer <= 0;
        write_addr  <= 0;
        writing     <= 0;
    end else begin
        case (write_state)
            WRITE_IDLE: begin
                if (init_done && start_write) begin
                    writing     <= 1;
                    write_state <= WRITE_ACTIVATE;
                end
            end

            WRITE_ACTIVATE: begin
                write_state <= WRITE_WAIT_RCD;
                write_timer <= 3; // tRCD
            end

            WRITE_WAIT_RCD: begin
                if (write_timer == 0)
                    write_state <= WRITE_CMD;
                else
                    write_timer <= write_timer - 1;
            end

            WRITE_CMD: begin
                write_state <= WRITE_WAIT_WR;
                write_timer <= 2; // tWR
            end

            WRITE_WAIT_WR: begin
                if (write_timer == 0)
                    write_state <= WRITE_NEXT;
                else
                    write_timer <= write_timer - 1;
            end

            WRITE_NEXT: begin
                if (write_addr < 76800) begin
                    write_addr  <= write_addr + 1;
                    write_state <= WRITE_ACTIVATE;
                end else begin
                    writing     <= 0;
                    write_state <= WRITE_IDLE;
                end
            end
        endcase
    end
end

// Read FSM Logic
always_ff @(posedge clk_143MHz or negedge rst_n) begin
    if (!rst_n) begin
        read_state       <= READ_IDLE;
        read_timer       <= 0;
        read_addr_latched <= 0;
    end else begin
        case (read_state)
            READ_IDLE: begin
                if (init_done && start_read) begin
                    read_addr_latched <= read_addr;
                    read_state        <= READ_ACTIVATE;
                end
            end

            READ_ACTIVATE: begin
                read_state <= READ_WAIT_RCD;
                read_timer <= 3; // tRCD
            end

            READ_WAIT_RCD: begin
                if (read_timer == 0)
                    read_state <= READ_CMD;
                else
                    read_timer <= read_timer - 1;
            end

            READ_CMD: begin
                read_state <= READ_WAIT_CL;
                read_timer <= 3; // CAS latency
            end

            READ_WAIT_CL: begin
                if (read_timer == 0)
                    read_state <= READ_DONE;
                else
                    read_timer <= read_timer - 1;
            end

            READ_DONE: begin
                read_state <= READ_IDLE;
            end
        endcase
    end
end

// Init transitions 
always_comb begin
    case (state)
        RESET_WAIT:      next_state = (cycle_count >= 14300) ? PRECHARGE_ALL : RESET_WAIT;
        PRECHARGE_ALL:   next_state = LOAD_MODE;
        LOAD_MODE:       next_state = AUTO_REFRESH_1;
        AUTO_REFRESH_1:  next_state = AUTO_REFRESH_2;
        AUTO_REFRESH_2:  next_state = READY;
        READY:           next_state = READY;
        default:         next_state = RESET_WAIT;
    endcase
end

// init assigns
logic init_done;
assign init_done = (state == READY);

// write assigns
assign sdram_dq = (writing && write_state == WRITE_CMD) ? pixel_data : 16'bz;
assign write_ready = (write_state == WRITE_IDLE);

// data captures
assign read_pixel = (read_state == READ_DONE) ? sdram_dq : 16'b0;
assign read_valid = (read_state == READ_DONE);

// Commands
always_comb begin
    // Default to NOP
    sdram_cs_n   = 0;
    sdram_ras_n  = 1;
    sdram_cas_n  = 1;
    sdram_we_n   = 1;
    sdram_addr   = 12'b0;
    sdram_ba     = 2'b00;
    sdram_cke    = 1;
    sdram_ldqm   = 0;
    sdram_udqm   = 0;

    // init commands
    case (state)
        PRECHARGE_ALL: begin
            sdram_ras_n = 0;
            sdram_cas_n = 1;
            sdram_we_n  = 0;
            sdram_addr[10] = 1; // A10 = 1 → Precharge All Banks
        end

        LOAD_MODE: begin
            sdram_ras_n = 0;
            sdram_cas_n = 0;
            sdram_we_n  = 0;
            sdram_addr = 12'b0000_0011_0000; // CAS latency = 3, burst length = 1, sequential
        end

        AUTO_REFRESH_1,
        AUTO_REFRESH_2: begin
            sdram_ras_n = 0;
            sdram_cas_n = 0;
            sdram_we_n  = 1;
        end

        default: begin
            // NOP
        end
    endcase

    // write commands
    if (writing) begin
        case (write_state)
            WRITE_ACTIVATE: begin
                sdram_ras_n = 0;
                sdram_cas_n = 1;
                sdram_we_n  = 1;
                sdram_ba    = 2'b00;
                sdram_addr  = write_addr[19:8]; // Row address
            end

            WRITE_CMD: begin
                sdram_ras_n = 1;
                sdram_cas_n = 0;
                sdram_we_n  = 0;
                sdram_ba    = 2'b00;
                sdram_addr[10] = 1; // A10 = 1 → Auto Precharge
                sdram_addr[7:0] = write_addr[7:0]; // Column address
            end
        endcase
    end

    // read commands
    if (read_state != READ_IDLE) begin
        case (read_state)
            READ_ACTIVATE: begin
                sdram_ras_n = 0;
                sdram_cas_n = 1;
                sdram_we_n  = 1;
                sdram_ba    = 2'b00;
                sdram_addr  = read_addr_latched[19:8]; // Row
            end

            READ_CMD: begin
                sdram_ras_n = 1;
                sdram_cas_n = 0;
                sdram_we_n  = 1;
                sdram_ba    = 2'b00;
                sdram_addr[10] = 1; // Auto Precharge
                sdram_addr[7:0] = read_addr_latched[7:0]; // Column
            end
        endcase
    end

end
endmodule

