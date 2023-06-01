`timescale 1ns / 1ps


module send_256_8bit(
    input	            sys_clk,                  //时钟
    input               sys_rst_n,                //复位信号
    input               en_send,                  //数据生成模块使能
    //input               uart_tx_busy,             //检测发送通道是否忙
    output reg          data_ok,                  //生成数据完成
    output reg[7:0]     data_8bit                 //生成的数据
    );

    reg[7:0]            data_buf;
    parameter           IDLE    = 3'b001,
                        send    = 3'b010,
                        send_ok = 3'b100;


    reg[2:0] state = IDLE;

    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )  
        begin
            data_8bit <= 8'b0;
            data_buf <= 8'b0;
            data_ok   <= 1'b0;
        end
        
        else
        begin
            case ( state )
                IDLE:
                    if ( !data_ok && en_send ) state <= send;
                    else
                    begin
                        data_ok <= 1'b0;
                        state <= IDLE;
                    end   
                send:
                begin
                    data_8bit <= data_buf;
                    data_ok <= 1'b1;
                    state <= send_ok;
                end 
                send_ok:
                begin
                    data_buf <= data_buf + 1;
                    state <= IDLE;
                end
                default:
                    state <= IDLE;
            endcase
        end
    end
    //     else if ( en_send )
    //     begin

    //         data_8bit <= data_8bit + 1;
    //         data_ok <= 1'b1;
    //     end
    //     else
    //         data_8bit <= data_8bit;
    //         data_ok   <= 1'b0;
    // end

endmodule