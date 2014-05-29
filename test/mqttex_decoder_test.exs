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

	test "parse a fixed header" do
		header = <<0x32, 0>>
		h = Mqttex.Decoder.decode_fixheader(header, fn() -> next_byte([]) end)
		assert %Mqttex.Msg.FixedHeader{} = h
		assert h.message_type == :publish
		assert h.qos == :at_least_once
		assert h.retain == false
		assert h.duplicate == false
	end

	test "publish a message" do
		# anything after the initial 16 bits of the MQTT message, i.e. the optional
		# length encodings, the variable header and the 
		bytes = [0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0x0a, "h", "a", "l", "l", "o"]
		# header contains the fixed header byte and the initial length byte
		# the call of length(bytes) works only if bytes is shorter then 128 bytes long
		header = <<0x32, length(bytes)>> 
		buf_pid = spawn(fn() -> buffer(bytes) end)
		m = Mqttex.Decoder.decode(header, 
			fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
		assert %Mqttex.Msg.Publish{} = m
		assert m.topic == "a/b"
		assert m.msg_id == 10
		assert m.message == "hallo"
		Process.exit(buf_pid, :kill)
	end

	#############################
	#### Add Logging, system hangs
	####    Perhaps tracing is better to see the messages flowing around
	####
	#############################


	@doc "Simulates the TCP get functions to read the next byte from a list of bytes."
	def next_byte([]), do: {nil, nil} 
	def next_byte([h | t]) do
		{<<h>>, fn() -> (next_byte(t)) end}
	end
	# this instance runs with the buffer loop.
	def next_byte(pid) when is_pid(pid) do
		send(pid, {:byte, self})
		receive do
			byte -> {byte, fn() -> next_byte(pid) end}
		end
	end

	@doc "Simulates the TCP get functions to read `n` bytes from a list of bytes."
	def read_bytes(pid, n) when is_pid(pid) do
		send(pid, {:msg, n, self})
		receive do
			bytes -> bytes
		end
	end
	def read_bytes([], n), do: <<>>
	def read_bytes(bs, n), do: IO.iodata_to_binary(Enum.take(bs, n))
	
	@doc "A process that holds a buffer full of bytes and iterates over them."
	def buffer([]), do: :ok
	def buffer(bytes) do
		receive do
			{:byte, pid} -> 
				send(pid, <<hd bytes>>) 
				buffer(tl bytes)
			{:msg, n, pid} ->
				send(pid, IO.iodata_to_binary(Enum.take(bytes, n)))
				buffer(Enum.drop(bytes, n))
		end
	end
	
	test "Read UTF8" do
		string = <<0x0, 0x4, 0x4f, 0x54, 0x57, 0x50>>
		{u, r} = Mqttex.Decoder.utf8(string)
		assert u == "OTWP"
		assert r == <<>>
	end


end