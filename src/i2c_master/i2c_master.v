module i2c_master #(
    parameter CLK_DIVIDER = 250, // 1 scl pules per 250 system clk
    parameter CLK_CNT_WIDTH = 16
)(
    // System
    input  wire        clk,
    input  wire        rst_n,

    // I2C Physical Bus
    inout  wire        sda,
    output wire        scl,

    // Transaction Control
    input  wire        start,        
    input  wire [6:0]  slave_addr,   
    input  wire [7:0]  reg_addr,     

    // Status / Output
    output reg         busy,         
    output reg         done,         
    output reg         ack_error,  
    output reg [7:0]   read_data  
);

    // I2C Bus control
    reg sda_oe;

    assign sda = (sda_oe) ? 1'b0 : 1'bz;
    wire sda_in = sda;

    // Dividing clock for scl pulse
    reg scl_oe;
    assign scl = (scl_oe) ? 1'b1 : 1'b0;

    reg [CLK_CNT_WIDTH-1:0] clk_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 0;
            scl_oe <= 1;  // SCL high = IDEL state
        end else begin
            if (clk_cnt == CLK_DIVIDER - 1) begin
                clk_cnt <= 0;
                scl_oe <= ~scl_oe;  // Togle scl
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // Producing scl pulse falling, rising edge
    wire scl_val = scl_oe;
    reg scl_prev;
    wire scl_rise = (scl_prev == 0 && scl_val == 1);
    wire scl_fall = (scl_prev == 1 && scl_val == 0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scl_prev <= 1'b1;  // IDEL
        else scl_prev <= scl_val;
    end


    


    




