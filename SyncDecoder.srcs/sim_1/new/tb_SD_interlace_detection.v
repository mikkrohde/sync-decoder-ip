`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.12.2025 01:03:02
// Design Name: 
// Module Name: tb_SD_interlace_detection
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_SD_interlace_detection;
    localparam CLK_PERIOD = 10;  // 100 MHz
    
    // 480i timing (same as 480p but interlaced)
    localparam H_ACTIVE_480I        = 640;
    localparam H_FRONTPORCH_480I    = 16;
    localparam H_SYNC_480I          = 96;
    localparam H_BACKPORCH_480I     = 48;
    localparam H_TOTAL_480I         = 800;
    
    localparam V_ACTIVE_480I        = 480;
    localparam V_FRONTPORCH_480I    = 10;
    localparam V_SYNC_480I          = 3;  // One extra half-line for field offset
    localparam V_BACKPORCH_480I     = 32;
    localparam V_TOTAL_480I         = 525;
    
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
    wire        pixel_valid;
    wire [23:0] pixel_data;
    wire        line_start;
    wire        frame_start;

    // Instantiate DUT
    SyncDecoder #(
        .TOLERANCE(50)  // Wider tolerance for interlace detection
    ) dut (
        .pixel_clk(pixel_clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .rgb(rgb),
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
    integer field_count;
    integer pixel_count;
    reg     current_field;  // 0 = even field, 1 = odd field

    // Task: Generate one interlaced field
    task generate_interlaced_field;
        input field_type;  // 0 = even/first field, 1 = odd/second field
        begin
            pixel_count = 0;
            
            $display("\n=== Generating Field %0d (field_type=%0d) ===", field_count, field_type);
            
            // Generate field
            for (v_pos = 0; v_pos < V_TOTAL_480I; v_pos = v_pos + 1) begin
                for (h_pos = 0; h_pos < H_TOTAL_480I; h_pos = h_pos + 1) begin
                    
                    // HSYNC generation (normal)
                    if (h_pos < H_SYNC_480I)
                        hsync = 1'b1;
                    else
                        hsync = 1'b0;
                    
                    // VSYNC generation with interlaced offset
                    if (field_type == 0) begin
                        // Even field: VSYNC starts at beginning of line
                        if (v_pos < V_SYNC_480I)
                            vsync = 1'b1;
                        else
                            vsync = 1'b0;
                    end else begin
                        // Odd field: VSYNC starts at mid-line (half-line offset)
                        if (v_pos < V_SYNC_480I) begin
                            if (v_pos == 0 && h_pos < (H_TOTAL_480I/2))
                                vsync = 1'b0;  // First half of line 0: no sync
                            else
                                vsync = 1'b1;
                        end else if (v_pos == V_SYNC_480I && h_pos < (H_TOTAL_480I/2)) begin
                            vsync = 1'b1;  // Extend into first half of next line
                        end else begin
                            vsync = 1'b0;
                        end
                    end
                    
                    // DE (data enable) generation
                    // Only show even/odd lines depending on field
                    if ((h_pos >= H_SYNC_480I + H_BACKPORCH_480I) && 
                        (h_pos < H_SYNC_480I + H_BACKPORCH_480I + H_ACTIVE_480I) &&
                        (v_pos >= V_SYNC_480I + V_BACKPORCH_480I) && 
                        (v_pos < V_SYNC_480I + V_BACKPORCH_480I + V_ACTIVE_480I)) begin
                        
                        // Calculate which display line this would be
                        integer display_line;
                        display_line = v_pos - (V_SYNC_480I + V_BACKPORCH_480I);
                        
                        // Only show lines that match this field's parity
                        if ((display_line % 2) == field_type) begin
                            de = 1'b1;
                            rgb = {v_pos[7:0], h_pos[7:0], field_type ? 8'hAA : 8'h55};
                            pixel_count = pixel_count + 1;
                        end else begin
                            de = 1'b0;
                            rgb = 24'h000000;
                        end
                    end else begin
                        de = 1'b0;
                        rgb = 24'h000000;
                    end
                    
                    @(posedge pixel_clk);
                end
            end
            
            field_count = field_count + 1;
            $display("Generated field %0d with %0d active pixels", field_count, pixel_count);
        end
    endtask

    // Monitor
    integer vsync_count;
    integer last_vsync_h_pos;
    
    initial begin
        vsync_count = 0;
        last_vsync_h_pos = 0;
        
        forever begin
            @(posedge pixel_clk);
            if (frame_start) begin
                $display(" -> VSYNC at time %0t, h_count=%0d (field_id=%0d, interlaced=%0d)", 
                         $time, h_count, field_id, interlaced);
                vsync_count = vsync_count + 1;
                last_vsync_h_pos = h_count;
            end
        end
    end

    // Test procedure
    initial begin
        $display("========================================");
        $display("SyncDecoder Interlaced Detection Test");
        $display("========================================");
        
        // Initialize
        rst_n = 0;
        hsync = 0;
        vsync = 0;
        de = 0;
        rgb = 24'h000000;
        field_count = 0;
        current_field = 0;
        
        // Reset
        repeat (10) @(posedge pixel_clk);
        rst_n = 1;
        repeat (10) @(posedge pixel_clk);
        
        $display("\n>>> TEST: 480i NTSC Interlaced");
        $display("Expecting:");
        $display("  - First field: VSYNC at h_count ≈ 0");
        $display("  - Second field: VSYNC at h_count ≈ %0d (half-line)", H_TOTAL_480I/2);
        $display("  - Interlaced flag should be 1");
        
        // Generate several fields
        repeat (6) begin
            generate_interlaced_field(current_field);
            current_field = ~current_field;
        end
        
        // Wait for measurements to stabilize
        repeat (100) @(posedge pixel_clk);
        
        $display("\n========================================");
        $display("Final Measurements:");
        $display("========================================");
        $display("H_TOTAL:     %4d (expected %4d) %s", h_total, H_TOTAL_480I,
                 (h_total == H_TOTAL_480I) ? "[PASS]" : "[FAIL]");
        $display("H_ACTIVE:    %4d (expected %4d) %s", h_active, H_ACTIVE_480I,
                 (h_active == H_ACTIVE_480I) ? "[PASS]" : "[FAIL]");
        $display("V_TOTAL:     %4d (expected %4d) %s", v_total, V_TOTAL_480I,
                 (v_total == V_TOTAL_480I) ? "[PASS]" : "[FAIL]");
        $display("V_ACTIVE:    %4d (expected %4d) %s", v_active, V_ACTIVE_480I,
                 (v_active == V_ACTIVE_480I) ? "[PASS]" : "[FAIL]");
        $display("INTERLACED:  %4d (expected    1) %s", interlaced,
                 (interlaced == 1) ? "[PASS]" : "[FAIL]");
        $display("FIELD_ID:    %4d (toggles each field)", field_id);
        $display("========================================");
        
        if (interlaced == 1) begin
            $display(">>> PASS: Interlaced mode detected correctly!");
        end else begin
            $display(">>> FAIL: Interlaced mode NOT detected!");
            $display("    Check: VSYNC h_positions should alternate between ~0 and ~%0d", H_TOTAL_480I/2);
        end
        
        $display("\n========================================\n");
        $finish;
    end

endmodule