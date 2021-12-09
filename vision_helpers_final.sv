`timescale 1ns / 1ps
`default_nettype none

// Computes if the pixel passes the filter
module hsv_filter 
    #(
        parameter H_LO = 0, 
        parameter H_HI = 50,
        parameter S_LO = 0,
        parameter S_HI = 20,
        parameter V_LO = 0,
        parameter V_HI = 20
    ) (
        input wire clock_in,
        input wire [8:0] h_in, 
        input wire [7:0] s_in, v_in,
        input wire [10:0] hor_pos_in,
        input wire [9:0] ver_pos_in,
        output logic [8:0] h_out, 
        output logic [7:0] s_out, v_out,
        output logic [10:0] hor_pos_out,
        output logic [9:0] ver_pos_out,
        output logic passed_hsv_filter_out
    );

    always @(posedge clock_in) begin
        h_out <= h_in;
        s_out <= s_in;
        v_out <= v_in;
        hor_pos_out <= hor_pos_in;
        ver_pos_out <= ver_pos_in;
        
            if (h_in >= H_LO && h_in <= H_HI && s_in >= S_LO && s_in <= S_HI && v_in >= V_LO && v_in <= V_HI) begin
                passed_hsv_filter_out <= 1;
            end else begin
                passed_hsv_filter_out <=0;
            end
    end

endmodule

module rgb2hsv (
	input wire clock_in,
	input wire [7:0] r_in, 
    input wire [7:0] g_in, 
    input wire [7:0] b_in,
	input wire [10:0] hor_pos_in,
	input wire [9:0] ver_pos_in,
	output logic [8:0] hue_out,
    output logic [7:0] sat_out,
    output logic [7:0] val_out,
	output logic [10:0] hor_pos_out,
	output logic [9:0] ver_pos_out
	);

	logic [7:0] hue_dividend, hue_divisor;
	logic [13:0] hue_result;

	logic [7:0] sat_dividend, sat_divisor;
	logic [14:0] sat_result;

	logic [7:0] val_dividend;
	logic [14:0] val_result;

	limited_divider_60 hue_calculation 	(.clock_in(clock_in), .dividend_in(hue_dividend), .divisor_in(hue_divisor), .result_out(hue_result));
	limited_divider_100 sat_calculation (.clock_in(clock_in), .dividend_in(sat_dividend), .divisor_in(sat_divisor), .result_out(sat_result));
	limited_divider_100 val_calculation (.clock_in(clock_in), .dividend_in(val_dividend), .divisor_in(8'd255), .result_out(val_result));
	
	logic [7:0] cmin, cmax, delta;

	logic [7:0] my_r_delay1, my_g_delay1, my_b_delay1;
	logic [7:0] my_r_delay2, my_g_delay2, my_b_delay2;
	logic [7:0] my_r_delay3, my_g_delay3, my_b_delay3;

	logic [7:0] cmax_delay3;
	logic negate_output, negate_output_delay_5;
	logic [8:0] hue_to_add, hue_to_add_delay_5;

	parameter DELAY = 6;

	logic [10:0] hor_pos_delay [DELAY-2 : 0];
	logic [9:0] ver_pos_delay [DELAY-2 : 0];

	genvar i;
	generate
		for (i = 1; i <= DELAY - 2; i = i + 1) begin
			always @(posedge clock_in) begin
				hor_pos_delay[i] <= hor_pos_delay[i-1];
				ver_pos_delay[i] <= ver_pos_delay[i-1];
			end
		end
	endgenerate

	always @(posedge clock_in) begin

		// clock cycle 1:
		{my_r_delay1, my_g_delay1, my_b_delay1} <= {r_in, g_in, b_in};
		hor_pos_delay[0] <= hor_pos_in;
		ver_pos_delay[0] <= ver_pos_in;

		// clock cycle 2 (compute the cmax/cmin):
		{my_r_delay2, my_g_delay2, my_b_delay2} <= {my_r_delay1, my_g_delay1, my_b_delay1};

		if ((my_r_delay1 >= my_g_delay1) && (my_r_delay1 >= my_b_delay1)) begin // Cmax == R
			cmax <= my_r_delay1;
		end else if ((my_g_delay1 >= my_r_delay1) && (my_g_delay1 >= my_b_delay1)) begin // Cmax == G
			cmax <= my_g_delay1;
		end else begin	// Cmax == B
			cmax <= my_b_delay1;
		end

		if ((my_r_delay1 <= my_g_delay1) && (my_r_delay1 <= my_b_delay1)) begin // Cmin == R
			cmin <= my_r_delay1;
		end else if ((my_g_delay1 <= my_r_delay1) && (my_g_delay1 <= my_b_delay1)) begin // Cmin == G
			cmin <= my_g_delay1;
		end else begin // Cmin == b
			cmin <= my_b_delay1;
		end

		// clock cycle 3 (compute delta):
		{my_r_delay3, my_g_delay3, my_b_delay3} <= {my_r_delay2, my_g_delay2, my_b_delay2};
		delta <= cmax - cmin;
		cmax_delay3 <= cmax;

		// clock cycle 4 (divisions, set the numerators/denominators):

		// compute 100 * (delta / cmax)
		sat_dividend <= delta;
		sat_divisor <= cmax_delay3;

		// compute 100 * cmax
		val_dividend <= cmax_delay3;

		// hue computation
		hue_divisor <= delta; // set divisor

		// set the dividend
		if (cmax_delay3 == my_r_delay3) begin 				// if cmax equal r then compute h = (60 * ((g - b) / delta) + 360) % 360

			if (my_g_delay3 >= my_b_delay3) begin
				hue_dividend <= my_g_delay3 - my_b_delay3;	// compute g - b
				negate_output <= 0;
				hue_to_add <= 0;							// 0 because it will be on the positive side of the circle
			end else begin
				hue_dividend <= my_b_delay3 - my_g_delay3;	// compute b - g (will be negative though, so it will go around the circle)
				negate_output <= 1;
				hue_to_add <= 360;
			end

		end else if (cmax_delay3 == my_g_delay3) begin		// if cmax equal g then compute h = (60 * ((b - r) / delta) + 120) % 360

			hue_to_add <= 120;
			
			if (my_b_delay3 >= my_r_delay3) begin
				hue_dividend <= my_b_delay3 - my_r_delay3;	// compute b - r
				negate_output <= 0;
			end else begin
				hue_dividend <= my_r_delay3 - my_b_delay3;	// compute r - b and negate it at the end
				negate_output <= 1;
			end

		end else begin			// if cmax equals b then compute h = (60 * ((r - g) / diff) + 240) % 360
			
			hue_to_add <= 240;
			
			if (my_r_delay3 >= my_r_delay3) begin
				hue_dividend <= my_r_delay3 - my_g_delay3;	// compute r - g
				negate_output <= 0;
			end else begin
				hue_dividend <= my_g_delay3 - my_r_delay3;	// compute g - r and negate it at the end
				negate_output <= 1;
			end

		end

		// clock cycle 5 (wait for division)
		
		hue_to_add_delay_5 <= hue_to_add;
		negate_output_delay_5 <= negate_output;

		// clock cycle 6 (compute the outputs)

		sat_out <= sat_result;
		val_out <= val_result;

		if (negate_output_delay_5) begin
			hue_out <= hue_to_add_delay_5 - hue_result;
		end else begin
			hue_out <= hue_to_add_delay_5 + hue_result;
		end

		hor_pos_out <= hor_pos_delay[DELAY - 2];
		ver_pos_out <= ver_pos_delay[DELAY - 2];

	end

endmodule


// Computes the approximate value of 60 * (dividend_in / divisor_in)
module limited_divider_60 (
    input wire clock_in,
    input wire [7:0] dividend_in,
    input wire [7:0] divisor_in,
    output logic [13:0] result_out
    );

    always @(posedge clock_in) begin
        case (divisor_in)
            8'd1: result_out <= ((61440 * dividend_in) >> 10);
            8'd2: result_out <= ((30720 * dividend_in) >> 10);
            8'd3: result_out <= ((20480 * dividend_in) >> 10);
            8'd4: result_out <= ((15360 * dividend_in) >> 10);
            8'd5: result_out <= ((12288 * dividend_in) >> 10);
            8'd6: result_out <= ((10240 * dividend_in) >> 10);
            8'd7: result_out <= ((8777 * dividend_in) >> 10);
            8'd8: result_out <= ((7680 * dividend_in) >> 10);
            8'd9: result_out <= ((6827 * dividend_in) >> 10);
            8'd10: result_out <= ((6144 * dividend_in) >> 10);
            8'd11: result_out <= ((5585 * dividend_in) >> 10);
            8'd12: result_out <= ((5120 * dividend_in) >> 10);
            8'd13: result_out <= ((4726 * dividend_in) >> 10);
            8'd14: result_out <= ((4389 * dividend_in) >> 10);
            8'd15: result_out <= ((4096 * dividend_in) >> 10);
            8'd16: result_out <= ((3840 * dividend_in) >> 10);
            8'd17: result_out <= ((3614 * dividend_in) >> 10);
            8'd18: result_out <= ((3413 * dividend_in) >> 10);
            8'd19: result_out <= ((3234 * dividend_in) >> 10);
            8'd20: result_out <= ((3072 * dividend_in) >> 10);
            8'd21: result_out <= ((2926 * dividend_in) >> 10);
            8'd22: result_out <= ((2793 * dividend_in) >> 10);
            8'd23: result_out <= ((2671 * dividend_in) >> 10);
            8'd24: result_out <= ((2560 * dividend_in) >> 10);
            8'd25: result_out <= ((2458 * dividend_in) >> 10);
            8'd26: result_out <= ((2363 * dividend_in) >> 10);
            8'd27: result_out <= ((2276 * dividend_in) >> 10);
            8'd28: result_out <= ((2194 * dividend_in) >> 10);
            8'd29: result_out <= ((2119 * dividend_in) >> 10);
            8'd30: result_out <= ((2048 * dividend_in) >> 10);
            8'd31: result_out <= ((1982 * dividend_in) >> 10);
            8'd32: result_out <= ((1920 * dividend_in) >> 10);
            8'd33: result_out <= ((1862 * dividend_in) >> 10);
            8'd34: result_out <= ((1807 * dividend_in) >> 10);
            8'd35: result_out <= ((1755 * dividend_in) >> 10);
            8'd36: result_out <= ((1707 * dividend_in) >> 10);
            8'd37: result_out <= ((1661 * dividend_in) >> 10);
            8'd38: result_out <= ((1617 * dividend_in) >> 10);
            8'd39: result_out <= ((1575 * dividend_in) >> 10);
            8'd40: result_out <= ((1536 * dividend_in) >> 10);
            8'd41: result_out <= ((1499 * dividend_in) >> 10);
            8'd42: result_out <= ((1463 * dividend_in) >> 10);
            8'd43: result_out <= ((1429 * dividend_in) >> 10);
            8'd44: result_out <= ((1396 * dividend_in) >> 10);
            8'd45: result_out <= ((1365 * dividend_in) >> 10);
            8'd46: result_out <= ((1336 * dividend_in) >> 10);
            8'd47: result_out <= ((1307 * dividend_in) >> 10);
            8'd48: result_out <= ((1280 * dividend_in) >> 10);
            8'd49: result_out <= ((1254 * dividend_in) >> 10);
            8'd50: result_out <= ((1229 * dividend_in) >> 10);
            8'd51: result_out <= ((1205 * dividend_in) >> 10);
            8'd52: result_out <= ((1182 * dividend_in) >> 10);
            8'd53: result_out <= ((1159 * dividend_in) >> 10);
            8'd54: result_out <= ((1138 * dividend_in) >> 10);
            8'd55: result_out <= ((1117 * dividend_in) >> 10);
            8'd56: result_out <= ((1097 * dividend_in) >> 10);
            8'd57: result_out <= ((1078 * dividend_in) >> 10);
            8'd58: result_out <= ((1059 * dividend_in) >> 10);
            8'd59: result_out <= ((1041 * dividend_in) >> 10);
            8'd60: result_out <= ((1024 * dividend_in) >> 10);
            8'd61: result_out <= ((1007 * dividend_in) >> 10);
            8'd62: result_out <= ((991 * dividend_in) >> 10);
            8'd63: result_out <= ((975 * dividend_in) >> 10);
            8'd64: result_out <= ((960 * dividend_in) >> 10);
            8'd65: result_out <= ((945 * dividend_in) >> 10);
            8'd66: result_out <= ((931 * dividend_in) >> 10);
            8'd67: result_out <= ((917 * dividend_in) >> 10);
            8'd68: result_out <= ((904 * dividend_in) >> 10);
            8'd69: result_out <= ((890 * dividend_in) >> 10);
            8'd70: result_out <= ((878 * dividend_in) >> 10);
            8'd71: result_out <= ((865 * dividend_in) >> 10);
            8'd72: result_out <= ((853 * dividend_in) >> 10);
            8'd73: result_out <= ((842 * dividend_in) >> 10);
            8'd74: result_out <= ((830 * dividend_in) >> 10);
            8'd75: result_out <= ((819 * dividend_in) >> 10);
            8'd76: result_out <= ((808 * dividend_in) >> 10);
            8'd77: result_out <= ((798 * dividend_in) >> 10);
            8'd78: result_out <= ((788 * dividend_in) >> 10);
            8'd79: result_out <= ((778 * dividend_in) >> 10);
            8'd80: result_out <= ((768 * dividend_in) >> 10);
            8'd81: result_out <= ((759 * dividend_in) >> 10);
            8'd82: result_out <= ((749 * dividend_in) >> 10);
            8'd83: result_out <= ((740 * dividend_in) >> 10);
            8'd84: result_out <= ((731 * dividend_in) >> 10);
            8'd85: result_out <= ((723 * dividend_in) >> 10);
            8'd86: result_out <= ((714 * dividend_in) >> 10);
            8'd87: result_out <= ((706 * dividend_in) >> 10);
            8'd88: result_out <= ((698 * dividend_in) >> 10);
            8'd89: result_out <= ((690 * dividend_in) >> 10);
            8'd90: result_out <= ((683 * dividend_in) >> 10);
            8'd91: result_out <= ((675 * dividend_in) >> 10);
            8'd92: result_out <= ((668 * dividend_in) >> 10);
            8'd93: result_out <= ((661 * dividend_in) >> 10);
            8'd94: result_out <= ((654 * dividend_in) >> 10);
            8'd95: result_out <= ((647 * dividend_in) >> 10);
            8'd96: result_out <= ((640 * dividend_in) >> 10);
            8'd97: result_out <= ((633 * dividend_in) >> 10);
            8'd98: result_out <= ((627 * dividend_in) >> 10);
            8'd99: result_out <= ((621 * dividend_in) >> 10);
            8'd100: result_out <= ((614 * dividend_in) >> 10);
            8'd101: result_out <= ((608 * dividend_in) >> 10);
            8'd102: result_out <= ((602 * dividend_in) >> 10);
            8'd103: result_out <= ((597 * dividend_in) >> 10);
            8'd104: result_out <= ((591 * dividend_in) >> 10);
            8'd105: result_out <= ((585 * dividend_in) >> 10);
            8'd106: result_out <= ((580 * dividend_in) >> 10);
            8'd107: result_out <= ((574 * dividend_in) >> 10);
            8'd108: result_out <= ((569 * dividend_in) >> 10);
            8'd109: result_out <= ((564 * dividend_in) >> 10);
            8'd110: result_out <= ((559 * dividend_in) >> 10);
            8'd111: result_out <= ((554 * dividend_in) >> 10);
            8'd112: result_out <= ((549 * dividend_in) >> 10);
            8'd113: result_out <= ((544 * dividend_in) >> 10);
            8'd114: result_out <= ((539 * dividend_in) >> 10);
            8'd115: result_out <= ((534 * dividend_in) >> 10);
            8'd116: result_out <= ((530 * dividend_in) >> 10);
            8'd117: result_out <= ((525 * dividend_in) >> 10);
            8'd118: result_out <= ((521 * dividend_in) >> 10);
            8'd119: result_out <= ((516 * dividend_in) >> 10);
            8'd120: result_out <= ((512 * dividend_in) >> 10);
            8'd121: result_out <= ((508 * dividend_in) >> 10);
            8'd122: result_out <= ((504 * dividend_in) >> 10);
            8'd123: result_out <= ((500 * dividend_in) >> 10);
            8'd124: result_out <= ((495 * dividend_in) >> 10);
            8'd125: result_out <= ((492 * dividend_in) >> 10);
            8'd126: result_out <= ((488 * dividend_in) >> 10);
            8'd127: result_out <= ((484 * dividend_in) >> 10);
            8'd128: result_out <= ((480 * dividend_in) >> 10);
            8'd129: result_out <= ((476 * dividend_in) >> 10);
            8'd130: result_out <= ((473 * dividend_in) >> 10);
            8'd131: result_out <= ((469 * dividend_in) >> 10);
            8'd132: result_out <= ((465 * dividend_in) >> 10);
            8'd133: result_out <= ((462 * dividend_in) >> 10);
            8'd134: result_out <= ((459 * dividend_in) >> 10);
            8'd135: result_out <= ((455 * dividend_in) >> 10);
            8'd136: result_out <= ((452 * dividend_in) >> 10);
            8'd137: result_out <= ((448 * dividend_in) >> 10);
            8'd138: result_out <= ((445 * dividend_in) >> 10);
            8'd139: result_out <= ((442 * dividend_in) >> 10);
            8'd140: result_out <= ((439 * dividend_in) >> 10);
            8'd141: result_out <= ((436 * dividend_in) >> 10);
            8'd142: result_out <= ((433 * dividend_in) >> 10);
            8'd143: result_out <= ((430 * dividend_in) >> 10);
            8'd144: result_out <= ((427 * dividend_in) >> 10);
            8'd145: result_out <= ((424 * dividend_in) >> 10);
            8'd146: result_out <= ((421 * dividend_in) >> 10);
            8'd147: result_out <= ((418 * dividend_in) >> 10);
            8'd148: result_out <= ((415 * dividend_in) >> 10);
            8'd149: result_out <= ((412 * dividend_in) >> 10);
            8'd150: result_out <= ((410 * dividend_in) >> 10);
            8'd151: result_out <= ((407 * dividend_in) >> 10);
            8'd152: result_out <= ((404 * dividend_in) >> 10);
            8'd153: result_out <= ((402 * dividend_in) >> 10);
            8'd154: result_out <= ((399 * dividend_in) >> 10);
            8'd155: result_out <= ((396 * dividend_in) >> 10);
            8'd156: result_out <= ((394 * dividend_in) >> 10);
            8'd157: result_out <= ((391 * dividend_in) >> 10);
            8'd158: result_out <= ((389 * dividend_in) >> 10);
            8'd159: result_out <= ((386 * dividend_in) >> 10);
            8'd160: result_out <= ((384 * dividend_in) >> 10);
            8'd161: result_out <= ((382 * dividend_in) >> 10);
            8'd162: result_out <= ((379 * dividend_in) >> 10);
            8'd163: result_out <= ((377 * dividend_in) >> 10);
            8'd164: result_out <= ((375 * dividend_in) >> 10);
            8'd165: result_out <= ((372 * dividend_in) >> 10);
            8'd166: result_out <= ((370 * dividend_in) >> 10);
            8'd167: result_out <= ((368 * dividend_in) >> 10);
            8'd168: result_out <= ((366 * dividend_in) >> 10);
            8'd169: result_out <= ((364 * dividend_in) >> 10);
            8'd170: result_out <= ((361 * dividend_in) >> 10);
            8'd171: result_out <= ((359 * dividend_in) >> 10);
            8'd172: result_out <= ((357 * dividend_in) >> 10);
            8'd173: result_out <= ((355 * dividend_in) >> 10);
            8'd174: result_out <= ((353 * dividend_in) >> 10);
            8'd175: result_out <= ((351 * dividend_in) >> 10);
            8'd176: result_out <= ((349 * dividend_in) >> 10);
            8'd177: result_out <= ((347 * dividend_in) >> 10);
            8'd178: result_out <= ((345 * dividend_in) >> 10);
            8'd179: result_out <= ((343 * dividend_in) >> 10);
            8'd180: result_out <= ((341 * dividend_in) >> 10);
            8'd181: result_out <= ((339 * dividend_in) >> 10);
            8'd182: result_out <= ((338 * dividend_in) >> 10);
            8'd183: result_out <= ((336 * dividend_in) >> 10);
            8'd184: result_out <= ((334 * dividend_in) >> 10);
            8'd185: result_out <= ((332 * dividend_in) >> 10);
            8'd186: result_out <= ((330 * dividend_in) >> 10);
            8'd187: result_out <= ((329 * dividend_in) >> 10);
            8'd188: result_out <= ((327 * dividend_in) >> 10);
            8'd189: result_out <= ((325 * dividend_in) >> 10);
            8'd190: result_out <= ((323 * dividend_in) >> 10);
            8'd191: result_out <= ((322 * dividend_in) >> 10);
            8'd192: result_out <= ((320 * dividend_in) >> 10);
            8'd193: result_out <= ((318 * dividend_in) >> 10);
            8'd194: result_out <= ((317 * dividend_in) >> 10);
            8'd195: result_out <= ((315 * dividend_in) >> 10);
            8'd196: result_out <= ((313 * dividend_in) >> 10);
            8'd197: result_out <= ((312 * dividend_in) >> 10);
            8'd198: result_out <= ((310 * dividend_in) >> 10);
            8'd199: result_out <= ((309 * dividend_in) >> 10);
            8'd200: result_out <= ((307 * dividend_in) >> 10);
            8'd201: result_out <= ((306 * dividend_in) >> 10);
            8'd202: result_out <= ((304 * dividend_in) >> 10);
            8'd203: result_out <= ((303 * dividend_in) >> 10);
            8'd204: result_out <= ((301 * dividend_in) >> 10);
            8'd205: result_out <= ((300 * dividend_in) >> 10);
            8'd206: result_out <= ((298 * dividend_in) >> 10);
            8'd207: result_out <= ((297 * dividend_in) >> 10);
            8'd208: result_out <= ((295 * dividend_in) >> 10);
            8'd209: result_out <= ((294 * dividend_in) >> 10);
            8'd210: result_out <= ((293 * dividend_in) >> 10);
            8'd211: result_out <= ((291 * dividend_in) >> 10);
            8'd212: result_out <= ((290 * dividend_in) >> 10);
            8'd213: result_out <= ((288 * dividend_in) >> 10);
            8'd214: result_out <= ((287 * dividend_in) >> 10);
            8'd215: result_out <= ((286 * dividend_in) >> 10);
            8'd216: result_out <= ((284 * dividend_in) >> 10);
            8'd217: result_out <= ((283 * dividend_in) >> 10);
            8'd218: result_out <= ((282 * dividend_in) >> 10);
            8'd219: result_out <= ((281 * dividend_in) >> 10);
            8'd220: result_out <= ((279 * dividend_in) >> 10);
            8'd221: result_out <= ((278 * dividend_in) >> 10);
            8'd222: result_out <= ((277 * dividend_in) >> 10);
            8'd223: result_out <= ((276 * dividend_in) >> 10);
            8'd224: result_out <= ((274 * dividend_in) >> 10);
            8'd225: result_out <= ((273 * dividend_in) >> 10);
            8'd226: result_out <= ((272 * dividend_in) >> 10);
            8'd227: result_out <= ((271 * dividend_in) >> 10);
            8'd228: result_out <= ((269 * dividend_in) >> 10);
            8'd229: result_out <= ((268 * dividend_in) >> 10);
            8'd230: result_out <= ((267 * dividend_in) >> 10);
            8'd231: result_out <= ((266 * dividend_in) >> 10);
            8'd232: result_out <= ((265 * dividend_in) >> 10);
            8'd233: result_out <= ((264 * dividend_in) >> 10);
            8'd234: result_out <= ((263 * dividend_in) >> 10);
            8'd235: result_out <= ((261 * dividend_in) >> 10);
            8'd236: result_out <= ((260 * dividend_in) >> 10);
            8'd237: result_out <= ((259 * dividend_in) >> 10);
            8'd238: result_out <= ((258 * dividend_in) >> 10);
            8'd239: result_out <= ((257 * dividend_in) >> 10);
            8'd240: result_out <= ((256 * dividend_in) >> 10);
            8'd241: result_out <= ((255 * dividend_in) >> 10);
            8'd242: result_out <= ((254 * dividend_in) >> 10);
            8'd243: result_out <= ((253 * dividend_in) >> 10);
            8'd244: result_out <= ((252 * dividend_in) >> 10);
            8'd245: result_out <= ((251 * dividend_in) >> 10);
            8'd246: result_out <= ((250 * dividend_in) >> 10);
            8'd247: result_out <= ((249 * dividend_in) >> 10);
            8'd248: result_out <= ((248 * dividend_in) >> 10);
            8'd249: result_out <= ((247 * dividend_in) >> 10);
            8'd250: result_out <= ((246 * dividend_in) >> 10);
            8'd251: result_out <= ((245 * dividend_in) >> 10);
            8'd252: result_out <= ((244 * dividend_in) >> 10);
            8'd253: result_out <= ((243 * dividend_in) >> 10);
            8'd254: result_out <= ((242 * dividend_in) >> 10);
            8'd255: result_out <= ((241 * dividend_in) >> 10);
            default: result_out <= 0;
        endcase
    end
endmodule

// Compute the approximate value of 100 * (dividend_in / divisor_in).
module limited_divider_100 (
    input wire clock_in,
    input wire [7:0] dividend_in,
    input wire [7:0] divisor_in,
    output logic [14:0] result_out
    );

    always @(posedge clock_in) begin
        case (divisor_in)
            8'd1: result_out <= ((102400 * dividend_in) >> 10);
            8'd2: result_out <= ((51200 * dividend_in) >> 10);
            8'd3: result_out <= ((34133 * dividend_in) >> 10);
            8'd4: result_out <= ((25600 * dividend_in) >> 10);
            8'd5: result_out <= ((20480 * dividend_in) >> 10);
            8'd6: result_out <= ((17067 * dividend_in) >> 10);
            8'd7: result_out <= ((14629 * dividend_in) >> 10);
            8'd8: result_out <= ((12800 * dividend_in) >> 10);
            8'd9: result_out <= ((11378 * dividend_in) >> 10);
            8'd10: result_out <= ((10240 * dividend_in) >> 10);
            8'd11: result_out <= ((9309 * dividend_in) >> 10);
            8'd12: result_out <= ((8533 * dividend_in) >> 10);
            8'd13: result_out <= ((7877 * dividend_in) >> 10);
            8'd14: result_out <= ((7314 * dividend_in) >> 10);
            8'd15: result_out <= ((6827 * dividend_in) >> 10);
            8'd16: result_out <= ((6400 * dividend_in) >> 10);
            8'd17: result_out <= ((6024 * dividend_in) >> 10);
            8'd18: result_out <= ((5689 * dividend_in) >> 10);
            8'd19: result_out <= ((5389 * dividend_in) >> 10);
            8'd20: result_out <= ((5120 * dividend_in) >> 10);
            8'd21: result_out <= ((4876 * dividend_in) >> 10);
            8'd22: result_out <= ((4655 * dividend_in) >> 10);
            8'd23: result_out <= ((4452 * dividend_in) >> 10);
            8'd24: result_out <= ((4267 * dividend_in) >> 10);
            8'd25: result_out <= ((4096 * dividend_in) >> 10);
            8'd26: result_out <= ((3938 * dividend_in) >> 10);
            8'd27: result_out <= ((3793 * dividend_in) >> 10);
            8'd28: result_out <= ((3657 * dividend_in) >> 10);
            8'd29: result_out <= ((3531 * dividend_in) >> 10);
            8'd30: result_out <= ((3413 * dividend_in) >> 10);
            8'd31: result_out <= ((3303 * dividend_in) >> 10);
            8'd32: result_out <= ((3200 * dividend_in) >> 10);
            8'd33: result_out <= ((3103 * dividend_in) >> 10);
            8'd34: result_out <= ((3012 * dividend_in) >> 10);
            8'd35: result_out <= ((2926 * dividend_in) >> 10);
            8'd36: result_out <= ((2844 * dividend_in) >> 10);
            8'd37: result_out <= ((2768 * dividend_in) >> 10);
            8'd38: result_out <= ((2695 * dividend_in) >> 10);
            8'd39: result_out <= ((2626 * dividend_in) >> 10);
            8'd40: result_out <= ((2560 * dividend_in) >> 10);
            8'd41: result_out <= ((2498 * dividend_in) >> 10);
            8'd42: result_out <= ((2438 * dividend_in) >> 10);
            8'd43: result_out <= ((2381 * dividend_in) >> 10);
            8'd44: result_out <= ((2327 * dividend_in) >> 10);
            8'd45: result_out <= ((2276 * dividend_in) >> 10);
            8'd46: result_out <= ((2226 * dividend_in) >> 10);
            8'd47: result_out <= ((2179 * dividend_in) >> 10);
            8'd48: result_out <= ((2133 * dividend_in) >> 10);
            8'd49: result_out <= ((2090 * dividend_in) >> 10);
            8'd50: result_out <= ((2048 * dividend_in) >> 10);
            8'd51: result_out <= ((2008 * dividend_in) >> 10);
            8'd52: result_out <= ((1969 * dividend_in) >> 10);
            8'd53: result_out <= ((1932 * dividend_in) >> 10);
            8'd54: result_out <= ((1896 * dividend_in) >> 10);
            8'd55: result_out <= ((1862 * dividend_in) >> 10);
            8'd56: result_out <= ((1829 * dividend_in) >> 10);
            8'd57: result_out <= ((1796 * dividend_in) >> 10);
            8'd58: result_out <= ((1766 * dividend_in) >> 10);
            8'd59: result_out <= ((1736 * dividend_in) >> 10);
            8'd60: result_out <= ((1707 * dividend_in) >> 10);
            8'd61: result_out <= ((1679 * dividend_in) >> 10);
            8'd62: result_out <= ((1652 * dividend_in) >> 10);
            8'd63: result_out <= ((1625 * dividend_in) >> 10);
            8'd64: result_out <= ((1600 * dividend_in) >> 10);
            8'd65: result_out <= ((1575 * dividend_in) >> 10);
            8'd66: result_out <= ((1552 * dividend_in) >> 10);
            8'd67: result_out <= ((1528 * dividend_in) >> 10);
            8'd68: result_out <= ((1506 * dividend_in) >> 10);
            8'd69: result_out <= ((1484 * dividend_in) >> 10);
            8'd70: result_out <= ((1463 * dividend_in) >> 10);
            8'd71: result_out <= ((1442 * dividend_in) >> 10);
            8'd72: result_out <= ((1422 * dividend_in) >> 10);
            8'd73: result_out <= ((1403 * dividend_in) >> 10);
            8'd74: result_out <= ((1384 * dividend_in) >> 10);
            8'd75: result_out <= ((1365 * dividend_in) >> 10);
            8'd76: result_out <= ((1347 * dividend_in) >> 10);
            8'd77: result_out <= ((1330 * dividend_in) >> 10);
            8'd78: result_out <= ((1313 * dividend_in) >> 10);
            8'd79: result_out <= ((1296 * dividend_in) >> 10);
            8'd80: result_out <= ((1280 * dividend_in) >> 10);
            8'd81: result_out <= ((1264 * dividend_in) >> 10);
            8'd82: result_out <= ((1249 * dividend_in) >> 10);
            8'd83: result_out <= ((1234 * dividend_in) >> 10);
            8'd84: result_out <= ((1219 * dividend_in) >> 10);
            8'd85: result_out <= ((1205 * dividend_in) >> 10);
            8'd86: result_out <= ((1191 * dividend_in) >> 10);
            8'd87: result_out <= ((1177 * dividend_in) >> 10);
            8'd88: result_out <= ((1164 * dividend_in) >> 10);
            8'd89: result_out <= ((1151 * dividend_in) >> 10);
            8'd90: result_out <= ((1138 * dividend_in) >> 10);
            8'd91: result_out <= ((1125 * dividend_in) >> 10);
            8'd92: result_out <= ((1113 * dividend_in) >> 10);
            8'd93: result_out <= ((1101 * dividend_in) >> 10);
            8'd94: result_out <= ((1089 * dividend_in) >> 10);
            8'd95: result_out <= ((1078 * dividend_in) >> 10);
            8'd96: result_out <= ((1067 * dividend_in) >> 10);
            8'd97: result_out <= ((1056 * dividend_in) >> 10);
            8'd98: result_out <= ((1045 * dividend_in) >> 10);
            8'd99: result_out <= ((1034 * dividend_in) >> 10);
            8'd100: result_out <= ((1024 * dividend_in) >> 10);
            8'd101: result_out <= ((1014 * dividend_in) >> 10);
            8'd102: result_out <= ((1004 * dividend_in) >> 10);
            8'd103: result_out <= ((994 * dividend_in) >> 10);
            8'd104: result_out <= ((985 * dividend_in) >> 10);
            8'd105: result_out <= ((975 * dividend_in) >> 10);
            8'd106: result_out <= ((966 * dividend_in) >> 10);
            8'd107: result_out <= ((957 * dividend_in) >> 10);
            8'd108: result_out <= ((948 * dividend_in) >> 10);
            8'd109: result_out <= ((939 * dividend_in) >> 10);
            8'd110: result_out <= ((931 * dividend_in) >> 10);
            8'd111: result_out <= ((923 * dividend_in) >> 10);
            8'd112: result_out <= ((914 * dividend_in) >> 10);
            8'd113: result_out <= ((906 * dividend_in) >> 10);
            8'd114: result_out <= ((898 * dividend_in) >> 10);
            8'd115: result_out <= ((890 * dividend_in) >> 10);
            8'd116: result_out <= ((883 * dividend_in) >> 10);
            8'd117: result_out <= ((875 * dividend_in) >> 10);
            8'd118: result_out <= ((868 * dividend_in) >> 10);
            8'd119: result_out <= ((861 * dividend_in) >> 10);
            8'd120: result_out <= ((853 * dividend_in) >> 10);
            8'd121: result_out <= ((846 * dividend_in) >> 10);
            8'd122: result_out <= ((839 * dividend_in) >> 10);
            8'd123: result_out <= ((833 * dividend_in) >> 10);
            8'd124: result_out <= ((826 * dividend_in) >> 10);
            8'd125: result_out <= ((819 * dividend_in) >> 10);
            8'd126: result_out <= ((813 * dividend_in) >> 10);
            8'd127: result_out <= ((806 * dividend_in) >> 10);
            8'd128: result_out <= ((800 * dividend_in) >> 10);
            8'd129: result_out <= ((794 * dividend_in) >> 10);
            8'd130: result_out <= ((788 * dividend_in) >> 10);
            8'd131: result_out <= ((782 * dividend_in) >> 10);
            8'd132: result_out <= ((776 * dividend_in) >> 10);
            8'd133: result_out <= ((770 * dividend_in) >> 10);
            8'd134: result_out <= ((764 * dividend_in) >> 10);
            8'd135: result_out <= ((759 * dividend_in) >> 10);
            8'd136: result_out <= ((753 * dividend_in) >> 10);
            8'd137: result_out <= ((747 * dividend_in) >> 10);
            8'd138: result_out <= ((742 * dividend_in) >> 10);
            8'd139: result_out <= ((737 * dividend_in) >> 10);
            8'd140: result_out <= ((731 * dividend_in) >> 10);
            8'd141: result_out <= ((726 * dividend_in) >> 10);
            8'd142: result_out <= ((721 * dividend_in) >> 10);
            8'd143: result_out <= ((716 * dividend_in) >> 10);
            8'd144: result_out <= ((711 * dividend_in) >> 10);
            8'd145: result_out <= ((706 * dividend_in) >> 10);
            8'd146: result_out <= ((701 * dividend_in) >> 10);
            8'd147: result_out <= ((697 * dividend_in) >> 10);
            8'd148: result_out <= ((692 * dividend_in) >> 10);
            8'd149: result_out <= ((687 * dividend_in) >> 10);
            8'd150: result_out <= ((683 * dividend_in) >> 10);
            8'd151: result_out <= ((678 * dividend_in) >> 10);
            8'd152: result_out <= ((674 * dividend_in) >> 10);
            8'd153: result_out <= ((669 * dividend_in) >> 10);
            8'd154: result_out <= ((665 * dividend_in) >> 10);
            8'd155: result_out <= ((661 * dividend_in) >> 10);
            8'd156: result_out <= ((656 * dividend_in) >> 10);
            8'd157: result_out <= ((652 * dividend_in) >> 10);
            8'd158: result_out <= ((648 * dividend_in) >> 10);
            8'd159: result_out <= ((644 * dividend_in) >> 10);
            8'd160: result_out <= ((640 * dividend_in) >> 10);
            8'd161: result_out <= ((636 * dividend_in) >> 10);
            8'd162: result_out <= ((632 * dividend_in) >> 10);
            8'd163: result_out <= ((628 * dividend_in) >> 10);
            8'd164: result_out <= ((624 * dividend_in) >> 10);
            8'd165: result_out <= ((621 * dividend_in) >> 10);
            8'd166: result_out <= ((617 * dividend_in) >> 10);
            8'd167: result_out <= ((613 * dividend_in) >> 10);
            8'd168: result_out <= ((610 * dividend_in) >> 10);
            8'd169: result_out <= ((606 * dividend_in) >> 10);
            8'd170: result_out <= ((602 * dividend_in) >> 10);
            8'd171: result_out <= ((599 * dividend_in) >> 10);
            8'd172: result_out <= ((595 * dividend_in) >> 10);
            8'd173: result_out <= ((592 * dividend_in) >> 10);
            8'd174: result_out <= ((589 * dividend_in) >> 10);
            8'd175: result_out <= ((585 * dividend_in) >> 10);
            8'd176: result_out <= ((582 * dividend_in) >> 10);
            8'd177: result_out <= ((579 * dividend_in) >> 10);
            8'd178: result_out <= ((575 * dividend_in) >> 10);
            8'd179: result_out <= ((572 * dividend_in) >> 10);
            8'd180: result_out <= ((569 * dividend_in) >> 10);
            8'd181: result_out <= ((566 * dividend_in) >> 10);
            8'd182: result_out <= ((563 * dividend_in) >> 10);
            8'd183: result_out <= ((560 * dividend_in) >> 10);
            8'd184: result_out <= ((557 * dividend_in) >> 10);
            8'd185: result_out <= ((554 * dividend_in) >> 10);
            8'd186: result_out <= ((551 * dividend_in) >> 10);
            8'd187: result_out <= ((548 * dividend_in) >> 10);
            8'd188: result_out <= ((545 * dividend_in) >> 10);
            8'd189: result_out <= ((542 * dividend_in) >> 10);
            8'd190: result_out <= ((539 * dividend_in) >> 10);
            8'd191: result_out <= ((536 * dividend_in) >> 10);
            8'd192: result_out <= ((533 * dividend_in) >> 10);
            8'd193: result_out <= ((531 * dividend_in) >> 10);
            8'd194: result_out <= ((528 * dividend_in) >> 10);
            8'd195: result_out <= ((525 * dividend_in) >> 10);
            8'd196: result_out <= ((522 * dividend_in) >> 10);
            8'd197: result_out <= ((520 * dividend_in) >> 10);
            8'd198: result_out <= ((517 * dividend_in) >> 10);
            8'd199: result_out <= ((515 * dividend_in) >> 10);
            8'd200: result_out <= ((512 * dividend_in) >> 10);
            8'd201: result_out <= ((509 * dividend_in) >> 10);
            8'd202: result_out <= ((507 * dividend_in) >> 10);
            8'd203: result_out <= ((504 * dividend_in) >> 10);
            8'd204: result_out <= ((502 * dividend_in) >> 10);
            8'd205: result_out <= ((500 * dividend_in) >> 10);
            8'd206: result_out <= ((497 * dividend_in) >> 10);
            8'd207: result_out <= ((495 * dividend_in) >> 10);
            8'd208: result_out <= ((492 * dividend_in) >> 10);
            8'd209: result_out <= ((490 * dividend_in) >> 10);
            8'd210: result_out <= ((488 * dividend_in) >> 10);
            8'd211: result_out <= ((485 * dividend_in) >> 10);
            8'd212: result_out <= ((483 * dividend_in) >> 10);
            8'd213: result_out <= ((481 * dividend_in) >> 10);
            8'd214: result_out <= ((479 * dividend_in) >> 10);
            8'd215: result_out <= ((476 * dividend_in) >> 10);
            8'd216: result_out <= ((474 * dividend_in) >> 10);
            8'd217: result_out <= ((472 * dividend_in) >> 10);
            8'd218: result_out <= ((470 * dividend_in) >> 10);
            8'd219: result_out <= ((468 * dividend_in) >> 10);
            8'd220: result_out <= ((465 * dividend_in) >> 10);
            8'd221: result_out <= ((463 * dividend_in) >> 10);
            8'd222: result_out <= ((461 * dividend_in) >> 10);
            8'd223: result_out <= ((459 * dividend_in) >> 10);
            8'd224: result_out <= ((457 * dividend_in) >> 10);
            8'd225: result_out <= ((455 * dividend_in) >> 10);
            8'd226: result_out <= ((453 * dividend_in) >> 10);
            8'd227: result_out <= ((451 * dividend_in) >> 10);
            8'd228: result_out <= ((449 * dividend_in) >> 10);
            8'd229: result_out <= ((447 * dividend_in) >> 10);
            8'd230: result_out <= ((445 * dividend_in) >> 10);
            8'd231: result_out <= ((443 * dividend_in) >> 10);
            8'd232: result_out <= ((441 * dividend_in) >> 10);
            8'd233: result_out <= ((439 * dividend_in) >> 10);
            8'd234: result_out <= ((438 * dividend_in) >> 10);
            8'd235: result_out <= ((436 * dividend_in) >> 10);
            8'd236: result_out <= ((434 * dividend_in) >> 10);
            8'd237: result_out <= ((432 * dividend_in) >> 10);
            8'd238: result_out <= ((430 * dividend_in) >> 10);
            8'd239: result_out <= ((428 * dividend_in) >> 10);
            8'd240: result_out <= ((427 * dividend_in) >> 10);
            8'd241: result_out <= ((425 * dividend_in) >> 10);
            8'd242: result_out <= ((423 * dividend_in) >> 10);
            8'd243: result_out <= ((421 * dividend_in) >> 10);
            8'd244: result_out <= ((420 * dividend_in) >> 10);
            8'd245: result_out <= ((418 * dividend_in) >> 10);
            8'd246: result_out <= ((416 * dividend_in) >> 10);
            8'd247: result_out <= ((415 * dividend_in) >> 10);
            8'd248: result_out <= ((413 * dividend_in) >> 10);
            8'd249: result_out <= ((411 * dividend_in) >> 10);
            8'd250: result_out <= ((410 * dividend_in) >> 10);
            8'd251: result_out <= ((408 * dividend_in) >> 10);
            8'd252: result_out <= ((406 * dividend_in) >> 10);
            8'd253: result_out <= ((405 * dividend_in) >> 10);
            8'd254: result_out <= ((403 * dividend_in) >> 10);
            8'd255: result_out <= ((402 * dividend_in) >> 10);
            default: result_out <= 0;
        endcase
    end
endmodule


module weighted_average #(
    // parameter LOWER = 0, 
    // parameter UPPER = 512,
    parameter POS_BITS = 11) (
    input wire clock_in,
    input wire reset_in,
    input wire start_in,
    input wire done_in,
    input wire [POS_BITS-1 : 0] pos_in,         // index on the axis
    input wire passed_hsv_filter_in,            // whether or not this pixel passed the filter
    output logic ready_out,
    output logic [POS_BITS-1 : 0] avg_out,      // the weighted average
    output logic [POS_BITS-1 : 0] avg_radius
    );
    
    localparam DIVISION_WIDTH = 30;

    localparam WAITING   = 2'b00;
    localparam SUMMING   = 2'b01;
    localparam DIVIDING  = 2'b10;
    localparam RESETTING = 2'b11;

    logic [1:0] state;
    logic [29:0] sum;       // 20 bits to accumulate on
    logic [29:0] count;      // 10 bits to accumulate the count
    logic [29:0] old_count;       // 20 bits to accumulate on

    logic start_dividing;   // indicate to the the divider module that it should start dividing

    logic division_finished;
    logic [DIVISION_WIDTH-1 : 0] quotient;
    logic [DIVISION_WIDTH-1 : 0] fractional;

    assign avg_out = quotient;

    divider #(.WIDTH(DIVISION_WIDTH)) d (.clock_in(clock_in), .reset_in(reset_in), 
        .start_in(start_dividing), .dividend_in(sum), .divisor_in(count), 
        .ready_out(division_finished), .quotient_out(quotient), 
        .fractional_out(fractional));
        
    sqrt_max_155 #(.POS_BITS(POS_BITS)) radius_calculator(.x(old_count), .result_out(avg_radius));

    always @(posedge clock_in) begin

        if (reset_in || state == RESETTING) begin

            state <= WAITING;
            sum <= 0;
            ready_out <= 0;
            count <= 0;
            start_dividing <= 0;
            old_count <= 0;
        end else if (start_in) begin

            state <= SUMMING;
            sum <= 0;
            ready_out <= 0;
            count <= 0;
            start_dividing <= 0;

        end else if (state == SUMMING) begin

            if (done_in) begin              // no more pixels -- we should start dividing
                state <= DIVIDING;
                start_dividing <= 1;
            end else if (passed_hsv_filter_in) begin
                sum <= sum + pos_in;
                count <= count + 1;
            end

        end else if (state == DIVIDING) begin
            old_count <= count;
            start_dividing <= 0;
            
            

            if (division_finished) begin    // the division completed -- raise the ready signal
                state <= RESETTING;
                ready_out <= 1;
            end

        end

    end

endmodule

module divider #(parameter WIDTH = 20) (
    input wire clock_in,
    input wire reset_in,
    input wire start_in,
    input wire [WIDTH-1 : 0] dividend_in,
    input wire [WIDTH-1 : 0] divisor_in,
    output logic ready_out,
    output logic [WIDTH-1 : 0] quotient_out,
    output logic [WIDTH-1 : 0] fractional_out
    );

    logic [WIDTH-1 : 0]     quotient_temp;
    logic [2*WIDTH-1 : 0]   dividend_copy, divider_copy, diff;

    assign quotient_out = quotient_temp;
    assign fractional_out = dividend_copy;

    logic [WIDTH-1 : 0] zeros;
    assign zeros = 0;

    logic [5:0] iteration;
    
    always @(posedge clock_in) begin
        if (reset_in || ready_out) begin // ready_out is turned on in the last iteration of the loop

            iteration <= 0; // iteration needs to be 0 to prevent it from running off
            ready_out <= 0;

        end else if (start_in) begin

            iteration <= WIDTH;
            ready_out <= 0;

            quotient_temp <= 0;

            dividend_copy <= {zeros, dividend_in}; // equivalent to R
            divider_copy <= {divisor_in, zeros};   // equivalent to D

        end else if (iteration > 0) begin
            
            if ((dividend_copy << 1) >= divider_copy) begin
                quotient_temp[iteration - 1] <= 1;
                dividend_copy <= (dividend_copy << 1) - divider_copy;
            end else begin
                quotient_temp[iteration - 1] <= 0;
                dividend_copy <= (dividend_copy << 1);
            end

            if (iteration == 1) begin
                ready_out <= 1;
            end
            
            iteration <= iteration - 1;
        end 
    end
    
endmodule



module sqrt_max_155 #(
    parameter POS_BITS = 11) (
    input wire [29:0] x,
    output logic [POS_BITS-1 : 0] result_out
    );

    always_comb begin
        if (x >= 0 && x < 1) begin
            result_out = 10;
        end else if (x >= 1 && x < 4) begin
            result_out = 10;
        end else if (x >= 4 && x < 9) begin
            result_out = 10;
        end else if (x >= 9 && x < 16) begin
            result_out = 10;
        end else if (x >= 16 && x < 25) begin
            result_out = 10;
        end else if (x >= 25 && x < 36) begin
            result_out = 10;
        end else if (x >= 36 && x < 49) begin
            result_out = 10;
        end else if (x >= 49 && x < 64) begin
            result_out = 10;
        end else if (x >= 64 && x < 81) begin
            result_out = 10;
        end else if (x >= 81 && x < 100) begin
            result_out = 10;
        end else if (x >= 100 && x < 121) begin
            result_out = 11;
        end else if (x >= 121 && x < 144) begin
            result_out = 12;
        end else if (x >= 144 && x < 169) begin
            result_out = 13;
        end else if (x >= 169 && x < 196) begin
            result_out = 14;
        end else if (x >= 196 && x < 225) begin
            result_out = 15;
        end else if (x >= 225 && x < 256) begin
            result_out = 16;
        end else if (x >= 256 && x < 289) begin
            result_out = 17;
        end else if (x >= 289 && x < 324) begin
            result_out = 18;
        end else if (x >= 324 && x < 361) begin
            result_out = 19;
        end else if (x >= 361 && x < 400) begin
            result_out = 20;
        end else if (x >= 400 && x < 441) begin
            result_out = 21;
        end else if (x >= 441 && x < 484) begin
            result_out = 22;
        end else if (x >= 484 && x < 529) begin
            result_out = 23;
        end else if (x >= 529 && x < 576) begin
            result_out = 24;
        end else if (x >= 576 && x < 625) begin
            result_out = 25;
        end else if (x >= 625 && x < 676) begin
            result_out = 26;
        end else if (x >= 676 && x < 729) begin
            result_out = 27;
        end else if (x >= 729 && x < 784) begin
            result_out = 28;
        end else if (x >= 784 && x < 841) begin
            result_out = 29;
        end else if (x >= 841 && x < 900) begin
            result_out = 30;
        end else if (x >= 900 && x < 961) begin
            result_out = 31;
        end else if (x >= 961 && x < 1024) begin
            result_out = 32;
        end else if (x >= 1024 && x < 1089) begin
            result_out = 33;
        end else if (x >= 1089 && x < 1156) begin
            result_out = 34;
        end else if (x >= 1156 && x < 1225) begin
            result_out = 35;
        end else if (x >= 1225 && x < 1296) begin
            result_out = 36;
        end else if (x >= 1296 && x < 1369) begin
            result_out = 37;
        end else if (x >= 1369 && x < 1444) begin
            result_out = 38;
        end else if (x >= 1444 && x < 1521) begin
            result_out = 39;
        end else if (x >= 1521 && x < 1600) begin
            result_out = 40;
        end else if (x >= 1600 && x < 1681) begin
            result_out = 41;
        end else if (x >= 1681 && x < 1764) begin
            result_out = 42;
        end else if (x >= 1764 && x < 1849) begin
            result_out = 43;
        end else if (x >= 1849 && x < 1936) begin
            result_out = 44;
        end else if (x >= 1936 && x < 2025) begin
            result_out = 45;
        end else if (x >= 2025 && x < 2116) begin
            result_out = 46;
        end else if (x >= 2116 && x < 2209) begin
            result_out = 47;
        end else if (x >= 2209 && x < 2304) begin
            result_out = 48;
        end else if (x >= 2304 && x < 2401) begin
            result_out = 49;
        end else if (x >= 2401 && x < 2500) begin
            result_out = 50;
        end else if (x >= 2500 && x < 2601) begin
            result_out = 51;
        end else if (x >= 2601 && x < 2704) begin
            result_out = 52;
        end else if (x >= 2704 && x < 2809) begin
            result_out = 53;
        end else if (x >= 2809 && x < 2916) begin
            result_out = 54;
        end else if (x >= 2916 && x < 3025) begin
            result_out = 55;
        end else if (x >= 3025 && x < 3136) begin
            result_out = 56;
        end else if (x >= 3136 && x < 3249) begin
            result_out = 57;
        end else if (x >= 3249 && x < 3364) begin
            result_out = 58;
        end else if (x >= 3364 && x < 3481) begin
            result_out = 59;
        end else if (x >= 3481 && x < 3600) begin
            result_out = 60;
        end else if (x >= 3600 && x < 3721) begin
            result_out = 61;
        end else if (x >= 3721 && x < 3844) begin
            result_out = 62;
        end else if (x >= 3844 && x < 3969) begin
            result_out = 63;
        end else if (x >= 3969 && x < 4096) begin
            result_out = 64;
        end else if (x >= 4096 && x < 4225) begin
            result_out = 65;
        end else if (x >= 4225 && x < 4356) begin
            result_out = 66;
        end else if (x >= 4356 && x < 4489) begin
            result_out = 67;
        end else if (x >= 4489 && x < 4624) begin
            result_out = 68;
        end else if (x >= 4624 && x < 4761) begin
            result_out = 69;
        end else if (x >= 4761 && x < 4900) begin
            result_out = 70;
        end else if (x >= 4900 && x < 5041) begin
            result_out = 71;
        end else if (x >= 5041 && x < 5184) begin
            result_out = 72;
        end else if (x >= 5184 && x < 5329) begin
            result_out = 73;
        end else if (x >= 5329 && x < 5476) begin
            result_out = 74;
        end else if (x >= 5476 && x < 5625) begin
            result_out = 75;
        end else if (x >= 5625 && x < 5776) begin
            result_out = 76;
        end else if (x >= 5776 && x < 5929) begin
            result_out = 77;
        end else if (x >= 5929 && x < 6084) begin
            result_out = 78;
        end else if (x >= 6084 && x < 6241) begin
            result_out = 79;
        end else if (x >= 6241 && x < 6400) begin
            result_out = 80;
        end else if (x >= 6400 && x < 6561) begin
            result_out = 81;
        end else if (x >= 6561 && x < 6724) begin
            result_out = 82;
        end else if (x >= 6724 && x < 6889) begin
            result_out = 83;
        end else if (x >= 6889 && x < 7056) begin
            result_out = 84;
        end else if (x >= 7056 && x < 7225) begin
            result_out = 85;
        end else if (x >= 7225 && x < 7396) begin
            result_out = 86;
        end else if (x >= 7396 && x < 7569) begin
            result_out = 87;
        end else if (x >= 7569 && x < 7744) begin
            result_out = 88;
        end else if (x >= 7744 && x < 7921) begin
            result_out = 89;
        end else if (x >= 7921 && x < 8100) begin
            result_out = 90;
        end else if (x >= 8100 && x < 8281) begin
            result_out = 91;
        end else if (x >= 8281 && x < 8464) begin
            result_out = 92;
        end else if (x >= 8464 && x < 8649) begin
            result_out = 93;
        end else if (x >= 8649 && x < 8836) begin
            result_out = 94;
        end else if (x >= 8836 && x < 9025) begin
            result_out = 95;
        end else if (x >= 9025 && x < 9216) begin
            result_out = 96;
        end else if (x >= 9216 && x < 9409) begin
            result_out = 97;
        end else if (x >= 9409 && x < 9604) begin
            result_out = 98;
        end else if (x >= 9604 && x < 9801) begin
            result_out = 99;
        end else if (x >= 9801 && x < 10000) begin
            result_out = 100;
        end else if (x >= 10000 && x < 10201) begin
            result_out = 101;
        end else if (x >= 10201 && x < 10404) begin
            result_out = 102;
        end else if (x >= 10404 && x < 10609) begin
            result_out = 103;
        end else if (x >= 10609 && x < 10816) begin
            result_out = 104;
        end else if (x >= 10816 && x < 11025) begin
            result_out = 105;
        end else if (x >= 11025 && x < 11236) begin
            result_out = 106;
        end else if (x >= 11236 && x < 11449) begin
            result_out = 107;
        end else if (x >= 11449 && x < 11664) begin
            result_out = 108;
        end else if (x >= 11664 && x < 11881) begin
            result_out = 109;
        end else if (x >= 11881 && x < 12100) begin
            result_out = 110;
        end else if (x >= 12100 && x < 12321) begin
            result_out = 111;
        end else if (x >= 12321 && x < 12544) begin
            result_out = 112;
        end else if (x >= 12544 && x < 12769) begin
            result_out = 113;
        end else if (x >= 12769 && x < 12996) begin
            result_out = 114;
        end else if (x >= 12996 && x < 13225) begin
            result_out = 115;
        end else if (x >= 13225 && x < 13456) begin
            result_out = 116;
        end else if (x >= 13456 && x < 13689) begin
            result_out = 117;
        end else if (x >= 13689 && x < 13924) begin
            result_out = 118;
        end else if (x >= 13924 && x < 14161) begin
            result_out = 119;
        end else if (x >= 14161 && x < 14400) begin
            result_out = 120;
        end else if (x >= 14400 && x < 14641) begin
            result_out = 121;
        end else if (x >= 14641 && x < 14884) begin
            result_out = 122;
        end else if (x >= 14884 && x < 15129) begin
            result_out = 123;
        end else if (x >= 15129 && x < 15376) begin
            result_out = 124;
        end else if (x >= 15376 && x < 15625) begin
            result_out = 125;
        end else if (x >= 15625 && x < 15876) begin
            result_out = 126;
        end else if (x >= 15876 && x < 16129) begin
            result_out = 127;
        end else if (x >= 16129 && x < 16384) begin
            result_out = 128;
        end else if (x >= 16384 && x < 16641) begin
            result_out = 129;
        end else if (x >= 16641 && x < 16900) begin
            result_out = 130;
        end else if (x >= 16900 && x < 17161) begin
            result_out = 131;
        end else if (x >= 17161 && x < 17424) begin
            result_out = 132;
        end else if (x >= 17424 && x < 17689) begin
            result_out = 133;
        end else if (x >= 17689 && x < 17956) begin
            result_out = 134;
        end else if (x >= 17956 && x < 18225) begin
            result_out = 135;
        end else if (x >= 18225 && x < 18496) begin
            result_out = 136;
        end else if (x >= 18496 && x < 18769) begin
            result_out = 137;
        end else if (x >= 18769 && x < 19044) begin
            result_out = 138;
        end else if (x >= 19044 && x < 19321) begin
            result_out = 139;
        end else if (x >= 19321 && x < 19600) begin
            result_out = 140;
        end else if (x >= 19600 && x < 19881) begin
            result_out = 141;
        end else if (x >= 19881 && x < 20164) begin
            result_out = 142;
        end else if (x >= 20164 && x < 20449) begin
            result_out = 143;
        end else if (x >= 20449 && x < 20736) begin
            result_out = 144;
        end else if (x >= 20736 && x < 21025) begin
            result_out = 145;
        end else if (x >= 21025 && x < 21316) begin
            result_out = 146;
        end else if (x >= 21316 && x < 21609) begin
            result_out = 147;
        end else if (x >= 21609 && x < 21904) begin
            result_out = 148;
        end else if (x >= 21904 && x < 22201) begin
            result_out = 149;
        end else if (x >= 22201 && x < 22500) begin
            result_out = 150;
        end else if (x >= 22500 && x < 22801) begin
            result_out = 151;
        end else if (x >= 22801 && x < 23104) begin
            result_out = 152;
        end else if (x >= 23104 && x < 23409) begin
            result_out = 153;
        end else if (x >= 23409 && x < 23716) begin
            result_out = 154;
        end else begin
            result_out = 155;
        end
    end
endmodule


`default_nettype wire