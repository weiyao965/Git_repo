`timescale 1ns / 1ps

module hdmi_driver(
    input               pixel_clk   ,
    input               sys_rst_n   ,

    //RGB接口
    output              video_hs    ,     
    output              video_vs    ,     
    output              video_de    ,     
    output      [23:0]  video_rgb   ,    
    output  reg         data_req    ,

    input       [23:0]  pixel_data  ,   
    output  reg [10:0]  pixel_xpos  ,   
    output  reg [10:0]  pixel_ypos    
);

    // 640x480@60Hz 分辨率时序参数（单位：像素时钟周期）
    parameter  H_SYNC   =  11'd96;
    parameter  H_BACK   =  11'd48;
    parameter  H_DISP   =  11'd640;
    parameter  H_FRONT  =  11'd16;
    parameter  H_TOTAL  =  11'd800;

    parameter  V_SYNC   =  11'd2;
    parameter  V_BACK   =  11'd33;
    parameter  V_DISP   =  11'd480;
    parameter  V_FRONT  =  11'd10;
    parameter  V_TOTAL  =  11'd525;

    reg  [11:0] cnt_h;
    reg  [11:0] cnt_v;

    // 请求像素点颜色数据输入
    always @(posedge pixel_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            data_req <= 1'b0;
        else if(((cnt_h >= H_SYNC + H_BACK - 2'd2) && (cnt_h < H_SYNC + H_BACK + H_DISP - 2'd2))
                && ((cnt_v >= V_SYNC + V_BACK) && (cnt_v < V_SYNC + V_BACK+V_DISP)))
            data_req <= 1'b1;
        else
            data_req <= 1'b0;
    end

    //像素点x坐标
    always@ (posedge pixel_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            pixel_xpos <= 11'd0;
        else if(data_req)
            pixel_xpos <= cnt_h + 2'd2 - H_SYNC - H_BACK ;
        else 
            pixel_xpos <= 11'd0;
    end
        
    //像素点y坐标    
    always@ (posedge pixel_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            pixel_ypos <= 11'd0;
        else if((cnt_v >= (V_SYNC + V_BACK)) && (cnt_v < (V_SYNC + V_BACK + V_DISP)))
            pixel_ypos <= cnt_v + 1'b1 - (V_SYNC + V_BACK) ;
        else 
            pixel_ypos <= 11'd0;
    end

    //行计数器对像素时钟计数
    always @(posedge pixel_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            cnt_h <= 11'd0;
        else begin
            if(cnt_h < H_TOTAL - 1'b1)
                cnt_h <= cnt_h + 1'b1;
            else 
                cnt_h <= 11'd0;
        end
    end

    //场计数器对行计数
    always @(posedge pixel_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            cnt_v <= 11'd0;
        else if(cnt_h == H_TOTAL - 1'b1) begin
            if(cnt_v < V_TOTAL - 1'b1)
                cnt_v <= cnt_v + 1'b1;
            else 
                cnt_v <= 11'd0;
        end
    end

    // =========================================================
    // 关键修正：控制信号全量打拍同步 (Total Delay = 7 Cycles)
    // 解释：FIFO读取(1拍) + 直方图管线(4拍) + MUX选择(1拍) + Display包装(1拍) = 7 拍
    // 将底层生成的原始消隐和同步信号无缝延迟 7 个时钟周期，强行吻合数据流！
    // =========================================================
    wire raw_hs = ( cnt_h < H_SYNC ) ? 1'b0 : 1'b1;
    wire raw_vs = ( cnt_v < V_SYNC ) ? 1'b0 : 1'b1;

    reg [6:0] de_shift;
    reg [6:0] hs_shift;
    reg [6:0] vs_shift;

    always @(posedge pixel_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            de_shift <= 7'd0;
            hs_shift <= 7'd0;
            vs_shift <= 7'd0;
        end else begin
            // data_req 就是最早触发图像数据流的 Enable 信号，我们将它打 7 拍变成最终的 DE 信号
            de_shift <= {de_shift[5:0], data_req};
            hs_shift <= {hs_shift[5:0], raw_hs};
            vs_shift <= {vs_shift[5:0], raw_vs};
        end
    end

    assign video_de = de_shift[6];
    assign video_hs = hs_shift[6];
    assign video_vs = vs_shift[6];

    // RGB888数据输出：现在 video_de 已经和 pixel_data 完美对齐，黑边遮罩不会再误杀正常像素
    assign video_rgb = video_de ? pixel_data : 24'd0;

endmodule