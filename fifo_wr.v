`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/05/31 20:58:24
// Design Name: 
// Module Name: fifo_wr
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// 本模块是负责写入的逻辑和信号的控制，具体信号生效在top模块中的fifo例化

module fifo_wr(
    input	            sys_clk,                  //时钟
    input               sys_rst_n,                //复位信号
    input               almost_empty,             //将空信号（比empty提前一个周期响应）
    input               almost_full,              //将满信号（比full提前一个周期响应
    input               ready_wr_data,            //外部输入的准备写入fifo的数据
    
    output reg          fifo_wr_ok,               //写入完成
    output reg          fifo_wr_en,               //写入使能（本模块是负责写入的逻辑和信号的控制，具体信号生效在top模块中的fifo例化）
    output reg[7:0]     fifo_wr_data              //每次写入fifo的数据
    );

    parameter           IDLE    = 4'b0001,
                        EN_WR   = 4'b0010,
                        WR_FIFO = 4'b0100,
                        WR_OK   = 4'b1000;


    reg [3:0]           fifo_wr_state;
    reg                 almost_empty_d0 ;          //almost_empty 延迟一拍
    reg                 almost_empty_d1 ;          //almost_empty 延迟两拍
    reg [3:0]           dly_cnt ;                  //延迟计数器



    //almost_empty属于读rd时钟域（读到空），所以在读写时钟异步时，要将almost_empty同步到写时钟下来，保证建立时间与保持时间，避免亚稳态
    always @( posedge sys_clk or negedge sys_rst_n )
    begin
        if ( !sys_rst_n )                   //复位
        begin
            almost_empty_d0 <= 1'b0;            //rxd在未接收数据时或数据没来时一直是处于高电平
            almost_empty_d1 <= 1'b0;
        end
        else
        begin                              //存下下降沿前后的值
            almost_empty_d0 <= almost_empty; 
            almost_empty_d1 <= almost_empty_d0;
        end    
    end

    always @( posedge sys_clk or negedge sys_rst_n )
    begin
        if ( !sys_rst_n )                   //复位
        begin
            fifo_wr_en <= 1'b0;
            fifo_wr_data <= 8'b0;
            fifo_wr_state <= IDLE;
            dly_cnt <= 4'b0;
        end
        else
        begin
            // fifo写数据逻辑与信号控制
            case ( fifo_wr_state )
                IDLE:
                    if ( almost_empty_d1 ) 
                        fifo_wr_state <= EN_WR;
                    else
                        fifo_wr_state <= IDLE;
                EN_WR:
                //延时 10 拍
                //原因是 FIFO IP 核内部状态信号的更新存在延时
                //延迟 10 拍以等待状态信号更新完毕 
                    if ( dly_cnt == 4'd10 )
                    begin
                        fifo_wr_en <= 1'b1;        //控制写使能信号
                        dly_cnt <= 4'b0;
                        fifo_wr_state <= WR_FIFO;
                    end
                    else
                        dly_cnt <= dly_cnt + 1;
                WR_FIFO:
                    if ( almost_full )             //快满了，则停止发送
                    begin
                        fifo_wr_en <= 1'b0;
                        fifo_wr_data <= 8'b0;
                    end

                default: fifo_wr_state <= IDLE;
            endcase
        end
            
    end


endmodule
