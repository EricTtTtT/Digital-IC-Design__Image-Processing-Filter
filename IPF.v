module IPF ( clk, reset, in_en, din, ipf_type, ipf_band_pos, ipf_wo_class, ipf_offset, lcu_x, lcu_y, lcu_size, busy, out_en, dout, dout_addr, finish);
input   clk;
input   reset;
input   in_en;
input   [7:0]  din;
input   [1:0]  ipf_type;
input   [4:0]  ipf_band_pos;
input          ipf_wo_class;
input   [15:0] ipf_offset;
input   [2:0]  lcu_x;
input   [2:0]  lcu_y;
input   [1:0]  lcu_size;
output reg busy;
output reg finish;
output reg out_en;
output reg [7:0] dout;
output reg [13:0] dout_addr;

//============ reg/wire declaration ===================
    parameter LCU_SIZE = 16;    // TODO: parameterized
    parameter logSIZE = 4;

    reg [7:0] din_po, din_wo, din_band, din_po_temp;
    reg signed [8:0] din_po_add, din_wo_add;
    reg [3:0] offset_po;
    reg [3:0] posi_a, posi_c;
    reg [4:0] low_bound, up_bound;
    reg [3:0] offset_wo;
    reg [7:0] a, b, c, c_new;
    reg [8:0] mid;

    // flip-flops
    reg [7:0] dout_buffer;
    reg [13:0] dout_addr_buffer;
    reg seq, seq_nxt;
    reg last_row, last_row_nxt;
    reg last_pix, last_pix_nxt;
    reg [2:0] last_x, last_y;
    reg finish_nxt;
    wire end_lcu;
    wire end_img;

    //============ extension ===================
    reg [7:0] window0 [0:LCU_SIZE-1]; //window size = 16, 32, 64
    reg [7:0] window1 [0:LCU_SIZE-1];
    reg [7:0] window0_nxt [0:LCU_SIZE-1];
    reg [7:0] window1_nxt [0:LCU_SIZE-1];
    reg [logSIZE-1: 0] col, col_nxt; // TODO: use 5 bits and detect col[4] when finish
    reg [logSIZE-1: 0] row, row_nxt;

    wire [logSIZE:0] col_a1, row_a1;

    assign col_a1 = col + 1;
    assign row_a1 = row + 1;
    assign end_lcu = (row_a1[logSIZE] & col_a1[logSIZE]);
    assign end_img = (lcu_y == 3'd7 & lcu_x==3'd7 & col_a1[logSIZE] & row_a1[logSIZE]); //lcu_x,y = 8, 4, 2
    //============ extension ====================

    //============ FSM ===================
    reg [3:0] state, state_nxt;
    parameter IDLE = 0;
    parameter OFF = 1;
    parameter PO = 2;
    parameter WO_IN0 = 3;
    parameter WO_0 = 4;
    parameter state_last_pix = 5;
    parameter WO_IN1 = 6;
    parameter WO_1 = 7;
    parameter state_last_row = 8;
    parameter WAIT = 9;
    parameter FINISH = 10;

//============ Finite State Machine ===================
always @(*) begin
    case(state)
        IDLE: begin
            busy = 0;
            out_en = 0;
            state_nxt = WAIT;
        end
        OFF: begin
            busy = 0;
            out_en = 1;
            if (end_lcu) state_nxt = WAIT;
            else state_nxt = state;
        end
        PO: begin     // TODO: merge with OFF
            busy = 0;
            out_en = 1;
            if (end_lcu) state_nxt = WAIT;
            else state_nxt = state;
        end
        WO_IN0: begin
            busy = 0;
            out_en = 1;
            if (col>=4'd1) state_nxt = WO_0;
            else state_nxt = state;
        end
        WO_0: begin
            busy = 0;
            out_en = 1;
            if (end_lcu & !last_pix) begin
                state_nxt = state_last_pix;
            end
            else if (end_lcu) begin
                state_nxt = WAIT;
            end
            else begin
                state_nxt = state;
            end
        end
        state_last_pix: begin   // TODO: merge with WO
            busy = 1;
            out_en = 1;
            if (end_img) state_nxt = FINISH;
            else if (end_lcu) state_nxt = WAIT;
            else state_nxt = state;
        end
        WO_IN1: begin
            busy = 0;
            out_en = 0;
            if (row==4'd0 & col_a1[logSIZE]) state_nxt = WO_1;
            else state_nxt = state;
        end
        WO_1: begin
            busy = 0;
            out_en = 1;
            if (end_lcu & !last_row) begin
                state_nxt = state_last_row;
            end
            else if (end_lcu) begin
                state_nxt = WAIT;
            end
            else begin
                state_nxt = state;
            end
        end
        state_last_row: begin   // TODO: merge with WO
            busy = 1;
            out_en = 1;
            if (end_img) state_nxt = FINISH;
            else if (end_lcu) state_nxt = WAIT;
            else state_nxt = state;
        end
        WAIT: begin // TODO: merge with IDLE
            busy = 1;
            out_en = 0;
            case(ipf_type)
                2'd0: state_nxt = OFF;
                2'd1: state_nxt = PO;
                2'd2: state_nxt = ipf_wo_class? WO_IN1 : WO_IN0;
                default: state_nxt = state;
            endcase
        end
        FINISH: begin   // TODO: merge with IDLE
            busy = 1;
            out_en = 1;
            state_nxt = state;
        end
        default: begin
            busy = 1;
            out_en = 0;
            state_nxt = WAIT;
        end
    endcase
end


//============ Combinatinoal Circuit ==================
integer i ;
always @(*) begin
    col_nxt = col_a1[logSIZE-1:0];
    row_nxt = (row!=4'd15 & col_a1[logSIZE])? row_a1[logSIZE-1:0] : row;
    dout_buffer = dout;
    dout_addr_buffer = dout_addr;
    seq_nxt = seq;
    last_row_nxt=0;
    last_pix_nxt=0;
    finish_nxt = 0;

    last_x = (end_img)? lcu_x : lcu_x - 1;
    last_y = (lcu_x==3'd0)? lcu_y-1 : lcu_y;

    for (i = 0 ; i<LCU_SIZE; i=i+1) begin
        window0_nxt[i]=window0[i];
        window1_nxt[i]=window1[i];
    end

    case(state)
        IDLE: begin
            col_nxt = col;
            row_nxt = row;
        end
        OFF: begin
            dout_buffer = din;
            dout_addr_buffer = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        PO: begin
            dout_buffer = din_po;
            dout_addr_buffer = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        WO_IN0: begin
            //out_en = (col==4'd1)? 1:0; //在col==1的時候剛好en=1剛好讓col=0的位置可以輸出
            window0_nxt[col] = din;
            dout_buffer = din;
            dout_addr_buffer = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        WO_0: begin
            window0_nxt[col] = din;
            if (col>= 4'd2 & col<=4'd15) begin
                dout_buffer = din_wo;
                dout_addr_buffer = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col-1;
            end
            else begin
                dout_buffer = window0[posi_c];
                dout_addr_buffer = (col==4'd0)? ((row-1)<<7) + (lcu_y<<11) + (lcu_x<<4) + 4'd15 : (row<<7) + (lcu_y<<11) + (lcu_x<<4) + 4'd0; 
            end
            if (row_a1[logSIZE] & col_a1[logSIZE]) begin
                row_nxt = row; 
                col_nxt=col; 
            end
        end
        state_last_pix: begin
            last_pix_nxt = (row_a1[logSIZE] & col_a1[logSIZE]);
            dout_buffer = window0[15] ;
            dout_addr_buffer = (row<<7) + (last_y<<11) + (last_x<<4) + col;
        end
        WO_IN1: begin
            window0_nxt[col] = din;
            seq_nxt = 1'b1;
        end
        WO_1: begin
            if (seq==1'b0) begin
                window0_nxt[col] = din;
                seq_nxt = (row!=4'd15 & col_a1[logSIZE])? 1'b1:seq;  // TODO: detect one bit!
            end
            else if (seq==1'b1) begin
                window1_nxt[col] = din;
                seq_nxt = (row!=4'd15 & col_a1[logSIZE])? 1'b0:seq;
            end
            dout_buffer = (row>=4'd2)? din_wo : window0[col];
            dout_addr_buffer = ((row-1)<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end

        state_last_row: begin
            last_row_nxt = (row_a1[logSIZE] & col_a1[logSIZE]);
            dout_buffer = (seq==1'b0)? window0[col] :  window1[col];
            dout_addr_buffer = (row<<7) + (last_y<<11) + (last_x<<4) + col;
        end

        WAIT: begin
            col_nxt = 0;
            row_nxt = 0;
        end

        FINISH: begin
            finish_nxt = 1;
        end
    endcase

end


//============ Operation ==============================
always @(*) begin
    //============= PO ================
    din_band = din >> 3;
    low_bound = ipf_band_pos - 1;
    up_bound = ipf_band_pos + 1;
    case (din_band[1:0])
        2'd0: offset_po = ipf_offset[15:12];
        2'd1: offset_po = ipf_offset[11:8];
        2'd2: offset_po = ipf_offset[7:4];
        2'd3: offset_po = ipf_offset[3:0];
    endcase
    din_po_add = $signed(din) + $signed(offset_po);

    // range constraint: 0-255
    case ({din[7], din_po_add[8]})
        2'b10: din_po_temp = 8'd255;
        2'b01: din_po_temp = 8'd0;
        default: din_po_temp = din_po_add[7:0];
    endcase
    // bound overflow is possible!! 
    din_po = (din_band == low_bound | din_band == up_bound | din_band == ipf_band_pos)? din : din_po_temp; 

    //============= WO ================
    posi_a = col-2;
    posi_c = col-1;
    case (ipf_wo_class)
        1'b0: begin
            a = window0[posi_a];
            c = window0[posi_c];
            b = din;
        end
        1'b1: begin
            case(seq)
                1'b0: begin a = window0[col]; c = window1[col]; b = din; end
                1'b1: begin a = window1[col]; c = window0[col]; b = din; end
            endcase
        end
    endcase

    mid = (a+b)>>1;     // TODO: without mid??
 
    case ({c<a, c==a, c<b, c==b, c<mid, c==mid})    // TODO: critical path or not??
        6'b101010: offset_wo = ipf_offset[15:12];   // Category 0
        6'b000000: offset_wo = ipf_offset[3:0];     // Category 3
        6'b001010: offset_wo = ipf_offset[11:8];    // Category 1 (c < mid)
        6'b000110: offset_wo = ipf_offset[11:8];    //   >= min and <= max (8 cases)
        6'b011010: offset_wo = ipf_offset[11:8];
        6'b010110: offset_wo = ipf_offset[11:8];
        6'b100010: offset_wo = ipf_offset[11:8];
        6'b010010: offset_wo = ipf_offset[11:8];
        6'b100110: offset_wo = ipf_offset[11:8];
        6'b010110: offset_wo = ipf_offset[11:8];
        6'b001000: offset_wo = ipf_offset[7:4];     // Category 2 (c > mid)
        6'b000100: offset_wo = ipf_offset[7:4];     //   >= min and <= max (8 cases)
        6'b011000: offset_wo = ipf_offset[7:4];
        6'b010100: offset_wo = ipf_offset[7:4];
        6'b100000: offset_wo = ipf_offset[7:4];
        6'b010000: offset_wo = ipf_offset[7:4];
        6'b100100: offset_wo = ipf_offset[7:4];
        6'b010100: offset_wo = ipf_offset[7:4];
        default: offset_wo = 4'd0;
    endcase
    din_wo_add = $signed(c)+$signed(offset_wo);
    // check overflow (0-255)
    // TODO: wtf?? why use din_po_add is correct and din_wo_add is wrong
    din_wo = (din[7] & !din_po_add[8])? 8'd255 : (!din[7] & din_po_add[8])? 8'd0 : din_wo_add[7:0]; 
end


//============ Sequential Circuit =====================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        for (i = 0 ; i<LCU_SIZE; i=i+1) begin
            window0[i]<= 0;
            window1[i]<= 0;
        end
        col <= 0;
        row <= 0;
        seq <= 0;
        last_row <= 0;
        last_pix <= 0;
        dout <= 0;
        dout_addr <= 0;
        finish <= 0;
        state <= IDLE;
    end
    else begin
        for (i = 0 ; i<LCU_SIZE; i=i+1) begin
            window0[i]<=window0_nxt[i];
            window1[i]<=window1_nxt[i];
        end
        col <= col_nxt;
        row <= row_nxt;
        seq <= seq_nxt; 
        last_row <= last_row_nxt;
        last_pix <= last_pix_nxt;
        dout <= dout_buffer;
        dout_addr <= dout_addr_buffer;
        finish <= finish_nxt;
        state <= state_nxt;
    end
end

endmodule

