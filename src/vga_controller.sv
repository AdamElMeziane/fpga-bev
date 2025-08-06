module vga_controller (
    input  logic       clk,
    input  logic       reset,
    output logic       hsync,
    output logic       vsync,
    output logic       video_on,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic       frame_start
);
    localparam H_VISIBLE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48, H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam V_VISIBLE = 480, V_FRONT = 10, V_SYNC = 2,  V_BACK = 33, V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_count, v_count;

    assign x = h_count;
    assign y = v_count;
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign hsync = ~(h_count >= H_VISIBLE + H_FRONT && h_count < H_VISIBLE + H_FRONT + H_SYNC);
    assign vsync = ~(v_count >= V_VISIBLE + V_FRONT && v_count < V_VISIBLE + V_FRONT + V_SYNC);
    assign frame_start = (h_count == 0 && v_count == 0);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end
endmodule
