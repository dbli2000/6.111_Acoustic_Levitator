`timescale 1ns / 1ps
`default_nettype none

module camera_read(
	input wire p_clock_in,
	input wire vsync_in,
	input wire href_in,
	input wire [7:0] p_data_in,
	output logic [15:0] pixel_data_out,
	output logic pixel_valid_out,
	output logic frame_done_out
    );
	 
	
	logic [1:0] FSM_state = 0;
    logic pixel_half = 0;
	
	localparam WAIT_FRAME_START = 0;
	localparam ROW_CAPTURE = 1;
	
	
	always_ff@(posedge p_clock_in)
	begin 
	case(FSM_state)
	
	WAIT_FRAME_START: begin //wait for VSYNC
	   FSM_state <= (!vsync_in) ? ROW_CAPTURE : WAIT_FRAME_START;
	   frame_done_out <= 0;
	   pixel_half <= 0;
	end
	
	ROW_CAPTURE: begin 
	   FSM_state <= vsync_in ? WAIT_FRAME_START : ROW_CAPTURE;
	   frame_done_out <= vsync_in ? 1 : 0;
	   pixel_valid_out <= (href_in && pixel_half) ? 1 : 0; 
	   if (href_in) begin
	       pixel_half <= ~ pixel_half;
	       if (pixel_half) pixel_data_out[7:0] <= p_data_in;
	       else pixel_data_out[15:8] <= p_data_in;
	   end
	end
	endcase
	end
	
endmodule

module ultrasound_controller (input wire reset_in, clock_in, up_in, down_in, start_in,
                              input wire [15:0] sw_in,
                              input wire [9:0] ball_y_in, target_y_in, 
                              output logic [10:0] phase1_out, phase2_out);	
    
    parameter HIGH_THRESHOLD = 10'd30; // How many pixels the ball can be off
    parameter MED_THRESHOLD = 10'd15; // How many pixels the ball can be off
    parameter LOW_THRESHOLD = 10'd2; // How many pixels the ball can be off
    parameter HIGH_DELTA = 10'd50;
    parameter MED_DELTA = 10'd25;
    parameter LOW_DELTA = 10'd10;
   
    always_ff @(posedge clock_in) begin
        if (reset_in) begin
            phase1_out <= 0;
            phase2_out <= 0;
        end else if (up_in == 1'b1 && sw_in[1] == 1'b1 && sw_in[2] == 1'b1 && sw_in[5] == 1'b1) begin
            if ((phase1_out + 125) <= 11'd1250) begin
                phase1_out <= phase1_out + 125;
            end else begin
                phase1_out <= 0;
            end
        end else if (down_in == 1'b1 && sw_in[1] == 1'b1 && sw_in[2] == 1'b1 && sw_in[5] == 1'b1) begin
            if ((phase2_out + 125) <= 11'd1250) begin
                phase2_out <= phase2_out + 125;
            end else begin
                phase2_out <= 0;
            end
        end else if (start_in == 1'b1 && sw_in[1] == 1'b1 && sw_in[2] == 1'b0 && sw_in[5] == 1'b1) begin
            if (ball_y_in > target_y_in + HIGH_THRESHOLD) begin
                if ((phase1_out + HIGH_DELTA) <= 11'd1250) begin
                    phase1_out <= phase1_out + HIGH_DELTA;
                end else begin
                    phase1_out <= 0;
                end
            end else if (ball_y_in > target_y_in + MED_THRESHOLD) begin
                if ((phase1_out + MED_DELTA) <= 11'd1250) begin
                    phase1_out <= phase1_out + MED_DELTA;
                end else begin
                    phase1_out <= 0;
                end
            end else if (ball_y_in > target_y_in + LOW_THRESHOLD) begin
                if ((phase1_out + LOW_DELTA) <= 11'd1250) begin
                    phase1_out <= phase1_out + LOW_DELTA;
                end else begin
                    phase1_out <= 0;
                end
            end else if (ball_y_in + HIGH_THRESHOLD < target_y_in) begin
                if ((phase2_out + HIGH_DELTA) <= 11'd1250) begin
                    phase2_out <= phase2_out + HIGH_DELTA;
                end else begin
                    phase2_out <= 0;
                end
            end else if (ball_y_in + MED_THRESHOLD < target_y_in) begin
                if ((phase2_out + MED_DELTA) <= 11'd1250) begin
                    phase2_out <= phase2_out + MED_DELTA;
                end else begin
                    phase2_out <= 0;
                end
            end else if (ball_y_in + LOW_THRESHOLD < target_y_in) begin
                if ((phase2_out + LOW_DELTA) <= 11'd1250) begin
                    phase2_out <= phase2_out + LOW_DELTA;
                end else begin
                    phase2_out <= 0;
                end
            end
        end
    end 

endmodule

module ultrasound_out (input wire reset_in, clock_in, 
                       input wire [10:0] phase1, phase2,
                       output logic output1, output2);	
   
    parameter HZ_40k = 18'd1250;// 100mhz/40khz/2
    
    logic [18:0] counter;
    logic [18:0] counter1;
    logic [18:0] counter2;

    always_ff @(posedge clock_in) begin
        if (reset_in) begin
            counter <= 19'b0;
            counter1 <= phase1;
            counter2 <= phase2;
            output1 <= 0;
            output2 <= 0;
        end else begin
            // Reference counter that keeps the global 40hz waveform
            if (counter == HZ_40k) begin
                counter <= 0;
            end else begin
                counter <= counter + 1;
            end 
            // Counter1 maintains top output
            if (counter1 == HZ_40k) begin  
                if (counter + phase1 < 1250) begin       
                    counter1 <= counter + phase1;
                end else begin
                    counter1 <= counter + phase1 - 1250;
                end
                output1 <= ~output1;
            end else begin
                counter1 <= counter1 + 1;
            end
            // Counter1 maintains bottom output
            if (counter2 == HZ_40k) begin  
                if (counter + phase2 < 1250) begin       
                    counter2 <= counter + phase2;
                end else begin
                    counter2 <= counter + phase2 - 1250;
                end
                output2 <= ~output2;
            end else begin
                counter2 <= counter2 + 1;
            end
        end
    end
                                    
endmodule
                               
    
module rising_edge (input wire reset_in, clock_in, clean_in,
                    output logic rising_out);
    
    logic old;
    assign rising_out = !old & clean_in;
    
    always_ff @(posedge clock_in) begin
        if (reset_in) begin
            old <= 0;
        end else begin
            old <= clean_in;
        end
    end

endmodule

module debounce (input wire reset_in, clock_in, noisy_in,
                 output logic clean_out);

   logic [19:0] count;
   logic new_input;

   always_ff @(posedge clock_in)
     if (reset_in) begin 
        new_input <= noisy_in; 
        clean_out <= noisy_in; 
        count <= 0; end
     else if (noisy_in != new_input) begin new_input<=noisy_in; count <= 0; end
     else if (count == 650000) clean_out <= new_input;
     else count <= count+1;

endmodule

`default_nettype wire
