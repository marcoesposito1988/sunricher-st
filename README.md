# SmartThings Edge Driver for Sunricher SR-ZG2856-PRO

This repository contains the local SmartThings Edge Driver for the **Sunricher SR-ZG2856-PRO** (10-button Zigbee 3.0 Smart Remote, model `HK-ZRC-K10N-E`).

## Overview & Local Execution

Unlike cloud-dependent integrations, this driver executes **100% locally on your SmartThings Hub** using the Lua-based SmartThings Edge Driver architecture. 

### Key Benefits
- **Zero Cloud Latency:** All button triggers, double presses, and hold events execute instantly and directly on the local hub.
- **High Reliability & Resilience:** Automations continue operating seamlessly even during internet outages.
- **Maximum Utility:** Full 10-button matrix (K1 through K10) exposed with individual component controls for granular SmartThings Routine automation.
- **Battery Efficient:** Low-power Zigbee 3.0 reporting with configurable PowerConfiguration attributes.

---

## Home Assistant Blueprint Equivalence

This driver matches and expands the functionality provided in the Home Assistant blueprint repository ([sr_ha_blueprints](https://github.com/maginawin/sr_ha_blueprints)):

| Home Assistant Action | SmartThings Capability Event | Button Component | Description |
|-----------------------|------------------------------|------------------|-------------|
| `short_press`         | `pushed`                     | `button1` - `button10` | Single press on key K1..K10 |
| `double_press`        | `double`                     | `button1` - `button10` | Double tap on key K1..K10 |
| `hold`                | `held`                       | `button1` - `button10` | Long press / hold on key K1..K10 |
| `hold_released`       | `up_hold`                    | `button1` - `button10` | Release after hold on key K1..K10 |

---

## Technical Specifications & Protocol

- **Zigbee Model:** `HK-ZRC-K10N-E`, `SR-ZG2856-Pro`, `SR-ZG2856-PRO`
- **Vendor:** Sunricher
- **Custom Button Cluster:** `0xFF03`
  - **Command ID:** `0x01` (`press`)
  - **Payload Structure:**
    - `messageType` (1 byte, `0x01`)
    - `button2` (1 byte, MSB of button bitmask)
    - `button1` (1 byte, LSB of button bitmask)
    - `pressType` (1 byte: 1 = `pushed`, 2 = `double`, 3 = `held`, 4 = `up_hold`)
- **Battery Cluster:** `0x0001` (PowerConfiguration)
  - `BatteryPercentageRemaining` (Attribute `0x0021`)
  - `BatteryVoltage` (Attribute `0x0020`)

---

## Driver Structure

```
sunricher-st/
├── config.yml                         # Driver package metadata & Zigbee permissions
├── fingerprints.yml                   # Zigbee model & manufacturer fingerprints
├── profiles/
│   └── sunricher-sr-zg2856-pro.yml    # Device profile (main + button1..button10)
├── src/
│   ├── init.lua                       # Core Edge Driver lifecycle & Zigbee handlers
│   └── button_utils.lua               # Frame parsing, bitmask decoding & event emission
├── test/
│   └── test_sunricher_remote.lua      # Unit test suite verifying frame decoding & events
└── README.md
```

---

## How to Package and Install via SmartThings CLI

### Prerequisites
- [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) installed and configured on your computer.
- A SmartThings Hub (v2, v3, or Aeotec Smart Home Hub).

### Step 1: Package the Driver
```bash
smartthings edge:drivers:package .
```

### Step 2: Create a Driver Channel (if not already done)
Run without positional arguments to create a channel interactively:
```bash
smartthings edge:channels:create
```
*(You will be prompted to enter the channel Name, Description, and Terms of Service)*

### Step 3: Assign the Driver to Your Channel
```bash
smartthings edge:channels:assign <DRIVER_ID> --channel <CHANNEL_ID>
```

### Step 4: Install the Driver to Your SmartThings Hub
```bash
smartthings edge:drivers:install <DRIVER_ID> --channel <CHANNEL_ID> --hub <HUB_ID>
```

> **Tip:** You can also package, assign, and install in a single step:
> ```bash
> smartthings edge:drivers:package --channel <CHANNEL_ID> --hub <HUB_ID>
> ```

### Step 5: Pair the Sunricher SR-ZG2856-PRO
1. In the SmartThings mobile app, tap **+** -> **Add device** -> **Scan for nearby devices**.
2. Put the Sunricher remote into pairing mode (press and hold the pairing buttons according to the manual until the LED flashes).
3. The remote will be detected and automatically assigned to this driver.

---

## Running Unit Tests

Run the included standalone unit test suite:
```bash
lua test/test_sunricher_remote.lua
```
