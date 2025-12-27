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
    parameter TOLERANCE = 4  // Tolerance for interlace detection
)(
    input  wire         pixel_clk,
    input  wire         rst_n,
    input  wire         hsync,        // Horizontal sync pulse
    input  wire         vsync,        // Vertical sync pulse
    input  wire         de,           // Data enable (optional) - added for compatibilty with analog frontends
    input  wire [23:0]  rgb,          // Pixel data
    
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

    // Edge detection registers
    reg hsync_d;
    reg vsync_d;
    reg de_d;
    //reg hsync_idle_level;
    //wire hsync_active   = (hsync != hsync_idle_level);
    wire hsync_start    = (hsync && !hsync_d);
    wire hsync_end      = (!hsync && hsync_d);
    wire vsync_start    = (vsync && !vsync_d);
    wire vsync_end      = (!vsync && vsync_d);
    wire de_start       = (de && !de_d);

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
    
    // Determine HSYNC idle level
    //always @(posedge pixel_clk or negedge rst_n) begin
    //    if (!rst_n) begin
    //        hsync_idle_level <= 1'b1; // Default to active-low sync (idle = 1) which is standard for VGA/HDMI
    //    end else if (de_start) begin
    //        hsync_idle_level <= hsync_d;
    //    end
    //end

    // Horizontal pixel counter (good)
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

    // Vertical line counter (good)
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 0;
            v_total <= 0;
        end else if (vsync_start) begin
            v_total <= v_count + 1'b1;
            v_count <= 0;
        end else if (hsync_end) begin
            v_count <= v_count + 1'b1;
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

            if (hsync_end) begin
                h_active   <= h_de_count;
            end
            
            if (de_start) begin
                h_backporch <= h_count; //From hsync_end to de_start is the backporch
                h_de_count  <= 1'b0;  // Start counting from 1 on first DE pixel
            end else if (de) begin
                h_de_count <= h_de_count + 1'b1;  // Only count while DE is high
            end

            //if (hsync_end) begin
            //    h_active    <= h_de_count;
            //    h_de_count  <= 0;
            //end else if (de_start) begin
            //    h_backporch <= h_count - h_sync_len;
            //    h_de_start  <= h_count;
            //    h_de_count  <= 1'b1;  // Start counting from 1 on first DE pixel
            //end else if (de) begin
            //    h_de_count <= h_de_count + 1'b1;  // Only count while DE is high
            //end
        end
    end

    // Measure VSYNC pulse width
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_sync_count <= 0;
            v_sync_len   <= 0;
        end else begin 
            if (vsync_end) begin
                v_sync_len   <= v_sync_count;
                v_sync_count <= 1'b0;
            end else if (vsync && hsync_start) begin
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
                        v_backporch <= v_count - v_sync_len;
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

    // Interlace detection - VSYNC occurs mid-line in interlaced signals
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            interlaced         <= 1'b0;
            field_id           <= 1'b0;
            vsync_h_position   <= 0;
        end else if (vsync_start && h_total > 0) begin
            vsync_h_position <= h_count;
            
            // Check if VSYNC occurs near half-line position
            if ((h_count > (h_total/2 - TOLERANCE)) && 
                (h_count < (h_total/2 + TOLERANCE))) begin
                interlaced <= 1'b1;  // VSYNC is mid-line: interlaced
            end else begin
                interlaced <= 1'b0;  // VSYNC is at line start: progressive
            end
            
            field_id <= ~field_id; // Field ID toggles each VSYNC
        end
    end

    // Output assignments
    assign pixel_valid  = de;
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
