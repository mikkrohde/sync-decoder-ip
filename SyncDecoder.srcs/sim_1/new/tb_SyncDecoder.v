`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 
// Create Date: 26.12.2025 12:05:52
// Design Name: 
// Module Name: tb_SyncDecoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench for SyncDecoder - with NTSC and PAL test signals
// 
// Revision 1.0 - Initial Implementation
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_SyncDecoder;
    // Parameters
    localparam CLK_PERIOD = 10;  // 100 MHz pixel clock (flexible for testing)
    
    // Test video modes
    localparam TEST_480P = 0;  // NTSC progressive
    localparam TEST_720P = 1;  // HD progressive
    localparam TEST_480I = 2;  // NTSC interlaced
    localparam TEST_576P = 3;  // PAL progressive
    localparam TEST_576I = 4;  // PAL interlaced
    
    // 480p timing (640x480 @ 60Hz VGA - NTSC)
    localparam H_ACTIVE_480P        = 640;
    localparam H_FRONTPORCH_480P    = 16;
    localparam H_SYNC_480P          = 96;
    localparam H_BACKPORCH_480P     = 48;
    localparam H_TOTAL_480P         = 800;
    
    localparam V_ACTIVE_480P        = 480;
    localparam V_FRONTPORCH_480P    = 10;
    localparam V_SYNC_480P          = 2;
    localparam V_BACKPORCH_480P     = 33;
    localparam V_TOTAL_480P         = 525;
    
    // 480I timing (640x450 @ 60hz VGA - NTSC)
    localparam H_ACTIVE_480I        = 640;
    localparam H_FRONTPORCH_480I    = 16;
    localparam H_SYNC_480I          = 64;
    localparam H_BACKPORCH_480I     = 80;
    localparam H_TOTAL_480I         = 800;

    localparam V_ACTIVE_480I        = 240;
    localparam V_FRONTPORCH_480I    = 3;
    localparam V_SYNC_480I          = 4;
    localparam V_BACKPORCH_480I     = 14;
    localparam V_TOTAL_480I         = 261.5;
    
    // 720p timing (simplified)
    localparam H_ACTIVE_720P        = 1280;
    localparam H_FRONTPORCH_720P    = 110;
    localparam H_SYNC_720P          = 40;
    localparam H_BACKPORCH_720P     = 220;
    localparam H_TOTAL_720P         = 1650;
    
    localparam V_ACTIVE_720P        = 720;
    localparam V_FRONTPORCH_720P    = 5;
    localparam V_SYNC_720P          = 5;
    localparam V_BACKPORCH_720P     = 20;
    localparam V_TOTAL_720P         = 750;

    // 576p/576i timing (720x576 @ 50Hz - PAL)
    localparam H_ACTIVE_576P        = 720;
    localparam H_FRONTPORCH_576P    = 12;
    localparam H_SYNC_576P          = 64;
    localparam H_BACKPORCH_576P     = 68;
    localparam H_TOTAL_576P         = 864;
    
    localparam V_ACTIVE_576P        = 576;
    localparam V_FRONTPORCH_576P    = 5;
    localparam V_SYNC_576P          = 5;
    localparam V_BACKPORCH_576P     = 39;
    localparam V_TOTAL_576P         = 625;

    //576i timing (720x576 @ 50Hz - PAL)
    localparam H_ACTIVE_576I        = 720;
    localparam H_FRONTPORCH_576I    = 12;
    localparam H_SYNC_576I          = 64;
    localparam H_BACKPORCH_576I     = 68;
    localparam H_TOTAL_576I         = 864;

    localparam V_ACTIVE_576I        = 288;
    localparam V_FRONTPORCH_576I    = 3;
    localparam V_SYNC_576I          = 5;
    localparam V_BACKPORCH_576I     = 19;
    localparam V_TOTAL_576I         = 312.5;


    // DUT signals
    reg         pixel_clk;
    reg         rst_n;
    reg         hsync;
    reg         vsync;
    reg         de;
    reg [23:0]  rgb;

    reg [11:0]   decode_h_active_width;       // Expected active width
    reg [11:0]   decode_h_sync_width;         // Expected HSYNC width (For noise filtering)
    reg [11:0]   decode_h_backporch;          // Expected H Backporch (For aligning image if no DE)
    reg [11:0]   decode_v_active_lines;       // Expected active lines
    reg [11:0]   decode_v_sync_width;         // Expected VSYNC width
    reg [11:0]   decode_v_backporch;          // Expected V Backporch (For aligning image)
    reg          decode_force_interlaced;     // 1 = Force Interlaced mode (override detection)
    reg          decode_force_progressive;    // 1 = Force Progressive mode (override detection)
    reg          decode_ignore_de;  
    
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
    wire        pixel_valid;
    wire [23:0] pixel_data;
    wire        line_start;
    wire        frame_start;

    // Instantiate DUT
    SyncDecoder #(
        .TOLERANCE(4),
        .STABILITY_COUNT(2),
        .ENABLE_INTERLACE_DETECTION(1)
    ) dut (
        .pixel_clk(pixel_clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .rgb(rgb),
        .cfg_h_active_width(decode_h_active_width),   // Expected active width
        .cfg_h_sync_width(decode_h_sync_width),     // Expected HSYNC width (For noise filtering)
        .cfg_h_backporch(decode_h_backporch),      // Expected H Backporch (For aligning image if no DE)
        .cfg_v_active_lines(decode_v_active_lines),   // Expected active lines
        .cfg_v_sync_width(decode_v_sync_width),     // Expected VSYNC width
        .cfg_v_backporch(decode_v_backporch),      // Expected V Backporch (For aligning image)
        .cfg_force_interlaced(decode_force_interlaced),  // 1 = Force Interlaced mode (override detection)
        .cfg_force_progressive(decode_force_progressive), // 1 = Force Progressive mode (override detection)
        .cfg_ignore_de(decode_ignore_de),  
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
        .pixel_valid(pixel_valid),
        .pixel_data(pixel_data),
        .line_start(line_start),
        .frame_start(frame_start)
    );

    // Clock generation
    initial begin
        pixel_clk = 0;
        forever #(CLK_PERIOD/2) pixel_clk = ~pixel_clk;
    end

    // Test variables
    integer h_pos, v_pos;
    integer test_mode;
    integer h_total_cfg, v_total_cfg;
    integer h_sync_cfg, v_sync_cfg;
    integer h_active_cfg, v_active_cfg;
    integer h_frontporch_cfg, v_frontporch_cfg;
    integer h_backporch_cfg, v_backporch_cfg;
    integer frame_count;
    integer pixel_count;
    reg interlaced_mode;

    // Task: Generate one frame of video
    task generate_frame;
        input integer mode;
        begin
            // Set timing parameters based on mode
            case (mode)
                TEST_480P: begin
                    h_total_cfg                 = H_TOTAL_480P;
                    h_active_cfg                = H_ACTIVE_480P;
                    h_sync_cfg                  = H_SYNC_480P;
                    h_frontporch_cfg            = H_FRONTPORCH_480P;
                    h_backporch_cfg             = H_BACKPORCH_480P;
                    v_total_cfg                 = V_TOTAL_480P;
                    v_active_cfg                = V_ACTIVE_480P;
                    v_sync_cfg                  = V_SYNC_480P;
                    v_frontporch_cfg            = V_FRONTPORCH_480P;
                    v_backporch_cfg             = V_BACKPORCH_480P;
                    interlaced_mode             = 0;

                    decode_h_active_width       = H_ACTIVE_480P;       // Expected active width
                    decode_h_sync_width         = H_SYNC_480P;         // Expected HSYNC width (For noise filtering)
                    decode_h_backporch          = H_BACKPORCH_480P;          // Expected H Backporch (For aligning image if no DE)
                    decode_v_active_lines       = V_ACTIVE_480P;       // Expected active lines
                    decode_v_sync_width         = V_SYNC_480P;         // Expected VSYNC width
                    decode_v_backporch          = V_BACKPORCH_480P;          // Expected V Backporch (For aligning image)
                    decode_force_interlaced     = 1'b0;     // 1 = Force Interlaced mode (override detection)
                    decode_force_progressive    = 1'b0;    // 1 = Force Progressive mode (override detection)
                    decode_ignore_de            = 1'b0;



                    if (frame_count == 0)
                        $display("\n=== Generating 480p (NTSC) Frame ===");
                end
                TEST_720P: begin
                    h_total_cfg                 = H_TOTAL_720P;
                    h_active_cfg                = H_ACTIVE_720P;
                    h_sync_cfg                  = H_SYNC_720P;
                    h_frontporch_cfg            = H_FRONTPORCH_720P;
                    h_backporch_cfg             = H_BACKPORCH_720P;
                    v_total_cfg                 = V_TOTAL_720P;
                    v_active_cfg                = V_ACTIVE_720P;
                    v_sync_cfg                  = V_SYNC_720P;
                    v_frontporch_cfg            = V_FRONTPORCH_720P;
                    v_backporch_cfg             = V_BACKPORCH_720P;
                    interlaced_mode             = 0;

                    decode_h_active_width       = H_ACTIVE_720P;       // Expected active width
                    decode_h_sync_width         = H_SYNC_720P;         // Expected HSYNC width (For noise filtering)
                    decode_h_backporch          = H_BACKPORCH_720P;          // Expected H Backporch (For aligning image if no DE)
                    decode_v_active_lines       = V_ACTIVE_720P;       // Expected active lines
                    decode_v_sync_width         = V_SYNC_720P;         // Expected VSYNC width
                    decode_v_backporch          = V_BACKPORCH_720P;          // Expected V Backporch (For aligning image)
                    decode_force_interlaced     = 1'b0;     // 1 = Force Interlaced mode (override detection)
                    decode_force_progressive    = 1'b0;    // 1 = Force Progressive mode (override detection)
                    decode_ignore_de            = 1'b0;

                    if (frame_count == 0)
                        $display("\n=== Generating 720p (HD) Frame ===");
                end
                TEST_480I: begin
                    h_total_cfg                 = H_TOTAL_480I;
                    h_active_cfg                = H_ACTIVE_480I;
                    h_sync_cfg                  = H_SYNC_480I;
                    h_frontporch_cfg            = H_FRONTPORCH_480I;
                    h_backporch_cfg             = H_BACKPORCH_480I;
                    v_total_cfg                 = V_TOTAL_480I;
                    v_active_cfg                = V_ACTIVE_480I;
                    v_sync_cfg                  = V_SYNC_480I;
                    v_frontporch_cfg            = V_FRONTPORCH_480I;
                    v_backporch_cfg             = V_BACKPORCH_480I;
                    interlaced_mode             = 1;

                    decode_h_active_width       = H_ACTIVE_480I;       // Expected active width
                    decode_h_sync_width         = H_SYNC_480I;         // Expected HSYNC width (For noise filtering)
                    decode_h_backporch          = H_BACKPORCH_480I;          // Expected H Backporch (For aligning image if no DE)
                    decode_v_active_lines       = V_ACTIVE_480I;       // Expected active lines
                    decode_v_sync_width         = V_SYNC_480I;         // Expected VSYNC width
                    decode_v_backporch          = V_BACKPORCH_480I;          // Expected V Backporch (For aligning image)
                    decode_force_interlaced     = 1'b0;     // 1 = Force Interlaced mode (override detection)
                    decode_force_progressive    = 1'b0;    // 1 = Force Progressive mode (override detection)
                    decode_ignore_de            = 1'b0;
                    if (frame_count == 0)
                        $display("\n=== Generating 480i (NTSC) Field ===");
                end
                TEST_576P: begin
                    h_total_cfg                 = H_TOTAL_576P;
                    h_active_cfg                = H_ACTIVE_576P;
                    h_sync_cfg                  = H_SYNC_576P;
                    h_frontporch_cfg            = H_FRONTPORCH_576P;
                    h_backporch_cfg             = H_BACKPORCH_576P;
                    v_total_cfg                 = V_TOTAL_576P;
                    v_active_cfg                = V_ACTIVE_576P;
                    v_sync_cfg                  = V_SYNC_576P;
                    v_frontporch_cfg            = V_FRONTPORCH_576P;
                    v_backporch_cfg             = V_BACKPORCH_576P;
                    interlaced_mode             = 0;

                    decode_h_active_width       = H_ACTIVE_576P;       // Expected active width
                    decode_h_sync_width         = H_SYNC_576P;         // Expected HSYNC width (For noise filtering)
                    decode_h_backporch          = H_BACKPORCH_576P;          // Expected H Backporch (For aligning image if no DE)
                    decode_v_active_lines       = V_ACTIVE_576P;       // Expected active lines
                    decode_v_sync_width         = V_SYNC_576P;         // Expected VSYNC width
                    decode_v_backporch          = V_BACKPORCH_576P;          // Expected V Backporch (For aligning image)
                    decode_force_interlaced     = 1'b0;     // 1 = Force Interlaced mode (override detection)
                    decode_force_progressive    = 1'b0;    // 1 = Force Progressive mode (override detection)
                    decode_ignore_de            = 1'b0;

                    if (frame_count == 0)
                        $display("\n=== Generating 576p (PAL) Frame ===");
                end
                TEST_576I: begin
                    h_total_cfg                 = H_TOTAL_576I;
                    h_active_cfg                = H_ACTIVE_576I;
                    h_sync_cfg                  = H_SYNC_576I;
                    h_frontporch_cfg            = H_FRONTPORCH_576I;
                    h_backporch_cfg             = H_BACKPORCH_576I;
                    v_total_cfg                 = V_TOTAL_576I;
                    v_active_cfg                = V_ACTIVE_576I;
                    v_sync_cfg                  = V_SYNC_576I;
                    v_frontporch_cfg            = V_FRONTPORCH_576I;
                    v_backporch_cfg             = V_BACKPORCH_576I;
                    interlaced_mode             = 1;

                    decode_h_active_width       = H_ACTIVE_576I;       // Expected active width
                    decode_h_sync_width         = H_SYNC_576I;         // Expected HSYNC width (For noise filtering)
                    decode_h_backporch          = H_BACKPORCH_576I;          // Expected H Backporch (For aligning image if no DE)
                    decode_v_active_lines       = V_ACTIVE_576I;       // Expected active lines
                    decode_v_sync_width         = V_SYNC_576I;         // Expected VSYNC width
                    decode_v_backporch          = V_BACKPORCH_576I;          // Expected V Backporch (For aligning image)
                    decode_force_interlaced     = 1'b0;     // 1 = Force Interlaced mode (override detection)
                    decode_force_progressive    = 1'b0;    // 1 = Force Progressive mode (override detection)
                    decode_ignore_de            = 1'b0;
                    if (frame_count == 0)
                        $display("\n=== Generating 576i (PAL) Field ===");
                end
            endcase

            pixel_count = 0;
            
            // Generate frame
            for (v_pos = 0; v_pos < v_total_cfg; v_pos = v_pos + 1) begin
                for (h_pos = 0; h_pos < h_total_cfg; h_pos = h_pos + 1) begin
                    // HSYNC generation
                    if (h_pos < h_sync_cfg)
                        hsync <= 1'b1;
                    else
                        hsync <= 1'b0;
                    
                    // VSYNC generation (with interlace offset)
                    if (interlaced_mode && (frame_count % 2 == 1)) begin
                        // Second field: VSYNC at half-line offset
                        if ( (v_pos == 0 && h_pos >= (h_total_cfg/2)) || 
                             (v_pos > 0 && v_pos < v_sync_cfg) ||
                             (v_pos == v_sync_cfg && h_pos < (h_total_cfg/2)))
                            vsync <= 1'b1;
                        else
                            vsync <= 1'b0;
                    end else begin
                        // First field or progressive
                        if (v_pos < v_sync_cfg)
                            vsync <= 1'b1;
                        else
                            vsync <= 1'b0;
                    end
                    
                    // DE (data enable) generation
                    if ((h_pos >= h_sync_cfg + h_backporch_cfg) && 
                        (h_pos < h_sync_cfg + h_backporch_cfg + h_active_cfg) &&
                        (v_pos >= v_sync_cfg + v_backporch_cfg) && 
                        (v_pos < v_sync_cfg + v_backporch_cfg + v_active_cfg)) begin
                        de <= 1'b1;
                        // Generate test pattern (row/col encoding)
                        rgb <= {v_pos[7:0], h_pos[7:0], 8'h00};
                        pixel_count <= pixel_count + 1;
                    end else begin
                        de <= 1'b0;
                        rgb <= 24'h000000;
                    end
                    
                    @(posedge pixel_clk);
                end
            end
            
            frame_count = frame_count + 1;
            //$display("Generated frame/field %0d with %0d active pixels", frame_count, pixel_count);
        end
    endtask

    // Task: Check measurements
    task check_measurements;
        input integer expected_h_total;
        input integer expected_h_active;
        input integer expected_h_sync;
        input integer expected_h_backporch;
        input integer expected_v_total;
        input integer expected_v_active;
        input integer expected_v_sync;
        input integer expected_v_backporch;
        input integer expected_interlaced;
        
        reg pass;
        begin
            pass = 1;
            
            $display("\n========================================");
            $display("Measurement Results:");
            $display("========================================");
            $display("H_TOTAL:     %4d (expected %4d) %s", h_total, expected_h_total, 
                     (h_total == expected_h_total) ? "[PASS]" : "[FAIL]");
            $display("H_ACTIVE:    %4d (expected %4d) %s", h_active, expected_h_active,
                     (h_active == expected_h_active) ? "[PASS]" : "[FAIL]");
            $display("H_SYNC:      %4d (expected %4d) %s", h_sync_len, expected_h_sync,
                     (h_sync_len == expected_h_sync) ? "[PASS]" : "[FAIL]");
            $display("H_BACKPORCH: %4d (expected %4d) %s", h_backporch, expected_h_backporch,
                     (h_backporch == expected_h_backporch) ? "[PASS]" : "[FAIL]");
            $display("V_TOTAL:     %4d (expected %4d) %s", v_total, expected_v_total,
                     (v_total == expected_v_total) ? "[PASS]" : "[FAIL]");
            $display("V_ACTIVE:    %4d (expected %4d) %s", v_active, expected_v_active,
                     (v_active == expected_v_active) ? "[PASS]" : "[FAIL]");
            $display("V_SYNC:      %4d (expected %4d) %s", v_sync_len, expected_v_sync,
                     (v_sync_len == expected_v_sync) ? "[PASS]" : "[FAIL]");
            $display("V_BACKPORCH: %4d (expected %4d) %s", v_backporch, expected_v_backporch,
                     (v_backporch == expected_v_backporch) ? "[PASS]" : "[FAIL]");
            $display("INTERLACED:  %4d (expected %4d) %s", interlaced, expected_interlaced,
                     (interlaced == expected_interlaced) ? "[PASS]" : "[FAIL]");
            
            if (h_active == expected_h_active && 
                v_active == expected_v_active && 
                interlaced == expected_interlaced &&
                h_total == expected_h_total &&
                v_total == expected_v_total) begin
                $display(">>> PASS: Mode detected correctly!");
            end else begin
                $display(">>> FAIL: Mode detection mismatch!");
                pass = 0;
            end
        end
    endtask

    // Test procedure
    initial begin
        $display("========================================");
        $display("SyncDecoder Testbench");
        $display("Testing NTSC and PAL signals");
        $display("========================================");
        
        // Initialize
        rst_n <= 0;
        hsync <= 0;
        vsync <= 0;
        de <= 0;
        rgb <= 24'h000000;
        frame_count = 0;
        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        // ==========================================
        // Test 1: 480p NTSC progressive
        // ==========================================
        $display("\n>>> TEST 1: NTSC 480p Progressive");
        test_mode = TEST_480P;
        frame_count = 0;
        repeat (3) generate_frame(TEST_480P);
        
        // *** KEY FIX: Wait while continuing to generate signal! ***
        // The decoder needs stable input to finalize measurements
        // Generate one MORE frame so measurements from frame 3 are latched
        $display("Stabilizing measurements...");
        generate_frame(TEST_480P);
        
        repeat (10) @(posedge pixel_clk);  // Just a small gap
        
        check_measurements(H_TOTAL_480P, H_ACTIVE_480P, H_SYNC_480P, 
                        H_BACKPORCH_480P, V_TOTAL_480P, V_ACTIVE_480P, 
                        V_SYNC_480P, V_BACKPORCH_480P, 0);
        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        // ==========================================
        // Test 2: 480i NTSC interlaced
        // ==========================================
        $display("\n>>> TEST 2: NTSC 480i Interlaced");
        frame_count = 0;
        repeat (10) @(posedge pixel_clk);
        
        test_mode = TEST_480I;
        repeat (10) generate_frame(TEST_480I);  // Two fields
        ///// Fix generation frame for interlaced since there should be two vsync withing 480 vertical lines
        ///// Currently there is just a higher frequency signal i.e. 2x 480 vertical lines instead of 2x 240 :/
        ///// the issue there is is that for the interlaced, the vertical counter is reset
        $display("Stabilizing measurements...");
        repeat (5) generate_frame(TEST_480I);  // Two more fields to stabilize
        
        repeat (10) @(posedge pixel_clk);
        
        check_measurements(H_TOTAL_480I, H_ACTIVE_480I, H_SYNC_480I,
                        H_BACKPORCH_480I, V_TOTAL_480I, V_ACTIVE_480I,
                        V_SYNC_480I, V_BACKPORCH_480I, 1);
                        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        // ==========================================
        // Test 3: 576p PAL progressive
        // ==========================================
        $display("\n>>> TEST 3: PAL 576p Progressive");
        frame_count = 0;
        repeat (10) @(posedge pixel_clk);
        
        test_mode = TEST_576P;
        repeat (3) generate_frame(TEST_576P);
        
        $display("Stabilizing measurements...");
        generate_frame(TEST_576P);
        
        repeat (10) @(posedge pixel_clk);
        
        check_measurements(H_TOTAL_576P, H_ACTIVE_576P, H_SYNC_576P,
                        H_BACKPORCH_576P, V_TOTAL_576P, V_ACTIVE_576P,
                        V_SYNC_576P, V_BACKPORCH_576P, 0);
                        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        // ==========================================
        // Test 4: 576i PAL interlaced
        // ==========================================
        $display("\n>>> TEST 4: PAL 576i Interlaced");
        frame_count = 0;
        repeat (10) @(posedge pixel_clk);
        
        test_mode = TEST_576I;
        repeat (4) generate_frame(TEST_576I);  // Two fields
        
        $display("Stabilizing measurements...");
        repeat (2) generate_frame(TEST_576I);
        
        repeat (10) @(posedge pixel_clk);

        check_measurements(H_TOTAL_576I, H_ACTIVE_576I, H_SYNC_576I,
                        H_BACKPORCH_576I, V_TOTAL_576I, V_ACTIVE_576I,
                        V_SYNC_576I, V_BACKPORCH_576I, 1);
                        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        // ==========================================
        // Test 5: 720p HD
        // ==========================================
        $display("\n>>> TEST 5: 720p HD Progressive");
        frame_count = 0;
        repeat (10) @(posedge pixel_clk);
        
        test_mode = TEST_720P;
        repeat (10) generate_frame(TEST_720P);
        
        $display("Stabilizing measurements...");
        generate_frame(TEST_720P);
        
        repeat (10) @(posedge pixel_clk);
        
        check_measurements(H_TOTAL_720P, H_ACTIVE_720P, H_SYNC_720P,
                        H_BACKPORCH_720P, V_TOTAL_720P, V_ACTIVE_720P,
                        V_SYNC_720P, V_BACKPORCH_720P, 0);
                        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n <= 1;
        repeat (10) @(posedge pixel_clk);
        
        $display("\n========================================");
        $display("All Tests Complete!");
        $display("========================================");
        $display("Tested formats:");
        $display(" NTSC 480p (progressive)");
        $display(" NTSC 480i (interlaced)");
        $display(" PAL 576p (progressive)");
        $display(" PAL 576i (interlaced)");
        $display(" HD 720p (progressive)");
        $display("========================================\n");
        $finish;
    end

    // Monitor
    integer valid_count;
    initial begin
        valid_count = 0;
        forever begin
            @(posedge pixel_clk);
            if (pixel_valid) begin
                valid_count = valid_count + 1;
            end
            if (frame_start) begin
                //$display(" -> Frame start at time %0t (valid pixels: %0d)", $time, valid_count);
                valid_count = 0;
            end
        end
    end

endmodule
