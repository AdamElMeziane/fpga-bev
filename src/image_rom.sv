module image_rom (
    input  logic        clk,
    input  logic [16:0] addr,
    output logic [2:0]  pixel
);

    (* rom_style = "block" *) logic [2:0] mem [0:76799];

    initial $readmemb("../assets/image_3bit.mem", mem);

    always_ff @(posedge clk)
        pixel <= mem[addr];

endmodule
