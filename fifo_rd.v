`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/05/31 20:58:24
// Design Name: 
// Module Name: fifo_rd
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


module fifo_rd(
    input	            sys_clk,                  //时钟
    input               sys_rst_n,                //复位信号
    input               almost_empty,             //将空信号（比empty提前一个周期响应）
    input               almost_full,              //将满信号（比full提前一个周期响应

    output reg          fifo_rd_empty,
    output reg          fifo_rd_en
    );


    parameter           IDLE    = 4'b0001,
                        EN_RD   = 4'b0010,
                        RD_FIFO = 4'b0100,
                        RD_OK   = 4'b1000;


    reg [2:0]           fifo_rd_state;
    reg                 almost_full_d0 ;          //almost_full 延迟一拍
    reg                 almost_full_d1 ;          //almost_full 延迟两拍
    reg [3:0]           dly_cnt ;                  //延迟计数器


        //almost_empty属于读rd时钟域（读到空），所以在读写时钟异步时，要将almost_empty同步到写时钟下来，保证建立时间与保持时间，避免亚稳态
    always @( posedge sys_clk or negedge sys_rst_n )
    begin
        if ( !sys_rst_n )                   //复位
        begin
            almost_full_d0 <= 1'b0;            //rxd在未接收数据时或数据没来时一直是处于高电平
            almost_full_d1 <= 1'b0;
        end
        else
        begin                              //存下下降沿前后的值
            almost_full_d0 <= almost_full; 
            almost_full_d1 <= almost_full_d0;
        end    
    end

    always @( posedge sys_clk or negedge sys_rst_n )
    begin
        if ( !sys_rst_n )                   //复位
        begin
            fifo_rd_en <= 1'b0;
            fifo_rd_state <= IDLE;
            fifo_rd_empty <= 1'b0;
            dly_cnt <= 4'b0;
        end
        else
        begin
            // fifo写数据逻辑与信号控制
            case ( fifo_rd_state )
                IDLE:
                begin
                    if ( almost_full_d1 )
                    begin
                        fifo_rd_state <= EN_RD; 
                    end      
                    else
                        fifo_rd_state <= IDLE;
                end
                EN_RD:
                //延时 10 拍
                //原因是 FIFO IP 核内部状态信号的更新存在延时
                //延迟 10 拍以等待状态信号更新完毕 
                    if ( dly_cnt == 4'd10 )
                    begin
                        fifo_rd_en <= 1'b1;        //控制写使能信号
                        dly_cnt <= 4'b0;
                        fifo_rd_state <= RD_FIFO;
                    end
                    else
                        dly_cnt <= dly_cnt + 1;
                RD_FIFO:
                    if ( almost_empty )             //快空了，则停止读取
                    begin
                        fifo_rd_en <= 1'b0;
                        fifo_rd_empty <= 1'b1;     //读完了fifo中所有内容的标志
                        fifo_rd_state <= IDLE;
                    end
                    else
                    begin
                        fifo_rd_en <= 1'b1;
                        fifo_rd_state <= RD_OK;
                    end
                RD_OK:                          //等一拍让读出数据稳定，
                begin
                    fifo_rd_state <= IDLE;
                end               
                default: fifo_rd_state <= IDLE;
            endcase
        end          
    end

endmodule
