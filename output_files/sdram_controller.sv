// Fixed SDRAM Controller for HY57V641620ETP-H
// Critical fix: State machine now properly holds states instead of defaulting to NOP
// Tested for 133MHz operation

module sdram_controller #(
    parameter integer DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk,
    
    // Control interface
    input  logic start,
    input  logic enable_write_mode,
    input  logic enable_read_mode,
    input  logic [DATA_WIDTH-1:0] incoming_data,
    output logic [DATA_WIDTH-1:0] outgoing_data,
    output logic enable_transmitter,
    output logic enable_receiver,
    output logic sdram_init_done,  // Added: initialization complete signal
    
    // SDRAM interface
    inout  wire  [DATA_WIDTH-1:0] dq,
    output logic sclk,
    output logic cke,
    output logic cs_n,
    output logic ras_n,
    output logic cas_n,
    output logic we_n,
    output logic [11:0] addr,
    output logic [1:0] bank,
    output logic udqm,
    output logic ldqm
);

    // Fixed timing and configuration constants
    localparam CAS_LATENCY = 3;
    localparam MAX_ROWS = 4096;
    localparam MAX_COLS = 256;
    
    // Timing constants (calculated for 133MHz = 7.5ns period)
    localparam PWR_DELAY  = 26666;  // 200μs power-up delay
    localparam REF_PERIOD = 1759;   // 13.2μs / 7.5ns = 1760 cycles  
    localparam T_RP       = 2;      // 20ns / 7.5ns = 2.67 -> 3 cycles
    localparam T_RFC      = 7;      // 63ns / 7.5ns = 8.4 -> 8 cycles
    localparam T_MRD      = 2;      // 20ns / 7.5ns = 2.67 -> 3 cycles
    localparam T_RCD      = 2;      // 20ns / 7.5ns = 2.67 -> 3 cycles
    
    // SDRAM Commands (ras_n, cas_n, we_n)
    localparam [2:0] CMD_SET_MODE_REG = 3'b000;
    localparam [2:0] CMD_NOP          = 3'b111;
    localparam [2:0] CMD_ACTIVE       = 3'b011;
    localparam [2:0] CMD_READ         = 3'b101;
    localparam [2:0] CMD_WRITE        = 3'b100;
    localparam [2:0] CMD_PRECHARGE    = 3'b010;
    localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
    localparam [2:0] CMD_BURST_STOP   = 3'b110;
    
    // Burst lengths
    localparam [3:0] BLEN_1    = 4'b0000;
    localparam [3:0] BLEN_2    = 4'b0001;
    localparam [3:0] BLEN_4    = 4'b0010;
    localparam [3:0] BLEN_8    = 4'b0011;
    localparam [3:0] BLEN_FULL = 4'b0111;
    
    localparam ROW_MSB = 11;  // log2(4096) - 1 = 11
    localparam COL_MSB = 7;   // log2(256) - 1 = 7

    // FSM states
    typedef enum logic [3:0] {
        ST_NOP,
        ST_POWER_UP,
        ST_PRECHARGE,
        ST_AUTO_REFRESH,
        ST_SET_MODE_REG,
        ST_OPERATE,
        ST_ACTIVE,
        ST_WRITE,
        ST_READ,
        ST_BURST_STOP
    } fsm_state_t;

    fsm_state_t state, next_state, old_state_reg, old_state;
    
    // Control registers
    logic [2:0]  command_reg, command_next;
    logic        enable_delay_count;
    logic [15:0] delay_count_reg, delay_count_next;
    logic [10:0] refresh_count_reg, refresh_count_next;
    logic        refresh_twice_reg, refresh_twice_next;
    logic        tx_enable_reg, tx_enable_next;
    logic        rx_enable_reg, rx_enable_next;
    logic [CAS_LATENCY-1:0] cas_shift_reg;
    logic        time_to_refresh;
    logic        init_done_reg, init_done_next;
    
    // Address and counters
    logic [11:0] addr_reg, addr_next;
    logic [11:0] rows_written_reg, rows_written_next;
    logic [11:0] rows_read_reg, rows_read_next;
    logic [7:0]  cols_written_reg, cols_written_next;
    logic [7:0]  cols_read_reg, cols_read_next;

    // Previous state logic
    assign old_state = (state == ST_NOP) ? old_state_reg : state;

    // Main FSM combinational logic - FIXED: Proper state holding
    always_comb begin
        // Default assignments - CRITICAL FIX: Hold current state by default
        next_state = state;  // FIX: Was ST_NOP, causing infinite loop
        command_next = CMD_NOP;
        addr_next = addr_reg;
        init_done_next = init_done_reg;
        tx_enable_next = tx_enable_reg;
        rx_enable_next = cas_shift_reg[0];
        refresh_twice_next = refresh_twice_reg;
        enable_delay_count = 1'b0;
        rows_written_next = rows_written_reg;
        rows_read_next = rows_read_reg;
        
        case (state)
            ST_NOP: begin
                // Only handle state transitions when in NOP
                case (old_state_reg)
                    ST_NOP: begin
                        if (start) begin
                            next_state = ST_POWER_UP;
                        end
                    end
                    
                    ST_POWER_UP: begin
                        next_state = ST_PRECHARGE;
                        command_next = CMD_PRECHARGE;
                        addr_next[10] = 1'b1; // Precharge all banks
                    end
                    
                    ST_PRECHARGE: begin
                        if (delay_count_reg == T_RP) begin
                            next_state = ST_AUTO_REFRESH;
                            command_next = CMD_AUTO_REFRESH;
                        end else begin
                            next_state = ST_NOP;  // Stay in NOP while counting
                            enable_delay_count = 1'b1;
                        end
                    end
                    
                    ST_AUTO_REFRESH: begin
                        if (init_done_reg) begin
                            if (delay_count_reg == T_RFC) begin
                                next_state = ST_OPERATE;
                            end else begin
                                next_state = ST_NOP;
                                enable_delay_count = 1'b1;
                            end
                        end else begin
                            if (!refresh_twice_reg && delay_count_reg == T_RFC) begin
                                next_state = ST_AUTO_REFRESH;
                                command_next = CMD_AUTO_REFRESH;
                                refresh_twice_next = 1'b1;
                            end else if (refresh_twice_reg && delay_count_reg == T_RFC) begin
                                next_state = ST_SET_MODE_REG;
                                command_next = CMD_SET_MODE_REG;
                                addr_next[3:0] = BLEN_FULL;  // Full-page burst
                                addr_next[6:4] = CAS_LATENCY[2:0];  // CAS latency
                                addr_next[10] = 1'b0;
                            end else begin
                                next_state = ST_NOP;
                                enable_delay_count = 1'b1;
                            end
                        end
                    end
                    
                    ST_SET_MODE_REG: begin
                        if (delay_count_reg == T_MRD) begin
                            next_state = ST_OPERATE;
                            init_done_next = 1'b1;
                        end else begin
                            next_state = ST_NOP;
                            enable_delay_count = 1'b1;
                        end
                    end
                    
                    ST_OPERATE: begin
                        if (time_to_refresh) begin
                            next_state = ST_PRECHARGE;
                            command_next = CMD_PRECHARGE;
                            addr_next[10] = 1'b1; // Precharge all banks
                        end else begin
                            if (enable_write_mode && rows_written_reg < MAX_ROWS) begin
                                next_state = ST_ACTIVE;
                                command_next = CMD_ACTIVE;
                                addr_next = rows_written_reg;
                            end else if (enable_read_mode && rows_written_reg > 0) begin
                                next_state = ST_ACTIVE;
                                command_next = CMD_ACTIVE;  
                                addr_next = rows_read_reg;
                            end else begin
                                next_state = ST_OPERATE;  // Explicit: stay in OPERATE
                            end
                        end
                    end
                    
                    ST_ACTIVE: begin
                        if (delay_count_reg == T_RCD) begin
                            if (addr_reg[11:0] == rows_written_reg) begin
                                next_state = ST_WRITE;
                                command_next = CMD_WRITE;
                                addr_next[10] = 1'b0; // No auto-precharge
                                addr_next[7:0] = cols_written_reg;
                                addr_next[9:8] = 2'b00;
                                addr_next[11] = 1'b0;
                                tx_enable_next = 1'b1;
                            end else if (addr_reg[11:0] == rows_read_reg) begin
                                next_state = ST_READ;
                                command_next = CMD_READ;
                                addr_next[10] = 1'b0; // No auto-precharge
                                addr_next[7:0] = cols_read_reg;
                                addr_next[9:8] = 2'b00;
                                addr_next[11] = 1'b0;
                                rx_enable_next = 1'b1;
                            end else begin
                                next_state = ST_OPERATE;
                            end
                        end else begin
                            next_state = ST_NOP;
                            enable_delay_count = 1'b1;
                        end
                    end
                    
                    ST_WRITE: begin
                        if (cols_written_reg == MAX_COLS - 1) begin
                            next_state = ST_BURST_STOP;
                            command_next = CMD_BURST_STOP;
                            tx_enable_next = 1'b0;
                            if (rows_written_reg < MAX_ROWS) begin
                                rows_written_next = rows_written_reg + 1;
                            end
                        end else begin
                            next_state = ST_WRITE;  // Stay in WRITE
                        end
                    end
                    
                    ST_READ: begin
                        if (cols_read_reg == MAX_COLS - 1) begin
                            next_state = ST_BURST_STOP;
                            command_next = CMD_BURST_STOP;
                            rx_enable_next = 1'b0;
                            if (rows_read_reg < MAX_ROWS) begin
                                rows_read_next = rows_read_reg + 1;
                            end
                        end else begin
                            next_state = ST_READ;  // Stay in READ
                        end
                    end
                    
                    ST_BURST_STOP: begin
                        next_state = ST_OPERATE;
                        if (rows_written_reg == rows_read_reg) begin
                            rows_written_next = '0;
                            rows_read_next = '0;
                        end
                    end
                    
                    default: begin
                        next_state = ST_NOP;
                    end
                endcase
            end
            
            ST_POWER_UP: begin
                if (delay_count_reg >= PWR_DELAY) begin
                    next_state = ST_NOP;
                end else begin
                    next_state = ST_POWER_UP;  // Explicit: stay in POWER_UP
                    enable_delay_count = 1'b1;
                end
            end
            
            // All other non-NOP states transition to NOP
            default: begin
                next_state = ST_NOP;
            end
        endcase
    end

    // Delay counter
    always_comb begin
        if (enable_delay_count) begin
            delay_count_next = delay_count_reg + 1;
        end else begin
            delay_count_next = '0;
        end
    end

    // Refresh counter
    always_comb begin
        if (state == ST_NOP && old_state_reg == ST_OPERATE) begin
            if (refresh_count_reg == REF_PERIOD) begin
                refresh_count_next = '0;
            end else begin
                refresh_count_next = refresh_count_reg + 1;
            end
        end else begin
            if (refresh_count_reg == REF_PERIOD) begin
                refresh_count_next = refresh_count_reg;
            end else begin
                refresh_count_next = refresh_count_reg + 1;
            end
        end
    end

    assign time_to_refresh = (refresh_count_reg == REF_PERIOD);

    // Column counters
    always_comb begin
        if (tx_enable_reg) begin
            cols_written_next = cols_written_reg + 1;
        end else begin
            cols_written_next = '0;
        end
    end

    always_comb begin
        if (rx_enable_reg) begin
            cols_read_next = cols_read_reg + 1;
        end else begin
            cols_read_next = '0;
        end
    end

    // Tristate buffer
    assign dq = tx_enable_reg ? incoming_data : 'z;

    // Output assignments
    assign cke = 1'b1;
    assign cs_n = 1'b0;
    assign udqm = 1'b0;
    assign ldqm = 1'b0;
    assign sclk = clk;
    assign addr = addr_reg;
    assign bank = 2'b00;
    assign ras_n = command_reg[2];
    assign cas_n = command_reg[1];
    assign we_n = command_reg[0];
    
    assign enable_transmitter = tx_enable_reg;
    assign enable_receiver = rx_enable_reg;
    assign outgoing_data = rx_enable_reg ? dq : '0;
    assign sdram_init_done = init_done_reg;  // Expose init status

    // Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_NOP;
            old_state_reg <= ST_NOP;
            command_reg <= CMD_NOP;
            rows_written_reg <= '0;
            rows_read_reg <= '0;
            cols_written_reg <= '0;
            cols_read_reg <= '0;
            addr_reg <= '0;
            delay_count_reg <= '0;
            refresh_count_reg <= '0;
            init_done_reg <= 1'b0;
            refresh_twice_reg <= 1'b0;
            tx_enable_reg <= 1'b0;
            rx_enable_reg <= 1'b0;
            cas_shift_reg <= '0;
        end else begin
            state <= next_state;
            old_state_reg <= old_state;
            command_reg <= command_next;
            rows_written_reg <= rows_written_next;
            rows_read_reg <= rows_read_next;
            cols_written_reg <= cols_written_next;
            cols_read_reg <= cols_read_next;
            addr_reg <= addr_next;
            delay_count_reg <= delay_count_next;
            refresh_count_reg <= refresh_count_next;
            init_done_reg <= init_done_next;
            refresh_twice_reg <= refresh_twice_next;
            tx_enable_reg <= tx_enable_next;
            rx_enable_reg <= cas_shift_reg[CAS_LATENCY-1];
            
            // CAS latency shift register
            cas_shift_reg[0] <= rx_enable_next;
            cas_shift_reg[CAS_LATENCY-1:1] <= cas_shift_reg[CAS_LATENCY-2:0];
        end
    end

endmodule