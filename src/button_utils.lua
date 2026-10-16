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
local log = require "log"

local button_utils = {}

button_utils.TOTAL_BUTTONS = 10
button_utils.SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double", "up_hold" }

-- Mapping of Sunricher press types (from cluster 0xFF03 cmd 0x01) to SmartThings capability events
local PRESS_TYPE_MAP = {
  [1] = "pushed",   -- Short press
  [2] = "double",   -- Double press
  [3] = "held",     -- Long press / hold
  [4] = "up_hold",  -- Hold release
}

--- Parse Sunricher Remote Cluster 0xFF03 Press message payload.
--- The payload can be passed either as a parsed ZCL structure or as raw body bytes.
---
--- Frame Structure:
--- - Message Type: 0x01 (Button press event)
--- - Button2: High byte of button bitmask
--- - Button1: Low byte of button bitmask
--- - PressType: 1=short_press, 2=double_press, 3=hold, 4=hold_released
---
--- @param zcl_body table|string The ZCL body or raw payload
--- @return string|nil action The SmartThings button action name ("pushed", "double", "held", "up_hold")
--- @return table action_buttons Array of integer button numbers (1..10)
button_utils.parse_sunricher_press = function(zcl_body)
  if not zcl_body then
    return nil, {}
  end

  local msg_type = nil
  local button2 = 0
  local button1 = 0
  local press_type = nil

  -- 1. Try reading as table/object fields
  if type(zcl_body) == "table" then
    msg_type = zcl_body.messageType or zcl_body.message_type or zcl_body.msg_type
    button2 = zcl_body.button2 or zcl_body.button_2 or 0
    button1 = zcl_body.button1 or zcl_body.button_1 or 0
    press_type = zcl_body.pressType or zcl_body.press_type
  end

  -- 2. If not found in table fields, extract from raw bytes
  if msg_type == nil or press_type == nil then
    local raw_bytes = nil
    if type(zcl_body) == "string" then
      raw_bytes = zcl_body
    elseif type(zcl_body) == "table" then
      if type(zcl_body.body_bytes) == "string" then
        raw_bytes = zcl_body.body_bytes
      elseif type(zcl_body.bytes) == "string" then
        raw_bytes = zcl_body.bytes
      elseif type(zcl_body.data) == "string" then
        raw_bytes = zcl_body.data
      end
    end

    if raw_bytes ~= nil and #raw_bytes >= 4 then
      local len = #raw_bytes
      -- If frame includes 3-byte ZCL header (frame control, seq, cmd) + 4-byte payload (len >= 7 and byte(4) == 0x01)
      if len >= 7 and raw_bytes:byte(4) == 0x01 then
        msg_type = raw_bytes:byte(4)
        button2 = raw_bytes:byte(5)
        button1 = raw_bytes:byte(6)
        press_type = raw_bytes:byte(7)
      -- If payload only (4 bytes starting with msgType 0x01)
      elseif raw_bytes:byte(1) == 0x01 and len >= 4 then
        msg_type = raw_bytes:byte(1)
        button2 = raw_bytes:byte(2)
        button1 = raw_bytes:byte(3)
        press_type = raw_bytes:byte(4)
      end
    end
  end

  if msg_type ~= 0x01 or press_type == nil then
    return nil, {}
  end

  local action = PRESS_TYPE_MAP[press_type] or "pushed"
  local button_mask = (button2 * 256) + button1
  local action_buttons = {}

  for i = 0, 15 do
    local is_set = (math.floor(button_mask / (2 ^ i)) % 2) == 1
    if is_set then
      local btn_num = i + 1
      if btn_num <= button_utils.TOTAL_BUTTONS then
        table.insert(action_buttons, btn_num)
      end
    end
  end

  return action, action_buttons
end

--- Emit a button event to the corresponding button component and the main component.
---
--- @param device ZigbeeDevice The SmartThings device instance
--- @param button_number number Button number (1..10)
--- @param action string Action name ("pushed", "double", "held", "up_hold")
button_utils.emit_button_event = function(device, button_number, action)
  local button_attr = capabilities.button.button[action]
  if not button_attr then
    log.warn(string.format("Unsupported button action: %s", tostring(action)))
    button_attr = capabilities.button.button.pushed
  end

  local additional_fields = {
    state_change = true
  }
  local event = button_attr(additional_fields)

  -- 1. Emit to specific button component
  local comp_name = string.format("button%d", button_number)
  local comp = device.profile.components[comp_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
    log.info(string.format("Emitted %s for component %s", action, comp_name))
  else
    log.warn(string.format("Component %s not found in device profile", comp_name))
  end

  -- 2. Emit to main component for general automations
  device:emit_event(event)
end

--- Initialize all button capability states and supported button values for all components.
---
--- @param device ZigbeeDevice The SmartThings device instance
button_utils.initialize_button_components = function(device)
  local supp_values = button_utils.SUPPORTED_BUTTON_VALUES

  for comp_id, comp in pairs(device.profile.components) do
    local num_buttons = 1
    if comp_id == "main" then
      num_buttons = button_utils.TOTAL_BUTTONS
    end

    device:emit_component_event(
      comp,
      capabilities.button.supportedButtonValues(supp_values, { visibility = { displayed = false } })
    )
    device:emit_component_event(
      comp,
      capabilities.button.numberOfButtons({ value = num_buttons }, { visibility = { displayed = false } })
    )

    -- Initialize state without triggering automations
    local initial_event = capabilities.button.button.pushed({ state_change = false })
    device:emit_component_event(comp, initial_event)
  end
end

return button_utils
