local resetModulesCode = [===[

local INITIAL_MODULES = { ".crypto.mac.hmac", "string", ".crypto.cipher.morus", "debug", ".handlers", ".crypto.padding.zero", ".crypto.digest.sha2_256", ".crypto.digest.md2", ".crypto.util.hex", ".default", ".eval", ".crypto.util.bit", ".utils", ".crypto.util.stream", "_G", "json", ".crypto.cipher.norx", ".base64", ".crypto.cipher.aes256", ".crypto.digest.md4", ".crypto.util.queue", ".stringify", ".handlers-utils", ".crypto.cipher.issac", "utf8", ".crypto.cipher.aes", ".dump", ".process", ".crypto.cipher.mode.cfb", "ao", ".pretty", ".crypto.digest.sha1", "coroutine", ".crypto.cipher.aes128", ".crypto.init", ".crypto.digest.sha2_512", ".crypto.cipher.aes192", ".crypto.kdf.pbkdf2", ".crypto.mac.init", ".crypto.digest.init", "package", "table", ".crypto.cipher.mode.ctr", ".crypto.util.array", "bit32", ".crypto.cipher.mode.ecb", ".crypto.kdf.init", ".assignment", ".crypto.cipher.mode.cbc", ".crypto.digest.blake2b", ".crypto.digest.sha3", ".crypto.digest.md5", ".crypto.cipher.mode.ofb", "io", "os", ".chance", ".crypto.util.init", ".crypto.cipher.init", ".boot" }
      
local function isInitialModule(value)
    for _, v in ipairs(INITIAL_MODULES) do
        if v == value then
            return true
        end
    end
    return false
end

for k, _ in pairs(package.loaded) do
    if not isInitialModule(k) then
        package.loaded[k] = nil
    end
end

]===] 

return resetModulesCode