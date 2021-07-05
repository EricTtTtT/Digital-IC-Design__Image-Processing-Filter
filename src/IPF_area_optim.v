module IPF (
    clk, reset,
    in_en, din, ipf_type, ipf_band_pos, ipf_wo_class, ipf_offset,
    lcu_x, lcu_y, lcu_size, busy, out_en, dout, dout_addr, finish
);
//=========== IO ====================
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
    integer i ;
    parameter WIN_SIZE = 64-1;  //15,31,63
    parameter logSIZE = 6-1;    //16=4bit, 31=5bit, 64=6bit

    wire [5:0] end_size;
    assign end_size = (lcu_size==2'b00)? 6'd15 : (lcu_size==2'b01)? 6'd31 : 6'd63;

    //======== data I/O ===============
        reg [7:0] din_po, din_wo, dout_nxt, din_po_temp;
        reg [13:0] dout_addr_nxt;
        reg [7:0] pix, pix_band;
        reg [7:0] pix_pip1, pix_pip2, pix_band_pip1, pix_band_pip2;
        reg [7:0] border;
        reg [7:0] border_pip1, border_pip2;
        reg [7:0] din_buffer, din_buffer_nxt;
        reg signed [9:0] din_po_add, din_wo_add;
        reg [7:0] din_off_pip1, din_off_pip2, din_off_nxt;

    //======== control signals ========
        reg [logSIZE:0] col, col_nxt, col_pip1, col_pip2; //col length = 16, 32, 64
        reg [logSIZE:0] row_in, row_in_nxt,row, row_pip1, row_pip2;
        reg [logSIZE:0] a_col, b_col;
        reg seq, seq_nxt;
        reg finish_nxt;

        wire col_end, row_pip2_end, col_pip2_end;
        wire end_lcu, end_lcu_pip2;
        wire end_img;

        reg [2:0] t_lcu_x, t_lcu_x_nxt, t_lcu_x_pip1, t_lcu_x_pip2;
        reg [2:0] t_lcu_y, t_lcu_y_nxt, t_lcu_y_pip1, t_lcu_y_pip2;
        reg t_ipf_wo_class, t_ipf_wo_class_nxt;
        reg [4:0] t_ipf_band_pos, t_ipf_band_pos_nxt, t_ipf_band_pos_pip1, t_ipf_band_pos_pip2;
        reg [15:0] t_ipf_offset, t_ipf_offset_nxt,t_ipf_offset_pip1;

    //======== operation ==============
        reg [4:0] low_bound, up_bound;
        reg [3:0] offset_po, offset_po_nxt;
        reg [3:0] offset_wo, offset_wo_nxt;
        reg [3:0] posi_a, posi_c, posi_b;
        reg [7:0] a,b,c;
        reg [7:0] c_pip1, c_pip2;
        reg [7:0] a_nxt,b_nxt,c_nxt;
        reg [8:0] mid;

    //======== data storage ===========
        reg [7:0] window0 [0:WIN_SIZE];   //window size = 16, 32, 64
        reg [7:0] window1 [0:WIN_SIZE];
        reg [7:0] window0_nxt [0:WIN_SIZE];
        reg [7:0] window1_nxt [0:WIN_SIZE];
        wire [7:0] window0_select, window1_select;

    //============ FSM ================
        reg [2:0] state, state_nxt, state_case_out;
        parameter IDLE = 3'd0;
        parameter WAIT = 3'd1;
        parameter INIT = 3'd2;
        parameter OFF = 3'd3;
        parameter PO = 3'd4;
        parameter WO_H = 3'd5;
        parameter WO_V = 3'd6;
        parameter FINISH = 3'd7;

//============= Wire assignment ===================
    assign  col_end = col==end_size;
    assign  row_pip2_end = row_pip2==end_size;
    assign  col_pip2_end = col_pip2==end_size;

    assign  end_lcu = (row==end_size & col_end); //col, row = 16, 32, 64
    assign  end_lcu_pip2 = (row_pip2_end & col_pip2_end); //col, row = 16, 32, 64
    assign  end_img = (!in_en & row_pip2_end & col_pip2_end); //lcu_x,y = 8, 4, 2

    assign window0_select = window0[col];
    assign window1_select = window1[col];
//============ Finite State Machine ===================
    always @(*) begin
        // generate duplicate case output
        case(ipf_type)
            2'd0: state_case_out = OFF;
            2'd1: state_case_out = PO;
            2'd2: state_case_out = ipf_wo_class? WO_V : WO_H;
            default: state_case_out = IDLE;
        endcase

        case(state)
            IDLE: begin
                busy = 1'b0;
                out_en = 1'b0;
                finish_nxt = 1'b0;
                state_nxt = WAIT;
            end
            INIT: begin
                busy = 1'b0;
                out_en = 1'b0;
                finish_nxt = 1'b0;
                if (end_lcu_pip2) state_nxt = state_case_out;
                else state_nxt = state;
            end
            WAIT: begin
                busy = 1'b0;
                out_en = 1'b0;
                finish_nxt = 1'b0;
                state_nxt = INIT;
            end
            OFF: begin
                busy = 1'b0;
                out_en = 1'b1;
                finish_nxt = 1'b0;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip2)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            PO: begin
                busy = 1'b0;
                out_en = 1'b1;
                finish_nxt = 1'b0;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip2)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_H: begin
                busy = 1'b0;
                out_en = 1'b1;
                finish_nxt = 1'b0;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip2)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_V: begin
                busy = 1'b0;
                out_en = 1'b1;
                finish_nxt = 1'b0;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip2)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            FINISH: begin
                busy = 1'b1;
                out_en = 1'b1;
                finish_nxt = 1'b1;
                state_nxt = state;
            end
        endcase
    end

//============= Combinational Circuit ========================
    always @(*) begin
        col_nxt = state==WAIT? 0 : (col_end)? 0 : col + 1;
        row_in_nxt = state==WAIT? 0 : (col_end)? (row_in==end_size)? 0 : row_in+1 : row_in;
        row = (row_in==0)? end_size : row_in - 1;
        case (lcu_size)
            2'd0: dout_addr_nxt = {t_lcu_y_pip2[2:0], row_pip2[3:0], t_lcu_x_pip2[2:0], col_pip2[3:0]};
            2'd1: dout_addr_nxt = {t_lcu_y_pip2[1:0], row_pip2[4:0], t_lcu_x_pip2[1:0], col_pip2[4:0]};
            default: dout_addr_nxt = {t_lcu_y_pip2[0], row_pip2[5:0], t_lcu_x_pip2[ 0 ], col_pip2[5:0]};
        endcase

        border = (seq==1'b0)? window1_select : window0_select;
        din_off_nxt = (seq==1'b0)? window1_select : window0_select;

        seq_nxt = seq;

        t_lcu_x_nxt = (end_lcu)? lcu_x : t_lcu_x;
        t_lcu_y_nxt = (end_lcu)? lcu_y : t_lcu_y;
        t_ipf_wo_class_nxt = (end_lcu)? ipf_wo_class : t_ipf_wo_class;
        t_ipf_band_pos_nxt = (end_lcu)? ipf_band_pos : t_ipf_band_pos;
        t_ipf_offset_nxt = (end_lcu)? ipf_offset : t_ipf_offset;

        for (i = 0 ; i<=WIN_SIZE; i=i+1) begin
            window0_nxt[i]=window0[i];
            window1_nxt[i]=window1[i];
        end

        if (seq==1'b0) begin
            window0_nxt[col] = din_buffer;
            seq_nxt = (col_end)? 1'b1:seq;
        end
        else if (seq==1'b1) begin
            window1_nxt[col] = din_buffer;
            seq_nxt = (col_end)? 1'b0:seq;
        end


    //========== dout_nxt =================
        case(state)
            OFF:begin
                // din_off_nxt = (seq==1'b0)? window1_select : window0_select;
                dout_nxt = din_off_pip2;
            end
            PO:begin
                dout_nxt = din_po;
            end
            WO_H:begin
                if (col_pip2==6'd0 | col_pip2_end) begin
                    dout_nxt = border_pip2;
                end
                else begin
                    dout_nxt = din_wo;
                end
            end
            WO_V:begin
                if (row_pip2==6'd0 | row_pip2_end) begin
                    dout_nxt = border_pip2;
                end
                else begin
                    dout_nxt = din_wo;
                end
            end
            default: dout_nxt = 0;
        endcase
    end

//============= operation ========================
    always @(*) begin
    //============== PO ================
        pix = (seq==1'b0)? window1_select : window0_select;
        pix_band = pix_pip1>>3;
        low_bound = (t_ipf_band_pos_pip2 == 5'd1)?  5'd0  : t_ipf_band_pos_pip2 - 1;
        up_bound = (t_ipf_band_pos_pip2 == 5'd31)?  5'd31 : t_ipf_band_pos_pip2 + 1;
        offset_po_nxt = ((pix_band[1:0])==2'd0)? t_ipf_offset_pip1[15:12] :
                        ((pix_band[1:0])==2'd1)? t_ipf_offset_pip1[11:8] :
                        ((pix_band[1:0])==2'd2)? t_ipf_offset_pip1[7:4] : t_ipf_offset_pip1[3:0];
        din_po_add = $signed( {1'b0,pix_pip2})+$signed(offset_po);
        //>255 or <0
        din_po_temp = (din_po_add[9])? 8'd0 : (din_po_add[8])? 8'd255 : din_po_add[7:0]; 
        din_po = (pix_band_pip2 == low_bound | pix_band_pip2 == up_bound | pix_band_pip2 == t_ipf_band_pos_pip2)? pix_pip2 : din_po_temp; 

    //============== WO ================
        a_col = (col==0)? end_size : col-1;
        b_col = (col_end)? 0 : col+1;
        case ({t_ipf_wo_class, seq})
            2'b00: begin
                a_nxt = window1[a_col];
                c_nxt = window1_select;
                b_nxt = window1[b_col];
            end
            2'b01: begin
                a_nxt = window0[a_col];
                c_nxt = window0_select;
                b_nxt = window0[b_col];
            end
            2'b10: begin
                a_nxt = window0_select;
                c_nxt = window1_select;
                b_nxt = din_buffer;
            end
            2'b11: begin
                a_nxt = window1_select;
                c_nxt = window0_select;
                b_nxt = din_buffer;
            end
        endcase

        mid = (a+b);
        if (c<a & c<b) begin //Category 0
            offset_wo_nxt = t_ipf_offset_pip1[15:12];
        end
        else if (c> a & c>b) begin //Category 3
            offset_wo_nxt = t_ipf_offset_pip1[3:0];
        end
        else begin
            if (c < mid[8:1]) begin //Category 1
                offset_wo_nxt = t_ipf_offset_pip1[11:8];
            end
            else if (c > mid[8:1]) begin //Category 2
                offset_wo_nxt = t_ipf_offset_pip1[7:4];
            end
            else begin
                offset_wo_nxt = 0;
            end
        end
        
        //>255 or <0
        din_wo_add = $signed({1'b0,c_pip1})+$signed(offset_wo);
        din_wo = din_wo_add[7:0]; 
    end

//============ Sequential Circuit =====================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0 ; i<=WIN_SIZE; i=i+1) begin
                window0[i]<= 0;
                window1[i]<= 0;
            end
            row_in <= 0;
            col <= 0;
            row_pip1 <= 0;
            row_pip2 <= 0;
            col_pip1 <= 0;
            col_pip2 <= 0;
            seq <= 0;
            dout <= 0;
            dout_addr <= 0;
            din_buffer <= 0;

            din_off_pip1 <= 0;
            din_off_pip2 <= 0;

            border_pip1 <= 0;
            border_pip2 <= 0;

            t_lcu_x <= 0;
            t_lcu_y <= 0;
            t_lcu_x_pip2 <= 0;
            t_lcu_y_pip2 <= 0;

            t_ipf_wo_class <= 0;
            t_ipf_band_pos <= 0;
            t_ipf_band_pos_pip2 <= 0;
            t_ipf_offset <= 0;
            pix_pip2 <= 0;
            pix_band_pip2 <= 0;

            a<=0;
            b<=0;
            c<=0;
            c_pip1 <= 0;
            c_pip2 <= 0;
            offset_wo <= 0;
            offset_po <= 0;

            finish <= 0;
            state <= IDLE;
        end
        else begin
            for (i = 0 ; i<=WIN_SIZE; i=i+1) begin
                window0[i]<=window0_nxt[i];
                window1[i]<=window1_nxt[i];
            end
            row_in <= row_in_nxt;
            col <= col_nxt;
            row_pip1 <= row;
            row_pip2 <= row_pip1;
            col_pip1 <= col;
            col_pip2 <= col_pip1;
            seq <= seq_nxt;
            dout <= dout_nxt;
            dout_addr <= dout_addr_nxt;
            din_buffer <= din;

            din_off_pip1 <= din_off_nxt;
            din_off_pip2 <= din_off_pip1;

            border_pip1 <= border;
            border_pip2 <= border_pip1;

            t_lcu_x <= t_lcu_x_nxt;
            t_lcu_y <= t_lcu_y_nxt;
            t_lcu_x_pip1 <= t_lcu_x;
            t_lcu_x_pip2 <= t_lcu_x_pip1;
            t_lcu_y_pip1 <= t_lcu_y;
            t_lcu_y_pip2 <= t_lcu_y_pip1;

            t_ipf_wo_class <= t_ipf_wo_class_nxt;
            t_ipf_band_pos <= t_ipf_band_pos_nxt;
            t_ipf_band_pos_pip1 <= t_ipf_band_pos;
            t_ipf_band_pos_pip2 <= t_ipf_band_pos_pip1;
            t_ipf_offset <= t_ipf_offset_nxt;
            t_ipf_offset_pip1 <= t_ipf_offset;
            pix_pip1 <= pix;
            pix_pip2 <= pix_pip1;
            pix_band_pip2 <= pix_band;

            a<=a_nxt;
            b<=b_nxt;
            c<=c_nxt;

            c_pip1 <= c;
            c_pip2 <= c_pip1;
            offset_wo <= offset_wo_nxt;
            offset_po <= offset_po_nxt;

            finish <= finish_nxt;
            state <= state_nxt;
        end
    end

endmodule