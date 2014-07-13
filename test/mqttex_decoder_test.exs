defmodule MqttexDecoderTest do
	@moduledoc """
	This test checks the decoding of binary messages to regular Elixir structs.
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

	test "parse a fixed header with a duplicate" do
		header = <<0x3a, 0>>
		h = Mqttex.Decoder.decode_fixheader(header, fn() -> next_byte([]) end)
		assert %Mqttex.Msg.FixedHeader{} = h
		assert h.message_type == :publish
		assert h.qos == :at_least_once
		assert h.retain == false
		assert h.duplicate == true
	end

	test "publish a message" do
		m = message(<<0x32>>, [0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0x0a, "h", "e", "l", "l", "o"])
		assert %Mqttex.Msg.Publish{} = m
		assert m.topic == "a/b"
		assert m.msg_id == 10
		assert m.message == "hello"
	end
 
	test "simple messages with message id" do
		garbage = [0x54, 0x43, 0xaf]

		message_types = %{ pub_ack: 4, pub_rec: 5, pub_comp: 7, unsub_ack: 11}
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
			header = <<(id <<< 4) + qos>>
			m = message(header, [], garbage)
			assert %Mqttex.Msg.Simple{} = m  
			assert m.msg_type == type
		end
	end

	test "decode PubRel messages" do
		m = message(<<0x6a>>, [0x00, 0x0a])
		assert %Mqttex.Msg.PubRel{} = m
		assert m.msg_id == 10
		assert m.duplicate == true
	end

	test "unsubscribe message" do
		m = message(<<0xa2>>, [0x00, 0x0b, 0x00, 0x03, 0x61, 0x2f, 0x62, 0x00, 0x03, 0x63, 0x2f, 0x64])
		assert %Mqttex.Msg.Unsubscribe{} = m
		assert m.msg_id == 11
		assert m.header.qos == :at_least_once
		assert m.topics == ["a/b", "c/d"]
	end

	test "sub_ack message" do
		m = message(<<0x90>>, [0x00, 0x0c, 0x00, 0x02])
		assert %Mqttex.Msg.SubAck{} = m
		assert m.msg_id == 12
		assert m.granted_qos == [:fire_and_forget, :exactly_once]
	end

	test "subscribe message" do 
		m = message(<<0x8a>>, [0x00, 0xff, 
			0x00, 0x03, 0x61, 0x2f, 0x62, 0x01,
			0x00, 0x03, 0x63, 0x2f, 0x64, 0x02])
		assert %Mqttex.Msg.Subscribe{} = m
		assert m.topics == [{"a/b", :at_least_once}, {"c/d", :exactly_once}]
		assert m.msg_id == 255
		assert m.header.duplicate == true
	end

	test "connect message" do
		header = <<0x10>>
		var_header = [0x00, 0x06, "M", "Q", "I", "s", "d", "p", 0x03, 0xce, 0x00, 0x10]
		payload = [ 0x00, 0x07, "c", "l", "i", "e", "n", "t", "A",
		       		0x00, 0x06, "t", "o", "p", "i", "c", "A",
		       		0x00, 0x04, "d", "i", "e", "d",
		            0x00, 0x03, "j", "o", "e", 
		            0x00, 0x02, "n", "o"
		       	]
		m = message(header, var_header ++ payload)
		assert %Mqttex.Msg.Connection{} = m
		assert m.user_name == "joe"
		assert m.client_id == "clientA"
		assert m.password == "no"
		assert m.will_topic == "topicA"
		assert m.will_retain == false
		assert m.will_message == "died"
		assert m.will_qos == :at_least_once
		assert m.clean_session == true
	end

	test "mosquitto connect" do
		# This is the connect string from mosquitto_sub -p 1178 -t "#"
		# header = <<16, 36>>
		header = <<16>> # the length 36 is added by calling `message`
		payload = [0, 6, 77, 81, 73, 115, 100, 112, 0x03, 0x02, 0x00, 60,] ++
			[0, 22, 109, 111, 115, 113, 95, 115, 117, 98, 95, 51, 53, 52, 
				56, 95, 102, 114, 97, 110, 48, 52, 53, 51]
		m = message(header, payload)
		assert %Mqttex.Msg.Connection{} = m
		IO.inspect m
	end

	test "Encode/Decode connect message" do
		connect = Mqttex.Msg.connection("client Nr. 1", "", "", true)
		IO.puts "connect = #{inspect connect}"
		m = Mqttex.Encoder.encode(connect)
		assert is_binary(m)
		
		IO.puts "encoded connect = #{inspect m}"

		<<header :: binary-size(1), l :: integer-size(8), msg :: binary>> = m
		assert connect.header.length == byte_size(msg)
		enc_msg = message(header, :binary.bin_to_list(msg))

		assert  connect == enc_msg
	end


	test "extract work with bits instead of booleans" do
		<<flag :: size(1), _ :: size(7)>> = <<0xff>>
		assert {"hallo", _} = Mqttex.Decoder.extract(flag, ["hallo"])

		<<flag :: size(1), _ :: size(7)>> = <<0x00>>
		assert {"", _} = Mqttex.Decoder.extract(flag, ["hallo"])
	end

	@doc """
	Creates a binary message and decodes it. 

	* `header`: contains the fixed header byte. The length is constructed from the length of `bytes`.
	* `bytes`: anything after the initial 16 bits of the MQTT message, i.e. the optional
		length encodings, the variable header and the payload
	"""
	def message(header, bytes, garbage \\ []) do
		h = header <> <<length(bytes)>> 
		buf_pid = spawn(fn() -> buffer(bytes ++ garbage) end)
		m = Mqttex.Decoder.decode(h, 
			fn() -> next_byte(buf_pid) end, fn(n) -> read_bytes(buf_pid, n) end)
		Process.exit(buf_pid, :kill)
		m
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