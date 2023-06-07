`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/05/25 20:42:32
// Design Name: 
// Module Name: uart_rx
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

// 串口接收端
// 波特率 ：115200

module uart_rx(
    input	            sys_clk,                  //时钟
    input               sys_rst_n,                //复位信号
    input               uart_rxd,                 //UART接收端
    output reg[7:0]     uart_dout,                //接收的串行信号中的有效数据转为并行信号
    output reg          uart_done                 //接收完成信号
    );

    //parameter define
    parameter           CLK_FREQ = 50000000;            //时钟频率50MHz
    parameter           UART_BPS = 115200;              //波特率
    localparam          BPS_CNT  = CLK_FREQ/UART_BPS;   //分频系数


    reg                 uart_rxd_d0;                                             //存储当前rx通道值,比rx慢了一拍
    reg                 uart_rxd_d1;                    //存储上一时刻rx通道值，比rx慢了两拍
    reg                 rx_flag;                        //接收过程的标志信号
    reg[3:0]            rx_cnt;                         //指示传输状态
    reg[16:0]           clk_cnt;                        //周期计数，位宽取决于波特率和系统时钟频率（一个波特率周期的大小
    reg[7:0]            rx_data;                        //中间变量，寄存rxd通道输入端口的值，最后并行值输出给uart_dout

    wire                start_flag;                    //下降沿标志

    // step1：根据接收数据uart_rxd的第一个下降沿(下降沿检测)，使start_flag信号有效，表明串行数据start下降沿标志来了(tx发送的数据起始位为0)
    assign start_flag = uart_rxd_d1 & ( ~ uart_rxd_d0 );        //下降沿检测

    always @( posedge sys_clk or negedge sys_rst_n )
    //将异步信号uart_rxd同步到系统时钟下来，保证建立时间与保持时间，避免亚稳态
    begin
        if ( !sys_rst_n )                   //复位
        begin
            uart_rxd_d0 <= 1'b0;            //rxd在未接收数据时或数据没来时一直是处于高电平
            uart_rxd_d1 <= 1'b0;
        end
        else
        begin                              //存下下降沿前后的值
            uart_rxd_d0 <= uart_rxd; 
            uart_rxd_d1 <= uart_rxd_d0;
        end    
    end

    // step2：根据start_flag信号有效，将rx_flag信号拉高，表明接收过程开始及正在进行,以及传输后结束后检测到停止位时
                                                        //提前半个波特率周期将rx_flag拉低，为下一轮接收留一点时间
    always @( posedge sys_clk or negedge sys_rst_n )
    //拉高rx_flag信号，传输开始
    begin
        if ( !sys_rst_n )                   //复位
            rx_flag <= 1'b0;
        else
        begin
            if ( start_flag )             //rx_flag拉高
            begin                              //
                rx_flag <= 1'b1;
            end
            else if ( ( rx_cnt == 4'd9 ) && ( clk_cnt == (BPS_CNT - 1) / 2 ) )   //当目前传输状态进入到第九位且过了一半波特率周期时
            begin                                                          //拉低rx_flag
                rx_flag <= 1'b0;
            end
            else rx_flag <= rx_flag;
        end
        
    end

    // step3：rx_flag信号拉高后，clk_cnt开始计数，计至一个BPS_CNT为止
    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )                   //复位
            clk_cnt <= 16'b0;
        else if ( rx_flag )        //rx_flag拉高才启动计数器
        begin
            if ( clk_cnt < ( BPS_CNT - 1 ) )
                clk_cnt <= clk_cnt + 1;
            else
                clk_cnt <= 16'b0;
        end
        else
            clk_cnt <= 16'b0;
    end
    // step4：每满一个BPS_CNT周期，表示接收到了一帧数据，用rx_cnt表示现在接收的状态
    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )                   //复位
        begin
            rx_cnt <= 4'b0;
        end
        else if ( rx_flag )
        begin
            if ( clk_cnt == ( BPS_CNT - 1 ) )    //每满一个波特率周期，状态加1
                rx_cnt <= rx_cnt + 1;
            else
                rx_cnt <= rx_cnt;
        end
        else
            rx_cnt <= 4'b0;
    end
    // step5：接收完毕后，uart_done信号拉高,最后赋值给uart_dout
    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )
        begin
            uart_done <= 1'b0;
            uart_dout <= 8'b0;
        end
        else if ( rx_cnt == 4'd9 )
        begin
            uart_dout <= rx_data;
            uart_done <= 1'b1;    
        end
        else
        begin
            uart_done <= 1'b0;
            uart_dout <= 8'b0;
        end
    end

    // step6：uart_done信号拉高，将接收到的数据转为并行数据输出（逐帧接收时用中间变量缓存，用于最后赋值给uart_dout）
    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )                   //复位
            rx_data <= 8'b0;
        else if ( rx_flag )
        begin
            // 此处不用uart_rxd给rx_data赋值，因为uart_rxd为异步信号，不和时钟同步
            // 各个状态存数据只需要存一次，只需要在一半波特率周期时存一次值就行，此时值相对稳定
            if ( clk_cnt == ( BPS_CNT - 1 )/2  )
            begin
                case ( rx_cnt )
                4'd1 : rx_data[0] <= uart_rxd_d1;
                4'd2 : rx_data[1] <= uart_rxd_d1;
                4'd3 : rx_data[2] <= uart_rxd_d1;
                4'd4 : rx_data[3] <= uart_rxd_d1;
                4'd5 : rx_data[4] <= uart_rxd_d1;
                4'd6 : rx_data[5] <= uart_rxd_d1;
                4'd7 : rx_data[6] <= uart_rxd_d1;
                4'd8 : rx_data[7] <= uart_rxd_d1;
                default :;
            endcase
            end
            else
                rx_data <= rx_data; 
        end
        else rx_data <= 8'b0;
    end
endmodule
