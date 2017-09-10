
local pipeline = require "pipeline"
local plugin = require "plugin"
local warning = require "warning"

local build = {}

function build:new( paths, environment, options )
	local b = setmetatable( {
		environment = environment,
		options = options,
		paths = paths,
		plugins = {},
	}, { __index = self } )

	return b
end

function build:plugin( plugin_name )
	for i = 1, #self.plugins do
		if self.plugins[i].name == plugin_name then
			return true
		end
	end

	local p = plugin.load( plugin_name, self.paths )

	if p then
		self.plugins[#self.plugins + 1] = p
		p:load( self )

		return true
	end

	return false
end

function build:get_URI_list( filename )
	local URIs
	local matches = {}
	local protocol = filename:match "^([%w_%-]+):" or "file"
	local protocol_matched = false

	for i = 1, #self.plugins do
		local result = self.plugins[i].file_lookup_callbacks[protocol] and self.plugins[i].file_lookup_callbacks[protocol]( filename, self )

		protocol_matched = protocol_matched or result and true or false

		if result and #result > 0 then
			URIs = result
			matches[#matches + 1] = self.plugins[i].name
		end
	end

	if #matches > 1 then
		warning.warn( warning.CONFLICTING_LOOKUP, "Conflicting file lookup results from plugins (" .. table.concat( matches, ", " ) .. ")" )
		return {}
	elseif not protocol_matched then
		warning.warn( warning.PROTOCOL_UNMATCHED, "The protocol '" .. protocol .. "' was not handled by any plugin" )
		return {}
	end

	return URIs
end

function build:add_pipeline( uri, mode, host )
	if not self.pipelines[uri] then
		local p = pipeline:new( uri, mode, self, host )
		self.pipelines[uri] = p

		-- do stuff with p
	end
end

function build:include( file, host )
	local URIs = self:get_URI_list( file )

	if URIs then
		for i = 1, #URIs do
			self:add_pipeline( URIs[i].uri, URIs[i].mode, host )
		end

		return true
	end

	return false
end

return build
