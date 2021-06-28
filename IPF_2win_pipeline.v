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

//============ reg/wire declaration ===================
    integer i ;
    parameter LCU_SIZE = 16-1;    //15,31,63
    parameter logSIZE = 4-1; //16=4bit, 31=6bit, 64=8bit

    wire [5:0] end_size;
    assign end_size = (lcu_size==2'b00)? 6'd15 : (lcu_size==2'b00)? 6'd31 : 6'd63;

    //======== data I/O ===============
        reg [7:0] din_po, din_wo, dout_nxt, din_po_temp;
        reg [13:0] dout_addr_nxt;
        reg [7:0] pix, pix_pip, pix_band, pix_band_pip;
        reg [7:0] border, border_pip;
        reg [7:0] din_buffer, din_buffer_nxt;
        reg signed [9:0] din_po_add, din_wo_add;
        reg [8:0] add_1,add_2;
        reg [7:0] din_off, din_off_nxt;

    //======== control signals ========
        reg [logSIZE:0] col, col_nxt, col_pip; //col length = 16, 32, 64
        reg [logSIZE:0] row_in, row_in_nxt,row, row_pip;
        reg [logSIZE:0] a_col, b_col;
        reg seq, seq_nxt;
        reg finish_nxt;

        wire end_lcu;
        wire end_lcu_pip;
        wire end_img;

        reg [2:0] t_lcu_x, t_lcu_x_nxt, t_lcu_x_pip;
        reg [2:0] t_lcu_y, t_lcu_y_nxt, t_lcu_y_pip;
        reg t_ipf_wo_class, t_ipf_wo_class_nxt;
        reg [4:0] t_ipf_band_pos, t_ipf_band_pos_nxt, t_ipf_band_pos_pip;
        reg [15:0] t_ipf_offset, t_ipf_offset_nxt;

    //======== operation ==============
        reg [4:0] low_bound, up_bound;
        reg [3:0] offset_po, offset_po_nxt;
        reg [3:0] offset_wo, offset_wo_nxt;
        reg [3:0] posi_a, posi_c, posi_b;
        reg [7:0] a,b,c;
        reg [7:0] c_pip;
        reg [7:0] a_nxt,b_nxt,c_nxt;
        reg [8:0] mid;

    //======== data storage ===========
        reg [7:0] window0 [0:LCU_SIZE];   //window size = 16, 32, 64
        reg [7:0] window1 [0:LCU_SIZE];
        reg [7:0] window0_nxt [0:LCU_SIZE];
        reg [7:0] window1_nxt [0:LCU_SIZE];

    //============ FSM ================
        reg [3:0] state, state_nxt, state_case_out;
        parameter IDLE = 0;
        parameter WAIT = 1;
        parameter INIT = 2;
        parameter OFF = 3;
        parameter PO = 4;
        parameter WO_H = 5;
        parameter WO_V = 6;
        parameter FINISH = 7;

//============= Wire assignment ===================
    assign  end_lcu = (row==end_size & col==end_size); //col, row = 16, 32, 64
    assign  end_lcu_pip = (row_pip==end_size & col_pip==end_size); //col, row = 16, 32, 64
    assign  end_img = (!in_en & row_pip==end_size & col_pip==end_size); //lcu_x,y = 8, 4, 2

//============ Finite State Machine (Designed for dout_nxt)===================
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
                busy = 0;
                out_en = 0;
                state_nxt = WAIT;
            end
            INIT: begin
                busy = 0;
                out_en = 0;
                if (end_lcu_pip) state_nxt = state_case_out;
                else state_nxt = state;
            end
            WAIT: begin
                busy = 0;
                out_en = 0;
                state_nxt = INIT;
            end
            OFF: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            PO: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_H: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_V: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu_pip)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            FINISH: begin
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

//============= Combinational ckt ========================
    always @(*)begin
        col_nxt = (col==end_size)? 0 : col + 1;
        row_in_nxt = (col==end_size)? (row_in==end_size)? 0 : row_in+1 : row_in;
        row = row_in - 1;

        dout_nxt = 0;
        dout_addr_nxt = {t_lcu_y_pip, row_pip, t_lcu_x_pip, col_pip};
        border = (seq==1'b0)? window1[col] : window0[col];
        din_off_nxt = (seq==1'b0)? window1[col] : window0[col];

        seq_nxt = seq;
        finish_nxt = 0;

        t_lcu_x_nxt = (end_lcu)? lcu_x : t_lcu_x;
        t_lcu_y_nxt = (end_lcu)? lcu_y : t_lcu_y;
        t_ipf_wo_class_nxt = (end_lcu)? ipf_wo_class : t_ipf_wo_class;
        t_ipf_band_pos_nxt = (end_lcu)? ipf_band_pos : t_ipf_band_pos;
        t_ipf_offset_nxt = (end_lcu)? ipf_offset : t_ipf_offset;


        for (i = 0 ; i<=LCU_SIZE; i=i+1)begin
            window0_nxt[i]=window0[i];
            window1_nxt[i]=window1[i];
        end

        din_buffer_nxt = din;
        if (seq==1'b0)begin
            window0_nxt[col] = din_buffer;
            seq_nxt = (col==end_size)? 1'b1:seq;
        end
        else if (seq==1'b1)begin
            window1_nxt[col] = din_buffer;
            seq_nxt = (col==end_size)? 1'b0:seq;
        end


    //========== dout_nxt =================
        case(state)
            IDLE:begin
                col_nxt = col;
                row_in_nxt = row;
            end

            WAIT:begin
                col_nxt = 0;
                row_in_nxt = 0;
            end
            
            OFF:begin
                din_off_nxt = (seq==1'b0)? window1[col] : window0[col];
                dout_nxt = din_off;
            end

            PO:begin
                dout_nxt = din_po;
            end

            WO_H:begin
                if (col_pip==4'd0 | col_pip==end_size)begin
                    dout_nxt = border_pip;
                end
                else begin
                    dout_nxt = din_wo;
                end
            end

            WO_V:begin
                if (row_pip==4'd0 | row_pip==end_size)begin
                    dout_nxt = border_pip;
                end
                else begin
                    dout_nxt = din_wo;
                end
            end
            
            FINISH:begin
                finish_nxt = 1;
            end
        endcase
    end

//============= operation ========================
    always @(*)begin
        //============== PO ================
        pix = (seq==1'b0)? window1[col] : window0[col];
        pix_band = pix>>3;
        low_bound = (t_ipf_band_pos_pip == 5'd1)?  5'd0  : t_ipf_band_pos_pip - 1;
        up_bound = (t_ipf_band_pos_pip == 5'd31)?  5'd31 : t_ipf_band_pos_pip + 1;
        offset_po_nxt = ((pix_band[1:0])==2'd0)? t_ipf_offset[15:12] :
                        ((pix_band[1:0])==2'd1)? t_ipf_offset[11:8] :
                        ((pix_band[1:0])==2'd2)? t_ipf_offset[7:4] : t_ipf_offset[3:0];
        din_po_add = $signed( {1'b0,pix_pip})+$signed(offset_po);
        //>255 or <0
        din_po_temp = (din_po_add[9])? 8'd0 : (din_po_add[8])? 8'd255 : din_po_add[7:0]; 
        din_po = (pix_band_pip == low_bound | pix_band_pip == up_bound | pix_band_pip == t_ipf_band_pos_pip)? pix_pip : din_po_temp; 

        //============== WO ================
        a_col = (col==0)? end_size : col-1;
        b_col = (col==end_size)? 0 : col+1;
        case ({t_ipf_wo_class, seq})
            2'b00: begin
                a = window1[a_col];
                c = window1[col];
                b = window1[b_col];
            end
            2'b01: begin
                a = window0[a_col];
                c = window0[col];
                b = window0[b_col];
            end
            2'b10: begin
                a = window0[col];
                c = window1[col];
                b = din_buffer;
            end
            2'b11: begin
                a = window1[col];
                c = window0[col];
                b = din_buffer;
            end
        endcase

        mid = (a+b);
        if (c<a & c<b)begin //Category 0
            offset_wo_nxt = t_ipf_offset[15:12];
        end
        else if (c < mid[8:1] & (c>=a | c>=b))begin //Category 1
            offset_wo_nxt = t_ipf_offset[11:8];
        end
        else if (c > mid[8:1] & (c<=a | c<=b))begin //Category 2
            offset_wo_nxt = t_ipf_offset[7:4];
        end
        else if (c > a & c>b)begin //Category 3
            offset_wo_nxt = t_ipf_offset[3:0];
        end
        else begin
            offset_wo_nxt = 0;
        end
        
        // mid = (a + b) >> 1;     // TODO: without mid?
        // case ({c<a, c==a, c<b, c==b, c<mid[7:0], c==mid[7:0]    })    // TODO: critical path or not??
        //     6'b101010:  offset_wo_nxt = t_ipf_offset[15:12];     // Category 0
        //     6'b000000:  offset_wo_nxt = t_ipf_offset[3:0];     // Category 3
        //     6'b001010:  offset_wo_nxt = t_ipf_offset[11:8];     // Category 1 (c < mid)
        //     6'b000110:  offset_wo_nxt = t_ipf_offset[11:8];     //   >= min and <= max (8 cases)
        //     6'b011010:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b010110:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b100010:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b010010:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b100110:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b010110:  offset_wo_nxt = t_ipf_offset[11:8];
        //     6'b001000:  offset_wo_nxt = t_ipf_offset[7:4];     // Category 2 (c > mid)
        //     6'b000100:  offset_wo_nxt = t_ipf_offset[7:4];     //   >= min and <= max (8 cases)
        //     6'b011000:  offset_wo_nxt = t_ipf_offset[7:4];
        //     6'b010100:  offset_wo_nxt = t_ipf_offset[7:4];
        //     6'b100000:  offset_wo_nxt = t_ipf_offset[7:4];
        //     6'b010000:  offset_wo_nxt = t_ipf_offset[7:4];
        //     6'b100100:  offset_wo_nxt = t_ipf_offset[7:4];
        //     6'b010100:  offset_wo_nxt = t_ipf_offset[7:4];
        //     default:    offset_wo_nxt = 0;
        // endcase


        //>255 or <0
        din_wo_add = $signed({1'b0,c_pip})+$signed(offset_wo);
        din_wo = din_wo_add[7:0]; 
    end

//============ Sequential Circuit =====================
    always @(posedge clk or posedge reset)begin
        if (reset)begin
            for (i = 0 ; i<=LCU_SIZE; i=i+1)begin
                window0[i]<= 0;
                window1[i]<= 0;
            end
            row_in <= 0;
            col <= 0;
            row_pip <= 0;
            col_pip <= 0;
            seq <= 0;
            dout <= 0;
            dout_addr <= 0;
            din_buffer <= 0;

            din_off <= 0;

            border_pip <= 0;

            t_lcu_x <= 0;
            t_lcu_y <= 0;
            t_lcu_x_pip <= 0;
            t_lcu_y_pip <= 0;

            t_ipf_wo_class <= 0;
            t_ipf_band_pos <= 0;
            t_ipf_band_pos_pip <= 0;
            t_ipf_offset <= 0;
            pix_pip <= 0;
            pix_band_pip <= 0;

            // a<=0;
            // b<=0;
            // c<=0;
            c_pip <= 0;
            offset_wo <= 0;
            offset_po <= 0;

            finish <= 0;
            state <= IDLE;
        end
        else begin
            for (i = 0 ; i<=LCU_SIZE; i=i+1)begin
                window0[i]<=window0_nxt[i];
                window1[i]<=window1_nxt[i];
            end
            row_in <= row_in_nxt;
            col <= col_nxt;
            row_pip <= row;
            col_pip <= col;
            seq <= seq_nxt;
            dout <= dout_nxt;
            dout_addr <= dout_addr_nxt;
            din_buffer <= din_buffer_nxt;

            din_off <= din_off_nxt;

            border_pip <= border;

            t_lcu_x <= t_lcu_x_nxt;
            t_lcu_y <= t_lcu_y_nxt;
            t_lcu_x_pip <= t_lcu_x;
            t_lcu_y_pip <= t_lcu_y;

            t_ipf_wo_class <= t_ipf_wo_class_nxt;
            t_ipf_band_pos <= t_ipf_band_pos_nxt;
            t_ipf_band_pos_pip <= t_ipf_band_pos;
            t_ipf_offset <= t_ipf_offset_nxt;
            pix_pip <= pix;
            pix_band_pip <= pix_band;

            // a<=a_nxt;
            // b<=b_nxt;
            // c<=c_nxt;
            c_pip <= c;
            offset_wo <= offset_wo_nxt;
            offset_po <= offset_po_nxt;

            finish <= finish_nxt;
            state <= state_nxt;
        end
    end

endmodule