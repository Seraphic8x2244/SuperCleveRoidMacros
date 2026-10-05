local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

local Storage = CleveRoids.ImmunityStorage or {}
CleveRoids.ImmunityStorage = Storage

Storage.DB_FILENAME = "SuperCleveRoidMacros_Immunity.db"
Storage.SCHEMA_VERSION = 1
Storage.handle = nil
Storage.ready = false
Storage.schemaVersion = nil
Storage.hearthDBVersion = nil
Storage.lastErrorCode = nil
Storage.lastError = nil
Storage.lastResetReason = nil

local REQUIRED_FUNCTIONS = {
    "HDB_GetVersion",
    "HDB_Open",
    "HDB_Close",
    "HDB_Execute",
    "HDB_Query",
}

local SCHEMA_SQL = [[
BEGIN;
CREATE TABLE IF NOT EXISTS mobs (
    mob_id INTEGER PRIMARY KEY,
    last_name TEXT
);
CREATE TABLE IF NOT EXISTS facts (
    mob_id INTEGER NOT NULL,
    dimension TEXT NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN ('immune', 'vulnerable')),
    dynamic_suspected INTEGER NOT NULL DEFAULT 0 CHECK (dynamic_suspected IN (0, 1)),
    proof_source TEXT,
    proof_spell_id INTEGER,
    proof_event TEXT,
    PRIMARY KEY (mob_id, dimension),
    FOREIGN KEY (mob_id) REFERENCES mobs(mob_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS hypotheses (
    hypothesis_id INTEGER PRIMARY KEY AUTOINCREMENT,
    mob_id INTEGER NOT NULL,
    proof_source TEXT,
    proof_spell_id INTEGER,
    proof_event TEXT,
    FOREIGN KEY (mob_id) REFERENCES mobs(mob_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS hypothesis_candidates (
    hypothesis_id INTEGER NOT NULL,
    dimension TEXT NOT NULL,
    PRIMARY KEY (hypothesis_id, dimension),
    FOREIGN KEY (hypothesis_id) REFERENCES hypotheses(hypothesis_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_hypotheses_mob_id ON hypotheses(mob_id);
PRAGMA user_version = 1;
COMMIT;
]]

local RESET_SCHEMA_SQL = [[
BEGIN;
DROP TABLE IF EXISTS hypothesis_candidates;
DROP TABLE IF EXISTS hypotheses;
DROP TABLE IF EXISTS facts;
DROP TABLE IF EXISTS mobs;
CREATE TABLE mobs (
    mob_id INTEGER PRIMARY KEY,
    last_name TEXT
);
CREATE TABLE facts (
    mob_id INTEGER NOT NULL,
    dimension TEXT NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN ('immune', 'vulnerable')),
    dynamic_suspected INTEGER NOT NULL DEFAULT 0 CHECK (dynamic_suspected IN (0, 1)),
    proof_source TEXT,
    proof_spell_id INTEGER,
    proof_event TEXT,
    PRIMARY KEY (mob_id, dimension),
    FOREIGN KEY (mob_id) REFERENCES mobs(mob_id) ON DELETE CASCADE
);
CREATE TABLE hypotheses (
    hypothesis_id INTEGER PRIMARY KEY AUTOINCREMENT,
    mob_id INTEGER NOT NULL,
    proof_source TEXT,
    proof_spell_id INTEGER,
    proof_event TEXT,
    FOREIGN KEY (mob_id) REFERENCES mobs(mob_id) ON DELETE CASCADE
);
CREATE TABLE hypothesis_candidates (
    hypothesis_id INTEGER NOT NULL,
    dimension TEXT NOT NULL,
    PRIMARY KEY (hypothesis_id, dimension),
    FOREIGN KEY (hypothesis_id) REFERENCES hypotheses(hypothesis_id) ON DELETE CASCADE
);
CREATE INDEX idx_hypotheses_mob_id ON hypotheses(mob_id);
PRAGMA user_version = 1;
COMMIT;
]]

local SCHEMA_PROBES = {
    "SELECT mob_id, last_name FROM mobs LIMIT 0",
    "SELECT mob_id, dimension, verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event FROM facts LIMIT 0",
    "SELECT hypothesis_id, mob_id, proof_source, proof_spell_id, proof_event FROM hypotheses LIMIT 0",
    "SELECT hypothesis_id, dimension FROM hypothesis_candidates LIMIT 0",
}

local function setError(code, message)
    Storage.ready = false
    Storage.lastErrorCode = code
    Storage.lastError = tostring(message or "unknown error")
    return false, Storage.lastError
end

local function clearError()
    Storage.lastErrorCode = nil
    Storage.lastError = nil
end

local function executeInternal(sql)
    if not Storage.handle then
        return false, "database is not open"
    end
    if type(sql) ~= "string" or sql == "" then
        return false, "SQL must be a non-empty string"
    end

    local ok, result = pcall(_G.HDB_Execute, Storage.handle, sql)
    if not ok then
        return false, tostring(result)
    end
    return true, result
end

local function queryInternal(sql)
    if not Storage.handle then
        return false, "database is not open"
    end
    if type(sql) ~= "string" or sql == "" then
        return false, "SQL must be a non-empty string"
    end

    local ok, rows = pcall(_G.HDB_Query, Storage.handle, sql)
    if not ok then
        return false, tostring(rows)
    end
    if type(rows) ~= "table" then
        return false, "HDB_Query returned a non-table result"
    end
    return true, rows
end

local function rollbackQuietly()
    if Storage.handle and type(_G.HDB_Execute) == "function" then
        pcall(_G.HDB_Execute, Storage.handle, "ROLLBACK;")
    end
end

local function createSchema()
    local ok, err = executeInternal(SCHEMA_SQL)
    if not ok then
        rollbackQuietly()
        return false, err
    end
    Storage.schemaVersion = Storage.SCHEMA_VERSION
    return true
end

local function readSchemaVersion()
    local ok, rows = queryInternal("PRAGMA user_version")
    if not ok then return false, rows end
    if table.getn(rows) < 1 or type(rows[1]) ~= "table" then
        return false, "PRAGMA user_version returned no row"
    end

    local version = tonumber(rows[1].user_version)
    if not version or version < 0 or version ~= math.floor(version) then
        return false, "PRAGMA user_version returned an invalid value"
    end
    return true, version
end

local function validateSchema()
    local i
    for i = 1, table.getn(SCHEMA_PROBES) do
        local ok, err = queryInternal(SCHEMA_PROBES[i])
        if not ok then
            return false, err
        end
    end
    return true
end

function Storage.IsHearthDBAvailable()
    local i
    for i = 1, table.getn(REQUIRED_FUNCTIONS) do
        local name = REQUIRED_FUNCTIONS[i]
        if type(_G[name]) ~= "function" then
            return false, name
        end
    end
    return true
end

function Storage.GetHearthDBVersion()
    if type(_G.HDB_GetVersion) ~= "function" then
        return nil, nil, nil
    end

    local ok, major, minor, patch = pcall(_G.HDB_GetVersion)
    if not ok then
        return nil, nil, nil
    end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function Storage.SQLText(value, allowNil)
    if value == nil and allowNil then return "NULL" end
    if type(value) ~= "string" then
        return nil, "expected string SQL value"
    end
    return "'" .. string.gsub(value, "'", "''") .. "'"
end

function Storage.SQLInteger(value, minValue, allowNil)
    if value == nil and allowNil then return "NULL" end
    local number = tonumber(value)
    if not number or number ~= math.floor(number) then
        return nil, "expected integer SQL value"
    end
    if minValue ~= nil and number < minValue then
        return nil, "integer SQL value is below minimum"
    end
    return string.format("%.0f", number)
end

function Storage.SQLBoolean(value, allowNil)
    if value == nil and allowNil then return "NULL" end
    if value == true or value == 1 then return "1" end
    if value == false or value == 0 then return "0" end
    return nil, "expected boolean SQL value"
end

function Storage.SQLEnum(value, allowed, allowNil)
    if value == nil and allowNil then return "NULL" end
    if type(value) ~= "string" or type(allowed) ~= "table" or not allowed[value] then
        return nil, "invalid enumerated SQL value"
    end
    return Storage.SQLText(value)
end

function Storage.Execute(sql)
    if not Storage.ready then
        return false, Storage.lastError or "immunity database is not ready"
    end
    return executeInternal(sql)
end

function Storage.Query(sql)
    if not Storage.ready then
        return false, Storage.lastError or "immunity database is not ready"
    end
    return queryInternal(sql)
end

function Storage.IsReady()
    return Storage.ready and true or false
end

function Storage.GetDiagnostics()
    return {
        ready = Storage.ready and true or false,
        database = Storage.DB_FILENAME,
        schemaVersion = Storage.schemaVersion,
        expectedSchemaVersion = Storage.SCHEMA_VERSION,
        hearthDBVersion = Storage.hearthDBVersion,
        lastErrorCode = Storage.lastErrorCode,
        lastError = Storage.lastError,
        lastResetReason = Storage.lastResetReason,
    }
end

function Storage.Close()
    local handle = Storage.handle
    Storage.handle = nil
    Storage.ready = false
    Storage.schemaVersion = nil

    if handle and type(_G.HDB_Close) == "function" then
        local ok, err = pcall(_G.HDB_Close, handle)
        if not ok then
            Storage.lastErrorCode = "close"
            Storage.lastError = tostring(err)
            return false, Storage.lastError
        end
    end
    return true
end

function Storage.ResetSchema(reason)
    if not Storage.handle then
        return setError("schema", "cannot reset schema before the database is open")
    end

    local ok, err = executeInternal(RESET_SCHEMA_SQL)
    if not ok then
        rollbackQuietly()
        return setError("schema", "schema reset failed: " .. tostring(err))
    end

    Storage.schemaVersion = Storage.SCHEMA_VERSION
    Storage.lastResetReason = reason or "manual reset"

    local valid, validationError = validateSchema()
    if not valid then
        return setError("schema", "schema validation failed after reset: " .. tostring(validationError))
    end

    clearError()
    Storage.ready = true
    return true
end

function Storage.Initialize()
    if Storage.handle then
        local closed, closeError = Storage.Close()
        if not closed then
            return setError("close", "could not close the previous HearthDB handle: " .. tostring(closeError))
        end
    end

    Storage.ready = false
    Storage.schemaVersion = nil
    Storage.hearthDBVersion = nil
    Storage.lastResetReason = nil
    clearError()

    local available, missing = Storage.IsHearthDBAvailable()
    if not available then
        return setError("missing", "HearthDB function is unavailable: " .. tostring(missing))
    end

    local major, minor, patch = Storage.GetHearthDBVersion()
    if major == nil or minor == nil or patch == nil then
        return setError("missing", "HDB_GetVersion failed")
    end
    Storage.hearthDBVersion = string.format("%d.%d.%d", major, minor, patch)

    local ok, handle = pcall(_G.HDB_Open, Storage.DB_FILENAME)
    if not ok then
        return setError("open", handle)
    end
    if type(handle) ~= "number" then
        return setError("open", "HDB_Open returned an invalid handle")
    end
    Storage.handle = handle

    local versionOK, version = readSchemaVersion()
    if not versionOK then
        local err = version
        Storage.Close()
        return setError("schema", "could not read schema version: " .. tostring(err))
    end
    Storage.schemaVersion = version

    if version == 0 then
        local created, createError = createSchema()
        if not created then
            Storage.Close()
            return setError("schema", "schema creation failed: " .. tostring(createError))
        end
    elseif version ~= Storage.SCHEMA_VERSION then
        local reset, resetError = Storage.ResetSchema(
            "schema version " .. tostring(version) .. " replaced by v" .. tostring(Storage.SCHEMA_VERSION)
        )
        if not reset then
            Storage.Close()
            return false, resetError
        end
        return true
    end

    local valid, validationError = validateSchema()
    if not valid then
        local reset, resetError = Storage.ResetSchema(
            "schema validation failed: " .. tostring(validationError)
        )
        if not reset then
            Storage.Close()
            return false, resetError
        end
        return true
    end

    clearError()
    Storage.ready = true
    Storage.schemaVersion = Storage.SCHEMA_VERSION
    return true
end
