module vga_display_controller (
    //==============================
    // System Signals
    //==============================
    input  logic        clk,         // Pixel clock (25 MHz)
    input  logic        rst_n,       // Active-low reset

    //==============================
    // VGA Output Signals
    //==============================
    output logic        hsync,       // Horizontal sync pulse
    output logic        vsync,       // Vertical sync pulse
    output logic        video_on,    // High during visible area
    output logic [9:0]  x,           // Current pixel X coordinate
    output logic [9:0]  y,           // Current pixel Y coordinate
    output logic        frame_start  // High for 1 cycle at top-left corner
);

    //==============================
    // VGA Timing Parameters (640x480 @ 60Hz)
    //==============================
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    //==============================
    // Internal Counters
    //==============================
    logic [9:0] h_count;  // Horizontal pixel counter
    logic [9:0] v_count;  // Vertical line counter

    //==============================
    // Horizontal & Vertical Counters
    //==============================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;

                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    //==============================
    // VGA Signal Generation
    //==============================
    assign hsync = ~(h_count >= H_VISIBLE + H_FRONT &&
                     h_count <  H_VISIBLE + H_FRONT + H_SYNC);

    assign vsync = ~(v_count >= V_VISIBLE + V_FRONT &&
                     v_count <  V_VISIBLE + V_FRONT + V_SYNC);

    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    assign frame_start = (h_count == 0) && (v_count == 0);

    assign x = h_count;
    assign y = v_count;

endmodule
