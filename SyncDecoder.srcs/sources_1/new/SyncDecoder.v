`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 
// Create Date: 26.12.2025 12:05:52
// Design Name: 
// Module Name: SyncDecoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Detects video timing parameters from HSYNC/VSYNC signals
// 
// Revision 1.0 - Initial Implementation
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module SyncDecoder #(
    parameter TOLERANCE = 4,  // Tolerance for interlace detection
    parameter STABILITY_COUNT = 3, // Number of consistent frames before locking timing
    parameter ENABLE_INTERLACE_DETECTION = 1 // Enable interlace detection logic
)(
    input  wire         pixel_clk,
    input  wire         rst_n,
    input  wire         hsync,        // Horizontal sync pulse
    input  wire         vsync,        // Vertical sync pulse
    input  wire         de,           // Data enable (optional) - added for compatibilty with analog frontends
    input  wire [23:0]  rgb,          // Pixel data

    // Configuration inputs
    input wire [11:0]   cfg_h_active_width,   // Expected active width
    input wire [11:0]   cfg_h_sync_width,     // Expected HSYNC width (For noise filtering)
    input wire [11:0]   cfg_h_backporch,      // Expected H Backporch (For aligning image if no DE)
    
    input wire [11:0]   cfg_v_active_lines,   // Expected active lines
    input wire [11:0]   cfg_v_sync_width,     // Expected VSYNC width
    input wire [11:0]   cfg_v_backporch,      // Expected V Backporch (For aligning image)
    
    input wire          cfg_force_interlaced,  // 1 = Force Interlaced mode (override detection)
    input wire          cfg_force_progressive, // 1 = Force Progressive mode (override detection)
    input wire          cfg_ignore_de,         // 1 = Ignore hardware DE, generate internally using cfg values

    // Detected timing parameters
    output reg [11:0]   h_total,       // Total pixels per line
    output reg [11:0]   h_active,      // Active pixels per line
    output reg [11:0]   h_sync_len,    // HSYNC pulse width
    output reg [11:0]   h_backporch,   // Back porch length
    
    output reg [11:0]   v_total,       // Total lines per frame
    output reg [11:0]   v_active,      // Active lines per frame
    output reg [11:0]   v_sync_len,    // VSYNC pulse width
    output reg [11:0]   v_backporch,   // Back porch length
    
    output reg  interlaced,    // 1=interlaced, 0=progressive
    output reg  field_id,      // Current field (odd/even)
    
    // Position counters
    output reg [11:0]   h_count,       // Current horizontal position
    output reg [11:0]   v_count,       // Current vertical position
    
    // Output stream (synchronized to active region)
    output wire         pixel_valid,
    output wire [23:0]  pixel_data,
    output wire         line_start,
    output wire         frame_start
);
    
    //reg hsync_idle_level;
    //reg vsync_idle_level;
    //reg polarity_locked;
    //wire hsync_active   = (hsync != hsync_idle_level);
    //wire vsync_active   = (vsync != vsync_idle_level);
    
    reg hsync_d;
    reg vsync_d;
    reg de_d;
    //wire hsync_start = (hsync != hsync_idle_level) && (hsync_d == hsync_idle_level);
    //wire hsync_end   = (hsync == hsync_idle_level) && (hsync_d != hsync_idle_level);
    //wire vsync_start = (vsync != vsync_idle_level) && (vsync_d == vsync_idle_level);
    //wire vsync_end   = (vsync == vsync_idle_level) && (vsync_d != vsync_idle_level);
    //wire de_start    = (de && !de_d);

    wire hsync_start    = (hsync && !hsync_d);
    wire hsync_end      = (!hsync && hsync_d);
    wire vsync_start    = (vsync && !vsync_d);
    wire vsync_end      = (!vsync && vsync_d);
    wire de_start       = (de && !de_d);
    
    wire internal_h_active  = (h_count >= h_sync_len + cfg_h_backporch) && 
                              (h_count <  h_sync_len + cfg_h_backporch + cfg_h_active_width);
    
    //reg [11:0] vsync_h_pos;
    //always @(posedge pixel_clk or negedge rst_n) begin
    //    if (!rst_n) begin
    //        vsync_h_pos <= 0;
    //    end else if (vsync && !vsync_d) begin
    //        // Capture h_count at the exact moment VSYNC goes high
    //        vsync_h_pos <= h_count;
    //    end
    //end
    
    wire is_vsync_mid_line  = (h_count > ((h_total >> 1) - h_sync_len) - TOLERANCE) &&     
                              (h_count < ((h_total >> 1) - h_sync_len) + TOLERANCE);
    
    // Measurement registers
    reg [11:0] h_sync_count;
    reg [11:0] h_de_count;
    reg [11:0] h_de_start;
    reg [11:0] v_sync_count;
    reg [11:0] v_de_count;
    reg [11:0] v_de_start;
    reg [11:0] vsync_h_position;
    reg        line_has_de;

    // Edge detection
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync_d <= 1'b0;
            vsync_d <= 1'b0;
            de_d    <= 1'b0;
        end else begin
            hsync_d <= hsync;
            vsync_d <= vsync;
            de_d    <= de;
        end
    end

    // Determine HSYNC & VSYNC idle level
    //always @(posedge pixel_clk or negedge rst_n) begin
    //    if (!rst_n) begin
    //        hsync_idle_level <= 1'b1;
    //        vsync_idle_level <= 1'b1;
    //        polarity_locked <= 1'b0;
    //    end else begin
    //        if (!de && !polarity_locked) begin
    //            hsync_idle_level <= hsync;
    //            vsync_idle_level <= vsync;
    //        end
    //        
    //        // Lock polarity after first VSYNC detection
    //        if (vsync_start) begin
    //            polarity_locked <= 1'b1;
    //        end
    //    end
    //end

    // Horizontal pixel counter
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 1'b0;
            h_total <= 1'b0;
        end else if (hsync_end) begin
            h_total <= h_count + 1'b1;
            h_count <= 0;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    // Measure HSYNC pulse width
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_sync_count <= 0;
            h_sync_len   <= 0;
        end else begin
            if (hsync_end) begin
                h_sync_len   <= h_sync_count;
                h_sync_count <= 0;
            end else if (hsync) begin
                h_sync_count <= h_sync_count + 1'b1;
            end
        end
    end

    // Measure horizontal active pixels and backporch
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_de_count  <= 0;
            h_de_start  <= 0;
            h_active    <= 0;
            h_backporch <= 0;
        end else begin
            if (de) begin
                h_de_count <= h_de_count + 1'b1;  // Only count while DE is high
            end

            if (hsync_end) begin
                h_active   <= h_de_count;
            end
            
            if (de_start) begin
                h_backporch <= h_count + 1'b1; //From hsync_end to de_start is the backporch
                h_de_count  <= 1'b1;  // Start counting from 1 on first DE pixel
            end
        end
    end
    
    // Vertical line counter
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 0;
            v_total <= 0;
        end else begin
            if (vsync_start) begin
                v_total <= v_count;
                v_count <= 0;
            end else if (hsync_end) begin
                v_count <= v_count + 1'b1;
            end
        end
    end

    // Measure VSYNC pulse width
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_sync_count <= 0;
            v_sync_len   <= 0;
        end else begin 
            if (vsync_start) begin
                v_sync_count <= 1'b0;
            end else if (vsync_end) begin
                v_sync_len   <= v_sync_count;    
            end else if (vsync && hsync_end) begin
                v_sync_count <= v_sync_count + 1'b1;
            end
        end
    end

    // Measure vertical active lines and backporch
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_de_count  <= 0;
            v_de_start  <= 0;
            v_active    <= 0;
            v_backporch <= 0;
            line_has_de <= 1'b0;
        end else begin
            if (vsync_start) begin
                v_active   <= v_de_count;
                v_de_count <= 0;
                line_has_de <= 1'b0;
            end else if (hsync_end) begin
                if (line_has_de) begin
                    if (v_de_count == 0) begin
                        v_backporch <= v_count - v_sync_len; // -1 bandaid solution for timing issue
                        v_de_start  <= v_count;
                    end
                    v_de_count <= v_de_count + 1'b1;
                end
                line_has_de <= 1'b0;
            end else if (de) begin
                line_has_de <= 1'b1;
            end
        end
    end
    
    // ---------------------------------------------------------
    // Interlace detection - VSYNC occurs mid-line in interlaced signals
    // ---------------------------------------------------------
    generate
        if (ENABLE_INTERLACE_DETECTION) begin : gen_interlace_logic
            reg auto_interlaced;
            reg [3:0] interlace_confidence;
            always @(posedge pixel_clk or negedge rst_n) begin
                if (!rst_n) begin
                    interlaced         <= 1'b0;
                    field_id           <= 1'b0;
                    interlace_confidence <= 4'b0;
                end else if (vsync_start) begin
                    // Update Confidence
                    if (is_vsync_mid_line) begin
                        if (interlace_confidence < STABILITY_COUNT)
                            interlace_confidence <= interlace_confidence + 1'b1;
                    end else begin
                        if (interlace_confidence > 0)
                            interlace_confidence <= interlace_confidence - 1'b1;
                    end

                    // Determine "Auto" State
                    if (interlace_confidence >= STABILITY_COUNT) begin
                        auto_interlaced <= 1'b1;
                    end else if (interlace_confidence == 0) begin
                        auto_interlaced <= 1'b0;
                    end else begin
                        auto_interlaced <= interlaced;
                    end
                    
                    // Force/Override Logic
                    if (cfg_force_interlaced) begin
                        interlaced <= 1'b1;
                    end else if (cfg_force_progressive) begin
                        interlaced <= 1'b0;
                    end else begin
                        interlaced <= auto_interlaced;
                    end

                    if (interlaced || cfg_force_interlaced) begin
                        if (is_vsync_mid_line) begin
                            field_id <= 1'b1;
                        end else begin
                            field_id <= 1'b0;
                        end
                    end else begin
                        field_id <= 1'b0; // Progressive mode, always field 0
                    end
                end
            end
        end else begin : gen_no_interlace
            // When interlace detection is disabled
            always @(posedge pixel_clk or negedge rst_n) begin
                if (!rst_n) begin
                    interlaced           <= 1'b0;
                    field_id             <= 1'b0;
                end else begin
                    if (cfg_force_interlaced) begin
                        interlaced <= 1'b1;
                        // In forced mode without detection, toggle field on each VSYNC
                        if (vsync_start) begin
                            field_id <= ~field_id;
                        end
                    end else if (cfg_force_progressive) begin
                        interlaced <= 1'b0;
                        field_id   <= 1'b0;
                    end
                end
            end
        end
    endgenerate
    

    // Output assignments
    assign pixel_valid = (cfg_ignore_de) ? internal_h_active : de;
    assign pixel_data   = rgb;
    assign line_start   = hsync_start;
    assign frame_start  = vsync_start;

    // Debugging output
    //always @(posedge pixel_clk) begin
    //    if (hsync_start)
    //        $display("Time=%0t: HSYNC-START h_count=%0d, h_total=%0d", $time, h_count, h_total);
    //    if (hsync_end)
    //        $display("Time=%0t: HSYNC-END - h_sync_count=%0d",$time, h_sync_count);
    //end
    
    //initial begin
    //    $monitor("Time=%0t: hsync=%b hsync_d=%b rising=%b h_count=%0d h_total=%0d",
    //    $time, hsync, hsync_d, hsync_start, h_count, h_total);
    //end
    //--------------------

endmodule
