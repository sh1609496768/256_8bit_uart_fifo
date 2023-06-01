`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/05/25 15:22:53
// Design Name: 
// Module Name: uart_tx
// Project Name: uart_tx
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

// 串口发送端
// 波特率 ：115200

module uart_tx(
    input	      sys_clk,                  //时钟
    input         sys_rst_n,                //复位信号
    (* mark_debug = "true" *)input         uart_en,                  //uart使能
    (* mark_debug = "true" *)input  [7:0]  uart_din,                 //输入数据
    output        uart_tx_busy,             //tx通道可用状态标志     
    output  reg   uart_txd                  //UART发送端
    );
    
//parameter define
parameter  CLK_FREQ = 50000000;            //时钟频率
parameter  UART_BPS = 115200;                //波特率
localparam  BPS_CNT  = CLK_FREQ/UART_BPS;   //分频系数

//reg define
reg        uart_en_d0;                      //连续寄存uart_en信号，为了实现边缘检测（检测上升沿）d0高，d1低
reg        uart_en_d1;  
reg [15:0] clk_cnt;                         //时钟周期计数
(* mark_debug = "true" *)reg [ 3:0] tx_cnt;                          //表征tx传输位数
(* mark_debug = "true" *)reg        tx_flag;                         //传输开始表示
reg [ 7:0] tx_data;                         //寄存输入的并行信号
//wire define
wire       en_flag;                         //使能标志

//*****************************************************
//**                    main code
//*****************************************************
//tx_flag是发送过程的标志，发送时则tx通道处于busy状态
assign uart_tx_busy = tx_flag;

//连续寄存uart_en信号，为了实现 边缘检测 （检测上升沿）d0高，d1低，使能标志en_flag开启，说明uart_en上升沿来了，接下来拉高tx_flag
assign en_flag = (~uart_en_d1) & uart_en_d0;

//连续寄存uart_en信号的过程
always @(posedge sys_clk or negedge sys_rst_n) begin         
    if (!sys_rst_n) begin
        uart_en_d0 <= 1'b1;                                  
        uart_en_d1 <= 1'b1;
    end                                                      
    else begin                                               
        uart_en_d0 <= uart_en;               //当前值                
        uart_en_d1 <= uart_en_d0;            //上一时刻值        
    end
end

// 当en_flag有效，所做的操作：将uart_din寄存在tx_data里
always @(posedge sys_clk or negedge sys_rst_n) begin         
    if (!sys_rst_n) begin                                  
        tx_flag <= 1'b0;
        tx_data <= 8'd0;
    end 
    else if (en_flag) begin                 //  
            tx_flag <= 1'b1;                //传输过程标志
            tx_data <= uart_din;            //当en_flag有效。将uart_din寄存在tx_data里
        end
                                            
    else if ((tx_cnt == 4'd9) && (clk_cnt == BPS_CNT - (BPS_CNT/16))) begin                                       
        tx_flag <= 1'b0;                //传输完毕后，所有标志或寄存器回到初始状态
        tx_data <= 8'd0;
    end
    else begin
        tx_flag <= tx_flag;             //en_flag没有拉高及uart_en上升沿没有来时，保持原值
        tx_data <= tx_data;
    end 
end

//根据tx_flag有效，即传输真正开始后，对clk_cnt进行计数
always @(posedge sys_clk or negedge sys_rst_n) begin         
    if (!sys_rst_n)                             
        clk_cnt <= 16'd0;                                  
    else if (tx_flag) begin                 //clk_cnt计数，计至一个BPS_CNT为止
        if (clk_cnt < BPS_CNT - 1)
            clk_cnt <= clk_cnt + 1'b1;
        else
            clk_cnt <= 16'd0;               //记满了，开始新一轮
    end
    else                             
        clk_cnt <= 16'd0; 				    //传输结束或传输未开始，clk_cnt回到初始状态
end

//在tx_flag有效时，根据clk_cnt计数值与波特率周期的比较，计算帧数状态，
always @(posedge sys_clk or negedge sys_rst_n) begin         
    if (!sys_rst_n)                             
        tx_cnt <= 4'd0;
    else if (tx_flag) begin                 //传输开始时
        if (clk_cnt == BPS_CNT - 1)			//BPS_CNT：波特率周期（即一帧数据的长度）
            tx_cnt <= tx_cnt + 1'b1;		//计数每到一个波特周期，就加1，表明传输过程中目前处于第几帧了
        else
            tx_cnt <= tx_cnt;       
    end
    else                              
        tx_cnt  <= 4'd0;				    //传输未开始的默认状态
end

// 将输入的并行数据按位转为串行传输出去
always @(posedge sys_clk or negedge sys_rst_n) begin        
    if (!sys_rst_n)  
        uart_txd <= 1'b1;                  //串口发送端在未发送数据时为高电平：因为如果数据来了，要以低电平为start标志  
    else if (tx_flag)
        case(tx_cnt)
            4'd0: uart_txd <= 1'b0;         //起始位
            4'd1: uart_txd <= tx_data[0];   //数据最低位
            4'd2: uart_txd <= tx_data[1];   
            4'd3: uart_txd <= tx_data[2];
            4'd4: uart_txd <= tx_data[3];
            4'd5: uart_txd <= tx_data[4];
            4'd6: uart_txd <= tx_data[5];
            4'd7: uart_txd <= tx_data[6];   
            4'd8: uart_txd <= tx_data[7];   //数据最高位
            4'd9: uart_txd <= 1'b1;         //ͣ结束位
            default: ;
        endcase
    else 
        uart_txd <= 1'b1;                   //没有数据发送时，tx通道持续为1
end
endmodule

