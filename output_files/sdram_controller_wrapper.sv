module sdram_controller_wrapper #(
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk,
    
    // Control interface
    input  logic start,
    output logic sdram_init_done,
    
    // Write interface
    input  logic write_enable,
    input  logic [17:0] write_addr,  // External write address
    input  logic [DATA_WIDTH-1:0] write_data,
    output logic write_ready,
    
    // Read interface
    input  logic read_enable,
    input  logic [17:0] read_addr,   // External read address
    output logic [DATA_WIDTH-1:0] read_data,
    output logic read_valid,
    
    // SDRAM physical interface
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

    // Internal control signals
    logic enable_write_mode;
    logic enable_read_mode;
    logic [DATA_WIDTH-1:0] incoming_data;
    logic [DATA_WIDTH-1:0] outgoing_data;
    logic enable_transmitter;
    logic enable_receiver;
    
    // Address tracking - much simpler!
    logic [17:0] current_addr;
    logic [17:0] next_addr;
    logic addr_changed;
    
    // Simple state machine for sequencing
    typedef enum logic [1:0] {
        IDLE,
        WRITING,
        READING
    } state_t;
    
    state_t state;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_addr <= 18'd0;
            addr_changed <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (write_enable) begin
                        state <= WRITING;
                        current_addr <= write_addr;
                        addr_changed <= (write_addr != current_addr);
                    end else if (read_enable) begin
                        state <= READING;
                        current_addr <= read_addr;
                        addr_changed <= (read_addr != current_addr);
                    end
                end
                
                WRITING: begin
                    if (!write_enable) begin
                        state <= IDLE;
                    end
                end
                
                READING: begin
                    if (!read_enable) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // Control signal generation
    assign enable_write_mode = (state == WRITING);
    assign enable_read_mode = (state == READING);
    assign incoming_data = write_data;
    assign read_data = outgoing_data;
    assign write_ready = enable_transmitter;
    assign read_valid = enable_receiver;
    
    // Use the existing SDRAM controller
    // We'll just pass through the address management
    sdram_controller sdram_ctrl (
        .rst_n(rst_n),
        .clk(clk),
        .start(start),
        .enable_write_mode(enable_write_mode),
        .enable_read_mode(enable_read_mode),
        .incoming_data(incoming_data),
        .outgoing_data(outgoing_data),
        .enable_transmitter(enable_transmitter),
        .enable_receiver(enable_receiver),
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

endmodule