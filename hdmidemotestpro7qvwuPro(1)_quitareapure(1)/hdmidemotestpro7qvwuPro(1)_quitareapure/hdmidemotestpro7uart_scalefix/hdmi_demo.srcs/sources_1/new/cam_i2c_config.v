// 摄像头I2C初始化控制器
// 复用工程中已有的 i2c_master_top 模块
// 支持16位寄存器地址的OV5640

module cam_i2c_config(
    input   wire        rst,            // 高电平复位
    input   wire        clk,            // 100MHz
    input   wire [15:0] clk_div_cnt,   // I2C时钟分频
    // LUT接口
    output  reg  [9:0]  lut_index,
    // lut_data: {dev_addr[7:0], reg_addr[15:0], reg_data[7:0]} 打包为40bit
    // [39:32]=dev_addr, [31:16]=reg_addr, [15:8]=unused, [7:0]=reg_data
    input   wire [31:0] lut_data,
    output  wire        init_done,
    // I2C物理接口
    inout   wire        i2c_scl,
    inout   wire        i2c_sda
);

wire        scl_pad_i, scl_pad_o, scl_padoen_o;
wire        sda_pad_i, sda_pad_o, sda_padoen_o;

assign sda_pad_i = i2c_sda;
assign i2c_sda   = (~sda_padoen_o) ? sda_pad_o : 1'bz;
assign scl_pad_i = i2c_scl;
assign i2c_scl   = (~scl_padoen_o) ? scl_pad_o : 1'bz;

reg         i2c_write_req;
wire        i2c_write_req_ack;
wire [7:0]  i2c_slave_dev_addr;
wire [15:0] i2c_slave_reg_addr;
wire [7:0]  i2c_write_data;
wire        i2c_error;

assign i2c_slave_dev_addr = lut_data[31:24];
assign i2c_slave_reg_addr = lut_data[23:8];
assign i2c_write_data     = lut_data[7:0];

localparam S_IDLE    = 3'd0;
localparam S_CHK     = 3'd1;
localparam S_WR      = 3'd2;
localparam S_WR_WAIT = 3'd3;
localparam S_DONE    = 3'd4;

reg [2:0] state;
assign init_done = (state == S_DONE);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state         <= S_IDLE;
        lut_index     <= 10'd0;
        i2c_write_req <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                lut_index <= 10'd0;
                state     <= S_CHK;
            end
            S_CHK: begin
                if (i2c_slave_dev_addr == 8'hFF)
                    state <= S_DONE;
                else begin
                    i2c_write_req <= 1'b1;
                    state         <= S_WR;
                end
            end
            S_WR: begin
                if (i2c_write_req_ack) begin
                    i2c_write_req <= 1'b0;
                    state         <= S_WR_WAIT;
                end
            end
            S_WR_WAIT: begin
                if (!i2c_write_req_ack) begin
                    lut_index <= lut_index + 10'd1;
                    state     <= S_CHK;
                end
            end
            S_DONE: state <= S_DONE;
            default: state <= S_IDLE;
        endcase
    end
end

i2c_master_top i2c_master_top_cam(
    .clk                (clk               ),
    .rst                (rst               ),
    .clk_div_cnt        (clk_div_cnt       ),
    .i2c_addr_2byte     (1'b1              ),
    .i2c_read_req       (1'b0              ),
    .i2c_read_req_ack   (                  ),
    .i2c_write_req      (i2c_write_req     ),
    .i2c_write_req_ack  (i2c_write_req_ack ),
    .i2c_slave_dev_addr (i2c_slave_dev_addr),
    .i2c_slave_reg_addr (i2c_slave_reg_addr),
    .i2c_write_data     (i2c_write_data    ),
    .i2c_read_data      (                  ),
    .error              (i2c_error         ),
    .scl_pad_i          (scl_pad_i         ),
    .scl_pad_o          (scl_pad_o         ),
    .scl_padoen_o       (scl_padoen_o      ),
    .sda_pad_i          (sda_pad_i         ),
    .sda_pad_o          (sda_pad_o         ),
    .sda_padoen_o       (sda_padoen_o      )
);

endmodule