module image_rom (
    input  logic        clk,
    input  logic [17:0] addr,  // 320 × 240 = 76,800 → needs 17 bits
    output logic [2:0]  pixel
);

    logic [2:0] mem [0:76799];

    initial $readmemb("../assets/image_3bit.mem", mem);

    always_ff @(posedge clk)
        pixel <= mem[addr];

endmodule
