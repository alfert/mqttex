defmodule Mqttex.Decoder do
	@moduledoc """
	Decoding and encoding of MQTT messages.
	"""

	use Bitwise

	@type next_byte_fun :: (() -> {binary, next_byte_fun})
	@type read_message_fun :: ((pos_integer) -> binary)

	# @type decode(binary, next_byte_fun) :: Mqttex.Msg.Simple.t 
	def decode(msg = <<_m :: size(16)>>, readByte, readMsg) do
		header = decode_fixheader(msg, readByte)
		var_m = readMsg.(header.length)
		# decode_message(var_m, header)
	end
	
	#####################################################
	## TODO:
	##
	## Replace the FixedHeader as a struct. 
	##
	#####################################################


	@spec decode_fixheader(binary, next_byte_fun ) :: Mqttex.Msg.FixedHeader.t
	def decode_fixheader(<<type :: size(4), dup :: size(1), qos :: size(2), 
						   retain :: size(1), len :: size(8)>>, readByte) do
		Mqttex.Msg.fixed_header(binary_to_msg_type(type), 
			(dup == 1), binary_to_qos(qos),(retain == 1),
			binary_to_length(len, readByte))
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
