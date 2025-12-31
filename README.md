# SyncDecoder

A Verilog module for detecting and measuring video timing parameters from HSYNC and VSYNC signals. This module automatically detects horizontal and vertical timing, discriminates between progressive and interlaced video formats, and provides synchronized pixel data output.

## Features

- **Automatic Timing Detection**
  - Horizontal total, active width, sync pulse width, and back porch
  - Vertical total, active lines, sync pulse width, and back porch
  - Real-time position counters (h_count, v_count)

- **Interlace Detection**
  - Automatic detection of interlaced vs progressive video
  - Field identification (odd/even field)
  - Confidence-based detection with hysteresis to prevent flickering
  - Manual override options (force interlaced or progressive mode)

- **Flexible Configuration**
  - Configurable expected timing parameters for validation
  - Optional DE (Data Enable) signal support
  - Internal DE generation based on configuration when hardware DE is unavailable
  - Adjustable tolerance and stability parameters

- **Output Synchronization**
  - Pixel valid signal aligned to active region
  - Line start and frame start pulses
  - Synchronized RGB pixel data passthrough

## Module Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TOLERANCE` | 4 | Tolerance (in pixels) for interlace detection mid-line check |
| `STABILITY_COUNT` | 3 | Number of consistent frames required before locking timing detection |
| `ENABLE_INTERLACE_DETECTION` | 1 | Enable (1) or disable (0) automatic interlace detection logic |

## Ports

### Inputs

| Port | Width | Description |
|------|-------|-------------|
| `pixel_clk` | 1 | Pixel clock input |
| `rst_n` | 1 | Active-low asynchronous reset |
| `hsync` | 1 | Horizontal sync pulse (active high) |
| `vsync` | 1 | Vertical sync pulse (active high) |
| `de` | 1 | Data enable signal (optional) |
| `rgb` | 24 | Input pixel data (RGB) |

### Configuration Inputs

| Port | Width | Description |
|------|-------|-------------|
| `cfg_h_active_width` | 12 | Expected horizontal active pixels |
| `cfg_h_sync_width` | 12 | Expected HSYNC pulse width (for noise filtering) |
| `cfg_h_backporch` | 12 | Expected horizontal back porch (for DE generation) |
| `cfg_v_active_lines` | 12 | Expected vertical active lines |
| `cfg_v_sync_width` | 12 | Expected VSYNC pulse width |
| `cfg_v_backporch` | 12 | Expected vertical back porch (for image alignment) |
| `cfg_force_interlaced` | 1 | Force interlaced mode (override auto-detection) |
| `cfg_force_progressive` | 1 | Force progressive mode (override auto-detection) |
| `cfg_ignore_de` | 1 | Ignore hardware DE and generate internally using config values |

### Outputs

#### Detected Timing Parameters

| Port | Width | Description |
|------|-------|-------------|
| `h_total` | 12 | Total pixels per line (including blanking) |
| `h_active` | 12 | Active pixels per line |
| `h_sync_len` | 12 | HSYNC pulse width in pixels |
| `h_backporch` | 12 | Horizontal back porch length |
| `v_total` | 12 | Total lines per frame (including blanking) |
| `v_active` | 12 | Active lines per frame |
| `v_sync_len` | 12 | VSYNC pulse width in lines |
| `v_backporch` | 12 | Vertical back porch length |

#### Interlace Status

| Port | Width | Description |
|------|-------|-------------|
| `interlaced` | 1 | 1 = interlaced video, 0 = progressive |
| `field_id` | 1 | Current field: 1 = odd field (mid-line VSYNC), 0 = even field |

#### Position & Output Stream

| Port | Width | Description |
|------|-------|-------------|
| `h_count` | 12 | Current horizontal pixel position |
| `v_count` | 12 | Current vertical line position |
| `pixel_valid` | 1 | High when pixel data is in active region |
| `pixel_data` | 24 | Synchronized RGB pixel data output |
| `line_start` | 1 | Pulse at the start of each line (HSYNC rising edge) |
| `frame_start` | 1 | Pulse at the start of each frame (VSYNC rising edge) |

## How It Works

### Horizontal Timing Detection

The module counts pixels on every `pixel_clk` cycle. When HSYNC ends (`hsync_end`), the horizontal counter resets and captures the total line length. The HSYNC pulse width is measured while HSYNC is active. If a DE signal is present, the module measures the horizontal active width and back porch by detecting when DE starts and ends.

### Vertical Timing Detection

The module counts lines on every HSYNC pulse. When VSYNC starts (`vsync_start`), the vertical counter resets and captures the total frame height. The VSYNC pulse width is measured in lines while VSYNC is active. Similar to horizontal timing, if DE is present on any line, the module measures vertical active lines and back porch.

### Interlace Detection Algorithm

Interlaced video has a distinctive characteristic: alternate fields start VSYNC at different horizontal positions.

- **Progressive video**: VSYNC always starts at h_count ≈ 0 (beginning of line)
- **Interlaced video**:
  - Even field: VSYNC starts at h_count ≈ 0
  - Odd field: VSYNC starts at h_count ≈ (h_total/2) - h_sync_len (mid-line)

**Detection Process:**

1. When VSYNC starts, the module captures the current `h_count` position
2. It checks if this position is near the half-line mark (within `TOLERANCE` pixels)
3. A confidence counter tracks consistency:
   - Increments by 2 when mid-line VSYNC detected (fast lock-on)
   - Decrements by 1 when start-of-line VSYNC detected (slow release)
4. When confidence reaches `STABILITY_COUNT`, the signal is declared interlaced
5. When confidence drops to ≤ 1, the signal is declared progressive
6. Hysteresis prevents flickering during transitions

**Field Identification:**

- When in interlaced mode, `field_id` is set based on VSYNC position:
  - `field_id = 1`: VSYNC occurred mid-line (odd field)
  - `field_id = 0`: VSYNC occurred at start-of-line (even field)

### Configuration Modes

The module supports three modes of operation:

1. **Auto-detection mode** (default)
   - Both force signals set to 0
   - Module automatically detects interlaced vs progressive
   - Recommended for most applications

2. **Force interlaced mode**
   - Set `cfg_force_interlaced = 1`
   - Overrides auto-detection
   - Useful for known interlaced sources

3. **Force progressive mode**
   - Set `cfg_force_progressive = 1`
   - Overrides auto-detection
   - Useful for known progressive sources

## Usage Example

```verilog
SyncDecoder #(
    .TOLERANCE(4),
    .STABILITY_COUNT(3),
    .ENABLE_INTERLACE_DETECTION(1)
) sync_decoder_inst (
    // Clock and reset
    .pixel_clk(pixel_clk),
    .rst_n(rst_n),

    // Input signals
    .hsync(hsync_in),
    .vsync(vsync_in),
    .de(de_in),
    .rgb(rgb_in),

    // Configuration
    .cfg_h_active_width(12'd1920),
    .cfg_h_sync_width(12'd44),
    .cfg_h_backporch(12'd148),
    .cfg_v_active_lines(12'd1080),
    .cfg_v_sync_width(12'd5),
    .cfg_v_backporch(12'd36),
    .cfg_force_interlaced(1'b0),
    .cfg_force_progressive(1'b0),
    .cfg_ignore_de(1'b0),

    // Detected timing
    .h_total(h_total_detected),
    .h_active(h_active_detected),
    .h_sync_len(h_sync_len_detected),
    .h_backporch(h_backporch_detected),
    .v_total(v_total_detected),
    .v_active(v_active_detected),
    .v_sync_len(v_sync_len_detected),
    .v_backporch(v_backporch_detected),

    // Interlace status
    .interlaced(is_interlaced),
    .field_id(current_field),

    // Position counters
    .h_count(h_position),
    .v_count(v_position),

    // Output stream
    .pixel_valid(pixel_valid_out),
    .pixel_data(pixel_data_out),
    .line_start(line_start_pulse),
    .frame_start(frame_start_pulse)
);
```

## Common Video Formats

Here are some common video timing parameters for reference:

### 1080p60 (Progressive)
- h_total: 2200, h_active: 1920, h_sync: 44, h_backporch: 148
- v_total: 1125, v_active: 1080, v_sync: 5, v_backporch: 36
- interlaced: 0

### 1080i60 (Interlaced)
- h_total: 2200, h_active: 1920, h_sync: 44, h_backporch: 148
- v_total: 562/563 (alternating), v_active: 540 per field, v_sync: 5, v_backporch: 18
- interlaced: 1
- field_id alternates between 0 and 1

### 720p60 (Progressive)
- h_total: 1650, h_active: 1280, h_sync: 40, h_backporch: 220
- v_total: 750, v_active: 720, v_sync: 5, v_backporch: 20
- interlaced: 0

### 480i60 (Interlaced, NTSC)
- h_total: 858, h_active: 720, h_sync: 62, h_backporch: 60
- v_total: 262/263 (alternating), v_active: 240 per field, v_sync: 3, v_backporch: 18
- interlaced: 1

## Timing Diagrams

### Progressive Scan
```
VSYNC: ___┌─┐_____________________________┌─┐___
             Field 0                        Field 0
       h_count = 0                      h_count = 0
```

### Interlaced Scan
```
VSYNC: ___┌─┐_____________┌─┐_____________┌─┐___
           Even Field      Odd Field       Even Field
       h_count = 0     h_count ≈ h_total/2  h_count = 0
       field_id = 0    field_id = 1         field_id = 0
```

## Implementation Notes

1. **Sync Polarity**: The module currently assumes active-high HSYNC and VSYNC. Commented-out code exists for automatic polarity detection if needed.

2. **Reset Behavior**: On reset, the module defaults to progressive mode and begins measuring timing immediately.

3. **Stability**: The `STABILITY_COUNT` parameter ensures the module doesn't switch modes on single frame glitches. Increase this value for noisier signals.

4. **Tolerance**: The `TOLERANCE` parameter accounts for timing variations in analog sources. For digital sources, this can be reduced.

5. **DE Signal**: If no hardware DE signal is available, set `cfg_ignore_de = 1` and provide expected timing parameters. The module will generate an internal DE signal.

## License

MIT License - See project root for details

## Revision History

- **v1.0** - Initial implementation with automatic timing detection and interlace detection
  - Fixed interlace detection timing issues
  - Added hysteresis for stable mode locking
  - Implemented field ID detection based on VSYNC position
