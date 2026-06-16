module key_debounce (
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output reg  key_pulse // 按键按下有效脉冲
);
    reg [19:0] cnt;
    reg key_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 20'd0;
            key_reg <= 1'b1;
            key_pulse <= 1'b0;
        end else begin
            key_reg <= key_in;
            if (key_reg != key_in) // 检测到电平变化
                cnt <= 20'd1000_000; // 20ms @ 50MHz
            else if (cnt > 0) begin
                cnt <= cnt - 1'b1;
                if (cnt == 20'd1) key_pulse <= ~key_in; // 稳定后采样
                else key_pulse <= 1'b0;
            end else key_pulse <= 1'b0;
        end
    end
endmodule