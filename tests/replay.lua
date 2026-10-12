dofile(os.getenv("T").."/harness.lua")
local file, plist = arg[1], {}
for i=2,#arg do plist[#plist+1]=arg[i] end
H.load(plist)
local out = io.open(os.getenv("OUT"), "w")
local fr, n = {}, 0
local function usage(ty, code)
  if ty==3 then return code>=0x2f and code or (0x100+code) elseif ty==1 then return code elseif ty==4 then return 0x200+code end end
for line in io.lines(file) do
  local s,us,ty,code,val = line:match("%-%s*%[%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%-?%d+)%]")
  if s then
    ty,code,val = tonumber(ty),tonumber(code),tonumber(val)
    if ty==0 and code==0 then
      H.send(fr, tonumber(s)*1000000+tonumber(us)); n=n+1; fr={}
      -- libinput view of non-palm touches after this frame
      local keys = {}
      for slot,t in pairs(H.li.touches) do if t.tool ~= 2 then keys[#keys+1]=("%d:%s,%s"):format(slot,t.x,t.y) end end
      table.sort(keys); out:write(table.concat(keys," "),"\n")
    elseif ty ~= 0 then fr[#fr+1] = {usage=usage(ty,code), value=val} end
  end
end
out:close(); io.stderr:write(("%s: %d frames\n"):format(file, n))
