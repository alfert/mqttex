defmodule MqttexDecoderTest do
	@moduledoc """
	This test requires the Lossy Channel for checking that the protocols work for many 
	messages to send.
	"""
	require Lager
	import Bitwise
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
		# length encodings, the variable header and the payload
		bytes = [0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0x0a, "h", "e", "l", "l", "o"]
		# header contains the fixed header byte and the initial length byte
		# the call of length(bytes) works only if bytes is shorter then 128 bytes long
		header = <<0x32, length(bytes)>> 
		buf_pid = spawn(fn() -> buffer(bytes) end)
		m = Mqttex.Decoder.decode(header, 
			fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
		assert %Mqttex.Msg.Publish{} = m
		assert m.topic == "a/b"
		assert m.msg_id == 10
		assert m.message == "hello"
		Process.exit(buf_pid, :kill)
	end
 
	test "simple messages with message id" do
		garbage = [0x54, 0x43, 0xaf]

		message_types = %{ pub_ack: 4, pub_rec: 5, pub_rel: 6, pub_comp: 7, unsub_ack: 11}
		message_types |> Enum.each fn({type, id}) -> 
			msg_id = :random.uniform(1<<<16) - 1
			msb = msg_id >>> 8
			lsb = msg_id &&& 0xff
			bytes = [msb, lsb] ++ garbage

			# hmm, the header must be changed for some message types (qos)
			qos = 1 <<< 1 # qos = at least once, require for pub_rel
			header = <<(id <<< 4) + qos,0x02>>
			buf_pid = spawn(fn() -> buffer(bytes) end)
			m = Mqttex.Decoder.decode(header, 
				fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
			assert %Mqttex.Msg.Simple{} = m  
			assert m.msg_id == msg_id
			assert m.msg_type == type
			Process.exit(buf_pid, :kill)
		end
	end

	test "simple messages without message id" do
		garbage = [0x54, 0x43, 0xaf]

		message_types = %{ ping_req: 12, ping_resp: 13, disconnect: 14}
		message_types |> Enum.each fn({type, id}) -> 
			bytes = [] ++ garbage
			# hmm, the header must be changed for some message types (qos)
			qos = 1 <<< 1 # qos = at least once, require for pub_rel
			header = <<(id <<< 4) + qos,0x00>>
			buf_pid = spawn(fn() -> buffer(bytes) end)
			m = Mqttex.Decoder.decode(header, 
				fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
			assert %Mqttex.Msg.Simple{} = m  
			assert m.msg_type == type
			Process.exit(buf_pid, :kill)
		end
	end

	test "unsubscribe message" do
		# anything after the initial 16 bits of the MQTT message, i.e. the optional
		# length encodings, the variable header and the payload
		bytes = [0x00, 0x0b, 0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0x03, 0x63, 0x2f, 0x64]
		# header contains the fix6ed header byte and the initial length byte
		# the call of length(bytes) works only if bytes is shorter then 128 bytes long
		header = <<0xa2, length(bytes)>> 
		buf_pid = spawn(fn() -> buffer(bytes) end)
		m = Mqttex.Decoder.decode(header, 
			fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
		assert %Mqttex.Msg.Unsubscribe{} = m
		assert m.msg_id == 11
		assert m.header.qos == :at_least_once
		assert m.topics == ["a/b", "c/d"]
		Process.exit(buf_pid, :kill)
	end

	test "sub_ack message" do
		# anything after the initial 16 bits of the MQTT message, i.e. the optional
		# length encodings, the variable header and the payload
		bytes = [0x00, 0x0c, 0x00, 0x02]
		# header contains the fix6ed header byte and the initial length byte
		# the call of length(bytes) works only if bytes is shorter then 128 bytes long
		header = <<0x90, length(bytes)>> 
		buf_pid = spawn(fn() -> buffer(bytes) end)
		m = Mqttex.Decoder.decode(header, 
			fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
		assert %Mqttex.Msg.SubAck{} = m
		assert m.msg_id == 12
		assert m.granted_qos == [:fire_and_forget, :exactly_once]
		Process.exit(buf_pid, :kill)
	end

	test "subscribe message" do 
		flunk "not implemented yet"
	end

	test "connect message" do
		flunk "not implemented yet"
	end

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