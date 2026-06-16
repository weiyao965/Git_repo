`timescale 1ns / 1ps

module cam_capture (
    input  wire        sys_rst_n,
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    input  wire [7:0]  cam_data,

    output wire [15:0] pixel_data, 
    output wire        pixel_valid
);

// 1. 打拍与边沿检测 (采用 negedge 下降沿采样)
reg vsync_dly;
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) vsync_dly <= 1'b0;
    else            vsync_dly <= cam_vsync;
end
wire pic_flag = (~vsync_dly) & cam_vsync; 

// 2. 丢弃前 10 帧防抖
reg [3:0] cnt_pic;
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        cnt_pic <= 4'd0;
    else if ((cnt_pic < 4'd10) && pic_flag)
        cnt_pic <= cnt_pic + 1'b1;
end
reg pic_valid;
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        pic_valid <= 1'b0;
    else if ((cnt_pic == 4'd10) && pic_flag)
        pic_valid <= 1'b1;
end

// 3. 严格的 640x480 像素裁剪 (核心保留！)
reg [10:0] h_cnt;
reg [10:0] v_cnt;
reg        data_flag;
reg [7:0]  pic_data_reg;
reg [15:0] data_out_reg;
reg        data_flag_dly1;

always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        h_cnt        <= 11'd0;
        v_cnt        <= 11'd0;
        data_flag    <= 1'b0;
        pic_data_reg <= 8'd0;
        data_out_reg <= 16'd0;
    end else begin
        if (pic_flag) begin
            h_cnt     <= 11'd0;
            v_cnt     <= 11'd0;
            data_flag <= 1'b0;
        end 
        else if (cam_href) begin
            data_flag    <= ~data_flag;
            pic_data_reg <= cam_data;
            
            if (data_flag == 1'b1) begin
                if (h_cnt >= 11'd320 && h_cnt < 11'd960 && v_cnt >= 11'd120 && v_cnt < 11'd600) begin
                    data_out_reg <= {pic_data_reg, cam_data};
                end
                h_cnt <= h_cnt + 1'b1; 
            end
        end 
        else begin
            data_flag <= 1'b0;
            if (h_cnt > 0) begin
                h_cnt <= 11'd0;
                v_cnt <= v_cnt + 1'b1; 
            end
        end
    end
end

always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        data_flag_dly1 <= 1'b0;
    else 
        data_flag_dly1 <= (data_flag == 1'b1 && h_cnt >= 11'd320 && h_cnt < 11'd960 && v_cnt >= 11'd120 && v_cnt < 11'd600);
end

// =========================================================
// 4. 终极时序修复：跨沿打拍桥梁 (半周期变全周期)
// =========================================================
// 提取出下降沿域的干净信号
wire [15:0] pixel_data_neg  = pic_valid ? data_out_reg   : 16'd0;
wire        pixel_valid_neg = pic_valid ? data_flag_dly1 : 1'b0;

// 在 FPGA 内部用上升沿接住它，完美衔接后级的 Wuji 和 SDRAM
reg [15:0] pixel_data_pos;
reg        pixel_valid_pos;

always @(posedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        pixel_data_pos  <= 16'd0;
        pixel_valid_pos <= 1'b0;
    end else begin
        pixel_data_pos  <= pixel_data_neg;
        pixel_valid_pos <= pixel_valid_neg;
    end
end

// 输出上升沿同步后的信号，时序和坐标系完美闭环
assign pixel_data  = pixel_data_pos;
assign pixel_valid = pixel_valid_pos;

endmodule

/*
module cam_capture (
    input  wire        sys_rst_n,
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    input  wire [7:0]  cam_data,

    output wire [15:0] pixel_data, 
    output wire        pixel_valid
);

// 1. 打拍与边沿检测 (采用 negedge 下降沿采样，完美避开数据翻转抖动期，彻底消灭彩色边带！)
reg vsync_dly;
// 将所有 posedge 改回 negedge，恢复最底层的时序稳定
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) vsync_dly <= 1'b0;
    else            vsync_dly <= cam_vsync;
end
wire pic_flag = (~vsync_dly) & cam_vsync; 

// 2. 丢弃前 10 帧防抖
reg [3:0] cnt_pic;
// 将所有 posedge 改回 negedge，恢复最底层的时序稳定
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        cnt_pic <= 4'd0;
    else if ((cnt_pic < 4'd10) && pic_flag)
        cnt_pic <= cnt_pic + 1'b1;
end
reg pic_valid;
// 将所有 posedge 改回 negedge，恢复最底层的时序稳定
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        pic_valid <= 1'b0;
    else if ((cnt_pic == 4'd10) && pic_flag)
        pic_valid <= 1'b1;
end

// 3. 严格的 640x480 像素裁剪
reg [10:0] h_cnt;
reg [10:0] v_cnt;
reg        data_flag;
reg [7:0]  pic_data_reg;
reg [15:0] data_out_reg;
reg        data_flag_dly1;

// 将所有 posedge 改回 negedge，恢复最底层的时序稳定
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        h_cnt        <= 11'd0;
        v_cnt        <= 11'd0;
        data_flag    <= 1'b0;
        pic_data_reg <= 8'd0;
        data_out_reg <= 16'd0;
    end else begin
        if (pic_flag) begin
            h_cnt     <= 11'd0;
            v_cnt     <= 11'd0;
            data_flag <= 1'b0;
        end 
        else if (cam_href) begin
            data_flag    <= ~data_flag;
            pic_data_reg <= cam_data;
            
            if (data_flag == 1'b1) begin
                if (h_cnt >= 11'd320 && h_cnt < 11'd960 && v_cnt >= 11'd120 && v_cnt < 11'd600) begin
                    data_out_reg <= {pic_data_reg, cam_data};
                end
                h_cnt <= h_cnt + 1'b1; 
            end
        end 
        else begin
            data_flag <= 1'b0;
            if (h_cnt > 0) begin
                h_cnt <= 11'd0;
                v_cnt <= v_cnt + 1'b1; 
            end
        end
    end
end

// 将所有 posedge 改回 negedge，恢复最底层的时序稳定
always @(negedge cam_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        data_flag_dly1 <= 1'b0;
    else 
        data_flag_dly1 <= (data_flag == 1'b1 && h_cnt >= 11'd320 && h_cnt < 11'd960 && v_cnt >= 11'd120 && v_cnt < 11'd600);
end

assign pixel_data  = pic_valid ? data_out_reg   : 16'd0;
assign pixel_valid = pic_valid ? data_flag_dly1 : 1'b0;

endmodule
*/