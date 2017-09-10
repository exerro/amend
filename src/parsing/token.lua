
local position = { mt = {} }
local token = { source = source, position = position, mt = {} }

token.EOF = "EOF"
token.BOF = "BOF"
token.UNDEFINED = "UNDEFINED"

function position:new( uri, line1, char1, line2, char2, indentation )
	return setmetatable( { uri = uri, line1 = line1, char1 = char1, line2 = line2, char2 = char2, indentation = indentation }, self.mt )
end

function position:tostring()
	return self.uri
	.. "["
		.. self.line1 .. "," .. self.char1 .. " .. "
		.. self.line2 .. "," .. self.char2 .. " >> "
		.. self.indentation
	.. "]"
end

function position:after( s, n )
	if type( s ) == "number" then
		return position.at( self.uri, self.line2, self.char2 + s, indentation )
	end

	local l = self.line2
	local c = self.char2
	local i = self.indentation
	local newline = s:find "\n" or self.line2 == 1 and self.char2 == 1

	if n then
		s = s:sub( 1, #s - n )
	end

	for a in s:gmatch "\n" do
		l = l + 1
		c = 1
	end

	c = c + #s:gsub( ".*\n", "" )

	if newline then
		i = #s:gsub( ".+\n", "" ):match( "^\10?(%s*)" )
	end

	return position.at( self.uri, l, c, i )
end

function position:extend( n )
	return position:new( self.uri, self.line1, self.char1, self.line2, math.max( self.char2 + n, 1 ), self.indentation )
end

function position:to( p )
	if not p then
		return error( "hi")
	end
	return position:new( self.uri, self.line1, self.char1, p.line2, p.char2, self.indentation )
end

function position:follows( p )
	return p.line2 == self.line1 and p.char2 == self.char1 - 1
end

function position.at( uri, line, char, indentation )
	return position:new( uri, line, char, line, char, indentation or 0 )
end

function position.atl( uri, line, char, l, indentiation )
	return position:new( uri, line, char, line, char + l - 1, indentiation or 0 )
end

function token:new( type, value, position )
	return setmetatable( { type = type, value = value, position = position, meta = {} }, self.mt )
end

function token:tostring()
	return self.type .. " (" .. self.value .. ") @ " .. self.position:tostring()
end

function position.mt:__sub( n )
	return self:extend( -n )
end

position.mt.__tostring = position.tostring
position.mt.__index = position
position.mt.__add = position.extend
token.mt.__tostring = token.tostring
token.mt.__index = token

setmetatable( position, { __call = position.new } )
setmetatable( token, { __call = token.new } )

return token
