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

reg [7:0] din_po, din_wo, dout_nxt, din_po_temp, pix, pix_band;
reg [7:0] din_temp, din_temp_nxt;
reg signed [8:0] din_po_add, din_wo_add;
reg [4:0] low_bound, up_bound;
reg [3:0] off_po;
reg [3:0] off_wo;
reg [3:0] posi_a, posi_c, posi_b;
reg [7:0] a,b,c;
reg [8:0] mid;

reg [2:0] t_lcu_x, t_lcu_x_nxt;
reg [2:0] t_lcu_y, t_lcu_y_nxt;
reg t_ipf_wo_class, t_ipf_wo_class_nxt;
reg [4:0] t_ipf_band_pos, t_ipf_band_pos_nxt;
reg [15:0] t_ipf_offset, t_ipf_offset_nxt;

reg [13:0] dout_addr_nxt;
reg seq, seq_nxt;
reg finish_nxt;
wire end_lcu;
wire end_img;

//============= extension ===================
reg [7:0] window0[0:15]; //window size = 16, 32, 64
reg [7:0] window1[0:15];
reg [7:0] window0_nxt[0:15];
reg [7:0] window1_nxt[0:15];
reg [3:0] col, col_nxt, t_col; //col length = 16, 32, 64
reg [3:0] row, row_nxt, t_row;

assign  end_lcu = (t_row==4'd15 & t_col==4'd15); //col, row = 16, 32, 64
assign  end_img = (!in_en & t_row==4'd15 & t_col==4'd15); //lcu_x,y = 8, 4, 2
//============= extension ====================

//============= FSM ===================
reg [3:0] state, nxt_state;
parameter state_idle = 0;
parameter state_off = 1;
parameter state_po = 2;
parameter state_in = 3;
parameter state_wait = 4;
parameter state_wo_0 = 5;
parameter state_wo_1 = 6;
parameter state_finish = 7;
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
        state_in:begin
            busy = 0;
            out_en = 0;
            if (row==4'd0 & col==4'd15) begin
                if (ipf_type==2'd0) nxt_state = state_off;
                else if (ipf_type==2'd1) nxt_state = state_po;
                else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_wo_0; //需要等資料
                else nxt_state = state_wo_1; //需要等資料
            end
            else nxt_state = state;
        end

        state_wait:begin
            busy = 0;
            out_en = 0;
            nxt_state = state_in;
        end

        state_off:begin
            busy = 0;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)begin
                if (ipf_type==2'd0) nxt_state = state_off;
                else if (ipf_type==2'd1) nxt_state = state_po;
                else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_wo_0;
                else nxt_state = state_wo_1;
            end
            else nxt_state = state;
        end
        state_po:begin
            busy = 0;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)begin
                if (ipf_type==2'd0) nxt_state = state_off;
                else if (ipf_type==2'd1) nxt_state = state_po;
                else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_wo_0;
                else nxt_state = state_wo_1;
            end
            else nxt_state = state;
        end
        state_wo_0:begin
            busy = 0;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)begin
                if (ipf_type==2'd0) nxt_state = state_off;
                else if (ipf_type==2'd1) nxt_state = state_po;
                else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_wo_0;
                else nxt_state = state_wo_1;
            end
            else nxt_state = state;
        end
        state_wo_1:begin
            busy = 0;
            out_en = 1;
            if (end_img) nxt_state = state_finish;
            else if (end_lcu)begin
                if (ipf_type==2'd0) nxt_state = state_off;
                else if (ipf_type==2'd1) nxt_state = state_po;
                else if (ipf_type==2'd2 & ipf_wo_class==1'b0) nxt_state = state_wo_0;
                else nxt_state = state_wo_1;
            end
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
    row_nxt = (col==4'd15)? row+1 : row;
    t_col = col;
    t_row = row - 1;
    dout_nxt = dout;
    dout_addr_nxt = dout_addr;
    seq_nxt = seq;
    finish_nxt = 0;
    t_lcu_x_nxt = (end_lcu)? lcu_x : t_lcu_x;
    t_lcu_y_nxt = (end_lcu)? lcu_y : t_lcu_y;
    t_ipf_wo_class_nxt = (end_lcu)? ipf_wo_class : t_ipf_wo_class;
    t_ipf_band_pos_nxt = (end_lcu)? ipf_band_pos : t_ipf_band_pos;
    t_ipf_offset_nxt = (end_lcu)? ipf_offset : t_ipf_offset;

    for (i = 0 ; i<16; i=i+1)begin
        window0_nxt[i]=window0[i];
        window1_nxt[i]=window1[i];
    end

    din_temp_nxt = din;
    if (seq==1'b0)begin
        window0_nxt[col] = din_temp;
        seq_nxt = (t_col==4'd15)? 1'b1:seq;
    end
    else if (seq==1'b1)begin
        window1_nxt[col] = din_temp;
        seq_nxt = (t_col==4'd15)? 1'b0:seq;
    end

    case(state)
        state_idle:begin
            col_nxt = col;
            row_nxt = row;
        end

        state_wait:begin
            col_nxt = 0;
            row_nxt = 0;
            din_temp_nxt = din;
        end

        state_off:begin
            dout_nxt = (seq==1'b0)? window1[t_col] : window0[t_col];
            dout_addr_nxt = (t_row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + t_col;
        end

        state_po:begin
            dout_nxt = din_po;
            dout_addr_nxt = (t_row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + t_col;
        end

        state_wo_0:begin
            if (t_col==4'd0 | t_col==4'd15)begin
                dout_nxt = (seq==1'b0)? window1[t_col] : window0[t_col];
            end
            else begin
                dout_nxt = din_wo;
            end
            dout_addr_nxt = (t_row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + t_col;
        end
        state_wo_1:begin
            if (t_row==4'd0 | t_row==4'd15)begin
                dout_nxt = (seq==1'b0)? window1[t_col] : window0[t_col];
            end
            else begin
                dout_nxt = din_wo;
            end
            dout_addr_nxt = (t_row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + t_col;
        end
        state_finish:begin
            finish_nxt = 1;
        end
    endcase
end

//============= operation ========================
always @(*)begin
    //============== PO ================
    pix = (seq==1'b0)? window1[t_col] : window0[t_col];
    pix_band = pix>>3;
    low_bound = t_ipf_band_pos - 1;
    up_bound = t_ipf_band_pos + 1;
    off_po = ((pix_band[1:0])==2'd0)? t_ipf_offset[15:12] :
             ((pix_band[1:0])==2'd1)? t_ipf_offset[11:8] :
             ((pix_band[1:0])==2'd2)? t_ipf_offset[7:4] : t_ipf_offset[3:0];
    din_po_add = $signed(pix) + $signed(off_po);
    //判斷是否超過255或小於0
    din_po_temp = (pix[7] & !din_po_add[8])? 8'd255 : (!pix[7] & din_po_add[8])? 8'd0 : din_po_add[7:0]; 
    //因為bound可能overflow，故用or
    din_po = (pix_band == low_bound | pix_band == up_bound | pix_band == t_ipf_band_pos)? pix : din_po_temp; 

    //============== WO ================
    posi_a = t_col-1;
    posi_c = t_col;
    posi_b = t_col+1;
    case (t_ipf_wo_class)
        1'b0:begin
            if (seq==1'b0) begin a = window1[posi_a];c = window1[posi_c];b = window1[posi_b];end
            else begin a = window0[posi_a];c = window0[posi_c];b = window0[posi_b];end
        end
        1'b1:begin
            if (seq==1'b0)begin a = window0[col]; c = window1[col]; b = din_temp;end
            else begin a = window1[col]; c = window0[col]; b = din_temp;end
        end
    endcase

    mid = (a+b)>>1;
    if (c<a & c<b)begin //Category 0
        off_wo = t_ipf_offset[15:12];
    end
    else if (c < mid & (c>=a | c>=b))begin //Category 1
        off_wo = t_ipf_offset[11:8];
    end
    else if (c > mid & (c<=a | c<=b))begin //Category 2
        off_wo = t_ipf_offset[7:4];
    end
    else if (c > a & c>b)begin //Category 3
        off_wo = t_ipf_offset[3:0];
    end
    else begin
        off_wo = 0;
    end
    din_wo_add = $signed(c)+$signed(off_wo);
    //判斷是否超過255或小於0
    din_wo = (c[7] & !din_wo_add[8])? 8'd255 : (!c[7] & din_wo_add[8])? 8'd0 : din_wo_add[7:0]; 
end



always @(posedge clk or posedge reset)begin
    if (reset)begin
        for (i = 0 ; i<16; i=i+1)begin
            window0[i]<= 0;
            window1[i]<= 0;
        end
        row <= 0;
        col <= 0;
        seq <= 0;
        dout <= 0;
        dout_addr <= 0;
        din_temp <= 0;

        t_lcu_x <= 0;
        t_lcu_y <= 0;
        t_ipf_wo_class <= 0;
        t_ipf_band_pos <= 0;
        t_ipf_offset <= 0;

        finish <= 0;
        state <= state_idle;
    end
    else begin
        for (i = 0 ; i<16; i=i+1)begin
            window0[i]<=window0_nxt[i];
            window1[i]<=window1_nxt[i];
        end
        row <= row_nxt;
        col <= col_nxt;
        seq <= seq_nxt;
        dout <= dout_nxt;
        dout_addr <= dout_addr_nxt;
        din_temp <= din_temp_nxt;

        t_lcu_x <= t_lcu_x_nxt;
        t_lcu_y <= t_lcu_y_nxt;
        t_ipf_wo_class <= t_ipf_wo_class_nxt;
        t_ipf_band_pos <= t_ipf_band_pos_nxt;
        t_ipf_offset <= t_ipf_offset_nxt;

        finish <= finish_nxt;
        state <= nxt_state;
    end
end

endmodule