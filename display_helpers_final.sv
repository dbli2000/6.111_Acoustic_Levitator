`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// Update: 8/8/2019 GH 
// Create Date: 10/02/2015 02:05:19 AM
// Module Name: xvga
//
// xvga: Generate VGA display signals (1024 x 768 @ 60Hz)
//
//                              ---- HORIZONTAL -----     ------VERTICAL -----
//                              Active                    Active
//                    Freq      Video   FP  Sync   BP      Video   FP  Sync  BP
//   640x480, 60Hz    25.175    640     16    96   48       480    11   2    31
//   800x600, 60Hz    40.000    800     40   128   88       600     1   4    23
//   1024x768, 60Hz   65.000    1024    24   136  160       768     3   6    29
//   1280x1024, 60Hz  108.00    1280    48   112  248       768     1   3    38
//   1280x720p 60Hz   75.25     1280    72    80  216       720     3   5    30
//   1920x1080 60Hz   148.5     1920    88    44  148      1080     4   5    36
//
// change the clock frequency, front porches, sync's, and back porches to create 
// other screen resolutions
////////////////////////////////////////////////////////////////////////////////

module xvga(input wire vclock_in,
            output reg [10:0] hcount_out,    // pixel number on current line
            output reg [9:0] vcount_out,     // line number
            output reg vsync_out, hsync_out,
            output reg blank_out);

   parameter DISPLAY_WIDTH  = 1024;      // display width
   parameter DISPLAY_HEIGHT = 768;       // number of lines

   parameter  H_FP = 24;                 // horizontal front porch
   parameter  H_SYNC_PULSE = 136;        // horizontal sync
   parameter  H_BP = 160;                // horizontal back porch

   parameter  V_FP = 3;                  // vertical front porch
   parameter  V_SYNC_PULSE = 6;          // vertical sync 
   parameter  V_BP = 29;                 // vertical back porch

   // horizontal: 1344 pixels total
   // display 1024 pixels per line
   reg hblank,vblank;
   wire hsyncon,hsyncoff,hreset,hblankon;
   assign hblankon = (hcount_out == (DISPLAY_WIDTH -1));    
   assign hsyncon = (hcount_out == (DISPLAY_WIDTH + H_FP - 1));  //1047
   assign hsyncoff = (hcount_out == (DISPLAY_WIDTH + H_FP + H_SYNC_PULSE - 1));  // 1183
   assign hreset = (hcount_out == (DISPLAY_WIDTH + H_FP + H_SYNC_PULSE + H_BP - 1));  //1343

   // vertical: 806 lines total
   // display 768 lines
   wire vsyncon,vsyncoff,vreset,vblankon;
   assign vblankon = hreset & (vcount_out == (DISPLAY_HEIGHT - 1));   // 767 
   assign vsyncon = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP - 1));  // 771
   assign vsyncoff = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP + V_SYNC_PULSE - 1));  // 777
   assign vreset = hreset & (vcount_out == (DISPLAY_HEIGHT + V_FP + V_SYNC_PULSE + V_BP - 1)); // 805

   // sync and blanking
   wire next_hblank,next_vblank;
   assign next_hblank = hreset ? 0 : hblankon ? 1 : hblank;
   assign next_vblank = vreset ? 0 : vblankon ? 1 : vblank;
   always_ff @(posedge vclock_in) begin
      hcount_out <= hreset ? 0 : hcount_out + 1;
      hblank <= next_hblank;
      hsync_out <= hsyncon ? 0 : hsyncoff ? 1 : hsync_out;  // active low

      vcount_out <= hreset ? (vreset ? 0 : vcount_out + 1) : vcount_out;
      vblank <= next_vblank;
      vsync_out <= vsyncon ? 0 : vsyncoff ? 1 : vsync_out;  // active low

      blank_out <= next_vblank | (next_hblank & ~hreset);
   end
   
endmodule


//////////////////////////////////////////////////////////////////////////////////
// Engineer:   g.p.hom
// 
// Create Date:    18:18:59 04/21/2013 
// Module Name:    display_8hex 
// Description:  Display 8 hex numbers on 7 segment display
//
//////////////////////////////////////////////////////////////////////////////////

module display_8hex(
    input wire clk_in,                 // system clock
    input wire [31:0] data_in,         // 8 hex numbers, msb first
    output reg [6:0] seg_out,     // seven segment display output
    output reg [7:0] strobe_out   // digit strobe
    );

    localparam bits = 13;
     
    reg [bits:0] counter = 0;  // clear on power up
     
    wire [6:0] segments[15:0]; // 16 7 bit memorys
    assign segments[0]  = 7'b100_0000;  // inverted logic
    assign segments[1]  = 7'b111_1001;  // gfedcba
    assign segments[2]  = 7'b010_0100;
    assign segments[3]  = 7'b011_0000;
    assign segments[4]  = 7'b001_1001;
    assign segments[5]  = 7'b001_0010;
    assign segments[6]  = 7'b000_0010;
    assign segments[7]  = 7'b111_1000;
    assign segments[8]  = 7'b000_0000;
    assign segments[9]  = 7'b001_1000;
    assign segments[10] = 7'b000_1000;
    assign segments[11] = 7'b000_0011;
    assign segments[12] = 7'b010_0111;
    assign segments[13] = 7'b010_0001;
    assign segments[14] = 7'b000_0110;
    assign segments[15] = 7'b000_1110;
     
    always_ff @(posedge clk_in) begin
      // Here I am using a counter and select 3 bits which provides
      // a reasonable refresh rate starting the left most digit
      // and moving left.
      counter <= counter + 1;
      case (counter[bits:bits-2])
          3'b000: begin  // use the MSB 4 bits
                  seg_out <= segments[data_in[31:28]];
                  strobe_out <= 8'b0111_1111 ;
                 end

          3'b001: begin
                  seg_out <= segments[data_in[27:24]];
                  strobe_out <= 8'b1011_1111 ;
                 end

          3'b010: begin
                   seg_out <= segments[data_in[23:20]];
                   strobe_out <= 8'b1101_1111 ;
                  end
          3'b011: begin
                  seg_out <= segments[data_in[19:16]];
                  strobe_out <= 8'b1110_1111;        
                 end
          3'b100: begin
                  seg_out <= segments[data_in[15:12]];
                  strobe_out <= 8'b1111_0111;
                 end

          3'b101: begin
                  seg_out <= segments[data_in[11:8]];
                  strobe_out <= 8'b1111_1011;
                 end

          3'b110: begin
                   seg_out <= segments[data_in[7:4]];
                   strobe_out <= 8'b1111_1101;
                  end
          3'b111: begin
                  seg_out <= segments[data_in[3:0]];
                  strobe_out <= 8'b1111_1110;
                 end

       endcase
      end

endmodule

module sync_delay (
   input wire vclock_in,        // 65MHz clock
   input wire reset_in,         // 1 to initialize module
   input wire hsync_in,         // XVGA horizontal sync signal (active low)
   input wire vsync_in,         // XVGA vertical sync signal (active low)
   input wire blank_in,         // XVGA blanking (1 means output black pixel)
   input wire ball_bounded_in,
   input wire target_bounded_in,
   input wire virtual_bounded_in,
   input wire [11:0] cam_in,
        
   output logic phsync_out,    
   output logic pvsync_out, 
   output logic pblank_out,     
   output logic ball_bounded_out,
   output logic target_bounded_out,
   output logic virtual_bounded_out,
   output logic [11:0] cam_out
   );
    
    localparam DELAY = 13;  //16, 12
    logic [DELAY-1:0] hsync_buffer, vsync_buffer, blank_buffer;
    
    localparam DELAY_2 = 7; //10, 6
    logic [DELAY_2-1:0] ball_buffer, target_buffer, virtual_buffer;
    logic [DELAY_2-1:0][11:0] cam_buffer;
    

    genvar i;
	generate
		for (i = 1; i <= DELAY-1; i = i + 1) begin
			always @(posedge vclock_in) begin
				hsync_buffer[i] <= hsync_buffer[i-1];
				vsync_buffer[i] <= vsync_buffer[i-1];
                blank_buffer[i] <= blank_buffer[i-1];
                ball_buffer[i] <= ball_buffer[i-1];
                target_buffer[i] <= target_buffer[i-1];
                virtual_buffer[i] <= virtual_buffer[i-1];
                cam_buffer[i][11:0] <= cam_buffer[i-1][11:0];
			end
		end
	endgenerate

    always @(posedge vclock_in) begin
        hsync_buffer[0] <= hsync_in;
        vsync_buffer[0] <= vsync_in;
        blank_buffer[0] <= blank_in;
        ball_buffer[0] <= ball_bounded_in;
        target_buffer[0] <= target_bounded_in;
        virtual_buffer[0] <= virtual_bounded_in;
        cam_buffer[0][11:0] <= cam_in;

        phsync_out <= hsync_buffer[DELAY-1];
        pvsync_out <= vsync_buffer[DELAY-1];
        pblank_out <= blank_buffer[DELAY-1];
        ball_bounded_out <= ball_buffer[DELAY_2-1];
        target_bounded_out <= target_buffer[DELAY_2-1];
        virtual_bounded_out <= virtual_buffer[DELAY_2-1];
        cam_out <= cam_buffer[DELAY_2-1][11:0];
    end
endmodule

module within_bounding_box (
    input wire [10:0] hcount_in, // horizontal index of current pixel (0..1023)
    input wire [9:0]  vcount_in, // vertical index of current pixel (0..767)
    input wire [10:0] h_center_in,  // the horizontal center of the ball from the previous frame
    input wire [9:0] v_center_in,   // the vertical center of the ball from the previous frame
    input wire [10:0] radius_in,
    output logic bounded_out,
    output logic within_circle_out
);

    logic [10:0] h_diff;
    logic [9:0] v_diff;
    abs #(.WIDTH(11)) h_diff_mod (.a(hcount_in), .b(h_center_in), .c(h_diff));
    abs #(.WIDTH(10)) v_diff_mod (.a(vcount_in), .b(v_center_in), .c(v_diff));

    always_comb begin
        if ((h_diff + v_diff <= radius_in + 5) && (h_diff + v_diff >= radius_in)) begin
            bounded_out = 1;
        end else begin
            bounded_out = 0;
        end
        
        if ((2 * (h_diff * h_diff + v_diff * v_diff)) < (radius_in * radius_in)) begin // within the circle
            within_circle_out = 1;
        end else begin
            within_circle_out = 0;
        end
    end

endmodule


// computes the absolute value of (a-b) and puts the result in c
module abs #(parameter WIDTH = 11) (
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output logic [WIDTH-1:0] c
);
    
    always_comb begin

        if (a > b) begin
            c = a - b;
        end else begin
            c = b - a;
        end
    
    end

endmodule
`default_nettype wire