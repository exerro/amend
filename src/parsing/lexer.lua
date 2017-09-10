
local lexer = {}
local token = dofile "/amend/src/parsing/token.lua" or require "parsing.token"

local function clear_buffer( buffer, position, mark )
	for i = 1, math.min( position, mark or position ) - 2 do
		table.remove( buffer, 1 )
		position = position - 1
	end
	return position
end

function lexer:new( stream, uri )
	local s = setmetatable( {}, { __index = self } )

	s.buffer = {}
	s.position = 1
	s.stream = stream
	s.uri = uri
	s.sposition = token.position.at( uri, 1, 1, 0 )
	s.marks = {}

	return s
end

function lexer:on_directive( name )
	print( "directive " .. name .. "!" )
end

function lexer:can_push()
	return true
end

function lexer:peek( n )
	n = self.position + (n or 0)

	if n < 1 then
		return token:new( token.BOF, "", token.position.at( self.source, 1, 1 ) )
	end

	while not self.buffer[n] do
		self:consume()
	end

	return self.buffer[n]
end

function lexer:next()
	local t = self:peek()
	self.position = clear_buffer( self.buffer, self.position + 1, self.marks[1] )
	return t
end

function lexer:mark()
	self.marks[#self.marks + 1] = self.position
	return self
end

function lexer:back()
	self.position = self.marks[#self.marks] or self.position
	return self
end

function lexer:unmark()
	local n = #self.marks
	if n == 1 then
		self.marks[1] = nil
		self.position = clear_buffer( self.buffer, self.position, nil )
	else
		self.marks[n] = nil
	end
	return self
end

function lexer:test( type, value, n )
	local t = self:peek( n )
	return t.type == type and (t.value == value or not value) and t or nil
end

function lexer:skip( type, value )
	local t = self:peek()
	if t.type == type and (t.value == value or not value) then
		self:next()
		return t
	end
	return nil
end

function lexer:eof()
	return self:test( token.EOF )
end

function lexer:pusht( t, force )
	if force or self:can_push() then
		self.buffer[#self.buffer + 1] = t
	end
	return self
end

function lexer:consume()
	if self.stream:test_comment() then
		local n = 0
		while self.stream:getch( 2 + n ):find "[^%S\n]" do
			n = n + 1
		end
		if self.stream:getch( 2 + n ) == "@" then
			if self.stream:test_word() then
				local name = self.stream:consume_word()
				self.sposition = self.sposition:after( self.stream:next( 2 + n ) )

				self:on_directive( name )
			else
				return error( "expected directive after '@'", 0 )
			end
		else
			self.sposition = self.sposition:after( self.stream:consume_comment() )
			return self:consume()
		end
	elseif self.stream:test_whitespace() then
		self.sposition = self.sposition:after( self.stream:consume_whitespace() )
		return self:consume()
	end

	if self.stream:test_string() then
		local s = self.stream:consume_string()

		self:pusht( token:new( "String", s, self.sposition:to( self.sposition:after( s ) - 1 ) ) )
		self.sposition = self.sposition:after( s )
	elseif self.stream:test_number() then
		local n = self.stream:consume_number()

		self:pusht( token:new( "Number", n, self.sposition:to( self.sposition:after( n ) - 1 ) ) )
		self.sposition = self.sposition:after( n )
	elseif self.stream:test_word() then
		local w = self.stream:consume_word()
		local t = keywords[w] and "Keyword" or "Identifier"

		self:pusht( token:new( t, w, self.sposition:to( self.sposition:after( w ) - 1 ) ) )
		self.sposition = self.sposition:after( w )
	elseif self.stream:test_symbol() then -- TODO: add multi-character symbols
		local s = self.stream:consume_symbol()

		self:pusht( token:new( "Symbol", s, self.sposition:to( self.sposition:after( s ) - 1 ) ) )
		self.sposition = self.sposition:after( s )
	end

	self:pusht( token:new( token.EOF, "", self.sposition ), true )
end

return lexer
