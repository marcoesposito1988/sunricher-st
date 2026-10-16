-- Copyright 2026 SmartThings, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local log = require "log"
local utils = require "st.utils"

local button_utils = require "button_utils"

local PowerConfiguration = zcl_clusters.PowerConfiguration
local Basic = zcl_clusters.Basic

local SUNRICHER_REMOTE_CLUSTER_ID = 0xFF03
local SUNRICHER_PRESS_COMMAND_ID = 0x01

--- Handle button press event from Sunricher Remote Cluster 0xFF03 Command 0x01.
---
--- @param driver Driver The current driver
--- @param device ZigbeeDevice The device that generated the message
--- @param zb_rx ZigbeeMessageRx The full Zigbee message
local function sunricher_press_handler(driver, device, zb_rx)
  local zcl_body = (zb_rx.body and zb_rx.body.zcl_body) or zb_rx.body
  local action, buttons = button_utils.parse_sunricher_press(zcl_body)

  if action and #buttons > 0 then
    for _, btn_num in ipairs(buttons) do
      button_utils.emit_button_event(device, btn_num, action)
    end
  else
    log.warn(string.format("Unable to parse Sunricher button event from payload on cluster 0x%04X", zb_rx.address_header.cluster.value))
  end
end

--- Battery Percentage Attribute Handler (PowerConfiguration 0x0001, Attribute 0x0021)
---
--- @param driver Driver
--- @param device ZigbeeDevice
--- @param value Int8|Uint8 The reported battery percentage remaining
--- @param zb_rx ZigbeeMessageRx
local function battery_percentage_handler(driver, device, value, zb_rx)
  local raw_val = value.value
  -- Zigbee specification reports 0-200 for 0%-100% (half percent increments)
  local percentage = math.floor((raw_val / 2.0) + 0.5)
  percentage = utils.clamp_value(percentage, 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
  log.info(string.format("Battery reported: %d%% (raw: %d)", percentage, raw_val))
end

--- Battery Voltage Attribute Handler (PowerConfiguration 0x0001, Attribute 0x0020)
---
--- @param driver Driver
--- @param device ZigbeeDevice
--- @param value Int8|Uint8 The reported battery voltage in 100mV
--- @param zb_rx ZigbeeMessageRx
local function battery_voltage_handler(driver, device, value, zb_rx)
  local raw_voltage = value.value -- 100mV units, e.g. 30 = 3.0V
  -- Calculate percentage based on 2x AAA batteries (nominal 3.0V, min 2.2V)
  local min_v = 22
  local max_v = 30
  local percentage = math.floor(((raw_voltage - min_v) / (max_v - min_v)) * 100 + 0.5)
  percentage = utils.clamp_value(percentage, 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
  log.info(string.format("Battery voltage reported: %.1fV -> %d%%", raw_voltage / 10.0, percentage))
end

--- Capability Command Handler: Refresh
---
--- @param driver Driver
--- @param device ZigbeeDevice
--- @param command table
local function refresh_handler(driver, device, command)
  log.info("Refreshing Sunricher SR-ZG2856-PRO state...")
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

--- Lifecycle Handler: added
---
--- @param driver Driver
--- @param device ZigbeeDevice
local function device_added(driver, device)
  log.info("Sunricher SR-ZG2856-PRO added to hub")
  button_utils.initialize_button_components(device)
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

--- Lifecycle Handler: init
---
--- @param driver Driver
--- @param device ZigbeeDevice
local function device_init(driver, device)
  log.info("Sunricher SR-ZG2856-PRO initialized")
end

--- Lifecycle Handler: doConfigure
---
--- @param driver Driver
--- @param device ZigbeeDevice
local function device_doconfigure(driver, device)
  log.info("Configuring Sunricher SR-ZG2856-PRO bindings and reporting...")
  local hub_eui = driver.environment_info.hub_zigbee_eui
  local ep = 1

  -- 1. Bind Battery / Power Configuration cluster and configure reporting
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, hub_eui, ep))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))

  -- 2. Bind Sunricher custom remote cluster 0xFF03
  device:send(device_management.build_bind_request(device, SUNRICHER_REMOTE_CLUSTER_ID, hub_eui, ep))

  -- 3. Read initial battery status
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))

  log.info("Sunricher SR-ZG2856-PRO configuration complete")
end

--- Fallback handler for raw or unexpected messages
---
--- @param driver Driver
--- @param device ZigbeeDevice
--- @param zb_rx ZigbeeMessageRx
local function fallback_message_handler(driver, device, zb_rx)
  local cluster_id = zb_rx.address_header.cluster.value
  if cluster_id == SUNRICHER_REMOTE_CLUSTER_ID then
    log.info(string.format("Fallback handler intercepted message on Sunricher cluster 0x%04X", cluster_id))
    sunricher_press_handler(driver, device, zb_rx)
  else
    log.debug(string.format("Unhandled Zigbee message on cluster 0x%04X", cluster_id))
  end
end

local sunricher_driver_template = {
  NAME = "Sunricher SR-ZG2856-PRO Driver",
  supported_capabilities = {
    capabilities.button,
    capabilities.battery,
    capabilities.refresh,
    capabilities.firmwareUpdate,
  },
  zigbee_handlers = {
    cluster = {
      [SUNRICHER_REMOTE_CLUSTER_ID] = {
        [SUNRICHER_PRESS_COMMAND_ID] = sunricher_press_handler,
      }
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler,
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler,
      }
    },
    fallback = fallback_message_handler,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = device_doconfigure,
  },
  ias_zone_configuration_method = nil,
  health_check = false,
  shared_device_thread_enabled = true,
}

defaults.register_for_default_handlers(sunricher_driver_template, sunricher_driver_template.supported_capabilities)
local sunricher_driver = ZigbeeDriver("sunricher-sr-zg2856-pro", sunricher_driver_template)
sunricher_driver:run()
