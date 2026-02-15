`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 
// Module Name: SyncDecoder_AXI
// Description: AXI4-Lite wrapper for SyncDecoder module
//              Provides register-based configuration and status monitoring
// 
// Register Map (Active Low Synchronous Reset):
//   Offset  | R/W | Name              | Description
//   --------|-----|-------------------|--------------------------------------------
//   0x00    | R/W | CONTROL           | [0] soft_reset, [1] force_interlaced, 
//          |     |                   | [2] force_progressive, [3] ignore_de
//   0x04    | R   | STATUS            | [0] polarity_locked, [1] interlaced, [2] field_id
//   0x08    | R/W | CFG_H_ACTIVE      | [11:0] Expected horizontal active width
//   0x0C    | R/W | CFG_H_SYNC        | [11:0] Expected HSYNC width
//   0x10    | R/W | CFG_H_BACKPORCH   | [11:0] Expected H backporch
//   0x14    | R/W | CFG_V_ACTIVE      | [11:0] Expected vertical active lines
//   0x18    | R/W | CFG_V_SYNC        | [11:0] Expected VSYNC width
//   0x1C    | R/W | CFG_V_BACKPORCH   | [11:0] Expected V backporch
//   0x20    | R   | DET_H_TOTAL       | [11:0] Detected H total pixels
//   0x24    | R   | DET_H_ACTIVE      | [11:0] Detected H active pixels
//   0x28    | R   | DET_H_SYNC_LEN    | [11:0] Detected HSYNC pulse width
//   0x2C    | R   | DET_H_BACKPORCH   | [11:0] Detected H backporch
//   0x30    | R   | DET_V_TOTAL       | [11:0] Detected V total lines
//   0x34    | R   | DET_V_ACTIVE      | [11:0] Detected V active lines
//   0x38    | R   | DET_V_SYNC_LEN    | [11:0] Detected VSYNC pulse width
//   0x3C    | R   | DET_V_BACKPORCH   | [11:0] Detected V backporch
//   0x40    | R   | POSITION          | [27:16] v_count, [11:0] h_count
//   0x44    | R   | VERSION           | [31:0] IP Version (0x00010000 = v1.0)
//
//////////////////////////////////////////////////////////////////////////////////

module SyncDecoder_AXI #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 7,
    parameter TOLERANCE = 4,
    parameter STABILITY_COUNT = 3,
    parameter ENABLE_INTERLACE_DETECTION = 1,
    parameter IP_VERSION = 32'h00010000
)(
    // AXI4-Lite Slave Interface
    input  wire                                s_axi_aclk,
    input  wire                                s_axi_aresetn,
    
    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire [2:0]                          s_axi_awprot,
    input  wire                                s_axi_awvalid,
    output wire                                s_axi_awready,
    
    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output wire                                s_axi_wready,
    
    // Write response channel
    output wire [1:0]                          s_axi_bresp,
    output wire                                s_axi_bvalid,
    input  wire                                s_axi_bready,
    
    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire [2:0]                          s_axi_arprot,
    input  wire                                s_axi_arvalid,
    output wire                                s_axi_arready,
    
    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_rdata,
    output wire [1:0]                          s_axi_rresp,
    output wire                                s_axi_rvalid,
    input  wire                                s_axi_rready,
    
    // Video Input Interface (directly from video source)
    input  wire                                pixel_clk,
    input  wire                                hsync,
    input  wire                                vsync,
    input  wire                                de,
    
    // VPU Output Stream (active region, directly from SyncDecoder)
    output wire                                VPU_out_valid,
    output wire [23:0]                         VPU_out_pixel,
    output wire                                VPU_out_line_start,
    output wire                                VPU_out_frame_start,
    output wire                                VPU_out_interlaced,
    output wire                                VPU_out_field_id,
    output wire [11:0]                         VPU_out_h_count,
    output wire [11:0]                         VPU_out_v_count,
    output wire [11:0]                         VPU_out_h_active,
    output wire [11:0]                         VPU_out_v_active,
    
    // Interrupt output (directly from SyncDecoder)
    output wire                                irq_frame_start
);

    // Register address offsets
    localparam ADDR_CONTROL         = 7'h00;
    localparam ADDR_STATUS          = 7'h04;
    localparam ADDR_CFG_H_ACTIVE    = 7'h08;
    localparam ADDR_CFG_H_SYNC      = 7'h0C;
    localparam ADDR_CFG_H_BACKPORCH = 7'h10;
    localparam ADDR_CFG_V_ACTIVE    = 7'h14;
    localparam ADDR_CFG_V_SYNC      = 7'h18;
    localparam ADDR_CFG_V_BACKPORCH = 7'h1C;
    localparam ADDR_DET_H_TOTAL     = 7'h20;
    localparam ADDR_DET_H_ACTIVE    = 7'h24;
    localparam ADDR_DET_H_SYNC_LEN  = 7'h28;
    localparam ADDR_DET_H_BACKPORCH = 7'h2C;
    localparam ADDR_DET_V_TOTAL     = 7'h30;
    localparam ADDR_DET_V_ACTIVE    = 7'h34;
    localparam ADDR_DET_V_SYNC_LEN  = 7'h38;
    localparam ADDR_DET_V_BACKPORCH = 7'h3C;
    localparam ADDR_POSITION        = 7'h40;
    localparam ADDR_VERSION         = 7'h44;

    // AXI4-Lite internal signals
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready;
    reg                          axi_wready;
    reg [1:0]                    axi_bresp;
    reg                          axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                    axi_rresp;
    reg                          axi_rvalid;

    // Configuration registers (directly in AXI clock domain)
    reg        reg_soft_reset;
    reg        reg_force_interlaced;
    reg        reg_force_progressive;
    reg        reg_ignore_de;
    reg [11:0] reg_cfg_h_active;
    reg [11:0] reg_cfg_h_sync;
    reg [11:0] reg_cfg_h_backporch;
    reg [11:0] reg_cfg_v_active;
    reg [11:0] reg_cfg_v_sync;
    reg [11:0] reg_cfg_v_backporch;

    // Status registers (directly from SyncDecoder, no CDC for simplicity)
    wire [11:0] det_h_total;
    wire [11:0] det_h_active;
    wire [11:0] det_h_sync_len;
    wire [11:0] det_h_backporch;
    wire [11:0] det_v_total;
    wire [11:0] det_v_active;
    wire [11:0] det_v_sync_len;
    wire [11:0] det_v_backporch;
    wire        det_interlaced;
    wire        det_field_id;
    wire [11:0] det_h_count;
    wire [11:0] det_v_count;

    // CDC synchronizers for configuration (AXI -> pixel_clk)
    // Using simple 2-stage synchronizers for control signals
    reg [2:0] sync_soft_reset;
    reg [2:0] sync_force_interlaced;
    reg [2:0] sync_force_progressive;
    reg [2:0] sync_ignore_de;
    
    // Synchronized configuration values in pixel clock domain
    reg [11:0] sync_cfg_h_active;
    reg [11:0] sync_cfg_h_sync;
    reg [11:0] sync_cfg_h_backporch;
    reg [11:0] sync_cfg_v_active;
    reg [11:0] sync_cfg_v_sync;
    reg [11:0] sync_cfg_v_backporch;
    
    // CDC: AXI clock -> pixel clock for control signals
    always @(posedge pixel_clk) begin
        sync_soft_reset <= {sync_soft_reset[1:0], reg_soft_reset};
        sync_force_interlaced <= {sync_force_interlaced[1:0], reg_force_interlaced};
        sync_force_progressive <= {sync_force_progressive[1:0], reg_force_progressive};
        sync_ignore_de <= {sync_ignore_de[1:0], reg_ignore_de};
    end
    
    // CDC: Configuration values - sample when soft_reset asserted for clean handoff
    // In practice, configuration should only change when decoder is in reset
    always @(posedge pixel_clk) begin
        if (sync_soft_reset[2]) begin
            sync_cfg_h_active    <= reg_cfg_h_active;
            sync_cfg_h_sync      <= reg_cfg_h_sync;
            sync_cfg_h_backporch <= reg_cfg_h_backporch;
            sync_cfg_v_active    <= reg_cfg_v_active;
            sync_cfg_v_sync      <= reg_cfg_v_sync;
            sync_cfg_v_backporch <= reg_cfg_v_backporch;
        end
    end

    // Combined reset: external reset OR soft reset
    wire pixel_rst_n = s_axi_aresetn & ~sync_soft_reset[2];

    // AXI output assignments
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = axi_rresp;
    assign s_axi_rvalid  = axi_rvalid;

    // Interrupt generation
    assign irq_frame_start = VPU_out_frame_start;

    // AXI4-Lite Write Address Channel
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready <= 1'b0;
            axi_awaddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // AXI4-Lite Write Data Channel
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_wready <= 1'b0;
        end else begin
            if (!axi_wready && s_axi_awvalid && s_axi_wvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end
        end
    end

    // Register write logic
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            reg_soft_reset        <= 1'b0;
            reg_force_interlaced  <= 1'b0;
            reg_force_progressive <= 1'b0;
            reg_ignore_de         <= 1'b0;
            reg_cfg_h_active      <= 12'd640;   // Default: 640 pixels
            reg_cfg_h_sync        <= 12'd96;    // Default: 96 pixels
            reg_cfg_h_backporch   <= 12'd48;    // Default: 48 pixels
            reg_cfg_v_active      <= 12'd480;   // Default: 480 lines
            reg_cfg_v_sync        <= 12'd2;     // Default: 2 lines
            reg_cfg_v_backporch   <= 12'd33;    // Default: 33 lines
        end else begin
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid) begin
                case (axi_awaddr[6:2])
                    ADDR_CONTROL[6:2]: begin
                        if (s_axi_wstrb[0]) begin
                            reg_soft_reset        <= s_axi_wdata[0];
                            reg_force_interlaced  <= s_axi_wdata[1];
                            reg_force_progressive <= s_axi_wdata[2];
                            reg_ignore_de         <= s_axi_wdata[3];
                        end
                    end
                    ADDR_CFG_H_ACTIVE[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_h_active[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_h_active[11:8] <= s_axi_wdata[11:8];
                    end
                    ADDR_CFG_H_SYNC[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_h_sync[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_h_sync[11:8] <= s_axi_wdata[11:8];
                    end
                    ADDR_CFG_H_BACKPORCH[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_h_backporch[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_h_backporch[11:8] <= s_axi_wdata[11:8];
                    end
                    ADDR_CFG_V_ACTIVE[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_v_active[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_v_active[11:8] <= s_axi_wdata[11:8];
                    end
                    ADDR_CFG_V_SYNC[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_v_sync[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_v_sync[11:8] <= s_axi_wdata[11:8];
                    end
                    ADDR_CFG_V_BACKPORCH[6:2]: begin
                        if (s_axi_wstrb[0]) reg_cfg_v_backporch[7:0]  <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1]) reg_cfg_v_backporch[11:8] <= s_axi_wdata[11:8];
                    end
                    default: ; // Read-only registers, ignore writes
                endcase
            end
        end
    end

    // AXI4-Lite Write Response
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && s_axi_awvalid && axi_wready && s_axi_wvalid && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY response
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite Read Address Channel
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // AXI4-Lite Read Data Channel
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
            axi_rdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (axi_arready && s_axi_arvalid && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00; // OKAY response
                
                case (axi_araddr[6:2])
                    ADDR_CONTROL[6:2]:         axi_rdata <= {28'b0, reg_ignore_de, reg_force_progressive, reg_force_interlaced, reg_soft_reset};
                    ADDR_STATUS[6:2]:          axi_rdata <= {29'b0, det_field_id, det_interlaced, 1'b1}; // polarity_locked placeholder
                    ADDR_CFG_H_ACTIVE[6:2]:    axi_rdata <= {20'b0, reg_cfg_h_active};
                    ADDR_CFG_H_SYNC[6:2]:      axi_rdata <= {20'b0, reg_cfg_h_sync};
                    ADDR_CFG_H_BACKPORCH[6:2]: axi_rdata <= {20'b0, reg_cfg_h_backporch};
                    ADDR_CFG_V_ACTIVE[6:2]:    axi_rdata <= {20'b0, reg_cfg_v_active};
                    ADDR_CFG_V_SYNC[6:2]:      axi_rdata <= {20'b0, reg_cfg_v_sync};
                    ADDR_CFG_V_BACKPORCH[6:2]: axi_rdata <= {20'b0, reg_cfg_v_backporch};
                    ADDR_DET_H_TOTAL[6:2]:     axi_rdata <= {20'b0, det_h_total};
                    ADDR_DET_H_ACTIVE[6:2]:    axi_rdata <= {20'b0, det_h_active};
                    ADDR_DET_H_SYNC_LEN[6:2]:  axi_rdata <= {20'b0, det_h_sync_len};
                    ADDR_DET_H_BACKPORCH[6:2]: axi_rdata <= {20'b0, det_h_backporch};
                    ADDR_DET_V_TOTAL[6:2]:     axi_rdata <= {20'b0, det_v_total};
                    ADDR_DET_V_ACTIVE[6:2]:    axi_rdata <= {20'b0, det_v_active};
                    ADDR_DET_V_SYNC_LEN[6:2]:  axi_rdata <= {20'b0, det_v_sync_len};
                    ADDR_DET_V_BACKPORCH[6:2]: axi_rdata <= {20'b0, det_v_backporch};
                    ADDR_POSITION[6:2]:        axi_rdata <= {4'b0, det_v_count, 4'b0, det_h_count};
                    ADDR_VERSION[6:2]:         axi_rdata <= IP_VERSION;
                    default:                   axi_rdata <= 32'hDEADBEEF;
                endcase
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // SyncDecoder instance
    SyncDecoder #(
        .TOLERANCE(TOLERANCE),
        .STABILITY_COUNT(STABILITY_COUNT),
        .ENABLE_INTERLACE_DETECTION(ENABLE_INTERLACE_DETECTION)
    ) sync_decoder_inst (
        .pixel_clk              (pixel_clk),
        .rst_n                  (pixel_rst_n),
        .hsync                  (hsync),
        .vsync                  (vsync),
        .de                     (de),
        
        // Configuration inputs (synchronized)
        .VPU_cfg_h_active_width     (sync_cfg_h_active),
        .VPU_cfg_h_sync_width       (sync_cfg_h_sync),
        .VPU_cfg_h_backporch        (sync_cfg_h_backporch),
        .VPU_cfg_v_active_lines     (sync_cfg_v_active),
        .VPU_cfg_v_sync_width       (sync_cfg_v_sync),
        .VPU_cfg_v_backporch        (sync_cfg_v_backporch),
        .VPU_cfg_force_interlaced   (sync_force_interlaced[2]),
        .VPU_cfg_force_progressive  (sync_force_progressive[2]),
        .VPU_cfg_ignore_de          (sync_ignore_de[2]),
        
        // Detected timing outputs
        .det_h_total                (det_h_total),
        .det_h_active               (det_h_active),
        .det_h_sync_len             (det_h_sync_len),
        .det_h_backporch            (det_h_backporch),
        .det_v_total                (det_v_total),
        .det_v_active               (det_v_active),
        .det_v_sync_len             (det_v_sync_len),
        .det_v_backporch            (det_v_backporch),
        .det_interlaced             (det_interlaced),
        .det_field_id               (det_field_id),
        .det_h_count                (det_h_count),
        .det_v_count                (det_v_count),
        
        // VPU outputs
        .VPU_out_valid          (VPU_out_valid),
        .VPU_out_pixel          (VPU_out_pixel),
        .VPU_out_line_start     (VPU_out_line_start),
        .VPU_out_frame_start    (VPU_out_frame_start),
        .VPU_out_interlaced     (VPU_out_interlaced),
        .VPU_out_field_id       (VPU_out_field_id),
        .VPU_out_h_count        (VPU_out_h_count),
        .VPU_out_v_count        (VPU_out_v_count),
        .VPU_out_h_active       (VPU_out_h_active),
        .VPU_out_v_active       (VPU_out_v_active)
    );

endmodule