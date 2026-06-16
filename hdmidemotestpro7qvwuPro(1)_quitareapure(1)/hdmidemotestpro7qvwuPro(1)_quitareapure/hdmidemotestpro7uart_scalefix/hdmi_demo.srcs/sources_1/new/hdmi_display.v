module hdmi_display(
    input               hdmi_clk,
    input               rst_n,
    input               data_req,
    input       [10:0]  pixel_xpos,
    input       [10:0]  pixel_ypos,
    output  reg [23:0]  pixel_data,
    input       [23:0]  cam_pixel_data,
    input               cam_buf_ready,
    output  wire        cam_rd_en,
    output  wire        vs_start,       // 保留端口但不使用
    input               dbg_vsync,
    input               dbg_href
);

// 摄像头读使能：在有效显示区域且缓存就绪时读取
assign cam_rd_en = data_req & cam_buf_ready;
assign vs_start  = 1'b0; // 不再需要

// =========================================================
// 绿纹暴力抑制器 (动态色彩超限抑制)
// =========================================================
wire [7:0] cur_r = cam_pixel_data[23:16];
wire [7:0] cur_g = cam_pixel_data[15:8];
wire [7:0] cur_b = cam_pixel_data[7:0];

// =========================================================

always @(posedge hdmi_clk or negedge rst_n) begin
    if (!rst_n) 
        pixel_data <= 24'h0;
    else if (data_req) begin// <--- 彻底去掉了 if (data_req) 的限制！
        if (!cam_buf_ready) begin
            // SDRAM未初始化完成时显示彩条
            if      (pixel_xpos < 11'd80)  pixel_data <= 24'hFFFFFF;
            else if (pixel_xpos < 11'd160) pixel_data <= 24'hFFFF00;
            else if (pixel_xpos < 11'd240) pixel_data <= 24'h00FFFF;
            else if (pixel_xpos < 11'd320) pixel_data <= 24'h00FF00;
            else if (pixel_xpos < 11'd400) pixel_data <= 24'hFF00FF;
            else if (pixel_xpos < 11'd480) pixel_data <= 24'hFF0000;
            else if (pixel_xpos < 11'd560) pixel_data <= 24'h0000FF;
            else                           pixel_data <= 24'h000000;
        end else begin
            // 输出经过安全处理的像素，彻底屏蔽耀眼的绿纹
            pixel_data <= {cur_r, cur_g, cur_b};
        end
    end
end

endmodule