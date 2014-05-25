defmodule MqttexDecoderTest do
	@moduledoc """
	This test requires the Lossy Channel for checking that the protocols work for many 
	messages to send.
	"""
	require Lager
	use ExUnit.Case


	test "length one byte values" do
		numbers = [0, 100, 127]
		numbers |> Enum.each fn(n) -> 
			assert n == Mqttex.Decoder.binary_to_length(<<n>>, fn() -> nil end)
		end
	end

	test "length 128 in one byte fails" do
		catch_error Mqttex.Decoder.binary_to_length(<<128>>, fn() -> nil end)
	end

	test "length with two bytes" do
		bytes = %{ 0 => [0], 128 => [0x80, 0x01], 16_383 => [0xFF, 0x7F]}
		bytes |> Enum.each fn({n, bs}) ->
			assert n == Mqttex.Decoder.binary_to_length(<<hd bs>>, fn () -> next_byte(tl bs) end)
		end 
	end

	test "length with three bytes" do
		bytes = %{ 0 => [0], 16_384 => [0x80, 0x80, 0x01], 2_097_151 => [0xFF, 0xFF, 0x7F]}
		bytes |> Enum.each fn({n, bs}) ->
			assert n == Mqttex.Decoder.binary_to_length(<<hd bs>>, fn () -> next_byte(tl bs) end)
		end 
	end

	test "length with four bytes" do
		bytes = %{ 0 => [0], 2_097_152 => [0x80, 0x80, 0x80, 0x01], 268_435_455 => [0xFF, 0xFF, 0xFF, 0x7F]}
		bytes |> Enum.each fn({n, bs}) ->
			assert n == Mqttex.Decoder.binary_to_length(<<hd bs>>, fn () -> next_byte(tl bs) end)
		end 
	end

	@doc "Simulates the TCP get functions to read the next byte from a list of bytes."
	def next_byte([]), do: {nil, nil} 
	def next_byte([h | t]) do
		{<<h>>, fn() -> (next_byte(t)) end}
	end
	
	test "Read UTF8" do
		string = <<0x0, 0x4, 0x4f, 0x54, 0x57, 0x50>>
		{u, r} = Mqttex.Decoder.utf8(string)
		assert u == "OTWP"
		assert r == <<>>
	end


end