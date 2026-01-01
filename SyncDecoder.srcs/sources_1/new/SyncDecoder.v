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
    input  wire         hsync,         
    input  wire         vsync,
    input  wire         de,
    input  wire [23:0]  rgb,

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
    
    output reg  interlaced,            // 1=interlaced, 0=progressive
    output reg  field_id,              // Current field (odd/even)
    
    // Position counters
    output reg [11:0]   h_count,       // Current horizontal position
    output reg [11:0]   v_count,       // Current vertical position
    
    // Output stream (synchronized to active region)
    output wire         pixel_valid,
    output wire [23:0]  pixel_data,
    output wire         line_start,
    output wire         frame_start
);
    
    // Polarity detection registers
    reg hsync_idle_level;
    reg vsync_idle_level;
    reg polarity_locked;

    // Delayed signals for edge detection
    reg hsync_d;
    reg vsync_d;
    reg de_d;

    // Active signals
    wire hsync_active   = (hsync != hsync_idle_level);
    wire vsync_active   = (vsync != vsync_idle_level);

    // Edge detection (polarity-aware)
    wire hsync_start = polarity_locked && (hsync != hsync_idle_level) && (hsync_d == hsync_idle_level);
    wire hsync_end   = polarity_locked && (hsync == hsync_idle_level) && (hsync_d != hsync_idle_level);
    wire vsync_start = polarity_locked && (vsync != vsync_idle_level) && (vsync_d == vsync_idle_level);
    wire vsync_end   = polarity_locked && (vsync == vsync_idle_level) && (vsync_d != vsync_idle_level);
    wire de_start    = (de && !de_d);
    
    wire internal_h_active  = (h_count >= h_sync_len + cfg_h_backporch) && 
                              (h_count <  h_sync_len + cfg_h_backporch + cfg_h_active_width);
    
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

    // Polarity detection - sample idle level during blanking periods
    reg [15:0] blanking_sample_count;
    reg [15:0] hsync_high_count;
    reg [15:0] vsync_high_count;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync_idle_level <= 1'b1;
            vsync_idle_level <= 1'b1;
            polarity_locked <= 1'b0;
            blanking_sample_count <= 16'b0;
            hsync_high_count <= 16'b0;
            vsync_high_count <= 16'b0;
        end else begin
            if (!polarity_locked) begin
                if (!de) begin // Sample during blanking period (no DE active)
                    if (blanking_sample_count < 16'd10000) begin
                        blanking_sample_count <= blanking_sample_count + 1'b1;

                        // Count how often each signal is high during blanking
                        if (hsync)
                            hsync_high_count <= hsync_high_count + 1'b1;
                        if (vsync)
                            vsync_high_count <= vsync_high_count + 1'b1;
                    end else begin
                        hsync_idle_level <= (hsync_high_count > (blanking_sample_count - (blanking_sample_count >> 2)));
                        vsync_idle_level <= (vsync_high_count > (blanking_sample_count - (blanking_sample_count >> 2)));
                        polarity_locked <= 1'b1;
                    end
                end
            end
        end
    end

    // Horizontal pixel counter
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 12'b0;
            h_total <= 12'b0;
        end else if (hsync_end) begin
            h_total <= h_count + 12'b1;
            h_count <= 12'b0;
        end else begin
            h_count <= h_count + 12'b1;
        end
    end

    // Measure HSYNC pulse width
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_sync_count <= 12'b0;
            h_sync_len   <= 12'b0;
        end else begin
            if (hsync_end) begin
                h_sync_len   <= h_sync_count;
                h_sync_count <= 12'b0;
            end else if (hsync_active) begin
                h_sync_count <= h_sync_count + 12'b1;
            end
        end
    end

    // Measure horizontal active pixels and backporch
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_de_count  <= 12'b0;
            h_de_start  <= 12'b0;
            h_active    <= 12'b0;
            h_backporch <= 12'b0;
        end else begin
            if (de) begin
                h_de_count <= h_de_count + 12'b1;  // Only count while DE is high
            end

            if (hsync_end) begin
                h_active   <= h_de_count;
            end
            
            if (de_start) begin
                h_backporch <= h_count + 12'b1; //From hsync_end to de_start is the backporch
                h_de_count  <= 12'b1;  // Start counting from 1 on first DE pixel
            end
        end
    end
    
    // Polarity lock detection (rising edge)
    reg polarity_locked_d;
    wire polarity_just_locked = polarity_locked && !polarity_locked_d;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n)
            polarity_locked_d <= 1'b0;
        else
            polarity_locked_d <= polarity_locked;
    end

    // Vertical line counter
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 12'b0;
            v_total <= 12'b0;
        end else if (vsync_start) begin
            v_total <= v_count;
            v_count <= 12'b0;
        end else if (hsync_end) begin
            v_count <= v_count + 12'b1;
        end
    end

    // Measure VSYNC pulse width
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_sync_count <= 12'b0;
            v_sync_len   <= 12'b0;
        end else begin
            if (vsync_start) begin
                v_sync_count <= 12'b0;
            end else if (vsync_end) begin
                v_sync_len   <= v_sync_count;
            end else if (vsync_active && hsync_end) begin
                v_sync_count <= v_sync_count + 12'b1;
            end
        end
    end

    // Measure vertical active lines and backporch
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_de_count  <= 12'b0;
            v_de_start  <= 12'b0;
            v_active    <= 12'b0;
            v_backporch <= 12'b0;
            line_has_de <= 1'b0;
        end else begin
            if (vsync_start) begin
                v_active   <= v_de_count;
                v_de_count <= 12'b0;
                line_has_de <= 1'b0;
            end else if (hsync_end) begin
                if (line_has_de) begin
                    if (v_de_count == 0) begin
                        v_backporch <= v_count - v_sync_len; // -1 bandaid solution for timing issue
                        v_de_start  <= v_count;
                    end
                    v_de_count <= v_de_count + 12'b1;
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
        if (ENABLE_INTERLACE_DETECTION) begin : gen_interlace_detection_logic
            reg auto_interlaced = 1'b0;
            reg [3:0] interlace_confidence = 4'b0;
            reg [11:0] vsync_h_pos_latched = 12'b0;
            reg is_vsync_mid_line_latched = 1'b0;

            // Check if current h_count indicates mid-line (half-line for interlace)
            // For interlaced: even fields start VSYNC at ~h_total/2, odd fields at ~0
            wire [11:0] half_line = h_total >> 1;
            wire is_vsync_mid_line_now = (h_count >= ((half_line - h_sync_len) - TOLERANCE)) &&
                                          (h_count <= ((half_line - h_sync_len) + TOLERANCE));

            // Latch h_count position and mid-line status when VSYNC starts
            always @(posedge pixel_clk or negedge rst_n) begin
                if (!rst_n) begin
                    vsync_h_pos_latched <= 12'b0;
                    is_vsync_mid_line_latched <= 1'b0;
                end else if (vsync_start) begin
                    vsync_h_pos_latched <= h_count;
                    is_vsync_mid_line_latched <= is_vsync_mid_line_now;
                end
            end

            always @(posedge pixel_clk or negedge rst_n) begin
                if (!rst_n) begin
                    auto_interlaced      <= 1'b0;
                    interlaced           <= 1'b0;
                    field_id             <= 1'b0;
                    interlace_confidence <= 4'b0;
                end else if (vsync_start) begin
                    if (is_vsync_mid_line_now) begin
                        if (interlace_confidence < (STABILITY_COUNT + 2))
                            interlace_confidence <= interlace_confidence + 2'b10;
                    end else begin
                        // Decrement slower to avoid flicker
                        if (interlace_confidence > 0)
                            interlace_confidence <= interlace_confidence - 1'b1;
                    end

                    // Determine "Auto" State with clear thresholds
                    if (interlace_confidence >= STABILITY_COUNT) begin
                        auto_interlaced <= 1'b1;
                    end else if (interlace_confidence <= 1) begin
                        auto_interlaced <= 1'b0;
                    end

                    // Apply Force/Override Logic
                    if (cfg_force_interlaced) begin
                        interlaced <= 1'b1;
                    end else if (cfg_force_progressive) begin
                        interlaced <= 1'b0;
                    end else begin
                        interlaced <= auto_interlaced;
                    end

                    // Determine field ID based on VSYNC position
                    if (interlaced || cfg_force_interlaced) begin
                        field_id <= is_vsync_mid_line_now ? 1'b1 : 1'b0;
                    end else begin
                        field_id <= 1'b0; // Progressive mode, always field 0
                    end
                end
            end
        end else begin : gen_no_auto_interlace_detection
            // When interlace detection is disabled
            always @(posedge pixel_clk or negedge rst_n) begin
                if (!rst_n) begin
                    interlaced           <= 1'b0;
                    field_id             <= 1'b0;
                end else begin
                    if (cfg_force_interlaced) begin
                        interlaced <= 1'b1;
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

endmodule
