-- check every plugin's own output, as libinput does
local send = H.send
function H.send(fr, t)
  for i, f in ipairs(H.fh) do local r = f(H.dev, fr, t or 0); if r then fr = r end
    for _, e in ipairs(fr) do if e.usage == nil or type(e.value) ~= "number" then return {{usage=e.usage, value=e.value}} end end end
  return fr
end
