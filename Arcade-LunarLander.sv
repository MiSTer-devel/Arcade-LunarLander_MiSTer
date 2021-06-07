module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;


`include "build_id.v" 
localparam CONF_STR = {
	"A.LLANDER;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"-;",
	"OD,Thruster,Analog Stick,D-Pad;",
	"-;",
	"O7,Test,Off,On;",
	"O89,Language,English,Spanish,French,German;",
	"OAC,Fuel,450,600,750,900,1100,1300,1550,1800;",
	"-;",
	"R0,Reset;",
	"J1,Abort,Turn Right,Turn Left,Start,Select,Coin;",	
    "jn,X,A,B,Start,L,R;",
	"jp,Y,B,A,Start,L,R;",
	"V,v",`BUILD_DATE
};
// 00010000
// on is 0
//wire [7:0] m_dip = {~status[12:11],1'b1,~status[10],~status[9:8],1'b0,1'b0};
wire [7:0] m_dip = {1'b0,1'b0,status[8],status[9],~status[10],1'b1,status[11],status[12]};
//wire [7:0] m_dip = 8'b00010000;

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_25,clk_50;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_50),	
	.outclk_1(clk_25),	
	.outclk_2(clk_6),	
	.locked(pll_locked)
);


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joy_0, joy_1;
wire [15:0] joy = joy_0 | joy_1;
wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_25),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),


        .buttons(buttons),
        .status(status),
        .status_menumask(direct_video),
        .forced_scandoubler(forced_scandoubler),
        .gamma_bus(gamma_bus),
        .direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joy_0),
	.joystick_1(joy_1),
	.joystick_analog_0(analog_joy_0),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_25) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			//'h03a: btn_fire         <= pressed; // M
			'h005: btn_one_player   <= pressed; // F1
			'h006: btn_two_players  <= pressed; // F2
			'h01C: btn_left         <= pressed; // A
			'h023: btn_right        <= pressed; // D
			'h004: btn_coin         <= pressed; // F3
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left         <= pressed; // left
			'hX74: btn_right        <= pressed; // right
			'h014: btn_abort        <= pressed; // ctrl
			'h011: btn_select       <= pressed; // Lalt
			'h029: btn_gselect      <= pressed; // space
			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1      <= pressed; // 1
			'h02E: btn_coin         <= pressed; // 5
			'h036: btn_coin         <= pressed; // 6
			
		endcase
	end
end

reg btn_right = 0;
reg btn_left = 0;
reg btn_up = 0;
reg btn_down = 0;
reg btn_one_player = 0;
reg btn_two_players = 0;
reg btn_abort = 0;
reg btn_coin = 0;
reg btn_select = 0;
reg btn_gselect =0;
reg btn_start_1=0;

wire hblank, vblank;
wire ohblank, ovblank;

wire hs, vs;
wire ohs, ovs;
wire [2:0] r,g,b;
wire [7:0] outr,outg,outb;



reg ce_pix;
always @(posedge clk_50) begin
       ce_pix <= !ce_pix;
end

arcade_video #(640,480,12) arcade_video
(
        .*,

        .clk_video(clk_50),

        .RGB_in({outr[7:5],outg[7:5],outb[7:5]}),

        .HBlank(ohblank),
        .VBlank(ovblank),
        .HSync(ohs),
        .VSync(ovs),

        .forced_scandoubler(0),
        .no_rotate(1),
        .rotate_ccw(0),
        .fx(0)
);



ovo #(.COLS(1), .LINES(1), .RGB(24'hFF00FF)) diff (
	.i_r({r,r,r[2:1]}),
	.i_g({g,g,g[2:1]}),
	.i_b({b,b,b[2:1]}),
	.i_hs(~hs),
	.i_vs(~vs),
	.i_de(vgade),
	.i_hblank(hblank),
	.i_vblank(vblank),
	.i_en(ce_pix),
	.i_clk(clk_50),

	.o_r(outr),
	.o_g(outg),
	.o_b(outb),
	.o_hs(ohs),
	.o_vs(ovs),
	.o_de(ode),
	.o_hblank(ohblank),
	.o_vblank(ovblank),

	.ena(diff_count > 0),

	.in0(difficulty),
	.in1(),
);

wire lamp2, lamp3, lamp4, lamp5;

wire [1:0] difficulty;

always_comb begin
	if(lamp5)
		difficulty = 2'd3;
	else if(lamp4)
		difficulty = 2'd2;
	else if(lamp3)
		difficulty = 2'd1;
	else
		difficulty = 2'd0;
end

int diff_count = 0;
always @(posedge CLK_50M) begin
	if (diff_count > 0)
		diff_count <= diff_count - 1;
	
	if (~in_select)
		diff_count <= 'd500_000_000; // 10 seconds
end


wire reset = (RESET | status[0] | buttons[1] | ioctl_download);
wire [7:0] audio;
assign AUDIO_L = {audio, audio};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
wire vgade;
wire [15:0] analog_joy_0;

wire signed [7:0] signedjoy = analog_joy_0[15:8];
wire signed [7:0] signedturn = analog_joy_0[7:0];
wire [8:0] us_joy = 9'sd255 - (signedjoy + 9'sd128);


// According to mame, because of the way the DAC worked for the thrust lever,
// it was unlikely that the board ever expected to get 0xFF, so we limit to 0xFE.
wire [8:0] us_joy_mod = us_joy > 9'd254 ? 9'd254 : us_joy;

reg [7:0] dpad_thrust = 0;

// 1 second = 50,000,000 cycles (duh)
// If we want to go from zero to full throttle in 1 second we tick every
// 196,850 cycles.
always @(posedge CLK_50M) begin :thrust_count
	int thrust_count;
	thrust_count <= thrust_count + 1'd1;

	if (thrust_count == 'd196_850) begin
		thrust_count <= 0;
		if ((joy[2]|btn_down) && dpad_thrust > 0)
			dpad_thrust <= dpad_thrust - 1'd1;

		if ((joy[3]|btn_up) && dpad_thrust < 'd254)
			dpad_thrust <= dpad_thrust + 1'd1;
	end
end

wire joy_turn_l = (signedturn < -8'sd64);
wire joy_turn_r = (signedturn > 8'sd64);

//4     5      6    7     8          9
//Start,Select,Coin,Abort,Turn Right,Turn Left

wire in_select = ~(joy[5] | btn_gselect);
wire in_start  = ~(joy[4] | btn_one_player | btn_start_1);
wire in_turn_l = ~(joy[9] | joy[1] | btn_left | joy_turn_l);
wire in_turn_r = ~(joy[8] | joy[0] | btn_right | joy_turn_r);
wire in_coin   = ~(joy[6] | btn_coin);
wire in_abort  = ~(joy[7] | btn_abort);

wire [7:0] in_thrust = status[13] ? dpad_thrust : us_joy_mod;

wire is_starting;

LLANDER_TOP LLANDER_TOP
(
	.ROT_LEFT_L(in_turn_l),
	.ROT_RIGHT_L(in_turn_r),
	.ABORT_L(in_abort),
	.GAME_SEL_L(in_select),
	.START_L(in_start),
	.COIN1_L(in_coin),
	.COIN2_L(in_coin),
	.THRUST(in_thrust),
	.DIAG_STEP_L(m_diag_step),
	.SLAM_L(m_slam),
	.SELF_TEST_L(~status[7]), 
	.START_SEL_L(is_starting),
	.LAMP2(lamp2),
	.LAMP3(lamp3),
	.LAMP4(lamp4),
	.LAMP5(lamp5),

	.AUDIO_OUT(audio),
	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),	
	.VIDEO_R_OUT(r),
	.VIDEO_G_OUT(g),
	.VIDEO_B_OUT(b),
	.HSYNC_OUT(hs),
	.VSYNC_OUT(vs),
	.VGA_DE(vgade),
	.VID_HBLANK(hblank),
	.VID_VBLANK(vblank),
	.DIP(m_dip),
	.RESET_L (~reset),	
	.clk_6(clk_6),
	.clk_25(clk_25)
);

endmodule
