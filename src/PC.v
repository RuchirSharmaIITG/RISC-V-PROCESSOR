
module PC_Module(clk,rst,EN,PC,PC_Next);
    input clk,rst,EN;
    input [31:0]PC_Next;
    output [31:0]PC;
    reg [31:0]PC;

    always @(posedge clk)
    begin
        if(rst == 1'b0)
            PC <= {32{1'b0}};
        else if(EN)
            PC <= PC_Next;
    end
endmodule