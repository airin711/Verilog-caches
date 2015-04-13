// Cache Memory (default : 8way 4word)                                //
// cache configuration can be changed by change and cache_config port //
// i_  means input port                                               //
// o_  means output port                                              //
// _p_  means data exchange with processor                            //
// _m_  means data exchange with memory                               //
// Replacement policy is pseudo LRU (7bit)                            //

`default_nettype none

  module cache(clk,
               rst,
               i_p_addr,
               i_p_byte_en,
               i_p_writedata,
               i_p_read,
               i_p_write,
               o_p_readdata,
               o_p_readdata_valid,
               o_p_waitrequest,

               o_m_addr,
               o_m_byte_en,
               o_m_writedata,
               o_m_read,
               o_m_write,
               i_m_readdata,
               i_m_readdata_valid,
               i_m_waitrequest,

               cnt_r,
               cnt_w,
               cnt_hit_r,
               cnt_hit_w,
               cnt_wb_r,
               cnt_wb_w,

               cache_config,
               change);

    parameter cache_entry = 9;
    input wire         clk, rst;
    input wire [24:0]  i_p_addr;
    input wire [3:0]   i_p_byte_en;
    input wire [31:0]  i_p_writedata;
    input wire         i_p_read, i_p_write;
    output reg [31:0]  o_p_readdata;
    output reg         o_p_readdata_valid;
    output wire        o_p_waitrequest;

    output reg [25:0]  o_m_addr;
    output wire [3:0]  o_m_byte_en;
    output reg [127:0] o_m_writedata;
    output reg         o_m_read, o_m_write;
    input wire [127:0] i_m_readdata;
    input wire         i_m_readdata_valid;
    input wire         i_m_waitrequest;

    output reg [31:0]  cnt_r;
    output reg [31:0]  cnt_w;
    output reg [31:0]  cnt_hit_r;
    output reg [31:0]  cnt_hit_w;
    output reg [31:0]  cnt_wb_r;
    output reg [31:0]  cnt_wb_w;

    input wire [3:0]   cache_config;
    input wire         change;

    wire [7:0]    hit;
    wire [7:0]    modify;
    wire [7:0]    miss;
    wire [7:0]    valid;
    wire [127:0]  readdata0, readdata1, readdata2, readdata3;
    wire [127:0]  readdata4, readdata5, readdata6, readdata7;
    wire [127:0]  writedata;
    wire          write0, write1, write2, write3;
    wire          write4, write5, write6, write7;
    wire [3:0]    word_en;
    wire [3:0] 	  byte_en;
    wire [22:0]   addr;
    wire [22:0]   wb_addr0, wb_addr1, wb_addr2, wb_addr3;
    wire [22:0]   wb_addr4, wb_addr5, wb_addr6, wb_addr7;
    wire [7:0] 	  r_cm_data;
    wire [3:0] 	  hit_num;
    wire [3:0] 	  invalid_num;

    reg  [3:0] 	  state;
    reg  [127:0]  writedata_buf;
    reg  [24:0]   write_addr_buf;
    reg  [3:0] 	  byte_en_buf;
    reg 		  write_buf, read_buf;
    reg  [7:0]    write_set;
    reg  [7:0]    fetch_write;
    reg  [7:0] 	  w_cm_data;
    reg 		  w_cm;
    wire [2:0]    replace;

    reg  [1:0]    flash;
    reg  [3:0]    phase;
    reg  [cache_entry:0] flash_cnt;
    wire [7:0]    dirty;
    reg  [3:0]    current_config;

    localparam IDLE = 0;
    localparam COMP = 1;
    localparam HIT  = 2;
    localparam FETCH1 = 3;
    localparam FETCH2 = 4;
    localparam FETCH3 = 5;
    localparam WB1 = 6;
    localparam WB2 = 7;
    localparam FLASH  = 8;

`ifdef SIM
    integer i;
    
    initial begin
        for(i = 0; i <=(2**cache_entry-1); i=i+1) begin
	        ram_hot.mem[i] = 0;
        end
    end
`endif

    simple_ram #(.width(8), .widthad(cache_entry)) ram_hot(clk, addr[cache_entry-1:0], w_cm, w_cm_data, addr[cache_entry-1:0], r_cm_data);

    config_ctrl #(.cache_entry(cache_entry))
    config_ctrl(.clk(clk),
                .rst(rst),
                .entry(addr[cache_entry-1:0]),
                .o_tag(addr[22:cache_entry]),
                .writedata(writedata),
                .byte_en(byte_en),
                .word_en(word_en),
                .write({write7, write6, write5, write4, write3, write2, write1, write0}),
                .readdata0(readdata0),
                .readdata1(readdata1),
                .readdata2(readdata2),
                .readdata3(readdata3),
                .readdata4(readdata4),
                .readdata5(readdata5),
                .readdata6(readdata6),
                .readdata7(readdata7),
                .wb_addr0(wb_addr0),
                .wb_addr1(wb_addr1),
                .wb_addr2(wb_addr2),
                .wb_addr3(wb_addr3),
                .wb_addr4(wb_addr4),
                .wb_addr5(wb_addr5),
                .wb_addr6(wb_addr6),
                .wb_addr7(wb_addr7),
                .hit(hit),
                .miss(miss),
                .dirty(dirty),
                .valid(valid),
                .read_miss(read_buf),
                .flash(flash),
                .c_fig(current_config)
                );

    assign writedata = (|fetch_write) ?	i_m_readdata : writedata_buf; //128bit
    assign write0 = (fetch_write[0]) ? i_m_readdata_valid : write_set[0];
    assign write1 = (fetch_write[1]) ? i_m_readdata_valid : write_set[1];
    assign write2 = (fetch_write[2]) ? i_m_readdata_valid : write_set[2];
    assign write3 = (fetch_write[3]) ? i_m_readdata_valid : write_set[3];
    assign write4 = (fetch_write[4]) ? i_m_readdata_valid : write_set[4];
    assign write5 = (fetch_write[5]) ? i_m_readdata_valid : write_set[5];
    assign write6 = (fetch_write[6]) ? i_m_readdata_valid : write_set[6];
    assign write7 = (fetch_write[7]) ? i_m_readdata_valid : write_set[7];
    assign addr = (state == FLASH) ? {write_addr_buf[24:cache_entry+2], flash_cnt[cache_entry-1:0]} : 
                  (o_p_waitrequest) ? write_addr_buf[24:2] : i_p_addr[24:2]; // set module input addr is 23bit 
    assign byte_en = (|fetch_write) ? 4'b1111 : byte_en_buf;
    assign o_p_waitrequest = (state != IDLE);
    assign o_m_byte_en = 4'b1111;

    assign hit_num = (hit[0]) ? 0 : 
                     (hit[1]) ? 1 : 
                     (hit[2]) ? 2 : 
                     (hit[3]) ? 3 : 
                     (hit[4]) ? 4 : 
                     (hit[5]) ? 5 : 
                     (hit[6]) ? 6 : 7;
    assign invalid_num = (!valid[0]) ? 0 : 
                         (!valid[1]) ? 1 : 
                         (!valid[2]) ? 2 : 
                         (!valid[3]) ? 3 : 
                         (!valid[4]) ? 4 : 
                         (!valid[5]) ? 5 : 
                         (!valid[6]) ? 6 : 7;
    assign word_en = (|fetch_write) ? 4'b1111 : 
                     (write_addr_buf[1:0] == 2'b00) ? 4'b0001 :
                     (write_addr_buf[1:0] == 2'b01) ? 4'b0010 :
                     (write_addr_buf[1:0] == 2'b10) ? 4'b0100 : 4'b1000;
    assign replace = (current_config) ? {1'b0, r_cm_data[1:0]} : 
                                        (r_cm_data[6]) ? ((r_cm_data[4]) ? ((r_cm_data[0]) ? 7 : 6) : ((r_cm_data[1]) ? 5 : 4)) :
                                                         ((r_cm_data[5]) ? ((r_cm_data[2]) ? 3 : 2) : ((r_cm_data[3]) ? 1 : 0));
                                       
    always @(posedge clk) begin
        if(current_config == 4'b0000) begin
            if(hit) begin
                case(hit_num)
                    0: w_cm_data <= {3'b011, r_cm_data[4], 1'b1, r_cm_data[2:0]};
                    1: w_cm_data <= {3'b011, r_cm_data[4], 1'b0, r_cm_data[2:0]};
                    2: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b1, r_cm_data[1:0]};
                    3: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b0, r_cm_data[1:0]};
                    4: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b1, r_cm_data[0]};
                    5: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b0, r_cm_data[0]};
                    6: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b1};
                    7: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b0};
                endcase
            end else if(!(&valid)) begin
                case(invalid_num)
//                    0: w_cm_data <= {3'b011, r_cm_data[4], 1'b1, r_cm_data[2:0]};
                    0: w_cm_data <= 8'b01101000;
                    1: w_cm_data <= {3'b011, r_cm_data[4], 1'b0, r_cm_data[2:0]};
                    2: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b1, r_cm_data[1:0]};
                    3: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b0, r_cm_data[1:0]};
                    4: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b1, r_cm_data[0]};
                    5: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b0, r_cm_data[0]};
                    6: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b1};
                    7: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b0};
                endcase
            end else begin
                case(replace)
                    0: w_cm_data <= {3'b011, r_cm_data[4], 1'b1, r_cm_data[2:0]};
                    1: w_cm_data <= {3'b011, r_cm_data[4], 1'b0, r_cm_data[2:0]};
                    2: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b1, r_cm_data[1:0]};
                    3: w_cm_data <= {3'b010, r_cm_data[4:3], 1'b0, r_cm_data[1:0]};
                    4: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b1, r_cm_data[0]};
                    5: w_cm_data <= {2'b00, r_cm_data[5], 1'b1, r_cm_data[3:2], 1'b0, r_cm_data[0]};
                    6: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b1};
                    7: w_cm_data <= {2'b00, r_cm_data[5], 1'b0, r_cm_data[3:1], 1'b0};
                endcase
            end
        end else if(current_config == 4'b0001) begin
            if(hit) begin
                w_cm_data <= (r_cm_data[1:0] == hit_num) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                             (r_cm_data[3:2] == hit_num) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                             (r_cm_data[5:4] == hit_num) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;
            end else if(!(&valid)) begin
                if(!valid[0]) w_cm_data <= 8'b00111001;
                else begin
                    w_cm_data <= (r_cm_data[1:0] == invalid_num) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                                 (r_cm_data[3:2] == invalid_num) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                                 (r_cm_data[5:4] == invalid_num) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;
                end
            end else begin
                w_cm_data <= {r_cm_data[1:0], r_cm_data[7:2]};
            end
        end else if(current_config == 4'b0010) begin
            if(hit) begin
                w_cm_data <= (r_cm_data[1:0] == hit_num) ? {r_cm_data[7:4], r_cm_data[1:0], r_cm_data[3:2]} : r_cm_data;
            end else if(!(&valid)) begin
                if(!valid[0]) w_cm_data <= 8'b11100001;
                else begin
                    w_cm_data <= (r_cm_data[1:0] == invalid_num) ? {r_cm_data[7:4], r_cm_data[1:0], r_cm_data[3:2]} : r_cm_data;
                end
            end else begin
                w_cm_data <= {r_cm_data[7:4], r_cm_data[1:0], r_cm_data[3:2]};
            end
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            o_p_readdata_valid <= 0;
            {o_m_read, o_m_write} <= 0;
            o_m_addr <= 0;
            write_addr_buf <= 0;
            byte_en_buf <= 0;
            writedata_buf <= 0;
            {write_buf, read_buf} <= 0;
            write_set <= 0;
            fetch_write <= 0;
            flash                 <= 0;
            phase                 <= 0;
            flash_cnt             <= 0;
            current_config        <= 0; // default cache config is 4way
            w_cm <= 0;
            {cnt_r, cnt_w} <= 0;
            {cnt_hit_r, cnt_hit_w} <= 0;
            {cnt_wb_r, cnt_wb_w} <= 0;
            state <= IDLE;
        end
        else begin
            case (state)
                IDLE: begin
                    write_set <= 0;
                    o_p_readdata_valid <= 0;
                    writedata_buf <= {i_p_writedata, i_p_writedata, i_p_writedata, i_p_writedata};
                    write_addr_buf <= i_p_addr;
                    byte_en_buf <= i_p_byte_en;
                    write_buf <= i_p_write;
                    read_buf <= i_p_read;
                    if(i_p_read) begin
                        state <= COMP;
                        cnt_r <= cnt_r + 1;
                    end else if(i_p_write) begin
                        state <= COMP;
                        cnt_w <= cnt_w + 1;
                    end else if(change) begin
                        state <= FLASH;
                        flash <= 2'b10;
                        phase <= 0;
                    end
                end
                COMP: begin
                    if((|hit) && write_buf) begin
                        state <= HIT;
                        w_cm <= 1;
                        write_set <= hit;
                        cnt_hit_w <= cnt_hit_w + 1;
                    end else if((|hit) && read_buf) begin
                        state <= IDLE;
                        w_cm <= 1;
                        o_p_readdata_valid <= 1;
                        cnt_hit_r <= cnt_hit_r + 1;
                        case(write_addr_buf[1:0])
                            2'b00: begin
                                o_p_readdata <= (hit[0]) ? readdata0[31:0] : 
                                                (hit[1]) ? readdata1[31:0] : 
                                                (hit[2]) ? readdata2[31:0] : 
                                                (hit[3]) ? readdata3[31:0] : 
                                                (hit[4]) ? readdata4[31:0] : 
                                                (hit[5]) ? readdata5[31:0] : 
                                                (hit[6]) ? readdata6[31:0] : readdata7[31:0];
                            end
                            2'b01: begin
                                o_p_readdata <= (hit[0]) ? readdata0[63:32] : 
                                                (hit[1]) ? readdata1[63:32] : 
                                                (hit[2]) ? readdata2[63:32] : 
                                                (hit[3]) ? readdata3[63:32] : 
                                                (hit[4]) ? readdata4[63:32] : 
                                                (hit[5]) ? readdata5[63:32] : 
                                                (hit[6]) ? readdata6[63:32] : readdata7[63:32];
                            end
                            2'b10: begin
                                o_p_readdata <= (hit[0]) ? readdata0[95:64] : 
                                                (hit[1]) ? readdata1[95:64] : 
                                                (hit[2]) ? readdata2[95:64] : 
                                                (hit[3]) ? readdata3[95:64] : 
                                                (hit[4]) ? readdata4[95:64] : 
                                                (hit[5]) ? readdata5[95:64] : 
                                                (hit[6]) ? readdata6[95:64] : readdata7[95:64];
                            end
                            2'b11: begin
                                o_p_readdata <= (hit[0]) ? readdata0[127:96] : 
                                                (hit[1]) ? readdata1[127:96] : 
                                                (hit[2]) ? readdata2[127:96] :
                                                (hit[3]) ? readdata3[127:96] : 
                                                (hit[4]) ? readdata4[127:96] : 
                                                (hit[5]) ? readdata5[127:96] : 
                                                (hit[6]) ? readdata6[127:96] : readdata7[127:96];
                            end
                        endcase
                    end else if(!(&valid)) begin
                        state <= FETCH1;
                        w_cm <= 1;
                        o_m_addr <= {write_addr_buf[24:2], 3'b000};
                        o_m_read <= 1;
                        case(invalid_num)
                            0: fetch_write <= 8'b00000001;
                            1: fetch_write <= 8'b00000010;
                            2: fetch_write <= 8'b00000100;
                            3: fetch_write <= 8'b00001000;
                            4: fetch_write <= 8'b00010000;
                            5: fetch_write <= 8'b00100000;
                            6: fetch_write <= 8'b01000000;
                            7: fetch_write <= 8'b10000000;
                        endcase 
                    end else if(miss[replace]) begin
                        state <= FETCH1;
                        w_cm <= 1;
                        o_m_addr <= {write_addr_buf[24:2], 3'b000};
                        o_m_read <= 1;
                        case(replace)
                            0: fetch_write <= 8'b00000001;
                            1: fetch_write <= 8'b00000010;
                            2: fetch_write <= 8'b00000100;
                            3: fetch_write <= 8'b00001000;
                            4: fetch_write <= 8'b00010000;
                            5: fetch_write <= 8'b00100000;
                            6: fetch_write <= 8'b01000000;
                            7: fetch_write <= 8'b10000000;
                        endcase 
                    end else begin
                        state <= WB1;
                        w_cm <= 1;
                        case(replace)
                            0: fetch_write <= 8'b00000001;
                            1: fetch_write <= 8'b00000010;
                            2: fetch_write <= 8'b00000100;
                            3: fetch_write <= 8'b00001000;
                            4: fetch_write <= 8'b00010000;
                            5: fetch_write <= 8'b00100000;
                            6: fetch_write <= 8'b01000000;
                            7: fetch_write <= 8'b10000000;
                        endcase 
                        if(read_buf) cnt_wb_r <= cnt_wb_r + 1;
                        else if(write_buf) cnt_wb_w <= cnt_wb_w + 1;
                    end
                end
                HIT: begin
                    w_cm <= 0;
                    write_set <= 0;
                    state <= IDLE;
                end
                FETCH1: begin
                    w_cm <= 0;
                    if(!i_m_waitrequest) begin
                        o_m_read <= 0;
                        state <= FETCH2;
                    end
                end
                FETCH2: begin
                    if(i_m_readdata_valid) begin
                        fetch_write <= 0;            //add 3/9
                        if(write_buf) begin
                            state <= FETCH3;
                            write_set <= fetch_write;
		                end else if(read_buf) begin
                            state <= IDLE;
		                    o_p_readdata_valid <= 1;
		                    case(write_addr_buf[1:0])
		                        2'b00: o_p_readdata <= i_m_readdata[ 31: 0];
		                        2'b01: o_p_readdata <= i_m_readdata[ 63:32];
		                        2'b10: o_p_readdata <= i_m_readdata[ 95:64];
		                        2'b11: o_p_readdata <= i_m_readdata[127:96];
		                    endcase
		                end
                    end
                end
                FETCH3: begin
                    state <= IDLE;
                    write_set <= 0;
                end
                WB1: begin
                    w_cm <= 0;
                    o_m_addr <= (fetch_write[0]) ? {wb_addr0, 3'b000} :
                                (fetch_write[1]) ? {wb_addr1, 3'b000} :
                                (fetch_write[2]) ? {wb_addr2, 3'b000} :
                                (fetch_write[3]) ? {wb_addr3, 3'b000} :
                                (fetch_write[4]) ? {wb_addr4, 3'b000} :
                                (fetch_write[5]) ? {wb_addr5, 3'b000} :
                                (fetch_write[6]) ? {wb_addr6, 3'b000} : {wb_addr7, 3'b000};
                    o_m_writedata <= (fetch_write[0]) ? readdata0 : 
                                     (fetch_write[1]) ? readdata1 : 
                                     (fetch_write[2]) ? readdata2 : 
                                     (fetch_write[3]) ? readdata3 : 
                                     (fetch_write[4]) ? readdata4 :
                                     (fetch_write[5]) ? readdata5 : 
                                     (fetch_write[6]) ? readdata6 : readdata7;
                    o_m_write <= 1;
                    state <= WB2;
                end
                WB2: begin
                    if(!i_m_waitrequest) begin
                        o_m_write <= 0;
                        o_m_addr <= {write_addr_buf[24:2], 3'b000};
                        o_m_read <= 1;
                        state <= FETCH1;
                    end
                end
                FLASH: begin
                    if(!i_m_waitrequest) begin
                        if(flash_cnt[cache_entry] && !change) begin
                            state          <= IDLE;
                            flash          <= 0;
                            o_m_write      <= 0;
                            flash_cnt      <= 0;
                            current_config <= cache_config;
                        end else if(flash_cnt[cache_entry]) begin
                            flash <= 0;
                            o_m_write <= 0;
                        end else begin
                            phase <= (phase == 10) ? 0 : phase + 1;
                            case(phase)
                                0: o_m_write <= 0;
                                1: begin
                                    if(dirty[0]) begin
                                        o_m_addr <= {wb_addr0, 3'b000};
                                        o_m_writedata <= readdata0;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                2: begin
                                    if(dirty[1]) begin
                                        o_m_addr <= {wb_addr1, 3'b000};
                                        o_m_writedata <= readdata1;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                3: begin
                                    if(dirty[2]) begin
                                        o_m_addr <= {wb_addr2, 3'b000};
                                        o_m_writedata <= readdata2;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                4: begin
                                    if(dirty[3]) begin
                                        o_m_addr <= {wb_addr3, 3'b000};
                                        o_m_writedata <= readdata3;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                5: begin
                                    if(dirty[4]) begin
                                        o_m_addr <= {wb_addr4, 3'b000};
                                        o_m_writedata <= readdata0;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                6: begin
                                    if(dirty[5]) begin
                                        o_m_addr <= {wb_addr5, 3'b000};
                                        o_m_writedata <= readdata1;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                7: begin
                                    if(dirty[6]) begin
                                        o_m_addr <= {wb_addr6, 3'b000};
                                        o_m_writedata <= readdata2;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                8: begin
                                    if(dirty[7]) begin
                                        o_m_addr <= {wb_addr7, 3'b000};
                                        o_m_writedata <= readdata3;
                                        o_m_write <= 1;
                                    end else begin
                                        o_m_write <= 0;
                                    end
                                end
                                9: begin
                                    o_m_write <= 0;
                                    flash     <= 2'b11;
                                end
                                10: begin
                                    flash     <= 2'b10;
                                    flash_cnt <= flash_cnt + 1;
                                end
                            endcase
                        end
                    end
                end
            endcase // case (state)
        end
    end

endmodule // cache

module config_ctrl(clk,
                   rst,
                   entry,
                   o_tag,
                   writedata,
                   byte_en,
                   word_en,
                   write,
                   readdata0,
                   readdata1,
                   readdata2,
                   readdata3,
                   readdata4,
                   readdata5,
                   readdata6,
                   readdata7,
                   wb_addr0,
                   wb_addr1,
                   wb_addr2,
                   wb_addr3,
                   wb_addr4,
                   wb_addr5,
                   wb_addr6,
                   wb_addr7,
                   hit,
                   miss,
                   dirty,
                   valid,
                   read_miss,
                   flash,
                   c_fig);

    parameter cache_entry = 14;
    
    input wire                    clk, rst;
    input wire [cache_entry-1:0]  entry;
    input wire [22-cache_entry:0] o_tag;
    input wire [127:0] 		      writedata;
    input wire [3:0] 		      byte_en;
    input wire [3:0]              word_en;
    input wire [7:0]   	          write;
    input wire 			          read_miss;
    input wire [1:0]	          flash;
    input wire [3:0]              c_fig;       

    output wire [127:0] 		  readdata0, readdata1, readdata2, readdata3;
    output wire [127:0] 		  readdata4, readdata5, readdata6, readdata7;
    output wire [22:0] 		      wb_addr0, wb_addr1, wb_addr2, wb_addr3;
    output wire [22:0] 		      wb_addr4, wb_addr5, wb_addr6, wb_addr7;
    output wire [7:0]    	      hit, miss, dirty, valid;

    wire [7:0] s_hit;
    wire [7:0] s_miss;
    wire [7:0] s_dirty;
    wire [7:0] s_valid;

    wire [127:0]     		  s_readdata0, s_readdata1, s_readdata2, s_readdata3;
    wire [127:0]     		  s_readdata4, s_readdata5, s_readdata6, s_readdata7;
    wire [22:0] 		      s_wb_addr0, s_wb_addr1, s_wb_addr2, s_wb_addr3;
    wire [22:0] 		      s_wb_addr4, s_wb_addr5, s_wb_addr6, s_wb_addr7;

    assign hit = (c_fig == 0) ? s_hit : 
                 (c_fig == 4'b0001) ? ((o_tag[0]) ? {4'b0000, s_hit[7], s_hit[5], s_hit[3], s_hit[1]} : 
                                                    {4'b0000, s_hit[6], s_hit[4], s_hit[2], s_hit[0]}) :
                 (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? {6'b000000, s_hit[4], s_hit[0]} :
                                       (o_tag[1:0] == 2'b01) ? {6'b000000, s_hit[5], s_hit[1]} :
                                       (o_tag[1:0] == 2'b10) ? {6'b000000, s_hit[6], s_hit[2]} : 
                                                               {6'b000000, s_hit[7], s_hit[3]}) : 8'b00000000;
    assign miss = (c_fig == 0) ? s_miss : 
                 (c_fig == 4'b0001) ? ((o_tag[0]) ? {4'b0000, s_miss[7], s_miss[5], s_miss[3], s_miss[1]} : 
                                                    {4'b0000, s_miss[6], s_miss[4], s_miss[2], s_miss[0]}) :
                 (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? {6'b000000, s_miss[4], s_miss[0]} :
                                       (o_tag[1:0] == 2'b01) ? {6'b000000, s_miss[5], s_miss[1]} :
                                       (o_tag[1:0] == 2'b10) ? {6'b000000, s_miss[6], s_miss[2]} : 
                                                                 {6'b000000, s_miss[7], s_miss[3]}) : 8'b00000000;
    assign dirty = s_dirty;
    assign valid = (c_fig == 0) ? s_valid : 
                 (c_fig == 4'b0001) ? ((o_tag[0]) ? {4'b1111, s_valid[7], s_valid[5], s_valid[3], s_valid[1]} : 
                                                    {4'b1111, s_valid[6], s_valid[4], s_valid[2], s_valid[0]}) :
                 (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? {6'b111111, s_valid[4], s_valid[0]} :
                                       (o_tag[1:0] == 2'b01) ? {6'b111111, s_valid[5], s_valid[1]} :
                                       (o_tag[1:0] == 2'b10) ? {6'b111111, s_valid[6], s_valid[2]} : 
                                                               {6'b111111, s_valid[7], s_valid[3]}) : 8'b00000000;
    assign readdata0 = ((c_fig == 0) || flash[1]) ? s_readdata0 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_readdata1 : s_readdata0) :
                       (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? s_readdata0 :
                                             (o_tag[1:0] == 2'b01) ? s_readdata1 :
                                             (o_tag[1:0] == 2'b10) ? s_readdata2 : s_readdata3) : s_readdata0;
    assign readdata1 = ((c_fig == 0) || flash[1]) ? s_readdata1 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_readdata3 : s_readdata2) :
                       (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? s_readdata4 :
                                             (o_tag[1:0] == 2'b01) ? s_readdata5 :
                                             (o_tag[1:0] == 2'b10) ? s_readdata6 : s_readdata7) : s_readdata1;
    assign readdata2 = ((c_fig == 0) || flash[1]) ? s_readdata2 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_readdata5 : s_readdata4) : readdata2;
    assign readdata3 = ((c_fig == 0) || flash[1]) ? s_readdata3 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_readdata7 : s_readdata6) : readdata3;
    assign readdata4 = s_readdata4;
    assign readdata5 = s_readdata5;
    assign readdata6 = s_readdata6;
    assign readdata7 = s_readdata7;

    assign wb_addr0 = ((c_fig == 0) || flash[1]) ? s_wb_addr0 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_wb_addr1 : s_wb_addr0) :
                       (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? s_wb_addr0 :
                                             (o_tag[1:0] == 2'b01) ? s_wb_addr1 :
                                             (o_tag[1:0] == 2'b10) ? s_wb_addr2 : s_wb_addr3) : s_wb_addr0;
    assign wb_addr1 = ((c_fig == 0) || flash[1]) ? s_wb_addr1 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_wb_addr3 : s_wb_addr2) :
                       (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? s_wb_addr4 :
                                             (o_tag[1:0] == 2'b01) ? s_wb_addr5 :
                                             (o_tag[1:0] == 2'b10) ? s_wb_addr6 : s_wb_addr7) : s_wb_addr1;
    assign wb_addr2 = ((c_fig == 0) || flash[1]) ? s_wb_addr2 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_wb_addr5 : s_wb_addr4) : wb_addr2;
    assign wb_addr3 = ((c_fig == 0) || flash[1]) ? s_wb_addr3 :
                       (c_fig == 4'b0001) ? ((o_tag[0]) ? s_wb_addr7 : s_wb_addr6) : wb_addr3;
    assign wb_addr4 = s_wb_addr4;
    assign wb_addr5 = s_wb_addr5;
    assign wb_addr6 = s_wb_addr6;
    assign wb_addr7 = s_wb_addr7;

    wire [7:0] s_write;
    assign s_write = (c_fig == 0) ? write :
                     (c_fig == 4'b0001) ? ((o_tag[0]) ? {write[3], 1'b0, write[2], 1'b0, write[1], 1'b0, write[0], 1'b0} :
                                                       {1'b0, write[3], 1'b0, write[2], 1'b0, write[1], 1'b0, write[0]}) :
                     (c_fig == 4'b0010) ? ((o_tag[1:0] == 2'b00) ? {3'b000, write[1], 3'b000, write[0]} :
                                           (o_tag[1:0] == 2'b01) ? {2'b00, write[1], 3'b000, write[0], 1'b0} :
                                           (o_tag[1:0] == 2'b10) ? {1'b0, write[1], 3'b000, write[0], 2'b00} : {write[1], 3'b000, write[0], 3'b000}) : 8'b00000000;

    set #(.cache_entry(cache_entry))
    set0(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[0]),
         .readdata(s_readdata0),
         .wb_addr(s_wb_addr0),
         .hit(s_hit[0]),
         .miss(s_miss[0]),
         .dirty(s_dirty[0]),
         .valid(s_valid[0]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set1(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[1]),
         .readdata(s_readdata1),
         .wb_addr(s_wb_addr1),
         .hit(s_hit[1]),
         .miss(s_miss[1]),
         .dirty(s_dirty[1]),
         .valid(s_valid[1]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set2(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[2]),
         .readdata(s_readdata2),
         .wb_addr(s_wb_addr2),
         .hit(s_hit[2]),
         .miss(s_miss[2]),
         .dirty(s_dirty[2]),
         .valid(s_valid[2]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set3(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[3]),
         .readdata(s_readdata3),
         .wb_addr(s_wb_addr3),
         .hit(s_hit[3]),
         .miss(s_miss[3]),
         .dirty(s_dirty[3]),
         .valid(s_valid[3]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set4(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[4]),
         .readdata(s_readdata4),
         .wb_addr(s_wb_addr4),
         .hit(s_hit[4]),
         .miss(s_miss[4]),
         .dirty(s_dirty[4]),
         .valid(s_valid[4]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set5(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[5]),
         .readdata(s_readdata5),
         .wb_addr(s_wb_addr5),
         .hit(s_hit[5]),
         .miss(s_miss[5]),
         .dirty(s_dirty[5]),
         .valid(s_valid[5]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set6(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[6]),
         .readdata(s_readdata6),
         .wb_addr(s_wb_addr6),
         .hit(s_hit[6]),
         .miss(s_miss[6]),
         .dirty(s_dirty[6]),
         .valid(s_valid[6]),
         .read_miss(read_miss),
         .flash(flash[0]));

    set #(.cache_entry(cache_entry))
    set7(.clk(clk),
         .rst(rst),
         .entry(entry),
         .o_tag(o_tag),
         .writedata(writedata),
         .byte_en(byte_en),
         .word_en(word_en), // 4word r/w change 
         .write(s_write[7]),
         .readdata(s_readdata7),
         .wb_addr(s_wb_addr7),
         .hit(s_hit[7]),
         .miss(s_miss[7]),
         .dirty(s_dirty[7]),
         .valid(s_valid[7]),
         .read_miss(read_miss),
         .flash(flash[0]));


endmodule // config_ctrl

module set(clk,
           rst,
           entry,
           o_tag,
           writedata,
           byte_en,
           write,
           word_en,

           readdata,
           wb_addr,
           hit,
           miss,
           dirty,
           valid,
           read_miss,
           flash);

    parameter cache_entry = 14;

    input wire                    clk, rst;
    input wire [cache_entry-1:0]  entry;
    input wire [22-cache_entry:0] o_tag;
    input wire [127:0] 		      writedata;
    input wire [3:0] 		      byte_en;
    input wire       	          write;
    input wire [3:0]              word_en;
    input wire 			          read_miss;
    input wire                    flash;

    output wire [127:0] 		  readdata;
    output wire [22:0] 		      wb_addr;
    output wire 			      hit, miss, dirty, valid;



    wire [22-cache_entry:0] 	 i_tag;
    wire 			             modify;
    wire [24-cache_entry:0] 	 write_tag_data;

    assign hit = valid && (o_tag == i_tag);
    assign modify = valid && (o_tag != i_tag) && dirty;
    assign miss = !valid || ((o_tag != i_tag) && !dirty);

    assign wb_addr = {i_tag, entry};

    //write -> [3:0] write, writedata/readdata 32bit -> 128bit
    simple_ram #(.width(8), .widthad(cache_entry)) ram11_3(clk, entry, write && word_en[3]  && byte_en[3], writedata[127:120], entry, readdata[127:120]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram11_2(clk, entry, write && word_en[3]  && byte_en[2], writedata[119:112], entry, readdata[119:112]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram11_1(clk, entry, write && word_en[3]  && byte_en[1], writedata[111:104], entry, readdata[111:104]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram11_0(clk, entry, write && word_en[3]  && byte_en[0], writedata[103:96], entry, readdata[103:96]);

    simple_ram #(.width(8), .widthad(cache_entry)) ram10_3(clk, entry, write && word_en[2]  && byte_en[3], writedata[95:88], entry, readdata[95:88]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram10_2(clk, entry, write && word_en[2]  && byte_en[2], writedata[87:80], entry, readdata[87:80]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram10_1(clk, entry, write && word_en[2]  && byte_en[1], writedata[79:72], entry, readdata[79:72]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram10_0(clk, entry, write && word_en[2]  && byte_en[0], writedata[71:64], entry, readdata[71:64]);

    simple_ram #(.width(8), .widthad(cache_entry)) ram01_3(clk, entry, write && word_en[1]  && byte_en[3], writedata[63:56], entry, readdata[63:56]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram01_2(clk, entry, write && word_en[1]  && byte_en[2], writedata[55:48], entry, readdata[55:48]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram01_1(clk, entry, write && word_en[1]  && byte_en[1], writedata[47:40], entry, readdata[47:40]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram01_0(clk, entry, write && word_en[1]  && byte_en[0], writedata[39:32], entry, readdata[39:32]);

    simple_ram #(.width(8), .widthad(cache_entry)) ram00_3(clk, entry, write && word_en[0]  && byte_en[3], writedata[31:24], entry, readdata[31:24]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram00_2(clk, entry, write && word_en[0]  && byte_en[2], writedata[23:16], entry, readdata[23:16]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram00_1(clk, entry, write && word_en[0]  && byte_en[1], writedata[15: 8], entry, readdata[15:8]);
    simple_ram #(.width(8), .widthad(cache_entry)) ram00_0(clk, entry, write && word_en[0]  && byte_en[0], writedata[ 7: 0], entry, readdata[ 7:0]);

    assign write_tag_data = (flash) ? {1'b0, 1'b0, i_tag} :
                            (read_miss) ? {1'b0, 1'b1, o_tag} : 
                            (modify || miss ) ? {1'b1, 1'b1, o_tag} : {1'b1, 1'b1, i_tag};
//    assign write_tag_data = (read_miss) ? {1'b0, 1'b1, o_tag} : (modify || miss ) ? {1'b1, 1'b1, o_tag} : {1'b1, 1'b1, i_tag};
    simple_ram #(.width(25-cache_entry), .widthad(cache_entry)) ram_tag(clk, entry, (write || flash), write_tag_data, entry, {dirty, valid, i_tag});

`ifdef SIM
    integer i;

    initial begin
        for(i = 0; i <=(2**cache_entry-1); i=i+1) begin
	        ram_tag.mem[i] = 0;
        end
    end
`endif

endmodule
