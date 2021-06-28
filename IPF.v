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

    integer i ;
    //======== data I/O ===============
        reg [7:0] din_buffer, din_po_temp, pix, pix_band;
        reg signed [8:0] din_po_add, din_wo_add;
        reg [7:0] dout_po, dout_po_tmp, dout_wo, dout_buffer;
        reg [13:0] dout_addr_buffer;

    //======== control signals ========
        reg [logSIZE-1:0] col, col_nxt;
        reg [logSIZE-1:0] row, row_in, row_in_nxt;
        wire [logSIZE:0] col_a1, row_in_a1;
        wire col_begin, col_end, row_begin, row_end;
        reg seq, seq_nxt;
        reg finish_nxt;
        wire end_lcu;
        wire end_img;

        reg [2:0] t_lcu_x, t_lcu_x_nxt;
        reg [2:0] t_lcu_y, t_lcu_y_nxt;
        reg t_ipf_wo_class, t_ipf_wo_class_nxt;
        reg [4:0] t_ipf_band_pos, t_ipf_band_pos_nxt;
        reg [15:0] t_ipf_offset, t_ipf_offset_nxt;

    //======== operation ==============
        reg [4:0] low_bound, up_bound;
        reg [3:0] offset_po;
        reg [3:0] offset_wo;
        reg [3:0] a_col, b_col;
        reg [7:0] a_pix, b_pix, c_pix;
        reg [8:0] mid;
        reg signed [8:0] adder_in1;
        reg signed [8:0] adder_0_in2, adder_1_in2, adder_2_in2, adder_3_in2;
        reg [8:0] adder_0_out, adder_0_out_tmp;
        reg [8:0] adder_1_out, adder_1_out_tmp;
        reg [8:0] adder_2_out, adder_2_out_tmp;
        reg [8:0] adder_3_out, adder_3_out_tmp;

    //======== data storage ===========
        reg [7:0] window0 [0:LCU_SIZE-1];   //window size = 16, 32, 64
        reg [7:0] window1 [0:LCU_SIZE-1];
        reg [7:0] window0_nxt [0:LCU_SIZE-1];
        reg [7:0] window1_nxt [0:LCU_SIZE-1];

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
                busy = 0;
                out_en = 0;
                state_nxt = WAIT;
            end
            INIT: begin
                busy = 0;
                out_en = 0;
                if (row_in==4'd0 & col_end) state_nxt = state_case_out;
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
                else if (end_lcu)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            PO: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_H: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu)   state_nxt = state_case_out;
                else                state_nxt = state;
            end
            WO_V: begin
                busy = 0;
                out_en = 1;
                if (end_img)        state_nxt = FINISH;
                else if (end_lcu)   state_nxt = state_case_out;
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

//============ Combinatinoal Circuit ==================
    //======== static assign ==========
        assign col_a1 = col + 1;
        assign row_in_a1 = row_in + 1;
        assign col_begin = col==4'd0;
        assign col_end = col==4'd15;   // end of col, row = 16, 32, 64
        assign row_begin = row==4'd0;
        assign row_end = row==4'd15;
        assign end_lcu = (row_end & col_end);
        assign end_img = (!in_en & row_end & col_end);
        always @(*) begin
            row = row_in - 1;
        end

    //======== Next Logic =============
    always @(*) begin
        col_nxt = col_a1;
        row_in_nxt = (col_end)? row_in_a1 : row_in;
        dout_buffer = dout;
        dout_addr_buffer = dout_addr;
        seq_nxt = seq;
        finish_nxt = 0;
        t_lcu_x_nxt = (end_lcu)? lcu_x : t_lcu_x;
        t_lcu_y_nxt = (end_lcu)? lcu_y : t_lcu_y;
        t_ipf_wo_class_nxt = (end_lcu)? ipf_wo_class : t_ipf_wo_class;
        t_ipf_band_pos_nxt = (end_lcu)? ipf_band_pos : t_ipf_band_pos;
        t_ipf_offset_nxt = (end_lcu)? ipf_offset : t_ipf_offset;

        for (i = 0 ; i<LCU_SIZE; i=i+1) begin
            window0_nxt[i]=window0[i];
            window1_nxt[i]=window1[i];
        end

        if (seq==1'b0) begin
            window0_nxt[col] = din_buffer;
            seq_nxt = (col_end)? 1'b1 : seq;
        end
        else if (seq==1'b1) begin
            window1_nxt[col] = din_buffer;
            seq_nxt = (col_end)? 1'b0 : seq;
        end

        case(state)
            IDLE: begin
                col_nxt = col;
                row_in_nxt = row_in;
            end
            WAIT: begin
                col_nxt = 0;
                row_in_nxt = 0;
            end
            OFF: begin
                dout_buffer = (seq==1'b0)? window1[col] : window0[col];
                dout_addr_buffer = (row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + col;
            end
            PO: begin
                dout_buffer = dout_po;
                dout_addr_buffer = (row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + col;
            end
            WO_H: begin
                if (col_begin | col_end) begin
                    dout_buffer = (seq==1'b0)? window1[col] : window0[col];
                end
                else begin
                    dout_buffer = dout_wo;
                end
                dout_addr_buffer = (row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + col;
            end
            WO_V: begin
                if (row_begin | row_end) begin
                    dout_buffer = (seq==1'b0)? window1[col] : window0[col];
                end
                else begin
                    dout_buffer = dout_wo;
                end
                dout_addr_buffer = (row<<7) + (t_lcu_y<<11) + (t_lcu_x<<4) + col;
            end
            FINISH: begin
                finish_nxt = 1;
            end
        endcase
    end

//============ Operation ==============================
    always @(*) begin
    //============ set up =============
        // PO
        pix = (seq==1'b0)? window1[col] : window0[col];
        pix_band = pix >> 3;
        // >31 or <0
        low_bound = (t_ipf_band_pos==5'd1)?  5'd0  : t_ipf_band_pos - 1;
        up_bound = (t_ipf_band_pos==5'd31)?  5'd31 : t_ipf_band_pos + 1;

        // WO
        a_col = col-1;
        b_col = col_a1;
        case ({t_ipf_wo_class, seq})
            2'b00: begin
                a_pix = window1[a_col];
                c_pix = window1[col];
                b_pix = window1[b_col];
            end
            2'b01: begin
                a_pix = window0[a_col];
                c_pix = window0[col];
                b_pix = window0[b_col];
            end
            2'b10: begin
                a_pix = window0[col];
                c_pix = window1[col];
                b_pix = din_buffer;
            end
            2'b11: begin
                a_pix = window1[col];
                c_pix = window0[col];
                b_pix = din_buffer;
            end
        endcase

    //============ Adder ==============
        adder_0_in2 = $signed(t_ipf_offset[15:12]);
        adder_1_in2 = $signed(t_ipf_offset[11:8]);
        adder_2_in2 = $signed(t_ipf_offset[7:4]);
        adder_3_in2 = $signed(t_ipf_offset[3:0]);
        if (state==PO) begin
            adder_in1 = $signed(pix);
        end else begin
            adder_in1 = $signed(c_pix);
        end
        adder_0_out_tmp = adder_in1 + adder_0_in2;
        adder_1_out_tmp = adder_in1 + adder_1_in2;
        adder_2_out_tmp = adder_in1 + adder_2_in2;
        adder_3_out_tmp = adder_in1 + adder_3_in2;

        // range constraint: 0-255
        case ({adder_in1[7], adder_0_out_tmp[8]})
            2'b10: adder_0_out = 8'd255;
            2'b01: adder_0_out = 8'd0;
            default: adder_0_out = adder_0_out_tmp[7:0];
        endcase
        case ({adder_in1[7], adder_1_out_tmp[8]})
            2'b10: adder_1_out = 8'd255;
            2'b01: adder_1_out = 8'd0;
            default: adder_1_out = adder_1_out_tmp[7:0];
        endcase
        case ({adder_in1[7], adder_2_out_tmp[8]})
            2'b10: adder_2_out = 8'd255;
            2'b01: adder_2_out = 8'd0;
            default: adder_2_out = adder_2_out_tmp[7:0];
        endcase
        case ({adder_in1[7], adder_3_out_tmp[8]})
            2'b10: adder_3_out = 8'd255;
            2'b01: adder_3_out = 8'd0;
            default: adder_3_out = adder_3_out_tmp[7:0];
        endcase
    
    //============ PO =================
        case (pix[4:3])
            2'd0: dout_po_tmp = adder_0_out;
            2'd1: dout_po_tmp = adder_1_out;
            2'd2: dout_po_tmp = adder_2_out;
            2'd3: dout_po_tmp = adder_3_out;
        endcase
        dout_po = (pix_band == low_bound | pix_band == up_bound | pix_band == t_ipf_band_pos)?
                pix
            :   dout_po_tmp;

    //============ WO =================
        mid = (a_pix + b_pix) >> 1;     // TODO: without mid?
        case ({c_pix<a_pix, c_pix==a_pix, c_pix<b_pix, c_pix==b_pix, c_pix<mid, c_pix==mid})    // TODO: critical path or not??
            6'b101010:  dout_wo = adder_0_out;     // Category 0
            6'b000000:  dout_wo = adder_3_out;     // Category 3
            6'b001010:  dout_wo = adder_1_out;     // Category 1 (c < mid)
            6'b000110:  dout_wo = adder_1_out;     //   >= min and <= max (8 cases)
            6'b011010:  dout_wo = adder_1_out;
            6'b010110:  dout_wo = adder_1_out;
            6'b100010:  dout_wo = adder_1_out;
            6'b010010:  dout_wo = adder_1_out;
            6'b100110:  dout_wo = adder_1_out;
            6'b010110:  dout_wo = adder_1_out;
            6'b001000:  dout_wo = adder_2_out;     // Category 2 (c > mid)
            6'b000100:  dout_wo = adder_2_out;     //   >= min and <= max (8 cases)
            6'b011000:  dout_wo = adder_2_out;
            6'b010100:  dout_wo = adder_2_out;
            6'b100000:  dout_wo = adder_2_out;
            6'b010000:  dout_wo = adder_2_out;
            6'b100100:  dout_wo = adder_2_out;
            6'b010100:  dout_wo = adder_2_out;
            default:    dout_wo = c_pix;
        endcase
    end

//============ Sequential Circuit =====================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0 ; i<LCU_SIZE; i=i+1) begin
                window0[i]<= 0;
                window1[i]<= 0;
            end
            row_in <= 0;
            col <= 0;
            seq <= 0;
            dout <= 0;
            dout_addr <= 0;

            t_lcu_x <= 0;
            t_lcu_y <= 0;
            t_ipf_wo_class <= 0;
            t_ipf_band_pos <= 0;
            t_ipf_offset <= 0;

            finish <= 0;
            state <= IDLE;
        end
        else begin
            for (i = 0 ; i<LCU_SIZE; i=i+1) begin
                window0[i]<=window0_nxt[i];
                window1[i]<=window1_nxt[i];
            end
            row_in <= row_in_nxt;
            col <= col_nxt;
            seq <= seq_nxt;
            dout <= dout_buffer;
            dout_addr <= dout_addr_buffer;
            din_buffer <= din;

            t_lcu_x <= t_lcu_x_nxt;
            t_lcu_y <= t_lcu_y_nxt;
            t_ipf_wo_class <= t_ipf_wo_class_nxt;
            t_ipf_band_pos <= t_ipf_band_pos_nxt;
            t_ipf_offset <= t_ipf_offset_nxt;

            finish <= finish_nxt;
            state <= state_nxt;
        end
    end

endmodule



//============ Sundry =================================
    // operation ver 1: one adder
    //============ Operation ==============================
        // always @(*) begin
        // //============ PO =================
        //     pix = (seq==1'b0)? window1[col] : window0[col];
        //     pix_band = pix>>3;
        //     // >31 or <0
        //     low_bound = (t_ipf_band_pos==5'd1)?  5'd0  : t_ipf_band_pos - 1;
        //     up_bound = (t_ipf_band_pos==5'd31)?  5'd31 : t_ipf_band_pos + 1;
        //     case (pix[4:3])     // TODO: 4 adder faster?
        //         2'd0: offset_po = t_ipf_offset[15:12];
        //         2'd1: offset_po = t_ipf_offset[11:8];
        //         2'd2: offset_po = t_ipf_offset[7:4];
        //         2'd3: offset_po = t_ipf_offset[3:0];
        //     endcase

        // //============ WO =================
        //     a_col = col-1;
        //     b_col = col_a1;
        //     case ({t_ipf_wo_class, seq})
        //         2'b00: begin
        //             a_pix = window1[a_col];
        //             c_pix = window1[col];
        //             b_pix = window1[b_col];
        //         end
        //         2'b01: begin
        //             a_pix = window0[a_col];
        //             c_pix = window0[col];
        //             b_pix = window0[b_col];
        //         end
        //         2'b10: begin
        //             a_pix = window0[col];
        //             c_pix = window1[col];
        //             b_pix = din_buffer;
        //         end
        //         2'b11: begin
        //             a_pix = window1[col];
        //             c_pix = window0[col];
        //             b_pix = din_buffer;
        //         end
        //     endcase

        //     mid = (a_pix + b_pix) >> 1;     // TODO: without mid?
        //     case ({c_pix<a_pix, c_pix==a_pix, c_pix<b_pix, c_pix==b_pix, c_pix<mid, c_pix==mid})    // TODO: critical path or not??
        //         6'b101010: offset_wo = t_ipf_offset[15:12];   // Category 0
        //         6'b000000: offset_wo = t_ipf_offset[3:0];     // Category 3
        //         6'b001010: offset_wo = t_ipf_offset[11:8];    // Category 1 (c < mid)
        //         6'b000110: offset_wo = t_ipf_offset[11:8];    //   >= min and <= max (8 cases)
        //         6'b011010: offset_wo = t_ipf_offset[11:8];
        //         6'b010110: offset_wo = t_ipf_offset[11:8];
        //         6'b100010: offset_wo = t_ipf_offset[11:8];
        //         6'b010010: offset_wo = t_ipf_offset[11:8];
        //         6'b100110: offset_wo = t_ipf_offset[11:8];
        //         6'b010110: offset_wo = t_ipf_offset[11:8];
        //         6'b001000: offset_wo = t_ipf_offset[7:4];     // Category 2 (c > mid)
        //         6'b000100: offset_wo = t_ipf_offset[7:4];     //   >= min and <= max (8 cases)
        //         6'b011000: offset_wo = t_ipf_offset[7:4];
        //         6'b010100: offset_wo = t_ipf_offset[7:4];
        //         6'b100000: offset_wo = t_ipf_offset[7:4];
        //         6'b010000: offset_wo = t_ipf_offset[7:4];
        //         6'b100100: offset_wo = t_ipf_offset[7:4];
        //         6'b010100: offset_wo = t_ipf_offset[7:4];
        //         default: offset_wo = 4'd0;
        //     endcase

        // //============ Adder ==============
        //     if (state==PO) begin
        //         adder_in1 = $signed(pix);
        //         adder_in2 = $signed(offset_po);
        //     end else begin
        //         adder_in1 = $signed(c_pix);
        //         adder_in2 = $signed(offset_wo);
        //     end
        //     adder_out_tmp = adder_in1 + adder_in2;  // TODO: adder * 4 for each offset
        //     // range constraint: 0-255
        //     case ({adder_in1[7], adder_out_tmp[8]})
        //         2'b10: adder_out = 8'd255;
        //         2'b01: adder_out = 8'd0;
        //         default: adder_out = adder_out_tmp[7:0];
        //     endcase

        //     dout_po = (pix_band == low_bound | pix_band == up_bound | pix_band == t_ipf_band_pos)?
        //                     pix
        //                 :   adder_out[7:0]; 
        //     dout_wo = adder_out[7:0]; 
        // end
