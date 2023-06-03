`timescale 1ns / 1ps

// 功能描述：
// 由数据生成模块 send_256_8bit 生成256位8bit数据，通过tx口发送给rx接收（自发自收）
// rx接收后写入FIFO，写完后再取出这256个8bit数据，用在线逻辑分析仪捕捉

module top(
    input	                   sys_clk,                  //时钟
    input                      sys_rst_n,                //复位信号
    input                      uart_rxd,                 //UART接收端
    output                     uart_txd                  //UART发送端
    // input                       uart_en,
    // input [7:0]                 uart_din,
    );             

    //parameter define
    parameter           CLK_FREQ        = 50000000;            //时钟频率
    parameter           UART_BPS        = 115200;                //波特率
    localparam          BPS_CNT         = CLK_FREQ/UART_BPS;   //分频系数

    parameter           IDLE            = 15'b000_0000_0000_0001,   // 1
                        GET_DATA        = 15'b000_0000_0000_0010,   // 2
                        BUF_DATA        = 15'b000_0000_0000_0100,   // 4
                        TX_RX_DATA      = 15'b000_0000_0000_1000,   // 8
                        TX_RX_OK        = 15'b000_0000_0001_0000,   // 16
                        WR_FIFO_READY   = 15'b000_0000_0010_0000,   // 32
                        WR_FIFO_WAIT    = 15'b000_0000_0100_0000,   // 64
                        WR_FIFO         = 15'b000_0000_1000_0000,   // 128
                        WR_FIFO_OK      = 15'b000_0001_0000_0000,   // 256
                        FULL_256        = 15'b000_0010_0000_0000,   // 512
                        RD_FIFO_READY   = 15'b000_0100_0000_0000,   // 1024
                        RD_FIFO_EN      = 15'b000_1000_0000_0000,   // 2048
                        RD_FIFO         = 15'b001_0000_0000_0000,   // 4096
                        RD_OK           = 15'b010_0000_0000_0000,   // 8192
                        EMPTY_256       = 15'b100_0000_0000_0000;   // 16384

                        

    //reg define
    reg                 en_send;                //数据生成模块的使能信号 
    reg [14:0]          state = IDLE;
    reg [7:0]           uart_din;               //TX发送的数据
    reg [7:0]           uart_dout_buf;          //uart_dout只在一个时间有值，其他时候都是0，需要一个变量保存
    
    reg [15:0]          count;                  //计数
    reg [15:0]          bps_cnt;

    reg                 ready_wr_data;


        //fifo
    reg [3:0]           fifo_dly_cnt;
    reg                 fifo_wr_en, fifo_rd_en;
    reg [7:0]           fifo_wr_data;                          //写入FIFO的数据
    
    //wire define

        //uart
    wire                uart_done;
    wire [7:0]          uart_dout;
    //wire                send_open_signal;       //开启数据生成模块的指示信号                     
    wire                uart_tx_busy;           //tx通道状态
    wire                data_ok;
    wire [7:0]          data_8bit;              //接收到的数据

        //fifo
  
    wire full, empty;
    wire almost_full, almost_empty;
    wire fifo_wr_ok;                            //FIFO写入一个数据完成的标志
    wire fifo_rd_empty;                         //FIFO读完所有数据完成的标志
    
    wire [7:0] fifo_rd_data;

    wire[7:0]  rd_data_count;
    wire[7:0]  wr_data_count;

    // reg uart_en = 0;
    // reg[7:0] uart_din = 8'b1110_1001;
    // reg[16:0] conut = 16'b0;
    // wire uart_en = 1'b1;

    // assign send_open_signal = ~ uart_tx_busy;

    always @( posedge sys_clk or negedge sys_rst_n ) 
    begin
        if ( !sys_rst_n )  
        begin
            count <= 16'b0;
            bps_cnt <= 16'b0;
            en_send <= 1'b0;
            uart_din <= 8'b0;
            uart_dout_buf <= 8'b0;
            fifo_dly_cnt <= 4'b0;
            fifo_wr_en <= 1'b0;
            fifo_rd_en <= 1'b0;
        end
        else
            case( state )
                // 1、根据tx通道状态（busy标志），等待发送开启信号，使能数据发生模块
                IDLE:
                begin
                    if ( ! uart_tx_busy )       // tx不忙，则开启数据生成器
                    begin
                        en_send <= 1'b1;
                        state <= GET_DATA;  
                    end
                    else state <= IDLE;
                end
                // 2、数据获取模块，只有数据发生模块发出OK信号后，才会进入TX发送，否则一直在该状态等待数据发生器数据发生成功
                GET_DATA:
                begin
                    if ( data_ok )              //数据生成完毕，uart_din可以接收data_8bit，data_ok作为传输的使能信号
                    begin
                        en_send <= 1'b0;
                        uart_din <= data_8bit;
                        count <= count + 1;
                        state <= BUF_DATA;
                    end
                    else state <= GET_DATA;     //继续等待发送完成
                end
                // 3、缓冲等待一个周期，主要是为了等待busy信号
                //（busy信号比tx使能信号要慢两拍，比TX_DATA状态慢一拍，所以加入缓冲BUF_DATA状态，使TX_DATA状态与busy同步）
                BUF_DATA:
                    state <= TX_RX_DATA;
                // 4、传输TX，RX同时，当RX接收完毕后，进入写FIFO，（接收传输过程与uart_done同步，比busy慢一拍结束）
                TX_RX_DATA:
                begin
                    if ( ! uart_done ) //没发完,没收完
                    begin    
                        state <= TX_RX_DATA;
                    end
                    else                //发完了,收完了，接着去写入FIFO
                    begin
                        uart_dout_buf <= uart_dout;
                        state <= TX_RX_OK;
                    end
                        
                end
                // 5、传输结束状态，根据计数值选择是继续获取数据还是结束获取数据
                TX_RX_OK:
                begin
                    if ( count < 256 )
                    begin
                        if ( bps_cnt < ( BPS_CNT - 1 ) )                    //延迟一个波特率周期，为了使uart_done能正确融入时序逻辑
                            bps_cnt <= bps_cnt + 1;
                        else
                        begin
                            bps_cnt <= 16'b0;
                            state <= WR_FIFO_READY;
                        end
                    end
                    else
                    begin
                        en_send <= 1'b0;
                        state <= FULL_256;   
                    end       
                end
                // 6、数据传输与接收完毕后，开始控制FIFO写使能
                WR_FIFO_READY:
                begin
                    state <= WR_FIFO_WAIT;
                end

                WR_FIFO_WAIT:
                //延时 10 拍
                //原因是 FIFO IP 核内部状态信号的更新存在延时
                //延迟 10 拍以等待状态信号更新完毕 
                begin
                    if ( fifo_dly_cnt == 4'd10 )
                    begin
                        fifo_dly_cnt <= 4'b0;
                        state <= WR_FIFO;
                    end
                    else
                        fifo_dly_cnt <= fifo_dly_cnt + 1;
                end

                WR_FIFO:
                begin
                    if ( almost_full )             //快满了，则停止发送
                    begin
                        fifo_wr_en <= 1'b0;
                        fifo_wr_data <= 8'b0;
                        state <= FULL_256;
                    end
                    else
                    begin
                        fifo_wr_en <= 1'b1;        //控制写使能信号
                        fifo_wr_data <= uart_dout_buf;   //将接收到的数据写入
                        state <= WR_FIFO_OK;
                    end
                end

                WR_FIFO_OK:
                begin                                   //等一拍让写入数据稳定，并将数据写入完毕信号置1
                    en_send <= 1'b1;
                    fifo_wr_en <= 1'b0;
                    state <= GET_DATA;
                end

                // 9、当256位8bit数据发送完毕后，进入此状态，不再接收与发送新的数据，准备从FIFO中读取
                FULL_256:
                begin
                    en_send <= 0;
                    uart_din <= 8'b0;
                    fifo_wr_en <= 1'b0;
                    state <= RD_FIFO_READY;
                end

                RD_FIFO_READY:
                begin
                        state <= RD_FIFO_EN; 
                end      

                RD_FIFO_EN:
                
                    state <= RD_FIFO;
                    

                RD_FIFO:
                    if ( almost_empty )             //快空了，则停止读取
                    begin
                        fifo_rd_en <= 1'b0;
                        state <= EMPTY_256;
                    end
                    else
                    begin
                        //延时 10 拍
                        //原因是 FIFO IP 核内部状态信号的更新存在延时
                        //延迟 10 拍以等待状态信号更新完毕
                        if ( fifo_dly_cnt == 4'd10 )
                        begin
                            fifo_rd_en <= 1'b1;        //控制写使能信号
                            fifo_dly_cnt <= 4'b0;
                            state <= RD_OK;
                        end
                        else
                            fifo_dly_cnt <= fifo_dly_cnt + 1;
                    end
                
                RD_OK:                          //等一拍让读出数据稳定，
                begin
                    fifo_rd_en <= 1'b0;
                    state <= RD_FIFO_READY;
                end

                EMPTY_256:
                begin
                    fifo_rd_en <= 1'b0;
                    state <= EMPTY_256;
                end

                default:
                begin
                    if ( count < 256 )
                    begin
                        state <= IDLE;
                    end
                    else state <= FULL_256;
                end 
            endcase
    end



    //instantiation define
    uart_rx        u_uart_rx            (
    .sys_clk                            ( sys_clk                  ),
    .sys_rst_n                          ( sys_rst_n                ),
    .uart_rxd                           ( uart_txd                 ),      //tx的io口接到发送给rx的io口（自发自收）

    .uart_dout                          ( uart_dout                ),
    .uart_done                          ( uart_done                )
);
    // 串口发送模块
    uart_tx        u_uart_tx            (
    .sys_clk                            ( sys_clk             ),
    .sys_rst_n                          ( sys_rst_n           ),
    .uart_en                            ( data_ok             ),
    .uart_din                           ( uart_din            ),

    .uart_tx_busy                       ( uart_tx_busy        ),
    .uart_txd                           ( uart_txd            )
);
    // 256位8bit数据生成模块
    send_256_8bit  u_send_256_8bit      (
    .sys_clk                            ( sys_clk                  ),
    .sys_rst_n                          ( sys_rst_n                ),
    .en_send                            ( en_send                  ),

    .data_ok                            ( data_ok                  ),
    .data_8bit                          ( data_8bit                )
);  


    // FIFO_ip例化
    //读写时钟一致
    fifo_256_8bit  u_fifo_256_8bit      (
    .wr_clk                             ( sys_clk                  ),                // input wire wr_clk
    .rd_clk                             ( sys_clk                  ),                // input wire rd_clk
    .din                                ( fifo_wr_data             ),                      // input wire [7 : 0] din
    .wr_en                              ( fifo_wr_en               ),                  // input wire wr_en
    .rd_en                              ( fifo_rd_en               ),                  // input wire rd_en
    .dout                               ( fifo_rd_data             ),                    // output wire [7 : 0] dout
    .full                               ( full                     ),                    // output wire full
    .almost_full                        ( almost_full              ),      // output wire almost_full
    .empty                              ( empty                    ),                  // output wire empty
    .almost_empty                       ( almost_empty             ),    // output wire almost_empty
    .rd_data_count                      ( rd_data_count            ),  // output wire [7 : 0] rd_data_count
    .wr_data_count                      ( wr_data_count            )  // output wire [7 : 0] wr_data_count
);

//     fifo_wr        u_fifo_wr    (
//     .sys_clk                    ( sys_clk                     ),
//     .sys_rst_n                  ( sys_rst_n                   ),
//     .almost_empty               ( almost_empty                ),
//     .almost_full                ( almost_full                 ),
//     .ready_wr_data              ( ready_wr_data               ),

//     .fifo_wr_ok                 ( fifo_wr_ok                  ),
//     .fifo_wr_en                 ( fifo_wr_en                  ),
//     .fifo_wr_data               ( fifo_wr_data                )
// );

//     fifo_rd        u_fifo_rd    (
//     .sys_clk                    ( sys_clk                     ),
//     .sys_rst_n                  ( sys_rst_n                   ),
//     .almost_empty               ( almost_empty                ),
//     .almost_full                ( almost_full                 ),
    
//     .fifo_rd_empty              ( fifo_rd_empty               ),
//     .fifo_rd_en                 ( fifo_rd_en                  )
// );




    // always @( posedge sys_clk ) 
    // begin
    //     if (  conut < 20 * BPS_CNT  )
    //     begin
    //         conut <= conut + 1;
    //         uart_en <= 0;
    //     end
           
    //     else if ( conut == 20 * BPS_CNT )
    //     begin
    //         // uart_din <= uart_din + 1;
    //         uart_en <= 1;
    //         conut <= 16'b0;
    //     end
    // end
    
    (* mark_debug = "true" *) reg                      uart_rxd_ila;                //UART接收端
    (* mark_debug = "true" *) reg                      uart_txd_ila;                //UART发送端
    // (* mark_debug = "true" *) reg [7:0]                uart_dout_ila;
    // (* mark_debug = "true" *) reg                      uart_done_ila;
    (* mark_debug = "true" *) reg                      data_ok_ila;
    (* mark_debug = "true" *) reg                      uart_tx_busy_ila;
    (* mark_debug = "true" *) reg[5:0]                 state_ila;


    always @(posedge sys_clk) begin
        uart_rxd_ila <= uart_rxd;
        uart_txd_ila <= uart_txd;
        // uart_dout_ila <= uart_dout;
        // uart_done_ila <= uart_done;
        state_ila <= state;
        data_ok_ila <= data_ok;
        uart_tx_busy_ila <= uart_tx_busy;
    end

endmodule


