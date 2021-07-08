module IPF (
    clk, reset,
    in_en, din, ipf_type, ipf_band_pos, ipf_wo_class, ipf_offset,
    lcu_x, lcu_y, lcu_size, busy, out_en, dout, dout_addr, finish
);
//=========== IO ====================
    input               clk;
    input               reset;
    input               in_en;
    input [7:0]         din;
    input [1:0]         ipf_type;
    input [4:0]         ipf_band_pos;
    input               ipf_wo_class;
    input [15:0]        ipf_offset;
    input [2:0]         lcu_x;
    input [2:0]         lcu_y;
    input [1:0]         lcu_size;
    output              busy;
    output              finish;
    output reg          out_en;
    output reg [7:0]    dout;
    output reg [13:0]   dout_addr;

//============ reg/wire declaration ===================
    integer i;
    parameter WIN_SIZE = 16-1;  // 15,31,63
    parameter logSIZE = 4-1;    // 16=4bit, 31=5bit, 64=6bit

    //======== Size Effect ============
        wire [5:0] end_size;
        wire [2:0] end_lcu_xy;
        assign end_size = (lcu_size==2'b00)?
                                6'd15
                            :   (lcu_size==2'b01)?
                                    6'd31
                                :   6'd63;
        assign end_lcu_xy = (lcu_size==2'b00)?
                                3'd7
                            :   (lcu_size==2'b01)?
                                    3'd3
                                :   3'd1;
        
        

    //======== data I/O ===============
        reg [7:0] dout_nxt;
        reg [13:0] dout_addr_nxt;
        wire [7:0] px;

    //======== control signals ========
        // ff: col, row_in, win
        reg [logSIZE:0] col, col_nxt;
        reg [logSIZE:0] row, row_in, row_in_nxt;
        reg win, win_nxt;

        // registers for operation info
        reg [1:0] ipf_type_op, ipf_type_op_nxt;
        reg [4:0] ipf_band_pos_op, ipf_band_pos_op_nxt;
        reg ipf_wo_class_op, ipf_wo_class_op_nxt;
        reg [15:0] ipf_offset_op, ipf_offset_op_nxt;
        reg [2:0] lcu_x_op, lcu_x_op_nxt;
        reg [2:0] lcu_y_op, lcu_y_op_nxt;

        wire end_col, end_row;
        wire end_lcu;
        wire end_img;

    //======== operation ==============
        // PO
        wire [1:0] px_band_id;
        reg [4:0] offset_po;

        // WO
        wire [logSIZE:0] a_col, b_col;
        reg [7:0] a, b, c;
        wire [7:0] ab_mid;
        reg [4:0] offset_wo;

        reg signed [4:0] offset_op;
        wire signed [9:0] dout_add;
        reg [7:0] dout_final;

    //======== data storage ===========
        reg  [7:0] window0 [0:WIN_SIZE];   //window size = 16, 32, 64
        reg  [7:0] window1 [0:WIN_SIZE];
        reg  [7:0] window0_nxt [0:WIN_SIZE];
        reg  [7:0] window1_nxt [0:WIN_SIZE];
        wire [7:0] window0_select, window1_select;

    //============ FSM ================
        reg [2:0] state, state_nxt, state_case_out;
        parameter IDLE = 3'd0;
        parameter INIT = 3'd1;
        parameter OFF = 3'd2;
        parameter PO = 3'd3;
        parameter WO_H = 3'd4;
        parameter WO_V = 3'd5;
        parameter FINISH = 3'd6;

//============= Wire assignment ===================
    assign end_row = row==end_size;
    assign end_col = col==end_size;
    assign end_lcu = end_row & end_col;
    assign end_img = end_lcu & lcu_x_op==end_lcu_xy & lcu_y_op==end_lcu_xy;  // & !in_en

    assign window0_select = window0[col];
    assign window1_select = window1[col];

//============ Finite State Machine ===================
    assign busy = state==IDLE & in_en;
    assign finish = state==FINISH;
    always @(*) begin
        case(ipf_type_op)
            2'd0: state_case_out = OFF;
            2'd1: state_case_out = PO;
            2'd2: state_case_out = ipf_wo_class_op? WO_V : WO_H;
            default: state_case_out = IDLE;
        endcase

        case(state)
            IDLE: begin
                out_en = 1'b0;
                state_nxt = in_en? INIT : IDLE;
            end
            INIT: begin
                out_en = 1'b0;
                state_nxt = (end_col & win)? state_case_out : INIT;
            end
            OFF: begin
                out_en = 1'b1;
                state_nxt = end_img? FINISH : end_lcu? state_case_out : OFF;
            end
            PO: begin
                out_en = 1'b1;
                state_nxt = end_img? FINISH : end_lcu? state_case_out : PO;
            end
            WO_H: begin
                out_en = 1'b1;
                state_nxt = end_img? FINISH : end_lcu? state_case_out : WO_H;
            end
            WO_V: begin
                out_en = 1'b1;
                state_nxt = end_img? FINISH : end_lcu? state_case_out : WO_V;
            end
            FINISH: begin
                out_en = 1'b0;
                state_nxt = state;
            end
        endcase
    end

//============= Combinational Circuit ========================
    always @(*) begin
        col_nxt = state==IDLE? 0 : col + 1;
        row_in_nxt = state==IDLE? 0 : end_col? row_in + 1: row_in;
        row = row_in - 1;
        case (lcu_size)
            2'd0: dout_addr_nxt =  {lcu_y_op[2:0], row[3:0], lcu_x_op[2:0], col[3:0]};
            2'd1: dout_addr_nxt =  {lcu_y_op[1:0], row[4:0], lcu_x_op[1:0], col[4:0]};
            default: dout_addr_nxt = {lcu_y_op[0], row[5:0],   lcu_x_op[0], col[5:0]};
        endcase

        //======== ctrl unit ==========
        if (end_col & win) begin
            lcu_x_op_nxt = lcu_x;
            lcu_y_op_nxt = lcu_y;
            ipf_type_op_nxt = ipf_type;
            ipf_band_pos_op_nxt = ipf_band_pos;
            ipf_wo_class_op_nxt = ipf_wo_class;
            ipf_offset_op_nxt = ipf_offset;
        end
        else begin
            lcu_x_op_nxt = lcu_x_op;
            lcu_y_op_nxt = lcu_y_op;
            ipf_type_op_nxt = ipf_type_op;
            ipf_band_pos_op_nxt = ipf_band_pos_op;
            ipf_wo_class_op_nxt = ipf_wo_class_op;
            ipf_offset_op_nxt = ipf_offset_op;
        end

        //======== window data ========
        for (i = 0 ; i<=WIN_SIZE; i=i+1) begin
            window0_nxt[i] = window0[i];
            window1_nxt[i] = window1[i];
        end
        if (win) begin
            window1_nxt[col] = din;
            win_nxt = !end_col;
        end
        else begin
            window0_nxt[col] = din;
            win_nxt = end_col;
        end

        //======== dout_nxt ===========
        case(state)
            OFF: begin
                dout_nxt = px;
            end
            PO: begin
                dout_nxt = dout_final;
            end
            WO_H: begin
                if (col==6'd0 | end_col) begin
                    dout_nxt = px;
                end
                else begin
                    dout_nxt = dout_final;
                end
            end
            WO_V: begin
                if (row==6'd0 | end_row) begin
                    dout_nxt = px;
                end
                else begin
                    dout_nxt = dout_final;
                end
            end
            default: dout_nxt = 0;
        endcase
    end

//============= Operation ========================
    assign px = win? window1_select : window0_select;
    assign px_band_id = ipf_band_pos_op >> 3;

    assign ab_mid = (a+b) >> 2;
    assign a_col = col - 1;
    assign b_col = col + 1;

    // determine offset, generate offset_op
    always @(*) begin
        //============== PO ================
        case(px_band_id)
            2'd0: offset_po = ipf_offset_op[15:12];
            2'd1: offset_po = ipf_offset_op[11:8];
            2'd2: offset_po = ipf_offset_op[7:4];
            2'd3: offset_po = ipf_offset_op[3:0];
        endcase

        //============== WO ================

        case ({ipf_wo_class_op, win})
            2'b00: begin
                a = window1[a_col];
                b = window1[b_col];
            end
            2'b01: begin
                a = window0[a_col];
                b = window0[b_col];
            end
            2'b10: begin
                a = window0_select;
                b = din;
            end
            2'b11: begin
                a = window1_select;
                b = din;
            end
        endcase

        if (c<a & c<b) begin  // Category 0
            offset_wo = ipf_offset_op[15:12];
        end
        else if (c> a & c>b) begin  // Category 3
            offset_wo = ipf_offset_op[3:0];
        end
        else begin
            if (c < ab_mid) begin  // Category 1
                offset_wo = ipf_offset_op[11:8];
            end
            else if (c > ab_mid) begin  // Category 2
                offset_wo = ipf_offset_op[7:4];
            end
            else begin
                offset_wo = 0;
            end
        end

        offset_op = state==PO? offset_po : offset_wo;
    end
    
    assign dout_add  = $signed({1'b0, px}) + $signed(offset_op);
    always @(*) begin
        if (dout_add[8]) begin
            dout_final = px[7]? 8'd255 : 8'd0;
        end
        else begin
            dout_final = dout_add[7:0];
        end
    end

//============ Sequential Circuit =====================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i<=WIN_SIZE; i=i+1) begin
                window0[i] <= 0;
                window1[i] <= 0;
            end

            col <= 0;
            row_in <= 0;
            win <= 0;
            dout <= 0;
            dout_addr <= 0;

            ipf_type_op <= 0;
            ipf_band_pos_op <= 0;
            ipf_wo_class_op <= 0;
            ipf_offset_op <= 0;
            lcu_x_op <= 0;
            lcu_y_op <= 0;
        end
        else begin
            state <= state_nxt;
            for (i=0; i<=WIN_SIZE; i=i+1) begin
                window0[i] <= window0_nxt[i];
                window1[i] <= window1_nxt[i];
            end

            col <= col_nxt;
            row_in <= row_in_nxt;
            win <= win_nxt;
            dout <= dout_nxt;
            dout_addr <= dout_addr_nxt;

            ipf_type_op <= ipf_type_op_nxt;
            ipf_band_pos_op <= ipf_band_pos_op_nxt;
            ipf_wo_class_op <= ipf_wo_class_op_nxt;
            ipf_offset_op <= ipf_offset_op_nxt;
            lcu_x_op <= lcu_x_op_nxt;
            lcu_y_op <= lcu_y_op_nxt;
        end
    end

endmodule