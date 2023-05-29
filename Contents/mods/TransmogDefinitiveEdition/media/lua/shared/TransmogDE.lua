TransmogDE = TransmogDE or {}

TransmogDE.ImmersiveModeMap = {}
TransmogDE.BackupClothingItemAsset = {}

TransmogDE.GenerateTransmogGlobalModData = function()
  TmogPrint('Server TransmogModData')
  local scriptManager = getScriptManager();
  local allItems = scriptManager:getAllItems()
  local transmogModData = TransmogDE.getTransmogModData()
  local itemToTransmogMap = transmogModData.itemToTransmogMap or {}
  local transmogToItemMap = transmogModData.transmogToItemMap or {}

  local serverTransmoggedItemCount = 0
  local size = allItems:size() - 1;
  for i = 0, size do
    local item = allItems:get(i);
    if TransmogDE.isTransmoggable(item) then
      local fullName = item:getFullName()
      serverTransmoggedItemCount = serverTransmoggedItemCount + 1
      if not itemToTransmogMap[fullName] then
        table.insert(transmogToItemMap, fullName)
        itemToTransmogMap[fullName] = 'TransmogDE.TransmogItem_' .. #transmogToItemMap
      end
      TmogPrint(fullName .. ' -> ' .. tostring(itemToTransmogMap[fullName]))
    end
  end

  if #transmogToItemMap >= 5000 then
    TmogPrint("ERROR: Reached limit of transmoggable items")
  end

  ModData.add("TransmogModData", transmogModData)
  ModData.transmit("TransmogModData")

  TmogPrint('Transmogged items count: ' .. tostring(serverTransmoggedItemCount))

  return transmogModData
end

TransmogDE.patchAllItemsFromModData = function(modData)
  for originalItemName, tmogItemName in pairs(modData.itemToTransmogMap) do
    local originalScriptItem = ScriptManager.instance:getItem(originalItemName)
    local tmogScriptItem = ScriptManager.instance:getItem(tmogItemName)
    if originalScriptItem ~= nil and tmogScriptItem ~= nil then
      local originalClothingItemAsset = originalScriptItem:getClothingItemAsset()

      if originalClothingItemAsset then
        local tmogClothingItemAsset = tmogScriptItem:getClothingItemAsset()
        tmogScriptItem:setClothingItemAsset(originalClothingItemAsset)

        if originalClothingItemAsset:isHat() or originalClothingItemAsset:isMask() then
          -- Since we use the tmog item to check textureChoices and colorTint in Transmog\InvContextMenu.lua
          -- using the backup will be handy to ensure we always select the original textureChoices and colorTint
          TransmogDE.BackupClothingItemAsset[originalItemName] = originalClothingItemAsset
          -- Hide hats to avoid having the hair being compressed if wearning an helmet or something similiar
          originalScriptItem:setClothingItemAsset(tmogClothingItemAsset)
        end
      end
    end
  end
  -- Must be triggered after items are patched
  TransmogDE.triggerUpdate()

  -- TmogPrintTable(TransmogDE.BackupClothingItemAsset)
end

TransmogDE.triggerUpdate = function(player)
  local player = player or getPlayer()
  TmogPrint('triggerUpdate')
  triggerEvent("ApplyTransmogToPlayerItems", player)
end

local invalidBodyLocations = {
  TransmogLocation = true,
  Bandage = true,
  Wound = true,
  ZedDmg = true,
  Hide_Everything = true,
  Fur = true, -- Support for "the furry mod"
}
TransmogDE.isTransmoggableBodylocation = function(bodyLocation)
  return not invalidBodyLocations[bodyLocation] and not string.find(bodyLocation, "MakeUp_")
end

TransmogDE.isTransmoggable = function(scriptItem)
  if scriptItem.getScriptItem then
    scriptItem = scriptItem:getScriptItem()
  end

  local typeString = scriptItem:getTypeString()
  local isClothing = typeString == 'Clothing'
  local bodyLocation = scriptItem:getBodyLocation()
  local isBackpack = typeString == "Container" and
      (scriptItem:InstanceItem(nil):canBeEquipped() or bodyLocation)
  local isClothingItemAsset = scriptItem:getClothingItemAsset() ~= nil
  local isWorldRender = scriptItem:isWorldRender()
  local isNotHidden = not scriptItem:isHidden()
  local isNotTransmog = scriptItem:getModuleName() ~= "TransmogDE"
  -- local isNotCosmetic = not scriptItem:isCosmetic()
  if (isClothing or isBackpack)
      and TransmogDE.isTransmoggableBodylocation(bodyLocation)
      -- and isNotCosmetic
      and isNotTransmog
      and isWorldRender
      and isClothingItemAsset
      and isNotHidden
      and isNotHidden then
    return true
  end
  return false
end

TransmogDE.isTransmogItem = function(scriptItem)
  if scriptItem.getScriptItem then
    scriptItem = scriptItem:getScriptItem()
  end

  return scriptItem:getModuleName() == "TransmogDE"
end

TransmogDE.getTransmogModData = function()
  local TransmogModData = ModData.get("TransmogModData");
  return TransmogModData or {
    itemToTransmogMap = {},
    transmogToItemMap = {},
  }
end

TransmogDE.giveHideClothingItemToPlayer = function()
  local player = getPlayer();
  local spawnedItem = player:getInventory():AddItem('TransmogDE.Hide_Everything');
  player:setWornItem(spawnedItem:getBodyLocation(), spawnedItem)
end

TransmogDE.giveTransmogItemToPlayer = function(ogItem)
  -- args.itemID = self.fuel:getID()
  local player = getPlayer();

  local transmogModData = TransmogDE.getTransmogModData()
  local itemTmogModData = TransmogDE.getItemTransmogModData(ogItem)

  local tmogItemName = transmogModData.itemToTransmogMap[itemTmogModData.transmogTo]

  if not tmogItemName then
    return
  end

  local tmogItem = player:getInventory():AddItem(tmogItemName);

  -- For debug purpose
  tmogItem:setName('Tmog: ' .. ogItem:getName())

  TransmogDE.setClothingColorModdata(ogItem, TransmogDE.getClothingColor(ogItem))
  TransmogDE.setClothingTextureModdata(ogItem, TransmogDE.getClothingTexture(ogItem))
  TransmogDE.setTmogColor(tmogItem, TransmogDE.getClothingColor(ogItem))
  TransmogDE.setTmogTexture(tmogItem, TransmogDE.getClothingTexture(ogItem))

  -- tmogItem:synchWithVisual()

  player:setWornItem(tmogItem:getBodyLocation(), tmogItem)

  TmogPrintTable(TransmogDE.getItemTransmogModData(ogItem))
end

-- Item Specific Code

TransmogDE.getClothingItemAsset = function(scriptItem)
  if scriptItem.getScriptItem then
    scriptItem = scriptItem:getScriptItem()
  end
  local fullName = scriptItem:getFullName()
  local clothingItemAsset = TransmogDE.BackupClothingItemAsset[fullName] or scriptItem:getClothingItemAsset()
  
  return clothingItemAsset
end

TransmogDE.getItemTransmogModData = function(item)
  local itemModData = item:getModData()
  itemModData['Transmog'] = itemModData['Transmog'] or {
    color = nil,
    texture = nil,
    transmogTo = item:getScriptItem():getFullName()
  }

  return itemModData['Transmog']
end

TransmogDE.setClothingColorModdata = function(item, color)
  if color == nil then
    return
  end

  local itemModData = TransmogDE.getItemTransmogModData(item)
  itemModData.color = {
    r = color:getRedFloat(),
    g = color:getGreenFloat(),
    b = color:getBlueFloat(),
    a = color:getAlphaFloat(),
  }
end

TransmogDE.setClothingTextureModdata = function(item, textureIdx)
  if textureIdx == nil then
    return
  end

  local itemModData = TransmogDE.getItemTransmogModData(item)
  itemModData.texture = textureIdx
end

TransmogDE.setTmogColor = function(item, color)
  if color == nil then
    return
  end

  item:getVisual():setTint(color)

  getPlayer():resetModelNextFrame();
end

TransmogDE.setTmogTexture = function(item, textureIndex)
  if textureIndex < 0 or textureIndex == nil then
    return
  end

  if item:getClothingItem():hasModel() then
    item:getVisual():setTextureChoice(textureIndex)
  else
    item:getVisual():setBaseTexture(textureIndex)
  end

  item:synchWithVisual();
  -- TmogPrint('setClothingTexture' .. tostring(textureIndex))
end

TransmogDE.getClothingColor = function(item)
  local itemModData = TransmogDE.getItemTransmogModData(item)
  local parsedColor = itemModData.color and
      ImmutableColor.new(Color.new(itemModData.color.r, itemModData.color.g, itemModData.color.b, itemModData.color.a))
  return parsedColor or item:getVisual():getTint()
end

TransmogDE.getClothingTexture = function(item)
  local itemModData = TransmogDE.getItemTransmogModData(item)

  if itemModData.texture then
    return itemModData.texture
  end

  -- Very similiar to what is done inside: media\lua\client\OptionScreens\CharacterCreationMain.lua
  local clothingItem = item:getVisual():getClothingItem()
  local texture = clothingItem:hasModel() and item:getVisual():getTextureChoice() or item:getVisual():getBaseTexture()
  return texture
end

TransmogDE.setItemTransmog = function(itemToTmog, scriptItem)
  local moddata = TransmogDE.getItemTransmogModData(itemToTmog)

  if scriptItem.getScriptItem then
    scriptItem = scriptItem:getScriptItem()
  end

  moddata.transmogTo = scriptItem:getFullName()
end

TransmogDE.setItemToDefault = function(item)
  local moddata = TransmogDE.getItemTransmogModData(item)

  moddata.transmogTo = item:getScriptItem():getFullName()
end

TransmogDE.setClothingHidden = function(item)
  local moddata = TransmogDE.getItemTransmogModData(item)

  moddata.transmogTo = nil
end

-- Immersive mode code

TransmogDE.getImmersiveModeData = function()
  return ModData.getOrCreate('TransmogImmersiveModeData')
end

TransmogDE.immersiveModeItemCheck = function(item)
  if SandboxVars.TransmogDE.ImmersiveModeToggle ~= true then
    return true
  end
  return TransmogDE.getImmersiveModeData()[item:getFullName()] == true
end
