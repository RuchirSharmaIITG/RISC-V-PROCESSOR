`timescale 1ns/1ps

module axi4_lite_master (
    input  wire        clk,
    input  wire        reset,

    // CPU Interface
    input  wire        req_enable,
    input  wire        req_write,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output wire        axi_busy,
    output reg  [31:0] axi_rdata,

    // AXI4-Lite Master Interface
    output reg  [31:0] m_axi_awaddr,
    output wire [2:0]  m_axi_awprot,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    output reg  [31:0] m_axi_araddr,
    output wire [2:0]  m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata_in,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;

    localparam STATE_IDLE     = 4'd0;
    localparam STATE_WADDR    = 4'd1;
    localparam STATE_WDATA    = 4'd2;
    localparam STATE_BRESP    = 4'd3;
    localparam STATE_RADDR    = 4'd4;
    localparam STATE_RDATA    = 4'd5;
    localparam STATE_DONE     = 4'd6;
    localparam STATE_COOLDOWN = 4'd7; 
    localparam STATE_WAIT     = 4'd8; 

    reg [3:0]  state;
    reg [31:0] last_triggered_addr;
    reg        last_triggered_write;
    reg        aw_done_int, w_done_int;

    // axi_busy logic: 
    // High during active transaction states (IDLE thru DONE).
    // Drops to 0 in STATE_COOLDOWN to allow the pipeline to capture the result.
    // If a new request arrives while in IDLE, assert busy combinationally to stall the pipeline
    // before the new memory operation escapes.
    assign axi_busy = ((state != STATE_IDLE) && (state != STATE_COOLDOWN)) || (state == STATE_IDLE && req_enable);

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state         <= STATE_IDLE;
            m_axi_awaddr  <= 0;
            m_axi_awvalid <= 0;
            m_axi_wdata   <= 0;
            m_axi_wstrb   <= 0;
            m_axi_wvalid  <= 0;
            m_axi_bready  <= 0;
            m_axi_araddr  <= 0;
            m_axi_arvalid <= 0;
            m_axi_rready  <= 0;
            axi_rdata     <= 32'h0;
            aw_done_int   <= 0;
            w_done_int    <= 0;
            last_triggered_addr  <= 32'hFFFFFFFF;
            last_triggered_write <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (req_enable) begin
                        last_triggered_addr  <= req_addr;
                        last_triggered_write <= req_write;
                        
                        if (req_write) begin
                            state         <= STATE_WADDR;
                            m_axi_awaddr  <= req_addr;
                            m_axi_awvalid <= 1;
                            m_axi_wdata   <= req_wdata;
                            m_axi_wstrb   <= req_wstrb;
                            m_axi_wvalid  <= 1;
                            aw_done_int   <= 0;
                            w_done_int    <= 0;
                        end else begin
                            state         <= STATE_RADDR;
                            m_axi_araddr  <= req_addr;
                            m_axi_arvalid <= 1;
                        end
                    end
                end

                STATE_WADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 0;
                        aw_done_int <= 1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 0;
                        w_done_int <= 1;
                    end
                    
                    if ((aw_done_int || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done_int  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_awvalid <= 0;
                        m_axi_wvalid  <= 0;
                        state         <= STATE_BRESP;
                        m_axi_bready  <= 1;
                    end
                end

                STATE_BRESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 0;
                        state        <= STATE_DONE;
                    end
                end

                STATE_RADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 0;
                        state         <= STATE_RDATA;
                    end
                end

                STATE_RDATA: begin
                    m_axi_rready <= 1;
                    if (m_axi_rvalid && m_axi_rready) begin
                        axi_rdata    <= m_axi_rdata_in;
                        m_axi_rready <= 0;
                        state        <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    // Busy is still 1 here. Pipeline is stalled.
                    state <= STATE_COOLDOWN;
                end

                STATE_COOLDOWN: begin
                    // axi_busy is 0 here. Pipeline advances at the end of this cycle.
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
