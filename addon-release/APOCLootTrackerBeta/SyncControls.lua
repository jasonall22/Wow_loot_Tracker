-- User-facing sync actions for the Run-ID-scoped Q4/LQ4 protocols.
-- The beta.73 N1/NK courier discarded drop IDs and pruned the visible session
-- from truncated item names. Never apply those unscoped mutation packets.

local PreviousSetShown = APOCLootPrio.SetRaidLootPanelShown

local function InGroup()
  return (IsInRaid and IsInRaid())
    or (IsInGroup and IsInGroup())
    or (GetNumRaidMembers and GetNumRaidMembers() > 0)
    or (GetNumGroupMembers and GetNumGroupMembers() > 1)
    or (GetNumPartyMembers and GetNumPartyMembers() > 0)
    or false
end

local function IsMasterLooter(self)
  return self.IsLocalLootSyncV2Authority and self:IsLocalLootSyncV2Authority()
end

function APOCLootPrio:AskLiveNotes(force)
  local now = GetTime and GetTime() or (time and time() or 0)
  local interval = force and 2 or 8
  if self.liveNoteAskedAt and now - self.liveNoteAskedAt < interval then
    return false, "Sync already requested. Wait a few seconds."
  end

  if self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly() then
    local id = self:GetSelectedLiveRaidID()
    if not id or not self:RequestLiveRaidWatchSnapshot(id) then
      return false, "Select an active Live Raid before requesting its list."
    end
    self.liveNoteAskedAt = now
    return true, "Requested the selected raid's complete loot list."
  end

  if not InGroup() then return false, "Join the raid or select a Live Raid to watch." end
  if IsMasterLooter(self) then return false, "You are the Master Looter. Press Share List instead." end
  if not self:RequestMultiRunSync() then return false, "Could not request the raid's Run ID." end
  self.liveNoteAskedAt = now

  -- Establish the Run ID before requesting a snapshot from the Master Looter.
  local function request()
    if InGroup() and not IsMasterLooter(self)
      and not (self.IsLiveRaidWatchOnly and self:IsLiveRaidWatchOnly()) then
      self:RequestLootSessionSync()
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, request) else request() end
  return true, "Requested the Master Looter\'s complete loot list."
end

function APOCLootPrio:ShareLiveList()
  if not InGroup() or not IsMasterLooter(self) then
    return false, "Only the Master Looter can share this list."
  end
  self:BroadcastMultiRunBeacon()
  if not self:QueueActiveRunSnapshot() then
    return false, "No active raid is available to share."
  end
  return true, "Queued the complete raid loot list for synchronization."
end

function APOCLootPrio:ForceLiveListSync()
  if InGroup() and IsMasterLooter(self) then return self:ShareLiveList() end
  return self:AskLiveNotes(true)
end



function APOCLootPrio:SetRaidLootPanelShown(enabled)
  if PreviousSetShown then PreviousSetShown(self, enabled) end
  if enabled then self:AskLiveNotes() end
end
