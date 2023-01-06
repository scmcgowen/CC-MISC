# MISC
## Modular Inventory Storage and Crafting

## Setup
A minimal MISC system consists of
* A single computer running MISC
* Any number of connected inventories
* (Optionally) A client access terminal

Functionality can be extended by attaching more devices to the network, and adding appropriate modules.
For example, grid crafting functionality can be added by adding the following modules.
* Crafting planner and executor `/modules/crafting.lua`
* Grid crafting provider `/modules/grid.lua`
You'll need some recipes, you can start with `/recipes/*`.

Then adding as many crafty turtles running `/clients/crafter.lua` as you'd like.

### MISC Server
To install the MISC server, you will need the following files.
* The main executable, `storage.lua`
* The modules you'd like in `/modules/`, `/modules/inventory.lua` is required
  * TODO add detail about changing module load order
* The shared library, `common.lua`

### MISC Terminal Client
To install the MISC terminal, attach a turtle to your MISC network and install the following files. These can both be installed to the root of the drive.
* The terminal executable `clients/terminal.lua`
* The generic modem interface library `clients/modem_lib.lua`

You'll also require a few additional modules on the MISC server
* Generic interface handler `/modules/interface.lua`
* Modem interface protocol `/modules/modem.lua`

## Development information
The entrypoint, `storage.lua` is nothing more than a module and config loader.
An example of a module this would load is as follows.
```lua
return {
id = "example",
version = "0.0.1",
config = {
  name = {
    type = "string", -- any serializable lua type is allowed here
    description = "A string configuration option.",
    default = "default",
    -- when this is loaded and passed into init the value of this option will be at ["value"]
  }
},
-- This function is optional. If present, this function will be called whenever a nil config option is encountered in this module's settings.
-- The moduleConfig passed in is the config settings for this specific module.
-- It is asserted that all settings are set to valid values when this function returns.
setup = function(moduleConfig) end,

-- This function is not required, but a warning will be printed if it is not present.
-- loaded is the module environment (more below)
-- config is the config environment (more below)
init = function(loaded, config)
  local interface = {}

  -- This function is optional, if present this will be executed in parallel with all other modules.
  function interface.start = function() end

  function interface
  return interface
end
}
```

The PLAN
* Module for importing/exporting items
* Split the crafting module into several peices
  * Craft scheduler
  * Grid recipe handler
  * Machine recipe handler
* Generic protocol module
  * Interfaces with modules that actually handle the communication i.e. Rednet, modem, encrypted rednet?
