module sdram_init_fsm (
    input  logic        clk,
    input  logic        reset_n,
    output logic        init_done,

    // SDRAM control signals
    output logic        cs_n,
    output logic        ras_n,
    output logic        cas_n,
    output logic        we_n,
    output logic [11:0] addr,
    output logic [1:0]  ba,
    output logic        cke
);

    // FSM states - added missing AUTO_REFRESH cycles
    typedef enum logic [3:0] {
        IDLE,
        WAIT_100US,
        PRECHARGE,
        WAIT_TRP1,
        AUTO_REFRESH1,
        WAIT_TRC1,
        AUTO_REFRESH2,
        WAIT_TRC2,
        LOAD_MODE,
        WAIT_TMRD,
        DONE
    } state_t;

    // SDRAM timing parameters (for 133MHz = 7.5ns period)
    localparam int T_100US_CYCLES = 13300;  // 100us / 7.5ns
    localparam int T_RP_CYCLES = 3;         // 20ns / 7.5ns = 2.67 -> 3
    localparam int T_RC_CYCLES = 9;         // 63ns / 7.5ns = 8.4 -> 9  
    localparam int T_MRD_CYCLES = 2;        // 2 clock cycles

    logic [13:0] wait_counter;
    state_t state, next_state;

    // State register
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            wait_counter <= 0;
        end else begin
            state <= next_state;
            
            // Counter logic
            if (state == WAIT_100US || state == WAIT_TRP1 || 
                state == WAIT_TRC1 || state == WAIT_TRC2 || state == WAIT_TMRD) begin
                wait_counter <= wait_counter + 1;
            end else begin
                wait_counter <= 0;
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:           next_state = WAIT_100US;
            WAIT_100US:     if (wait_counter >= T_100US_CYCLES-1) next_state = PRECHARGE;
            PRECHARGE:      next_state = WAIT_TRP1;
            WAIT_TRP1:      if (wait_counter >= T_RP_CYCLES-1) next_state = AUTO_REFRESH1;
            AUTO_REFRESH1:  next_state = WAIT_TRC1;
            WAIT_TRC1:      if (wait_counter >= T_RC_CYCLES-1) next_state = AUTO_REFRESH2;
            AUTO_REFRESH2:  next_state = WAIT_TRC2;
            WAIT_TRC2:      if (wait_counter >= T_RC_CYCLES-1) next_state = LOAD_MODE;
            LOAD_MODE:      next_state = WAIT_TMRD;
            WAIT_TMRD:      if (wait_counter >= T_MRD_CYCLES-1) next_state = DONE;
            DONE:           next_state = DONE;
            default:        next_state = IDLE;
        endcase
    end

    // Output logic
    always_comb begin
        // Default: NOP command
        cs_n   = 1;
        ras_n  = 1;
        cas_n  = 1;
        we_n   = 1;
        addr   = 12'd0;
        ba     = 2'b00;
        cke    = 1;
        init_done = 0;

        case (state)
            PRECHARGE: begin
                cs_n     = 0;
                ras_n    = 0;
                cas_n    = 1;
                we_n     = 0;
                addr[10] = 1;    // A10 = 1 for precharge all banks
            end
            
            AUTO_REFRESH1, AUTO_REFRESH2: begin
                cs_n  = 0;
                ras_n = 0;
                cas_n = 0;
                we_n  = 1;       // AUTO REFRESH command
            end
            
            LOAD_MODE: begin
                cs_n  = 0;
                ras_n = 0;
                cas_n = 0;
                we_n  = 0;
                // Mode register: CAS Latency = 3, Burst Length = 1, Sequential
                // A11-A10: Reserved (00)
                // A9: Write Burst Mode = 0 (burst read/write)
                // A8-A7: Reserved (00) 
                // A6-A4: CAS Latency = 011 (CL=3)
                // A3: Burst Type = 0 (sequential)
                // A2-A0: Burst Length = 001 (BL=1)
                addr = 12'b000_0_00_011_0_001;
                ba   = 2'b00;
            end
            
            DONE: begin
                init_done = 1;
            end
        endcase
    end

endmodule