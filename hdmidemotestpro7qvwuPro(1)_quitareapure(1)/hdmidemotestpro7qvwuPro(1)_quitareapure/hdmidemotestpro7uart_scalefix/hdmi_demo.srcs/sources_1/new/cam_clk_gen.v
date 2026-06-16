// 摄像头外部时钟分频器
// 从系统时钟/PLL输出分频产生摄像头所需的 XCLK (24MHz 或 12MHz)
// OV5640 支持 6~54MHz XCLK, 推荐 24MHz
// 若PLL c0=100MHz: 分频系数=4 → 25MHz (可用)
// 若PLL c1=25MHz(视频时钟): 直接使用
//
// 本模块从 clk_100mhz 分频产生 ~25MHz

module cam_clk_gen(
    input  wire clk_in,    // 100MHz (来自PLL clk_100mhz)
    input  wire rst_n,
    output wire cam_xclk   // ~25MHz 供摄像头使用
);

// 4分频: 100MHz / 4 = 25MHz
reg [1:0] cnt;
reg       clk_div;

always @(posedge clk_in or negedge rst_n) begin
    if (!rst_n) begin
        cnt     <= 2'd0;
        clk_div <= 1'b0;
    end else begin
        if (cnt == 2'd1) begin
            cnt     <= 2'd0;
            clk_div <= ~clk_div;
        end else begin
            cnt <= cnt + 2'd1;
        end
    end
end

assign cam_xclk = clk_div;

endmodule
