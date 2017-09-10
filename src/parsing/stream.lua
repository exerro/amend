
local util = require "util"

local stream = {}
local stringstream, filestream

function stream:new()
	local s = {}
	for k, v in pairs( self ) do
		s[k] = v
	end
	return s
end

function stream:getch( n )
	return ""
end

function stream:next( n )
	return ""
end

function stream:eof()
	return self:getch() == ""
end

function stream:test_string()
	return self:getch():find "[\"']"
end

function stream:consume_string()
	local open = self:getch():match "[\"']"
	local s = { open }
	local escaped = false
	local i = 2

	if open then
		self:next()

		while (escaped or self:getch() ~= open) and not self:eof() do
			local ch = self:next()
			s[i] = ch
			escaped = not escaped and ch == "\\"
			i = i + 1

			-- break on newline?
		end

		s[i] = self:next()
	end

	return table.concat( s )
end

function stream:test_word()
	return self:getch():find "[%w_]"
end

function stream:consume_word()
	local t, i = {}, 1
	while self:getch():find "[%w_]" do
		t[i] = self:next()
		i = i + 1
	end
	return table.concat( t )
end

function stream:test_number()
	return self:getch():find "%d" or self:getch():find "%." and self:getch( 1 ):find "%d"
end

function stream:consume_number() -- TODO: revise this
	local t, i = {}, 1
	local s = -1

	while true do
		local ch = self:getch()
		if (s == 0 or s == -1) and ch == "." then
			if self:getch( 1 ):find "%d" then
				s = 1
			else
				break
			end
		elseif (s == 0 or s == 1) and ch == "e" then
			s = 2
		elseif (ch == "-" or ch == "+") and s == 2 then
			s = 3
		elseif not ch:find "%d" then
			break
		elseif s == -1 then
			s = 0
		end

		t[i] = self:next()
		i = i + 1
	end

	return table.concat( t )
end

function stream:test_symbol()
	return self:getch():find "[^%w%s_%d]"
end

function stream:consume_symbol()
	if self:getch():find "[^%w%s_%d]" then
		return self:next()
	end
	return ""
end

function stream:test_whitespace()
	return self:getch():find "%s"
end

function stream:consume_whitespace()
	local t, i = {}, 1
	while self:getch():find "%s" do
		t[i] = self:next()
		i = i + 1
	end
	return table.concat( t )
end

function stream:test_comment()
	return self:getch() == "-" and self:getch( 1 ) == "-"
end

function stream:consume_comment()
	if self:getch() == "-" and self:getch( 1 ) == "-" then
		local t, i = {}, 2
		if self:getch( 2 ) == "[" then
			local n = 0
			while self:getch( 3 + n ) == "=" do
				n = n + 1
			end
			if self:getch( 3 + n ) == "[" then
				t[1] = self:next( 4 + n )
				local counter = 0
				local consuming = false

				while not self:eof() do
					if self:getch() == "]" then
						t[i] = self:next()
						i = i + 1
						if consuming and counter == n then
							break
						else
							consuming = true
							counter = 0
						end
					elseif self:getch() == "=" and consuming then
						counter = counter + 1
						t[i] = self:next()
						i = i + 1
					else
						consuming = false
						t[i] = self:next()
						i = i + 1
					end
				end

				return table.concat( t )
			end
		end
		t[1] = self:next( 2 )
		while self:getch() ~= "\n" and not self:eof() do
			t[i] = self:next()
			i = i + 1
		end
		t[i] = self:next()
		return table.concat( t )
	end
	return ""
end

stringstream = stream:new()

function stringstream:new( text, position )
	local s = setmetatable( {}, { __index = self } )
	s.text = text
	s.position = position or 1
	return s
end

function stringstream:getch( n )
	local p = self.position + (n or 0)
	return self.text:sub( p, p )
end

function stringstream:next( n )
	local p = self.position + (n or 1) - 1
	local c = self.text:sub( self.position, p )
	self.position = self.position + (n or 1)
	return c
end

function stringstream:eof()
	return self.position > #self.text
end

filestream = stream:new()

function filestream:new( uri )
	local s = setmetatable( {}, { __index = self } )
	s.handle = util.open_uri_handle( uri )
	s.buffer = ""
end

function filestream:getch( n )
	while #self.buffer < n + 1 do
		local line = self.handle:read "*l"
		if line then
			self.buffer = self.buffer .. line
		else
			return ""
		end
	end
	return self.buffer:sub( n + 1, n + 1 )
end

function filestream:next( n )
	local s
	self:getch( n - 1 )
	s = self.buffer:sub( 1, n )
	self.buffer = self.buffer:sub( n + 1 )
	return s
end

stream.stringstream = stringstream
stream.filestream = filestream

return stream
