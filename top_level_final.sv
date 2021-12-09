`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// David Li and William Luo 
// 6.111 Fall 2021 Final Project Team 11
// Acoustic Levitator
// Top level file that integrates all modules
//////////////////////////////////////////////////////////////////////////////////

module top_level(
    //Inputs
    input wire clk_100mhz,
    input wire [15:0] sw,
    input wire btnc, btnu, btnd,
    input wire [7:0] jc, //pixel data from camera
    input wire [2:0] jd, //other data from camera (including clock return)
    //Outputs
    output logic [3:0] ja, //drives ultrasound transducers
    output logic jdclk, //clock FPGA drives the camera with,
    output logic [3:0] vga_r,
    output logic [3:0] vga_b,
    output logic [3:0] vga_g,
    output logic vga_hs,
    output logic vga_vs,
    output logic led16_b, led16_g, led16_r,
    output logic led17_b, led17_g, led17_r,
    output logic [15:0] led,
    output logic ca, cb, cc, cd, ce, cf, cg, dp,  // segments a-g, dp
    output logic [7:0] an    // Display location 0-7
    );
    
   /*
   Setup
   */
   
    // Create clocks for VGA and Ultrasound
    logic clk_65mhz;
    logic also_100mhz;
    clk_wiz_0 clkdivider(.clk_in1(clk_100mhz),.clk_out1(also_100mhz), .clk_out2(clk_65mhz));
    
    // Handle all button inputs to the system by debouncing and rising edge
    wire reset, up, rising_up, down, rising_down;
    debounce db_reset(.reset_in(reset),.clock_in(also_100mhz),.noisy_in(btnc),.clean_out(reset));
    debounce db_up(.reset_in(reset),.clock_in(also_100mhz),.noisy_in(btnu),.clean_out(up));
    rising_edge rise_up(.reset_in(reset), .clock_in(also_100mhz), .clean_in(up), .rising_out(rising_up));
    debounce db_down(.reset_in(reset),.clock_in(also_100mhz),.noisy_in(btnd),.clean_out(down));
    rising_edge rise_down(.reset_in(reset), .clock_in(also_100mhz), .clean_in(down), .rising_out(rising_down));
    
    // Instantiate things used for VGA output
    wire [10:0] hcount;    // pixel on current line
    wire [9:0] vcount;     // line number
    wire hsync, vsync, blank;
    reg [11:0] rgb;
    xvga xvga1(.vclock_in(clk_65mhz),.hcount_out(hcount),.vcount_out(vcount),
               .hsync_out(hsync),.vsync_out(vsync),.blank_out(blank));

    /*
    Camera and BRAM
    */

    logic xclk;
    logic[1:0] xclk_count;
    
    logic pclk_buff, pclk_in;
    logic vsync_buff, vsync_in;
    logic href_buff, href_in;
    logic[7:0] pixel_buff, pixel_in;
    
    logic [11:0] cam;
    logic [11:0] frame_buff_out;
    logic [15:0] output_pixels;
    logic [15:0] old_output_pixels;
    logic [12:0] processed_pixels;
    logic valid_pixel;
    logic frame_done_out;
    
    logic [16:0] pixel_addr_in;
    
    assign xclk = (xclk_count >2'b01);
    assign jdclk = xclk;

    blk_mem_gen_0 camera_bram(.addra(pixel_addr_in), 
                             .clka(pclk_in),
                             .dina(processed_pixels),
                             .wea(valid_pixel),
                             .addrb(pixel_addr_out),
                             .clkb(clk_65mhz),
                             .doutb(frame_buff_out));
    
    always_ff @(posedge pclk_in)begin
        if (frame_done_out)begin
            pixel_addr_in <= 17'b0;  
        end else if (valid_pixel)begin
            pixel_addr_in <= pixel_addr_in +1;  
        end
    end
    
    always_ff @(posedge clk_65mhz) begin
        pclk_buff <= jd[0];
        vsync_buff <= jd[1];
        href_buff <= jd[2];
        pixel_buff <= jc;
        pclk_in <= pclk_buff;
        vsync_in <= vsync_buff;
        href_in <= href_buff;
        pixel_in <= pixel_buff;
        old_output_pixels <= output_pixels;
        xclk_count <= xclk_count + 2'b01;
        processed_pixels = {output_pixels[15:12],output_pixels[10:7],output_pixels[4:1]};
    end
                                        
    camera_read  my_camera(.p_clock_in(pclk_in),
                           .vsync_in(vsync_in),
                           .href_in(href_in),
                           .p_data_in(pixel_in),
                           .pixel_data_out(output_pixels),
                           .pixel_valid_out(valid_pixel),
                           .frame_done_out(frame_done_out));
   
    logic [16:0] pixel_addr_out;
    assign cam = ((hcount<640) &&  (vcount<480)) ? frame_buff_out:12'h000;
    assign pixel_addr_out = ((hcount>>1)+(vcount>>1)*32'd320);
    
    /*
    Computer Vision Pipeline
    */

    localparam ZEROS = 4'b0000;
    logic [8:0] hue_rgb, hue_filter;
    logic [7:0] sat_rgb, val_rgb, sat_filter, val_filter;
    logic [10:0] hpos_rgb, hpos_filter;
    logic [9:0] vpos_rgb, vpos_filter;
    logic passed_hsv_filter;
    
    rgb2hsv rgbconv (
        .clock_in(clk_65mhz), 
        .r_in({rgb[11:8], ZEROS}), 
        .g_in({rgb[7:4], ZEROS}), 
        .b_in({rgb[3:0], ZEROS}),
	    .hor_pos_in(hcount),
	    .ver_pos_in(vcount),
	    .hue_out(hue_rgb),
        .sat_out(sat_rgb),
        .val_out(val_rgb),
	    .hor_pos_out(hpos_rgb),
	    .ver_pos_out(vpos_rgb));

    localparam H_LO = 9'd160;// H used to be 200 to 260 for messenger filter
    localparam H_HI = 9'd360;
    localparam S_LO = 8'd30;
    localparam S_HI = 8'd100;
    localparam V_LO = 8'd30;
    localparam V_HI = 8'd100;

    hsv_filter #(.H_LO(H_LO), .H_HI(H_HI),
        .S_LO(S_LO), .S_HI(S_HI),
        .V_LO(V_LO), .V_HI(V_HI)) hsvfilter
        (
        .clock_in(clk_65mhz),
        .h_in(hue_rgb), .s_in(sat_rgb), .v_in(val_rgb),
        .hor_pos_in(hpos_rgb),
        .ver_pos_in(vpos_rgb),
        .h_out(hue_filter), .s_out(sat_filter), .v_out(val_filter),
        .hor_pos_out(hpos_filter), .ver_pos_out(vpos_filter),
        .passed_hsv_filter_out(passed_hsv_filter)
    );

    logic weighted_average_started, weighted_average_done, weighted_average_ready_h, weighted_average_ready_v;
    logic [10:0] ball_h_avg_pos, target_h_avg_pos, ball_avg_radius, target_avg_radius;
    logic [9:0] ball_v_avg_pos, target_v_avg_pos;

    assign weighted_average_done = (hcount == 0) && (vcount == 0);
    
    logic passed_hsv_filter_and_in_bounds, target_passed_hsv_and_in_bounds;
    assign passed_hsv_filter_and_in_bounds = passed_hsv_filter && (hcount>=20 && hcount<=319) && (vcount>=50 && vcount<=400);
    assign target_passed_hsv_and_in_bounds = passed_hsv_filter && (hcount>=320 && hcount<=639) && (vcount>=50 && vcount<=400);

    
    // for the levitated ball:
    weighted_average #(.POS_BITS(11)) wa_h (
        .clock_in(clk_65mhz), .reset_in(reset),
        .start_in(weighted_average_started), .done_in(weighted_average_done),
        .pos_in(hpos_filter),         // index on the horizontal axis
        .passed_hsv_filter_in(passed_hsv_filter_and_in_bounds),            // whether or not this pixel passed the filter
        .ready_out(weighted_average_ready_h),
        .avg_out(ball_h_avg_pos),      // the weighted average
        .avg_radius(ball_avg_radius)
    );

    weighted_average #(.POS_BITS(10)) wa_v (
        .clock_in(clk_65mhz), .reset_in(reset),
        .start_in(weighted_average_started), .done_in(weighted_average_done),
        .pos_in(vpos_filter),         // index on the horizontal axis
        .passed_hsv_filter_in(passed_hsv_filter_and_in_bounds),            // whether or not this pixel passed the filter
        .ready_out(weighted_average_ready_v),
        .avg_out(ball_v_avg_pos),      // the weighted average
        .avg_radius()
    );
    
    // for the target ball:
    weighted_average #(.POS_BITS(11)) target_wa_h (
        .clock_in(clk_65mhz), .reset_in(reset),
        .start_in(weighted_average_started), .done_in(weighted_average_done),
        .pos_in(hpos_filter),         // index on the horizontal axis
        .passed_hsv_filter_in(target_passed_hsv_and_in_bounds),            // whether or not this pixel passed the filter
        .ready_out(), // william comment: we don't need this output because it should be the same for both of the balls!
        .avg_out(target_h_avg_pos),      // the weighted average
        .avg_radius(target_avg_radius)
    );

    weighted_average #(.POS_BITS(10)) target_wa_v (
        .clock_in(clk_65mhz), .reset_in(reset),
        .start_in(weighted_average_started), .done_in(weighted_average_done),
        .pos_in(vpos_filter),         // index on the horizontal axis
        .passed_hsv_filter_in(target_passed_hsv_and_in_bounds),            // whether or not this pixel passed the filter
        .ready_out(), // william comment: we don't need this output because it should be the same for both of the balls!
        .avg_out(target_v_avg_pos),      // the weighted average
        .avg_radius()
    );
    
    /*
    Outputs
    */
    
    // Ultrasound Stuff
    logic rising_average_started;
    rising_edge rise_average(.reset_in(reset), .clock_in(also_100mhz), .clean_in(weighted_average_started), .rising_out(rising_average_started));
    
    logic [10:0] phase1, phase2;
    ultrasound_controller main_control(.reset_in(reset), .clock_in(also_100mhz), .sw_in(sw),
                                       .up_in(rising_up), .down_in(rising_down), .start_in(rising_average_started),
                                       .target_y_in(target_v_avg_pos_wbb), .ball_y_in(ball_v_avg_pos_wbb),
                                       .phase1_out(phase1), .phase2_out(phase2));
    ultrasound_out (.reset_in(reset), .clock_in(also_100mhz), .phase1(phase1), .phase2(phase2), .output1(ja[2]), .output2(ja[0]));
    assign ja[1] = ~ja[0];
    assign ja[3] = ~ja[2];
    
    
    // Logic for computing what is being shown on VGA
    
    logic ball_bounded, target_bounded, virtual_bounded, within_virtual_circle;
    logic [10:0] ball_h_avg_pos_wbb, target_h_avg_pos_wbb;
    logic [9:0] ball_v_avg_pos_wbb, target_v_avg_pos_wbb;
    logic [10:0] ball_avg_radius_wbb, target_avg_radius_wbb;
    
    always_ff @(posedge clk_65mhz) begin
      if (reset || weighted_average_ready_h) begin
          weighted_average_started <= 1;
          ball_h_avg_pos_wbb <= ball_h_avg_pos;
          ball_v_avg_pos_wbb <= ball_v_avg_pos;
          target_h_avg_pos_wbb <= target_h_avg_pos;
          target_v_avg_pos_wbb <= target_v_avg_pos;
          if (sw[4] == 1) begin
              ball_avg_radius_wbb <= 11'd15;//(ball_avg_radius>>2 + ball_avg_radius >> 1 + ball_avg_radius_wbb>>2); //IIR Smoothing
              target_avg_radius_wbb <= 11'd15; //(target_avg_radius>>2 + target_avg_radius >> 1 + target_avg_radius_wbb>>2);
          end else begin
              ball_avg_radius_wbb <= ball_avg_radius;//(ball_avg_radius>>2 + ball_avg_radius >> 1 + ball_avg_radius_wbb>>2); //IIR Smoothing
              target_avg_radius_wbb <= target_avg_radius; //(target_avg_radius>>2 + target_avg_radius >> 1 + target_avg_radius_wbb>>2);
          end
      end else if (weighted_average_started) begin
          weighted_average_started <= 0;
      end
    end
    
    within_bounding_box wbb (.hcount_in(hcount), .vcount_in(vcount), 
        .h_center_in(ball_h_avg_pos_wbb), .v_center_in(ball_v_avg_pos_wbb),
        .radius_in(ball_avg_radius_wbb), .bounded_out(ball_bounded),
        .within_circle_out());
        
    within_bounding_box target_wbb (.hcount_in(hcount), .vcount_in(vcount), 
        .h_center_in(target_h_avg_pos_wbb), .v_center_in(target_v_avg_pos_wbb),
        .radius_in(target_avg_radius_wbb), .bounded_out(target_bounded),
        .within_circle_out());
    
    // for the virtual ball
    within_bounding_box virtual_wbb (.hcount_in(hcount), .vcount_in(vcount), 
        .h_center_in(11'd480), .v_center_in(ball_v_avg_pos_wbb),
        .radius_in(11'd35), .bounded_out(virtual_bounded),
        .within_circle_out(within_virtual_circle));
   
    // VGA Handling    
    logic phsync,pvsync,pblank,ball_bound,target_bound,virtual_bound;
    logic [11:0] pcam;
    sync_delay main_delay(.vclock_in(clk_65mhz),.reset_in(reset),
                .hsync_in(hsync),.vsync_in(vsync),.blank_in(blank), .cam_in(cam),
                .phsync_out(phsync),.pvsync_out(pvsync),.pblank_out(pblank), .cam_out(pcam),
                .ball_bounded_in(ball_bounded), .target_bounded_in(target_bounded), .virtual_bounded_in(within_virtual_circle),
                .ball_bounded_out(ball_bound), .target_bounded_out(target_bound), .virtual_bounded_out(virtual_bound)
                );
                
    logic border;
    assign border = (hcount==0 | hcount==1023 |
                     vcount==0 | vcount==767 |
                     hcount == 512 | vcount == 384);
    
    logic [11:0] rgb2;
    logic b, hs, vs;             
    always_ff @(posedge clk_65mhz) begin
      if (sw[0] == 1'b1) begin
         // 1 pixel outline of visible area (white)
         hs <= hsync;
         vs <= vsync;
         b <= blank;
         rgb <= {12{border}};
         rgb2 <= {12{border}};
      end else begin
         hs <= phsync;
         vs <= pvsync;
         b <= pblank;
         rgb <= cam; 
         if (sw[1] == 1'b1 && sw[2] == 1'b0 && sw[3] == 1'b0) begin
            // physical control mode
            rgb2 <= ball_bound ? 12'hF00 : (target_bound? 12'h00F : pcam);   
         end else if (sw[1] == 1'b1 && sw[2] == 1'b1 && sw[3] == 1'b0) begin
            // virtual control mode
            rgb2 <= ball_bound ? 12'hF00 : (virtual_bound? 12'h80F : pcam);
         end else if (sw[1] == 1'b1 && sw[2] == 1'b0 && sw[3] == 1'b1) begin
            // show pixels passing HSV filter mode, physical control
            rgb2 <= passed_hsv_filter ? 12'h0F0 : (ball_bound ? 12'hF00 : (target_bound? 12'h00F : pcam));
         end else if (sw[1] == 1'b1 && sw[2] == 1'b1 && sw[3] == 1'b1) begin
            // show pixels passing HSV filter mode, virtual control
            rgb2 <= passed_hsv_filter ? 12'h0F0 : (ball_bound ? 12'hF00 : (virtual_bound? 12'h80F: pcam));
         end else begin
            rgb2 <= pcam;
         end
      end
    end
    
    always_comb begin
     vga_r = ~b ? rgb2[11:8]: 0;
     vga_g = ~b ? rgb2[7:4] : 0;
     vga_b = ~b ? rgb2[3:0] : 0;
     vga_hs = ~hs;
     vga_vs = ~vs;
    end

    // Code for the 7-segment display, LEDs, and RGB LEDs.
    logic [31:0] data;      //  instantiate 7-segment display; display (8) 4-bit hex
    logic [6:0] segments;
    assign {cg, cf, ce, cd, cc, cb, ca} = segments[6:0];
    display_8hex display(.clk_in(clk_65mhz),.data_in(data), .seg_out(segments), .strobe_out(an));
    assign  dp = 1'b1;  // turn off the period
    
    always_comb begin
        if (sw[15:14] == 2'b00) begin
            // controller phases
            data[31:16] = phase1;
            data[15:0] = phase2;
        end else if (sw[15:14] == 2'b01) begin
            // controlled ball position
            data[31:16] = ball_h_avg_pos_wbb; // 4 hex are horizontal
            data[15:0] = ball_v_avg_pos_wbb; // 4 hex are vertical
        end else if (sw[15:14] == 2'b01) begin
            // target ball position
            data[31:16] = target_h_avg_pos_wbb; // 4 hex are horizontal
            data[15:0] = target_v_avg_pos_wbb; // 4 hex are vertical
        end else begin
            // target and controlled ball vertical position
            data[31:16] = ball_v_avg_pos_wbb; // 4 hex are controlled vertical
            data[15:0] = target_v_avg_pos_wbb; // 4 hex are target vertical
        end
    end
    
    always_comb begin
        // Code for led16/17rgb
        // In physical control mode reflects feedback control status
        // In virtual control mode reflects pushbutton status
        led16_r = (sw[1] == 1'b1 && sw[2] == 1'b0)?(target_v_avg_pos_wbb+2<ball_v_avg_pos_wbb):((sw[1] == 1'b1 && sw[2] == 1'b1)?up:1'b0);
        led17_r = (sw[1] == 1'b1 && sw[2] == 1'b0)?(target_v_avg_pos_wbb+2<ball_v_avg_pos_wbb):((sw[1] == 1'b1 && sw[2] == 1'b1)?up:1'b0);
        led16_g = (sw[1] == 1'b1 && sw[2] == 1'b0)?(target_v_avg_pos_wbb>ball_v_avg_pos_wbb+2):((sw[1] == 1'b1 && sw[2] == 1'b1)?reset:1'b0);
        led17_g = (sw[1] == 1'b1 && sw[2] == 1'b0)?(target_v_avg_pos_wbb>ball_v_avg_pos_wbb+2):((sw[1] == 1'b1 && sw[2] == 1'b1)?reset:1'b0);
        led16_b = (sw[1] == 1'b1 && sw[2] == 1'b0)?~((target_v_avg_pos_wbb+2<ball_v_avg_pos_wbb)|(target_v_avg_pos_wbb>ball_v_avg_pos_wbb+2)):((sw[1] == 1'b1 && sw[2] == 1'b1)?down:1'b0);
        led17_b = (sw[1] == 1'b1 && sw[2] == 1'b0)?~((target_v_avg_pos_wbb+2<ball_v_avg_pos_wbb)|(target_v_avg_pos_wbb>ball_v_avg_pos_wbb+2)):((sw[1] == 1'b1 && sw[2] == 1'b1)?down:1'b0);
    end
    
    // LEDs correspond to switch inputs
    assign led = sw;
endmodule
`default_nettype wire