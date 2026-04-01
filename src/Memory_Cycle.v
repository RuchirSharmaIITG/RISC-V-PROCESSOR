

module memory_cycle(clk, rst, RegWriteM, MemWriteM, ResultSrcM, RD_M, PCPlus4M, WriteDataM, 
    ALU_ResultM, RegWriteW, ResultSrcW, RD_W, PCPlus4W, ALU_ResultW, ReadDataW,
    uart_tx, uart_rx);
    
    // Declaration of I/Os
    input clk, rst, RegWriteM, MemWriteM, ResultSrcM;
    input [4:0] RD_M; 
    input [31:0] PCPlus4M, WriteDataM, ALU_ResultM;
    input uart_rx;

    output RegWriteW, ResultSrcW, uart_tx; 
    output [4:0] RD_W;
    output [31:0] PCPlus4W, ALU_ResultW, ReadDataW;

    // Declaration of Interim Wires
    wire [31:0] ReadDataM, ReadDataM_dmem;
    wire tx_ready, rx_valid;
    wire [7:0] rx_data;

    wire is_uart_data = (ALU_ResultM == 32'h10000000);
    wire is_uart_stat = (ALU_ResultM == 32'h10000004);

    wire uart_we = is_uart_data & MemWriteM;
    wire dmem_we = MemWriteM & ~is_uart_data & ~is_uart_stat;

    assign ReadDataM = is_uart_data ? {24'd0, rx_data} : 
                       is_uart_stat ? {30'd0, rx_valid, tx_ready} : 
                       ReadDataM_dmem;

    // Declaration of Interim Registers
    reg RegWriteM_r, ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PCPlus4M_r, ALU_ResultM_r, ReadDataM_r;

    // Declaration of Module Initiation
    UART_TX tx_inst(
        .clk(clk), .rst(rst),
        .start(uart_we),
        .data(WriteDataM[7:0]),
        .tx(uart_tx),
        .ready(tx_ready)
    );

    UART_RX rx_inst(
        .clk(clk), .rst(rst),
        .rx(uart_rx),
        .data(rx_data),
        .valid(rx_valid)
    );

    Data_Memory dmem (
                        .clk(clk),
                        .rst(rst),
                        .WE(dmem_we),
                        .WD(WriteDataM),
                        .A(ALU_ResultM),
                        .RD(ReadDataM_dmem)
                    );

    // Memory Stage Register Logic
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteM_r <= 1'b0; 
            ResultSrcM_r <= 1'b0;
            RD_M_r <= 5'h00;
            PCPlus4M_r <= 32'h00000000; 
            ALU_ResultM_r <= 32'h00000000; 
            ReadDataM_r <= 32'h00000000;
        end
        else begin
            RegWriteM_r <= RegWriteM; 
            ResultSrcM_r <= ResultSrcM;
            RD_M_r <= RD_M;
            PCPlus4M_r <= PCPlus4M; 
            ALU_ResultM_r <= ALU_ResultM; 
            ReadDataM_r <= ReadDataM;
        end
    end 

    // Declaration of output assignments
    assign RegWriteW = RegWriteM_r;
    assign ResultSrcW = ResultSrcM_r;
    assign RD_W = RD_M_r;
    assign PCPlus4W = PCPlus4M_r;
    assign ALU_ResultW = ALU_ResultM_r;
    assign ReadDataW = ReadDataM_r;

endmodule
