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
    parameter           CLK_FREQ    = 50000000;            //时钟频率
    parameter           UART_BPS    = 115200;                //波特率
    localparam          BPS_CNT     = CLK_FREQ/UART_BPS;   //分频系数

    parameter           IDLE        = 6'b000001,
                        GET_DATA    = 6'b000010,
                        BUF_DATA    = 6'b000100,
                        TX_DATA     = 6'b001000,
                        TX_OK       = 6'b010000,
                        FULL_256    = 6'b100000;

    //reg define
    reg                 en_send;                //数据生成模块的使能信号 
    reg [5:0]           state = IDLE;
    reg [7:0]           uart_din;               //TX发送的数据
    
    reg [16:0]          count;                  //计数

    //wire define

        //uart
    wire                uart_done;
    wire                send_open_signal;       //开启数据生成模块的指示信号                     
    wire                uart_tx_busy;           //tx通道状态
    wire                data_ok;
    wire [7:0]          data_8bit;              //接收到的数据

        //fifo
    wire fifo_wr_en, fifo_rd_en;
    wire full, empty;
    wire almost_full, almost_empty;
    wire fifo_wr_ok;
    wire fifo_wr_data;
    wire fifo_rd_data;
    

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
            en_send <= 1'b0;
            uart_din <= 8'b0;
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
                    state <= TX_DATA;
                // 4、传输过程与busy同步，比busy慢一拍结束
                TX_DATA:
                begin
                    if ( uart_tx_busy ) //没发完
                    begin    
                        state <= TX_DATA;
                    end
                    else                //发完了,接着去GET
                        state <= TX_OK;
                end
                // 5、传输结束状态，根据计数值选择是继续获取数据还是结束获取数据
                TX_OK:
                begin
                    if ( count < 256 )
                    begin
                        en_send <= 1'b1;
                        state <= GET_DATA;
                    end
                    else
                    begin
                        en_send <= 1'b0;
                        state <= FULL_256;   
                    end       
                end
                // 6、当256位8bit数据发送完毕后，进入此状态，不再接收与发送新的数据
                FULL_256:
                begin
                    en_send <= 0;
                    uart_din <= 8'b0;
                    state <= FULL_256;
                end
                default:
                begin
                    if ( count < 255 )
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
    .uart_rxd                           ( uart_rxd                 ),      //tx的io口接到发送给rx的io口（自发自收）

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
    .wr_en                              ( wr_en                    ),                  // input wire wr_en
    .rd_en                              ( rd_en                    ),                  // input wire rd_en
    .dout                               ( fifo_rd_data             ),                    // output wire [7 : 0] dout
    .full                               ( full                     ),                    // output wire full
    .almost_full                        ( almost_full              ),      // output wire almost_full
    .empty                              ( empty                    ),                  // output wire empty
    .almost_empty                       ( almost_empty             ),    // output wire almost_empty
    .rd_data_count                      ( rd_data_count            ),  // output wire [7 : 0] rd_data_count
    .wr_data_count                      ( wr_data_count            )  // output wire [7 : 0] wr_data_count
);

    fifo_wr        u_fifo_wr    (
    .sys_clk                    ( sys_clk                     ),
    .sys_rst_n                  ( sys_rst_n                   ),
    .almost_empty               ( almost_empty                ),
    .almost_full                ( almost_full                 ),
    .ready_wr_data              ( ready_wr_data               ),

    .fifo_wr_ok                 ( fifo_wr_ok                  ),
    .fifo_wr_en                 ( fifo_wr_en                  ),
    .fifo_wr_data               ( fifo_wr_data                )
);

    fifo_rd        u_fifo_rd    (
    .sys_clk                    ( sys_clk                     ),
    .sys_rst_n                  ( sys_rst_n                   ),
    .almost_empty               ( almost_empty                ),
    .almost_full                ( almost_full                 ),
                  
    .fifo_rd_en                 ( fifo_rd_en                  )
);




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


