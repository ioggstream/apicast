--- This module is responsible for loading OIDC configuration via OIDC Discovery.
--- Discovered configuration is put back to the APIcast configuration and serialized to JSON.

local configuration_parser = require('apicast.configuration_parser')
local cjson = require('cjson')

local ipairs = ipairs
local select = select
local setmetatable = setmetatable

local _M = {}


local empty = {}

local function array(table)
    return setmetatable(table or {}, cjson.empty_array_mt)
end

_M.discovery = require('resty.oidc.discovery').new()

local function load_service(service)
    if not service or not service.proxy then return nil end

    return _M.discovery:call(service.proxy.oidc_issuer_endpoint)
end

function _M.call(...)
    local contents = select(1, ...)
    local config = configuration_parser.decode(contents)

    if config then
        local oidc = array(config.oidc)

        for i,service in ipairs(config.services or empty) do
            oidc[i] = oidc[i] or load_service(service)
        end

        config.oidc = oidc

        return cjson.encode(config), select(2, ...)
    else
        return ...
    end
end

return _M
