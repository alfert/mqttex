defmodule Mqttex.Decoder do
	@moduledoc """
	Decoding and encoding of MQTT messages.
	"""

	use Bitwise

	@type next_byte_fun :: (() -> {binary, next_byte_fun})
	@type read_message_fun :: ((pos_integer) -> binary)

	@type all_message_types :: Mqttex.Msg.Simple.t | Mqttex.Msg.Publish.t 

	# @type decode(binary, next_byte_fun, read_message_fun) :: all_message_types
	def decode(msg = <<_m :: size(16)>>, readByte, readMsg) do
		header = decode_fixheader(msg, readByte)
		var_m = readMsg.(header.length)
		decode_message(var_m, header)
	end

	@spec decode_fixheader(binary, next_byte_fun ) :: Mqttex.Msg.FixedHeader.t
	def decode_fixheader(<<type :: size(4), dup :: size(1), qos :: size(2), 
						   retain :: size(1), len :: size(8)>>, readByte) do
		Mqttex.Msg.fixed_header(binary_to_msg_type(type), 
			(dup == 1), binary_to_qos(qos),(retain == 1),
			binary_to_length(<<len>>, readByte))
	end

	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :publish}), do: decode_publish(msg, h)
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :ping_req, length: 0}), 
		do: Mqttex.Msg.ping_req()
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :ping_resp, length: 0}), 
		do: Mqttex.Msg.ping_resp()
	def decode_message(<<>>, %Mqttex.Msg.FixedHeader{message_type: :disconnect, length: 0}), 
		do: Mqttex.Msg.disconnect()
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_ack}), 
		do: Mqttex.Msg.pub_ack(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_rec}), 
		do: Mqttex.Msg.pub_rec(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_rel, qos: :at_least_once}), 
		do: Mqttex.Msg.pub_rel(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :pub_comp}), 
		do: Mqttex.Msg.pub_comp(get_msgid(msg))
	def decode_message(msg, h = %Mqttex.Msg.FixedHeader{message_type: :unsub_ack}), 
		do: Mqttex.Msg.unsub_ack(get_msgid(msg))


	@spec decode_publish(binary, Mqttex.Msg.FixedHeader.t) :: Mqttex.Msg.Publish.t
	def decode_publish(msg, h) do
		{topic, m1} = utf8(msg)
		# in m1 is the message id if qos = 1 or 2
		{msg_id, payload} = case h.qos do
			:fire_and_forget -> {0, m1}
			_   -> 
				<<id :: [integer, unsigned, size(16)], content :: binary>> = m1
				{id, content}
		end
		## create a publish message 
		p = Mqttex.Msg.publish(topic, payload, h.qos)
		%Mqttex.Msg.Publish{ p | header: h, msg_id: msg_id}
	end


	@doc "Expects a 16 bit binary and returns its value as integer"
	@spec get_msgid(binary) :: integer	
	def get_msgid(<<id :: [integer, unsigned, size(16)]>>), do: id	

	@doc """
	Decodes an utf8 string (in the header) of a MQTT message. Returns the string and the
	remaining input message.
	"""
	@spec utf8(binary) :: {binary, binary}
	def utf8(<<length :: [integer, unsigned, size(16)], content :: [bytes, size(length)], rest :: binary>>) do
		{content, rest}
	end
	


	@spec binary_to_length(binary, integer, next_byte_fun) :: integer
	def binary_to_length(<<overflow :: size(1), len :: size(7)>>, count = 0 \\ 4, readByte) do
		raise "Invalid length"
	end
	def binary_to_length(<<overflow :: size(1), len :: size(7)>>, count, readByte) do
		case overflow do
			1 ->
				{byte, nextByte} = readByte.() 
				len + (binary_to_length(byte, count - 1, nextByte) <<< 7)
			0 -> len
		end
	end


	@doc "convertes the binary qos to atoms"
	def binary_to_qos(0), do: :fire_and_forget
	def binary_to_qos(1), do: :at_least_once
	def binary_to_qos(2), do: :exactly_once
	def binary_to_qos(3), do: :reserved

	@doc "Converts the binary message type to atoms"
	def binary_to_msg_type(1), do: :connect
	def binary_to_msg_type(2), do: :conn_ack
	def binary_to_msg_type(3), do: :publish
	def binary_to_msg_type(4), do: :pub_ack
	def binary_to_msg_type(5), do: :pub_rec
	def binary_to_msg_type(6), do: :pub_rel
	def binary_to_msg_type(7), do: :pub_comp
	def binary_to_msg_type(8), do: :subscribe
	def binary_to_msg_type(9), do: :sub_ack
	def binary_to_msg_type(10), do: :unsubscribe
	def binary_to_msg_type(11), do: :unsub_ack
	def binary_to_msg_type(12), do: :ping_req
	def binary_to_msg_type(13), do: :ping_resp
	def binary_to_msg_type(14), do: :disconnect
	def binary_to_msg_type(0), do: :reserved
	def binary_to_msg_type(15), do: :reserved
	


end
