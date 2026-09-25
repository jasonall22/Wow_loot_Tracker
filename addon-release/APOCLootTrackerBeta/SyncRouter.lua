-- One receive entry point. Modules do not wrap each other's handlers.
local runKinds = {RR4=true,RB4=true,AS4=true,HB4=true,RF4=true,QR4=true,HR4=true,L4=true,LM4=true,Q4=true}
local historyKinds = {HS4=true,HP4=true,HK4=true,GH4=true,GA4=true,GD4=true}
local watchKinds = {LB4=true,LR4=true,LW4=true,LQ4=true}
local controlKinds = {C3=true,H3=true,K3=true,O3=true,S3=true,M3=true,H=true,R=true,H2=true}
local retiredKinds = {N1=true,NK=true,LD4=true,LD5=true,PING=true,PLIVE=true,
  U=true,S=true,LT=true,LH=true,LD=true,LE=true,LX=true,Q2=true,Q3=true,L3=true,LM3=true,AR3=true,AD3=true}

function APOCLootPrio:HandleSyncMessage(message, sender, channel)
  if type(message) ~= "string" or type(sender) ~= "string" or sender == "" then return end
  local function short(name) return string.lower(string.match(name or "", "^([^%-]+)") or "") end
  if short(sender) == short(self:GetPlayerDisplayName()) then return end
  local kind = string.match(message, "^([^\t]+)")
  if retiredKinds[kind] then self:MultiRunDiagnostic("ignoredUnscopedLoot"); return end
  if kind == "NQ" then
    if self:IsCurrentGroupMember(sender) and self:IsLocalLootSyncV2Authority() then self:QueueActiveRunSnapshot() end
    return
  end
  if runKinds[kind] then
    if channel and channel ~= "RAID" and channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then
      self:MultiRunDiagnostic("rejectedWrongChannel"); return
    end
    if not self:IsCurrentGroupMember(sender) then self:MultiRunDiagnostic("rejectedWrongGroup"); return end
    return self:HandleRunSyncMessage(message, sender)
  end
  if historyKinds[kind] then return self:HandleRunSyncMessage(message, sender) end
  if watchKinds[kind] then return self:HandleWatchSyncMessage(message, sender) end
  if controlKinds[kind] then return self:HandleControlSyncMessage(message, sender) end
  if kind == "V" or kind == "A" then return self:HandleInfoSyncMessage(message, sender) end
end
