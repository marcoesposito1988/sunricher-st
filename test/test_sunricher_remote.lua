-- Comprehensive Unit Test Suite for Sunricher SR-ZG2856-PRO SmartThings Edge Driver

package.path = package.path .. ";./src/?.lua;./src/?/init.lua"

-- Mock SmartThings environment
local mock_capabilities = {
  button = {
    ID = "button",
    supportedButtonValues = function(vals, opts)
      return { capability = "button", attribute = "supportedButtonValues", value = vals, options = opts }
    end,
    numberOfButtons = function(val, opts)
      return { capability = "button", attribute = "numberOfButtons", value = val.value, options = opts }
    end,
    button = {
      NAME = "button",
      pushed = function(fields) return { capability = "button", attribute = "button", value = "pushed", fields = fields } end,
      double = function(fields) return { capability = "button", attribute = "button", value = "double", fields = fields } end,
      held = function(fields) return { capability = "button", attribute = "button", value = "held", fields = fields } end,
      up_hold = function(fields) return { capability = "button", attribute = "button", value = "up_hold", fields = fields } end,
    }
  },
  battery = {
    ID = "battery",
    battery = function(pct)
      return { capability = "battery", attribute = "battery", value = pct }
    end
  },
  refresh = {
    ID = "refresh",
    commands = {
      refresh = { NAME = "refresh" }
    }
  },
  firmwareUpdate = {
    ID = "firmwareUpdate"
  }
}

package.loaded["st.capabilities"] = mock_capabilities
package.loaded["log"] = {
  info = function(msg) end,
  warn = function(msg) end,
  debug = function(msg) end,
  error = function(msg) end,
}
package.loaded["st.utils"] = {
  clamp_value = function(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
  end
}

local button_utils = require "button_utils"

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("Assertion failed: expected '%s', got '%s'. %s", tostring(expected), tostring(actual), msg or ""), 2)
  end
end

local function assert_tables_eq(actual, expected, msg)
  if #actual ~= #expected then
    error(string.format("Table length mismatch: expected %d, got %d. %s", #expected, #actual, msg or ""), 2)
  end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error(string.format("Element %d mismatch: expected %s, got %s. %s", i, tostring(expected[i]), tostring(actual[i]), msg or ""), 2)
    end
  end
end

print("=== Running Sunricher SR-ZG2856-PRO Unit Tests ===")

-- Test 1: Single button short press (K1, bit 0)
do
  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = 0x00,
    button1 = 0x01,
    pressType = 1
  })
  assert_eq(action, "pushed", "K1 short press should map to 'pushed'")
  assert_tables_eq(buttons, { 1 }, "Button mask 0x0001 should resolve to button 1")
  print("✓ Test 1 Passed: K1 short press")
end

-- Test 2: Double press (K5, bit 4 -> 0x0010)
do
  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = 0x00,
    button1 = 0x10,
    pressType = 2
  })
  assert_eq(action, "double", "K5 double press should map to 'double'")
  assert_tables_eq(buttons, { 5 }, "Button mask 0x0010 should resolve to button 5")
  print("✓ Test 2 Passed: K5 double press")
end

-- Test 3: Hold / Long press (K10, bit 9 -> 0x0200)
do
  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = 0x02,
    button1 = 0x00,
    pressType = 3
  })
  assert_eq(action, "held", "K10 hold should map to 'held'")
  assert_tables_eq(buttons, { 10 }, "Button mask 0x0200 should resolve to button 10")
  print("✓ Test 3 Passed: K10 hold")
end

-- Test 4: Hold release (K10, bit 9 -> 0x0200)
do
  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = 0x02,
    button1 = 0x00,
    pressType = 4
  })
  assert_eq(action, "up_hold", "K10 hold release should map to 'up_hold'")
  assert_tables_eq(buttons, { 10 }, "Button mask 0x0200 should resolve to button 10")
  print("✓ Test 4 Passed: K10 hold release")
end

-- Test 5: All 10 individual buttons bitmask check
for btn = 1, 10 do
  local bit_pos = btn - 1
  local mask = 2 ^ bit_pos
  local b2 = math.floor(mask / 256)
  local b1 = mask % 256

  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = b2,
    button1 = b1,
    pressType = 1
  })
  assert_eq(action, "pushed")
  assert_tables_eq(buttons, { btn }, string.format("Button K%d should match bit %d", btn, bit_pos))
end
print("✓ Test 5 Passed: All 10 buttons (K1..K10) bitmask decoding")

-- Test 6: Raw body bytes parsing (payload only: 4 bytes)
do
  -- messageType=0x01, button2=0x00, button1=0x04 (K3), pressType=0x03 (held)
  local raw_payload = string.char(0x01, 0x00, 0x04, 0x03)
  local action, buttons = button_utils.parse_sunricher_press({
    body_bytes = raw_payload
  })
  assert_eq(action, "held")
  assert_tables_eq(buttons, { 3 })
  print("✓ Test 6 Passed: Raw payload bytes (GenericBody)")
end

-- Test 7: Raw body bytes with 3-byte ZCL header (7 bytes)
do
  -- header: 0x01, 0x00, 0x01 (cmd 0x01) | payload: 0x01, 0x01 (button 9), 0x00, 0x02 (double)
  local raw_frame = string.char(0x01, 0x00, 0x01, 0x01, 0x01, 0x00, 0x02)
  local action, buttons = button_utils.parse_sunricher_press(raw_frame)
  assert_eq(action, "double")
  assert_tables_eq(buttons, { 9 })
  print("✓ Test 7 Passed: Raw 7-byte ZCL frame with header")
end

-- Test 8: Multiple simultaneous button presses (e.g. K1 and K2 pressed together)
do
  -- buttonMask = (1 << 0) | (1 << 1) = 0x0003
  local action, buttons = button_utils.parse_sunricher_press({
    messageType = 0x01,
    button2 = 0x00,
    button1 = 0x03,
    pressType = 1
  })
  assert_eq(action, "pushed")
  assert_tables_eq(buttons, { 1, 2 }, "Should return buttons 1 and 2")
  print("✓ Test 8 Passed: Simultaneous multi-button press decoding")
end

-- Test 9: Device Component Initialization & Event Emission
do
  local emitted_events = {}
  local mock_device = {
    profile = {
      components = {
        main = { id = "main" },
        button1 = { id = "button1" },
        button2 = { id = "button2" },
        button3 = { id = "button3" },
        button4 = { id = "button4" },
        button5 = { id = "button5" },
        button6 = { id = "button6" },
        button7 = { id = "button7" },
        button8 = { id = "button8" },
        button9 = { id = "button9" },
        button10 = { id = "button10" },
      }
    },
    emit_component_event = function(self, comp, event)
      table.insert(emitted_events, { comp = comp.id, event = event })
    end,
    emit_event = function(self, event)
      table.insert(emitted_events, { comp = "main_event", event = event })
    end
  }

  button_utils.initialize_button_components(mock_device)
  assert_eq(#emitted_events, 33, "11 components * 3 events each = 33 events on init")

  -- Now test emitting a button event
  emitted_events = {}
  button_utils.emit_button_event(mock_device, 7, "pushed")
  assert_eq(#emitted_events, 2, "Should emit to button7 component and main")
  assert_eq(emitted_events[1].comp, "button7")
  assert_eq(emitted_events[1].event.value, "pushed")
  assert_eq(emitted_events[1].event.fields.state_change, true)
  assert_eq(emitted_events[2].comp, "main_event")
  assert_eq(emitted_events[2].event.value, "pushed")
  print("✓ Test 9 Passed: Component initialization and event emission")
end

print("\n=== ALL TESTS PASSED SUCCESSFULLY! ===")
