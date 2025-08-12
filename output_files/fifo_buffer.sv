// FIFO Buffer for SDRAM to VGA data transfer
// Adapted from EP4CE6 project for VGA display

module fifo_buffer #(
    parameter ADDR_WIDTH = 11,  // 2048 entries for line buffer
    parameter DATA_WIDTH = 16
)(
    input  logic rst_n,
    input  logic clk_write,    // SDRAM clock domain (133MHz)
    input  logic clk_read,     // VGA clock domain (25MHz)
    
    // Write interface (SDRAM side)
    input  logic write_enable,
    input  logic [DATA_WIDTH-1:0] write_data,
    output logic fifo_full,
    
    // Read interface (VGA side)
    input  logic read_enable,
    output logic [DATA_WIDTH-1:0] read_data,
    output logic fifo_empty,
    output logic fifo_half_full
);

    // Dual-port RAM for FIFO storage
    logic [DATA_WIDTH-1:0] memory [0:2**ADDR_WIDTH-1];
    
    // Gray code pointers for clock domain crossing
    logic [ADDR_WIDTH:0] write_ptr_gray, write_ptr_gray_next;
    logic [ADDR_WIDTH:0] read_ptr_gray, read_ptr_gray_next;
    logic [ADDR_WIDTH:0] write_ptr_bin, write_ptr_bin_next;
    logic [ADDR_WIDTH:0] read_ptr_bin, read_ptr_bin_next;
    
    // Synchronized pointers
    logic [ADDR_WIDTH:0] write_ptr_gray_sync1, write_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] read_ptr_gray_sync1, read_ptr_gray_sync2;
    
    // Status signals
    logic full, empty, half_full;
    
    // Binary to Gray code conversion
    function [ADDR_WIDTH:0] bin2gray(logic [ADDR_WIDTH:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction
    
    // Gray to Binary code conversion
    function [ADDR_WIDTH:0] gray2bin(logic [ADDR_WIDTH:0] gray);
        logic [ADDR_WIDTH:0] bin;
        bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        gray2bin = bin;
    endfunction

    //========================================================================
    // Write Clock Domain
    //========================================================================
    
    // Write pointer logic
    assign write_ptr_bin_next = write_ptr_bin + (write_enable & ~full);
    assign write_ptr_gray_next = bin2gray(write_ptr_bin_next);
    
    // Full flag generation
    assign full = (write_ptr_gray_next == {~read_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], 
                                          read_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    
    // Write to memory
    always_ff @(posedge clk_write) begin
        if (write_enable && !full) begin
            memory[write_ptr_bin[ADDR_WIDTH-1:0]] <= write_data;
        end
    end
    
    // Write domain registers
    always_ff @(posedge clk_write or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr_bin <= '0;
            write_ptr_gray <= '0;
            read_ptr_gray_sync1 <= '0;
            read_ptr_gray_sync2 <= '0;
        end else begin
            write_ptr_bin <= write_ptr_bin_next;
            write_ptr_gray <= write_ptr_gray_next;
            read_ptr_gray_sync1 <= read_ptr_gray;
            read_ptr_gray_sync2 <= read_ptr_gray_sync1;
        end
    end

    //========================================================================
    // Read Clock Domain
    //========================================================================
    
    // Read pointer logic
    assign read_ptr_bin_next = read_ptr_bin + (read_enable & ~empty);
    assign read_ptr_gray_next = bin2gray(read_ptr_bin_next);
    
    // Empty flag generation
    assign empty = (read_ptr_gray == write_ptr_gray_sync2);
    
    // Half full flag (in read domain for VGA flow control)
    logic [ADDR_WIDTH:0] write_ptr_bin_sync;
    assign write_ptr_bin_sync = gray2bin(write_ptr_gray_sync2);
    assign half_full = ((write_ptr_bin_sync - read_ptr_bin) >= (2**ADDR_WIDTH / 2));
    
    // Read from memory
    always_ff @(posedge clk_read) begin
        if (read_enable && !empty) begin
            read_data <= memory[read_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end
    
    // Read domain registers
    always_ff @(posedge clk_read or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr_bin <= '0;
            read_ptr_gray <= '0;
            write_ptr_gray_sync1 <= '0;
            write_ptr_gray_sync2 <= '0;
        end else begin
            read_ptr_bin <= read_ptr_bin_next;
            read_ptr_gray <= read_ptr_gray_next;
            write_ptr_gray_sync1 <= write_ptr_gray;
            write_ptr_gray_sync2 <= write_ptr_gray_sync1;
        end
    end

    // Output assignments
    assign fifo_full = full;
    assign fifo_empty = empty;
    assign fifo_half_full = half_full;

endmodule