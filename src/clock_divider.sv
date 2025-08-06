module clock_divider #(
    parameter integer DIVIDE_BY = 2  // Must be >= 2
)(
    input  logic clk_in,
    output logic clk_out
);

    logic [$clog2(DIVIDE_BY)-1:0] counter = 0;
    logic clk_reg = 0;

    always_ff @(posedge clk_in) begin
        if (counter == (DIVIDE_BY/2 - 1)) begin
            clk_reg <= ~clk_reg;
            counter <= 0;
        end else begin
            counter <= counter + 1;
        end
    end

    assign clk_out = clk_reg;

endmodule
