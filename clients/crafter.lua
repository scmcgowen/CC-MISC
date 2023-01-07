-- file to put on a turtle
local modem = peripheral.find("modem", function(name, modem)
  -- return not modem.isWireless()
  return true
end)
rednet.open(peripheral.getName(modem))
local networkName = modem.getNameLocal()
---@enum State
local STATES = {
  READY = "READY",
  ERROR = "ERROR",
  BUSY = "BUSY",
  CRAFTING = "CRAFTING",
  DONE = "DONE",
}
local state = STATES.READY
local connected = false
local port = 121
local keepAliveTimeout = 10
local w,h = term.getSize()
local banner = window.create(term.current(), 1, 1, w, 1)
local panel = window.create(term.current(),1,2,w,h-1)

local lastStateChange = os.epoch("utc")

local turtleInventory = {}
local function refreshTurtleInventory()
  local f = {}
  for i = 1, 16 do
    f[i] = function()
      turtleInventory[i] = turtle.getItemDetail(i, true)
    end
  end
  parallel.waitForAll(table.unpack(f))
  return turtleInventory
end
---@type CraftingNode 
local task
term.redirect(panel)

modem.open(port)
local function validateMessage(message)
  local valid = type(message) == "table" and message.protocol ~= nil
  valid = valid and (message.destination == networkName or message.destination == "*")
  valid = valid and message.source ~= nil
  return valid
end
local function getModemMessage(filter, timeout)
  local timer
  if timeout then
    timer = os.startTimer(timeout)
  end
  while true do
    ---@type string, string, integer, integer, any, integer
    local event, side, channel, reply, message, distance = os.pullEvent()
    if event == "modem_message" and (filter == nil or filter(message)) then
      if timeout then
        os.cancelTimer(timer)
      end
      return {
        side = side,
        channel = channel,
        reply = reply,
        message = message,
        distance = distance
      }
    elseif event == "timer" and timeout and side == timer then
      return
    end
  end
end
local lastChar = "|"
local charStateLookup = {
  ["|"] = "/",
  ["/"] = "-",
  ["-"] = "\\",
  ["\\"] = "|",
}
local last_char_update = os.epoch("utc")
local function get_activity_char()
  if os.epoch("utc") - last_char_update < 50 then
    return lastChar
  end
  last_char_update = os.epoch("utc")
  lastChar = charStateLookup[lastChar]
  return lastChar
end
local function writeBanner()
  local x, y = term.getCursorPos()

  banner.setBackgroundColor(colors.gray)
  banner.setCursorPos(1,1)
  banner.clear()
  if connected then
    banner.setTextColor(colors.green)
    banner.write("CONNECTED")
  else
    banner.setTextColor(colors.red)
    banner.write("DISCONNECTED")
  end
  banner.setTextColor(colors.white)
  banner.setCursorPos(w-state:len(),1)
  banner.write(state)
  term.setCursorPos(x,y)

  local to_display = state
  if not connected then
    to_display = "!"..to_display
  end

  os.setComputerLabel(
    ("%s %s - %s"):format(get_activity_char(), networkName, to_display))
end
local function keepAlive()
  while true do
    local modem_message = getModemMessage(function(message)
      return validateMessage(message) and message.protocol == "KEEP_ALIVE"
    end, keepAliveTimeout)
    connected = modem_message ~= nil
    if modem_message then
      modem.transmit(port, port, {
        protocol = "KEEP_ALIVE",
        state = state,
        source = networkName,
        destination = "HOST",
      })
    end
    writeBanner()
  end
end
local function colWrite(fg, text)
  local old_fg = term.getTextColor()
  term.setTextColor(fg)
  term.write(text)
  term.setTextColor(old_fg)
end

---@param newState State
local function changeState(newState)
  if state ~= newState then
    lastStateChange = os.epoch("utc")
  end
  state = newState
  local itemSlots = {}
  for i, _ in pairs(turtleInventory) do
    table.insert(itemSlots, i)
  end
  modem.transmit(port, port, {
    protocol = "KEEP_ALIVE",
    state = state,
    source = networkName,
    destination = "HOST",
    itemSlots = itemSlots,
  })
  writeBanner()
end

local function getItemSlots()
  refreshTurtleInventory()
  local itemSlots = {}
  for i, _ in pairs(turtleInventory) do
    table.insert(itemSlots, i)
  end
  return itemSlots

end

local function empty()
  local itemSlots = getItemSlots()
  repeat
    modem.transmit(port, port, {
      protocol = "EMPTY",
      destination = "HOST",
      source = networkName,
      itemSlots = itemSlots
    })
    itemSlots = getItemSlots()
    os.sleep(3)
    -- this delay needs to be high enough
    -- to allow the inventory system to
    -- actually perform the transfers
  until #itemSlots == 0
end

local function signalDone()
  local itemSlots = getItemSlots()
  changeState(STATES.DONE)
  modem.transmit(port, port, {
    protocol = "CRAFTING_DONE",
    destination = "HOST",
    source = networkName,
    itemSlots = itemSlots,
  })
end

local function tryToCraft()
  local readyToCraft = true
  for slot,v in pairs(task.plan) do
    local x = (slot-1) % (task.width or 3) + 1
    local y = math.floor((slot-1) / (task.height or 3))
    local turtleSlot = y * 4 + x
    readyToCraft = readyToCraft and turtleInventory[turtleSlot]
    if not readyToCraft then
      break
    else
      readyToCraft = readyToCraft and turtleInventory[turtleSlot].count == v.count
      local error_free = turtleInventory[turtleSlot].name == v.name
      if not error_free then
        state = STATES.ERROR
        return
      end
    end
  end
  if readyToCraft then
    turtle.craft()
    signalDone()
  end
end


local protocols = {
  CRAFT = function (message)
    task = message.task
    changeState(STATES.CRAFTING)
    tryToCraft()
  end
}

local interface
local function modemInterface()
  while true do
    local event = getModemMessage(validateMessage)
    assert(event, "Got no message?")
    if protocols[event.message.protocol] then
      protocols[event.message.protocol](event.message)
    end
  end
end

local function turtleInventoryEvent()
  while true do
    os.pullEvent("turtle_inventory")
    refreshTurtleInventory()
    if state == STATES.CRAFTING then
      tryToCraft()
    elseif state == STATES.DONE then
      -- check if the items have been removed from the inventory
      refreshTurtleInventory()
      local empty_inv = not next(turtleInventory)
      if empty_inv then
        changeState(STATES.READY)
      end
    end
  end
end
local interfaceLUT
interfaceLUT = {
  help = function()
    local maxw = 0
    local commandList = {}
    for k,v in pairs(interfaceLUT) do
      maxw = math.max(maxw, k:len()+1)
      table.insert(commandList, k)
    end
    local elementW = math.floor(w / maxw)
    local formatStr = "%"..maxw.."s"
    for i,v in ipairs(commandList) do
      term.write(formatStr:format(v))
      if (i + 1) % elementW == 0 then
        print()
      end
    end
    print()
  end,
  clear = function()
    term.clear()
    term.setCursorPos(1,1)
  end,
  info = function()
    print(("Local network name: %s"):format(networkName))
  end,
  cinfo = function()
    if state == STATES.CRAFTING then
      print("Current recipe is:")
      print(textutils.serialise(task.plan))
    else
      print("Not crafting.")
    end
  end,
  reboot = function ()
    os.reboot()
  end
}
function interface()
  print("Crafting turtle indev")
  while true do
    colWrite(colors.cyan, "] ")
    local input = io.read()
    if interfaceLUT[input] then
      interfaceLUT[input]()
    else
      colWrite(colors.red, "Invalid command.")
      print()
    end
  end
end

local retries = 0
local function errorChecker()
  while true do
    if os.epoch("utc") - lastStateChange > 10000 then
      lastStateChange = os.epoch("utc")
      if state == STATES.DONE then
        signalDone()
        retries = retries + 1
        if retries > 2 then
          print("Done too long")
          changeState(STATES.ERROR)
        end
      elseif state == STATES.CRAFTING then
        retries = retries + 1
        if retries > 2 then
          print("Crafting too long")
          changeState(STATES.ERROR)
        end
      else
        retries = 0
      end
    end
    os.sleep(1)
    writeBanner()
  end
end

writeBanner()
local ok, err = pcall(parallel.waitForAny, interface, keepAlive, modemInterface, turtleInventoryEvent, errorChecker)

os.setComputerLabel(("X %s - %s"):format(networkName, "OFFLINE"))
error(err)