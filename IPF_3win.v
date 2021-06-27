module IPF ( clk, reset, in_en, din, ipf_type, ipf_band_pos, ipf_wo_class, ipf_offset, lcu_x, lcu_y, lcu_size, busy, out_en, dout, dout_addr, finish);
//===========IO====================
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
//===========IO====================

reg [7:0] din_po, din_wo, dout_nxt, din_band, din_po_temp;
reg signed [8:0] din_po_add, din_wo_add;
reg [3:0] off_po;
reg [3:0] posi_a,posi_c;
reg [4:0] low_bound, up_bound;
reg [3:0] off_wo;
reg [7:0] a,b,c, c_new;
reg [8:0] mid;

reg [13:0] dout_addr_nxt;
reg [1:0] seq, seq_nxt;
reg last_row, last_row_nxt;
reg last_pix, last_pix_nxt;
reg [2:0] last_x, last_y;
reg finish_nxt;
wire end_lcu;
wire end_img;

//============= extension ===================
reg [7:0] window0[0:15]; //window size = 16, 32, 64
reg [7:0] window1[0:15];
reg [7:0] window2[0:15];
reg [7:0] window0_nxt[0:15];
reg [7:0] window1_nxt[0:15];
reg [7:0] window2_nxt[0:15];
reg [3:0] col, col_nxt; //col length = 16, 32, 64
reg [3:0] row, row_nxt;

assign  end_lcu = (row==4'd15 & col==4'd15); //col, row = 16, 32, 64
assign  end_img = (lcu_y == 3'd7 & lcu_x==3'd7 & col==4'd15 & row==4'd15); //lcu_x,y = 8, 4, 2
//============= extension ====================

//============= FSM ===================
reg [3:0] state, nxt_state;
parameter state_idle = 0;
parameter state_off = 1;
parameter state_po = 2;
parameter state_in_0 = 3;
parameter state_wo_0 = 4;
parameter state_last_pix = 5;
parameter state_in_1 = 6;
parameter state_wo_1 = 7;
parameter state_last_row = 8;
parameter state_wait = 9;
parameter state_finish = 10;
//============= FSM ===================

//============= nxt_state ===================
always @(*)begin
    //default
    busy = 1;
    out_en = 0;
    nxt_state = state_wait;
    case(state)
        state_idle:begin
            busy = 0;
            out_en = 0;
            nxt_state = state_wait;
        end
        state_off:begin
            busy = 0;
            out_en = 1;
            if (end_lcu)nxt_state = state_wait;
            else nxt_state = state;
        end
        state_po:begin
            busy = 0;
            out_en = 1;
            if (end_lcu)nxt_state = state_wait;
            else nxt_state = state;
        end
        state_in_0:begin
            busy = 0;
            out_en = 1;
            if (col>=4'd1) nxt_state = state_wo_0;
            else nxt_state = state;
        end
        state_wo_0:begin
            busy = 0;
            out_en = 1;
            if (end_lcu & !last_pix)begin
                nxt_state = state_last_pix;
            end
            else if (end_lcu)begin
                nxt_state = state_wait;
            end
            else begin
                nxt_state = state;
            end
        end
        state_last_pix:begin
            busy = 1;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)nxt_state = state_wait;
            else nxt_state = state;
        end

        state_in_1:begin
            busy = 0;
            out_en = 0;
            if (row==4'd0 & col==4'd15) nxt_state = state_wo_1;
            else nxt_state = state;
        end

        state_wo_1:begin
            busy = 0;
            out_en = 1;
            if (end_lcu & !last_row)begin
                nxt_state = state_last_row;
            end
            else if (end_lcu)begin
                nxt_state = state_wait;
            end
            else begin
                nxt_state = state;
            end
        end

        state_last_row:begin
            busy = 1;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)nxt_state = state_wait;
            else nxt_state = state;
        end

        state_wait:begin
            busy = 1;
            out_en = 0;
            if (ipf_type==2'd0) nxt_state = state_off;
            else if (ipf_type==2'd1) nxt_state = state_po;
            else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_in_0; //需要等資料
            else if (ipf_type==2'd2 & ipf_wo_class==1'b1) nxt_state = state_in_1; //需要等資料
            else nxt_state = state;
        end
        state_finish:begin
            busy = 1;
            out_en = 1;
            nxt_state = state;
        end

    endcase
end


//============= comb ========================
integer i ;
always @(*)begin
    col_nxt = col + 1;
    row_nxt = (row!=4'd15 & col==4'd15)? row+1:row;
    dout_nxt = dout;
    dout_addr_nxt = dout_addr;
    seq_nxt = seq;
    last_row_nxt=0;
    last_pix_nxt=0;
    finish_nxt = 0;

    last_x = (end_img)? lcu_x : lcu_x - 1;
    last_y = (lcu_x==3'd0)? lcu_y-1 : lcu_y;

    for (i = 0 ; i<16; i=i+1)begin
        window0_nxt[i]=window0[i];
        window1_nxt[i]=window1[i];
        window2_nxt[i]=window2[i];
    end

    case(state)
        state_idle:begin
            col_nxt = col;
            row_nxt = row;
        end
        state_off:begin
            dout_nxt = din;
            dout_addr_nxt = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        state_po:begin
            dout_nxt = din_po;
            dout_addr_nxt = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        state_in_0:begin
            //out_en = (col==4'd1)? 1:0; //在col==1的時候剛好en=1剛好讓col=0的位置可以輸出
            window0_nxt[col] = din;
            dout_nxt = din;
            dout_addr_nxt = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end
        state_wo_0:begin
            window0_nxt[col] = din;
            if (col>= 4'd2 & col<=4'd15)begin
                dout_nxt = din_wo;
                dout_addr_nxt = (row<<7) + (lcu_y<<11) + (lcu_x<<4) + col-1;
            end
            else begin
                dout_nxt = window0[posi_c];
                dout_addr_nxt = (col==4'd0)? ((row-1)<<7) + (lcu_y<<11) + (lcu_x<<4) + 4'd15 : (row<<7) + (lcu_y<<11) + (lcu_x<<4) + 4'd0; 
            end
            if (row==4'd15 & col==4'd15) begin
                row_nxt = row; 
                col_nxt=col; 
            end
        end
        state_last_pix:begin
            last_pix_nxt = (row==4'd15 & col==4'd15);
            dout_nxt = (seq==2'd0)? window0[15] : (seq==2'd1)? window1[15] : window2[15];
            dout_addr_nxt = (row<<7) + (last_y<<11) + (last_x<<4) + col;
        end
        state_in_1:begin
            window0_nxt[col] = din;
            seq_nxt = 2'd1;
        end
        state_wo_1:begin
            if (seq==2'd0)begin
                window0_nxt[col] = din;
                seq_nxt = (row!=4'd15 & col==4'd15)? 2'd1:seq;
            end
            else if (seq==2'd1)begin
                window1_nxt[col] = din;
                seq_nxt = (row!=4'd15 & col==4'd15)? 2'd2:seq;
            end
            else begin //(seq==2'd2)
                window2_nxt[col] = din;
                seq_nxt = (row!=4'd15 & col==4'd15)? 2'd0:seq;
            end

            dout_nxt = (row>=4'd2)? din_wo : window0[col];
            dout_addr_nxt = ((row-1)<<7) + (lcu_y<<11) + (lcu_x<<4) + col;
        end

        state_last_row:begin
            last_row_nxt = (row==4'd15 & col==4'd15);
            dout_nxt = (seq==2'd0)? window0[col] : (seq==2'd1)? window1[col] : window2[col];
            dout_addr_nxt = (row<<7) + (last_y<<11) + (last_x<<4) + col;
        end

        state_wait:begin
            col_nxt = 0;
            row_nxt = 0;
        end

        state_finish:begin
            finish_nxt = 1;
        end
    endcase

end


//============= operation ========================
always @(*)begin
    //============== PO ================
    din_band = din>>3;
    low_bound = ipf_band_pos - 1;
    up_bound = ipf_band_pos + 1;
    off_po = ((din_band[1:0])==2'd0)? ipf_offset[15:12] :
             ((din_band[1:0])==2'd1)? ipf_offset[11:8] :
             ((din_band[1:0])==2'd2)? ipf_offset[7:4] : ipf_offset[3:0];
    din_po_add = $signed(din) + $signed(off_po);
    //判斷是否超過255或小於0
    din_po_temp = (din[7] & !din_po_add[8])? 8'd255 : (!din[7] & din_po_add[8])? 8'd0 : din_po_add[7:0]; 
    //因為bound可能overflow，故用or
    din_po = (din_band == low_bound | din_band == up_bound | din_band == ipf_band_pos)? din : din_po_temp; 

    //============== WO ================
    posi_a = col-2;
    posi_c = col-1;
    case (ipf_wo_class)
        1'b0:begin
            a = window0[posi_a];
            c = window0[posi_c];
            b = din;
        end
        1'b1:begin
            case(seq)
                2'd0:begin a = window1[col]; c = window2[col]; b = din;end
                2'd1:begin a = window2[col]; c = window0[col]; b = din;end
                2'd2:begin a = window0[col]; c = window1[col]; b = din;end
                default: begin a = window1[col]; c = window2[col]; b = din; end
            endcase
        end
    endcase

    mid = (a+b)>>1;
    if (c<a & c<b)begin //Category 0
        off_wo = ipf_offset[15:12];
    end
    else if (c < mid & (c>=a | c>=b))begin //Category 1
        off_wo = ipf_offset[11:8];
    end
    else if (c > mid & (c<=a | c<=b))begin //Category 2
        off_wo = ipf_offset[7:4];
    end
    else if (c > a & c>b)begin //Category 3
        off_wo = ipf_offset[3:0];
    end
    else begin
        off_wo = 0;
    end
    din_wo_add = $signed(c)+$signed(off_wo);
    //判斷是否超過255或小於0
    //寫錯?
    din_wo = (c[7] & !din_wo_add[8])? 8'd255 : (!c[7] & din_wo_add[8])? 8'd0 : din_wo_add[7:0]; 
end



always @(posedge clk or posedge reset)begin
    if (reset)begin
        for (i = 0 ; i<16; i=i+1)begin
            window0[i]<= 0;
            window1[i]<= 0;
            window2[i]<= 0;
        end
        col <= 0;
        row <= 0;
        seq <= 0;
        last_row <= 0;
        last_pix <= 0;
        dout <= 0;
        dout_addr <= 0;
        finish <= 0;
        state <= state_idle;
    end
    else begin
        for (i = 0 ; i<16; i=i+1)begin
            window0[i]<=window0_nxt[i];
            window1[i]<=window1_nxt[i];
            window2[i]<=window2_nxt[i];
        end
        col <= col_nxt;
        row <= row_nxt;
        seq <= seq_nxt; 
        last_row <= last_row_nxt;
        last_pix <= last_pix_nxt;
        dout <= dout_nxt;
        dout_addr <= dout_addr_nxt;
        finish <= finish_nxt;
        state <= nxt_state;
    end
end

endmodule

