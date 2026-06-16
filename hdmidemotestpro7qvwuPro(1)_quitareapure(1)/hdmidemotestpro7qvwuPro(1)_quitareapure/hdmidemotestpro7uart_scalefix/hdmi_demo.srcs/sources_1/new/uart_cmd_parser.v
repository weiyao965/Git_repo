`timescale 1ns / 1ps

module uart_cmd_parser(
    input  wire        clk,        
    input  wire        rst_n,      
    
    // 连接到 uart_rx
    input  wire [7:0]  rx_data,    
    input  wire        rx_flag,    
    
    // 输出给状态机的同步信号
    output reg         cmd_valid,  // 指令有效脉冲
    output reg  [7:0]  cmd_type,   // 指令类型
    output reg  [15:0] cmd_data    // 16位数据
);

    localparam S_IDLE   = 3'd0;
    localparam S_CMD    = 3'd1;
    localparam S_DATA_H = 3'd2;
    localparam S_DATA_L = 3'd3;
    localparam S_TAIL   = 3'd4;
    
    reg [2:0] state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cmd_valid <= 1'b0;
            cmd_type  <= 8'd0;
            cmd_data  <= 16'd0;
        end else begin
            cmd_valid <= 1'b0; // 默认拉低，只生成1拍脉冲
            
            if (rx_flag) begin
                case (state)
                    S_IDLE: begin
                        if (rx_data == 8'hAA) state <= S_CMD;
                    end
                    S_CMD: begin
                        cmd_type <= rx_data;
                        state <= S_DATA_H;
                    end
                    S_DATA_H: begin
                        cmd_data[15:8] <= rx_data;
                        state <= S_DATA_L;
                    end
                    S_DATA_L: begin
                        cmd_data[7:0] <= rx_data;
                        state <= S_TAIL;
                    end
                    S_TAIL: begin
                        if (rx_data == 8'h55) begin
                            cmd_valid <= 1'b1; // 校验成功，输出有效脉冲
                        end
                        state <= S_IDLE; 
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule