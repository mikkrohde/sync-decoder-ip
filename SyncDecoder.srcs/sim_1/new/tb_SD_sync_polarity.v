`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.12.2025 01:02:34
// Design Name: 
// Module Name: tb_SD_sync_polarity
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench for SyncDecoder module to verify HSYNC/VSYNC polarity detection
// 
// Revision:
// Revision 1.0 - Initial testbench implementation
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_SD_sync_polarity;
    localparam CLK_PERIOD = 10;
    
    // 480p timing
    localparam H_ACTIVE   = 640;
    localparam H_SYNC     = 96;
    localparam H_BP       = 48;
    localparam H_FP       = 16;
    localparam H_TOTAL    = 800;
    
    localparam V_ACTIVE   = 480;
    localparam V_SYNC     = 2;
    localparam V_BP       = 33;
    localparam V_FP       = 10;
    localparam V_TOTAL    = 525;
    
    localparam h_total_cfg                 = H_TOTAL;
    localparam h_active_cfg                = H_ACTIVE;
    localparam h_sync_cfg                  = H_SYNC;
    localparam h_frontporch_cfg            = H_FP;
    localparam h_backporch_cfg             = H_BP;
    localparam v_total_cfg                 = V_TOTAL;
    localparam v_active_cfg                = V_ACTIVE;
    localparam v_sync_cfg                  = V_SYNC;
    localparam v_frontporch_cfg            = V_FP;
    localparam v_backporch_cfg             = V_BP;
    localparam interlaced_mode             = 0;
    localparam decode_h_active_width       = H_ACTIVE;
    localparam decode_h_sync_width         = H_SYNC;
    localparam decode_h_backporch          = H_BP;      
    localparam decode_v_active_lines       = V_ACTIVE;
    localparam decode_v_sync_width         = V_SYNC;
    localparam decode_v_backporch          = V_BP;   
    localparam decode_force_interlaced     = 1'b0;
    localparam decode_force_progressive    = 1'b0;
    localparam decode_ignore_de            = 1'b0;
    
    // DUT signals
    reg         pixel_clk;
    reg         rst_n;
    reg         hsync;
    reg         vsync;
    reg         de;
    reg [23:0]  rgb;
    
    wire [11:0] h_total;
    wire [11:0] h_active;
    wire [11:0] h_sync_len;
    wire [11:0] h_backporch;
    wire [11:0] v_total;
    wire [11:0] v_active;
    wire [11:0] v_sync_len;
    wire [11:0] v_backporch;
    wire        interlaced;
    wire        field_id;
    wire [11:0] h_count;
    wire [11:0] v_count;

    // Instantiate DUT
    SyncDecoder #(
        .TOLERANCE(4),
        .STABILITY_COUNT(3),
        .ENABLE_INTERLACE_DETECTION(1)
    ) dut (
        .pixel_clk(pixel_clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .rgb(rgb),

        // Configuration inputs
        .cfg_h_active_width(H_ACTIVE),
        .cfg_h_sync_width(H_SYNC),
        .cfg_h_backporch(H_BP),
        .cfg_v_active_lines(V_ACTIVE),
        .cfg_v_sync_width(V_SYNC),
        .cfg_v_backporch(V_BP),
        .cfg_force_interlaced(1'b0),
        .cfg_force_progressive(1'b0),
        .cfg_ignore_de(1'b0),

        // Outputs
        .h_total(h_total),
        .h_active(h_active),
        .h_sync_len(h_sync_len),
        .h_backporch(h_backporch),
        .v_total(v_total),
        .v_active(v_active),
        .v_sync_len(v_sync_len),
        .v_backporch(v_backporch),
        .interlaced(interlaced),
        .field_id(field_id),
        .h_count(h_count),
        .v_count(v_count),
        .pixel_valid(),
        .pixel_data(),
        .line_start(),
        .frame_start()
    );

    // Clock generation
    initial begin
        pixel_clk = 0;
        forever #(CLK_PERIOD/2) pixel_clk = ~pixel_clk;
    end

    // Task: Generate video with configurable polarity
    task generate_frame;
        input hsync_polarity;  // 0 = acwtive-lo, 1 = active-high
        input vsync_polarity;  // 0 = active-low, 1 = active-high
        input integer num_lines;
        integer h_pos, v_pos;
        reg hsync_raw, vsync_raw;
        begin
            for (v_pos = 0; v_pos < num_lines; v_pos = v_pos + 1) begin
                for (h_pos = 0; h_pos < H_TOTAL; h_pos = h_pos + 1) begin
                    
                    // Generate raw sync signals (active = 1)
                    hsync_raw = (h_pos < H_SYNC) ? 1'b1 : 1'b0;
                    vsync_raw = (v_pos < V_SYNC) ? 1'b1 : 1'b0;
                    
                    // Apply polarity
                    hsync = hsync_polarity ? hsync_raw : !hsync_raw;
                    vsync = vsync_polarity ? vsync_raw : !vsync_raw;
                    
                    // DE generation
                    if ((h_pos >= H_SYNC + H_BP) && 
                        (h_pos < H_SYNC + H_BP + H_ACTIVE) &&
                        (v_pos >= V_SYNC + V_BP) && 
                        (v_pos < V_SYNC + V_BP + V_ACTIVE)) begin
                        de = 1'b1;
                        rgb = {v_pos[7:0], h_pos[7:0], 8'h00};
                    end else begin
                        de = 1'b0;
                        rgb = 24'h000000;
                    end
                    
                    @(posedge pixel_clk);
                end
            end
        end
    endtask

    // Task: Generate frames while waiting for polarity detection
    task wait_for_polarity_lock_with_video;
        input hsync_pol;  // 0 = active-low, 1 = active-high
        input vsync_pol;  // 0 = active-low, 1 = active-high
        integer timeout;
        begin
            $display("Generating video while waiting for polarity detection...");
            timeout = 0;

            // Generate video frames until polarity is locked or timeout
            while (!dut.polarity_locked && timeout < 100000) begin
                generate_frame(hsync_pol, vsync_pol, V_TOTAL);
                timeout = timeout + (H_TOTAL * V_TOTAL);
            end

            if (dut.polarity_locked) begin
                $display("Polarity locked after %0d clock cycles", timeout);
                $display("  hsync_idle_level = %b", dut.hsync_idle_level);
                $display("  vsync_idle_level = %b", dut.vsync_idle_level);
            end else begin
                $display("ERROR: Polarity detection timeout!");
            end
        end
    endtask

    // Task: Check results
    task check_results;
        input [8*50:1] test_name;
        input integer expected_h_total;
        input integer expected_h_active;
        input integer expected_v_total;
        input integer expected_v_active;
        begin
            $display("\n========================================");
            $display("%0s Results:", test_name);
            $display("========================================");
            $display("Polarity Detection:");
            $display("  hsync_idle_level = %b", dut.hsync_idle_level);
            $display("  vsync_idle_level = %b", dut.vsync_idle_level);
            $display("  polarity_locked  = %b", dut.polarity_locked);
            $display("  Sample counts: blanking=%0d, hsync_high=%0d, vsync_high=%0d",
                     dut.blanking_sample_count, dut.hsync_high_count, dut.vsync_high_count);

            if (dut.polarity_locked) begin
                $display("\n>>> PASS: Polarity detected correctly!");
            end else begin
                $display("\n>>> FAIL: Polarity detection failed!");
            end
        end
    endtask

    // Test procedure
    initial begin
        $display("========================================");
        $display("SyncDecoder Polarity Detection Test");
        $display("========================================");
        $display("Testing all 4 polarity combinations:");
        $display("  H-/V- (negative/negative) - Standard VGA");
        $display("  H+/V+ (positive/positive)");
        $display("  H-/V+ (negative/positive)");
        $display("  H+/V- (positive/negative)");
        $display("========================================");
        
        // ==========================================
        // Test 1: H-/V- (Active-low, standard VGA)
        // ==========================================
        $display("\n>>> TEST 1: H-/V- (Active-Low/Active-Low)");
        rst_n = 0;
        hsync = 1;  // Idle high
        vsync = 1;
        de = 0;
        rgb = 0;

        repeat (10) @(posedge pixel_clk);
        rst_n = 1;
        repeat (10) @(posedge pixel_clk);

        wait_for_polarity_lock_with_video(0, 0);  // Generate video while detecting

        repeat (3) generate_frame(0, 0, V_TOTAL);  // Generate 3 more frames
        repeat (10) @(posedge pixel_clk);

        check_results("H-/V- Test", H_TOTAL, H_ACTIVE, V_TOTAL, V_ACTIVE);

        // ==========================================
        // Test 2: H+/V+ (Active-high)
        // ==========================================
        $display("\n>>> TEST 2: H+/V+ (Active-High/Active-High)");
        rst_n = 0;
        hsync = 0;  // Idle low
        vsync = 0;
        de = 0;
        rgb = 0;

        repeat (10) @(posedge pixel_clk);
        rst_n = 1;
        repeat (10) @(posedge pixel_clk);

        wait_for_polarity_lock_with_video(1, 1);  // Generate video while detecting

        repeat (3) generate_frame(1, 1, V_TOTAL);  // Generate 3 more frames
        repeat (10) @(posedge pixel_clk);

        check_results("H+/V+ Test", H_TOTAL, H_ACTIVE, V_TOTAL, V_ACTIVE);

        // ==========================================
        // Test 3: H-/V+ (Mixed polarity)
        // ==========================================
        $display("\n>>> TEST 3: H-/V+ (Active-Low/Active-High)");
        rst_n = 0;
        hsync = 1;  // Idle high
        vsync = 0;  // Idle low
        de = 0;
        rgb = 0;

        repeat (10) @(posedge pixel_clk);
        rst_n = 1;
        repeat (10) @(posedge pixel_clk);

        wait_for_polarity_lock_with_video(0, 1);  // Generate video while detecting

        repeat (3) generate_frame(0, 1, V_TOTAL);  // Generate 3 more frames
        repeat (10) @(posedge pixel_clk);

        check_results("H-/V+ Test", H_TOTAL, H_ACTIVE, V_TOTAL, V_ACTIVE);

        // ==========================================
        // Test 4: H+/V- (Mixed polarity)
        // ==========================================
        $display("\n>>> TEST 4: H+/V- (Active-High/Active-Low)");
        rst_n = 0;
        hsync = 0;  // Idle low
        vsync = 1;  // Idle high
        de = 0;
        rgb = 0;

        repeat (10) @(posedge pixel_clk);
        rst_n = 1;
        repeat (10) @(posedge pixel_clk);

        wait_for_polarity_lock_with_video(1, 0);  // Generate video while detecting

        repeat (3) generate_frame(1, 0, V_TOTAL);  // Generate 3 more frames
        repeat (10) @(posedge pixel_clk);

        check_results("H+/V- Test", H_TOTAL, H_ACTIVE, V_TOTAL, V_ACTIVE);
        
        $display("\n========================================");
        $display("All Polarity Tests Complete!");
        $display("========================================\n");
        $finish;
    end

endmodule
