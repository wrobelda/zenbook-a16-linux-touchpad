dofile(os.getenv("T").."/harness2.lua")
local plist = {}; for i=2,#arg do plist[#plist+1]=arg[i] end
H.load(plist)
local out = io.open(os.getenv("OUT"), "w")
local raw, rslot, fr = {}, 0, {}
local function usage(ty, code)
  if ty==3 then return code>=0x2f and code or (0x100+code) elseif ty==1 then return code elseif ty==4 then return 0x200+code end end
for line in io.lines(arg[1]) do
  local s,us,ty,code,val = line:match("%-%s*%[%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%-?%d+)%]")
  if s then
    ty,code,val = tonumber(ty),tonumber(code),tonumber(val)
    if ty==3 and code==0x2f then rslot=val
    elseif ty==3 and code==0x39 then if val==-1 then raw[rslot]=nil else raw[rslot]={x=raw[rslot] and raw[rslot].x, y=raw[rslot] and raw[rslot].y, t0=tonumber(s)+tonumber(us)/1e6} end
    elseif ty==3 and code==0x35 and raw[rslot] then raw[rslot].x=val
    elseif ty==3 and code==0x36 and raw[rslot] then raw[rslot].y=val end
    if ty==0 and code==0 then
      local t = tonumber(s)*1000+tonumber(us)/1000
      H.send(fr, t*1000); fr = {}
      local r, v = {}, {}
      for sl,p in pairs(raw) do r[#r+1]=("%d:%s:%s"):format(sl,p.x,p.y) end
      for sl,p in pairs(H.li.touches) do v[#v+1]=("%d:%s:%s"):format(sl,p.x,p.y) end
      table.sort(r); table.sort(v)
      out:write(("%.3f|%s|%s\n"):format(t, table.concat(r," "), table.concat(v," ")))
    elseif ty ~= 0 then fr[#fr+1] = {usage=usage(ty,code), value=val} end
  end
end
out:close()
