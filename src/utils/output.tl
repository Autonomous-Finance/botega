local mod = {}

function mod.formatAddress(addr: string, len: number): string
  if not len then len = 3 end
  if not addr then return "unknown" end
  return Colors.green ..
    string.sub(addr, 1, len) ..
    "..." ..
    string.sub(addr, -len) ..
    Colors.reset
end

function mod.prefix(action: string, from: string): string
  return Colors.gray ..
    "New " ..
    Colors.blue ..
    action ..
    Colors.gray ..
    " from " ..
    mod.formatAddress(from) ..
    Colors.gray ..
    ": " ..
    Colors.reset
end

return mod
