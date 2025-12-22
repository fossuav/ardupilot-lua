# ArduPilot CRSF FFT Spectrum Menu - User Manual

## 1. Introduction

The CRSF FFT Spectrum Menu is a Lua script that provides in-field configuration of FFT visualization settings directly from your CRSF-compatible transmitter (such as EdgeTX or OpenTX). It works alongside the FFT visualization feature that streams real-time frequency spectrum data to your radio display.

This tool allows pilots to:
- Enable/disable FFT visualization on-the-fly
- Select which gyro axes to visualize
- Configure FFT analysis parameters (window size, resolution, averaging)
- View the resulting frequency range
- Trigger flight controller reboots after configuration changes

## 2. Prerequisites & Installation

### 2.1. Prerequisites

1. **FFT-enabled firmware:** Your flight controller must have FFT support compiled in (`HAL_GYROFFT_ENABLED`).
2. **FFT enabled:** Set `FFT_ENABLE = 1` in your parameters.
3. **Lua scripting enabled:** Set `SCR_ENABLE = 1`.
4. **CRSF telemetry:** Ensure your CRSF receiver has telemetry enabled and `RC_OPTIONS` does not disable CRSF telemetry.
5. **Compatible transmitter:** EdgeTX 2.9+ or OpenTX 2.3.15+ with CRSF menu support.

### 2.2. Installation

Two files are required:

1. `crsf-fft.lua` - The FFT configuration menu script
2. `crsf_helper.lua` - The CRSF menu helper library

**Installation Steps:**

1. Power down your flight controller and remove the SD card.
2. Navigate to the `APM/scripts/` directory on the SD card. Create it if it doesn't exist.
3. Copy both `crsf-fft.lua` and `crsf_helper.lua` into the `APM/scripts/` directory.
4. Safely eject the SD card and re-insert it into your flight controller.
5. Power on your flight controller. The script will load automatically.

## 3. Menu Overview

Access the menu via your transmitter's "Lua Scripts" or "Tools" menu. Look for the entry named **"Noise Spectrum"**.

### 3.1. Menu Items

| Item | Type | Description |
|------|------|-------------|
| **Enable** | Selection | Toggles FFT visualization On/Off |
| **Axis** | Selection | Selects which gyro axes to visualize |
| **Window Size** | Selection | FFT window size (32-512) |
| **Resolution** | Selection | Bin resolution in Hz (sets sample mode) |
| **Averaging** | Selection | Frame averaging for smoother display |
| **Sample Point** | Selection | Pre-filter or post-filter sampling |
| **Pan Channel** | Selection | RC channel for frequency panning (None/CH5-CH16) |
| **Zoom Channel** | Selection | RC channel for zoom control (None/CH5-CH16) |
| **Freq Range** | Info | Shows analyzable frequency range (0 to Nyquist) |
| **Status** | Info | Shows current state and pending changes |
| **Reboot FC** | Command | Reboots flight controller to apply changes |

### 3.2. Enable

Quickly toggle FFT visualization on or off:
- **Off:** Sets `FFT_VIS_MASK = 0`, disabling visualization output
- **On:** Restores the previously selected axis configuration

When toggled off, the script remembers your axis selection so it can be restored when re-enabled.

### 3.3. Axis Selection

Choose which gyro axes contribute to the visualization:

| Option | FFT_VIS_MASK | Description |
|--------|--------------|-------------|
| X | 1 | Roll axis only |
| Y | 2 | Pitch axis only |
| Z | 4 | Yaw axis only |
| X+Y | 3 | Roll and Pitch averaged |
| X+Z | 5 | Roll and Yaw averaged |
| Y+Z | 6 | Pitch and Yaw averaged |
| All | 7 | All three axes averaged (default) |

Averaging multiple axes provides a combined view of vibration across the airframe.

### 3.4. Window Size

Sets the FFT window size (`FFT_WINDOW_SIZE`). Larger windows provide better frequency resolution but require more processing time.

| Size | Notes |
|------|-------|
| 32 | Fastest, lowest resolution |
| 64 | Default for most setups |
| 128 | Good balance |
| 256 | High resolution |
| 512 | Highest resolution, most CPU |

**Note:** Changes to window size require a reboot to take effect. The Resolution options will update after reboot to reflect the new window size.

### 3.5. Resolution

Sets the frequency bin resolution by adjusting the FFT sample mode (`FFT_SAMPLE_MODE`). The displayed options show the actual bin resolution in Hz, calculated from:

```
bin_resolution = sample_rate / window_size
```

The sample rate depends on:
- **Gyro rate** (from `INS_GYRO_RATE`): Highest resolution, full gyro speed
- **Loop rate** (from `SCHED_LOOP_RATE`): Lower CPU usage
- **Loop/2, Loop/3**: Even lower CPU usage

Example options with 64 window size and 1kHz gyro / 400Hz loop:
| Option | Sample Mode | Sample Rate |
|--------|-------------|-------------|
| 15.6Hz | Gyro | 1000 Hz |
| 6.25Hz | Loop | 400 Hz |
| 3.13Hz | Loop/2 | 200 Hz |
| 2.08Hz | Loop/3 | 133 Hz |

Lower resolution values mean finer frequency detail but also reduce the maximum analyzable frequency (shown in **Freq Range**).

**Note:** Changes require a reboot to take effect.

### 3.6. Averaging

Controls frame averaging using Welch's method (`FFT_NUM_FRAMES`). More averaging produces a smoother display but slower response to changes.

| Option | Frames | Behavior |
|--------|--------|----------|
| Off | 0 | Instant response, may appear noisy |
| Light | 2 | Minimal smoothing |
| Medium | 4 | Balanced (recommended for 10Hz display) |
| Heavy | 8 | Maximum smoothing, slower response |

**Recommendation:** For a 10Hz display update rate, "Medium" (4 frames) provides a good balance between responsiveness and visual stability.

**Note:** Changes require a reboot to take effect.

### 3.7. Sample Point

Selects whether the FFT analyzes gyro data before or after the notch filters are applied (`FFT_OPTIONS` bit 0).

| Option | Description |
|--------|-------------|
| Pre-filter | Analyze raw gyro data before filtering (default) |
| Post-filter | Analyze gyro data after notch filters applied |

**Use cases:**
- **Pre-filter (default):** Shows the actual vibration spectrum as seen by the gyros. Use this to identify noise sources and set up notch filters.
- **Post-filter:** Shows what the flight controller sees after filtering. Use this to verify that notch filters are effectively attenuating target frequencies.

**Note:** Changes require a reboot to take effect.

### 3.8. Pan Channel

Assigns an RC channel to control frequency panning (which portion of the spectrum is displayed):

| Option | Effect |
|--------|--------|
| None | Pan disabled, always start at 0 Hz |
| CH5-CH16 | Assigned channel controls pan position |

When assigned:
- **Slider left/low:** View low frequencies (start of spectrum)
- **Slider right/high:** View high frequencies (end of spectrum)

The channel selection only shows unassigned channels (where `RC_OPTION = 0`) to prevent accidentally overwriting other aux function assignments.

**Parameter:** Sets `RCx_OPTION = 186` (FFT_VIS_PAN)

**Note:** Takes effect immediately, no reboot required.

### 3.9. Zoom Channel

Assigns an RC channel to control zoom level:

| Option | Effect |
|--------|--------|
| None | Zoom disabled, show full spectrum |
| CH5-CH16 | Assigned channel controls zoom level |

When assigned:
- **Slider left/low:** Zoomed out (full spectrum view, ~55 bars)
- **Slider right/high:** Zoomed in (1/8 spectrum, higher resolution, ~55 bars)

The display always shows approximately 55 bars regardless of zoom level. Zooming in provides higher frequency resolution for a narrower portion of the spectrum.

**Parameter:** Sets `RCx_OPTION = 187` (FFT_VIS_ZOOM)

**Note:** Takes effect immediately, no reboot required.

### 3.10. Freq Range

A read-only info field showing the analyzable frequency range based on current settings:
- Displays as `0-{max}Hz` where max is the Nyquist frequency (sample_rate / 2)
- Updates when Resolution is changed

Examples:
| Sample Mode | Sample Rate | Freq Range |
|-------------|-------------|------------|
| Gyro (1kHz) | 1000 Hz | 0-500Hz |
| Loop (400Hz) | 400 Hz | 0-200Hz |
| Loop/2 | 200 Hz | 0-100Hz |

### 3.11. Status

A read-only info field showing the current state:
- **FFT Disabled:** FFT_ENABLE is 0 at the firmware level
- **Vis: Off:** Visualization is disabled (FFT_VIS_MASK = 0)
- **Active:** Visualization is enabled and working
- **Reboot needed!:** Configuration changed, reboot required

### 3.12. Reboot FC

A command to reboot the flight controller:
- Shows **"No changes"** if no reboot-requiring parameters have been changed
- Shows **"Confirm?"** if configuration was changed
- Press to confirm and trigger an immediate reboot

## 4. Usage Workflow

### 4.1. Initial Setup

1. Ensure FFT is enabled: `FFT_ENABLE = 1`
2. Configure basic FFT parameters via GCS if needed:
   - `FFT_MINHZ` - Minimum frequency to analyze (default: 50 Hz)
   - `FFT_MAXHZ` - Maximum frequency to analyze (default: 450 Hz)
3. Install the Lua scripts as described above
4. Reboot the flight controller

### 4.2. In-Field Configuration

1. Access the **"FFT Spectrum"** menu on your transmitter
2. Set **Enable** to **On** to start visualization
3. Optionally adjust **Axis** to focus on specific gyro axes
4. Adjust **Averaging** to "Medium" for a stable display
5. If needed, adjust **Window Size** or **Resolution** and use **Reboot FC**

### 4.3. Typical Use Cases

**Troubleshooting vibrations:**
- Set Axis to individual axes (X, Y, Z) to isolate which axis has the most noise
- Use a larger window size (128 or 256) for better frequency resolution
- Use "Medium" or "Heavy" averaging for clearer peaks

**Quick motor noise check:**
- Set Axis to "All" for a combined view
- Use "Light" or "Off" averaging for real-time response
- Enable visualization, arm and spool up motors
- Look for peaks indicating motor or prop frequencies

**High-frequency analysis (up to 500Hz):**
- Use highest Resolution option (Gyro rate)
- Check Freq Range shows adequate coverage
- Useful for detecting high-RPM motor noise

**Minimizing CPU usage:**
- Use smaller window size (32 or 64)
- Select lower Resolution (Loop/2 or Loop/3)
- Trade-off: reduced maximum frequency range

**Smooth display for tuning:**
- Set Averaging to "Medium" or "Heavy"
- Provides stable peaks easier to read while adjusting filters

## 5. Troubleshooting

**Menu doesn't appear:**
- Verify `SCR_ENABLE = 1` and reboot
- Check that both `.lua` files are in `APM/scripts/`
- Ensure CRSF telemetry is working

**"FFT_ENABLE not found" error:**
- Your firmware doesn't have FFT support compiled in
- Use a firmware build with `HAL_GYROFFT_ENABLED`

**"FFT_VIS_MASK not found" error:**
- Your firmware is missing the visualization feature
- Update to a firmware version with FFT visualization support

**Changes don't take effect:**
- Window Size, Resolution, Averaging, and Sample Point all require a reboot
- Use the "Reboot FC" command after changing these settings

**Resolution options look wrong after changing Window Size:**
- Resolution options are calculated at script startup
- After changing Window Size, reboot to see correct values

**Display is too noisy/jumpy:**
- Increase Averaging to "Medium" or "Heavy"

**Display is too slow to respond:**
- Decrease Averaging to "Light" or "Off"

## 6. Parameter Reference

| Menu Item | Parameter | Valid Range | Reboot Required |
|-----------|-----------|-------------|-----------------|
| Enable | FFT_VIS_MASK | 0-7 | No |
| Axis | FFT_VIS_MASK | 1-7 | No |
| Window Size | FFT_WINDOW_SIZE | 32, 64, 128, 256, 512 | Yes |
| Resolution | FFT_SAMPLE_MODE | 0-3 | Yes |
| Averaging | FFT_NUM_FRAMES | 0, 2, 4, 8 | Yes |
| Sample Point | FFT_OPTIONS (bit 0) | 0=Pre, 1=Post | Yes |
| Pan Channel | RCx_OPTION | 186 (FFT_VIS_PAN) | No |
| Zoom Channel | RCx_OPTION | 187 (FFT_VIS_ZOOM) | No |

## 7. Related Documentation

- [ArduPilot FFT Setup Guide](https://ardupilot.org/copter/docs/common-imu-fft.html)
- [CRSF Telemetry Setup](https://ardupilot.org/copter/docs/common-crsf-telemetry.html)
