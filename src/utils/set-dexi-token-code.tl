local setDexiTokenCode = function(dexiToken: string): string
    return [[
    
    DexiTokenProcess = "]] .. dexiToken .. [["
    
    ]]
end 

return setDexiTokenCode