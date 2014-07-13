defmodule Mqttex.Encoder do
	
	use Bitwise


	def encode(%Mqttex.Msg.Simple{msg_type: type}) when type in [:ping_req, :ping_resp, :disconnect],
		do: <<msg_type_to_binary(type) :: size(4), 0 :: size(4), 0x00>>
	def encode(%Mqttex.Msg.Simple{msg_type: type, msg_id: id}) 
		when type in [:pub_ack, :pub_rec, :pub_comp, :unsub_ack], 
		do: <<msg_type_to_binary(type) :: size(4), 0 :: size(4), 0x02, msg_id(id) :: binary>>
	def encode(%Mqttex.Msg.ConnAck{status: status}), 
		do: <<msg_type_to_binary(:conn_ack) :: size(4), 0 :: size(4), 0x02, 0x00, conn_ack_status(status)>>
	def encode(%Mqttex.Msg.PubRel{msg_id: id, duplicate: dup}), 
		do: <<encode_header(:pub_rel, dup), msg_id(id) :: binary>>
	def encode(%Mqttex.Msg.Publish{msg_id: id, header: header, topic: topic, message: message}), 
		do: <<encode_header(header), utf8(topic), msg_id(id) :: binary, utf8(message)>>
	def encode(%Mqttex.Msg.Subscribe{msg_id: id, header: header, topics: topics}),
		do: <<encode_header(header), msg_id(id), 
			topics |> Enum.map_join(fn({t, q}) -> utf8(t) <> qos_binary(q) end)>>
	def encode(%Mqttex.Msg.SubAck{msg_id: id, header: header, granted_qos: qos}), 
		do: <<encode_header(header), msg_id(id), qos |> Enum.join_map &qos_binary/1 >>
	def encode(%Mqttex.Msg.Unsubscribe{msg_id: id, header: header, topics: topics}),
		do: <<encode_header(header), msg_id(id), topics |> Enum.join_map &utf8/1 >>
	def encode(%Mqttex.Msg.Connection{header: header, client_id: client_id, user_name: user, password: passwd, 
			keep_alive: keep_alive, last_will: last_will} = con) do
		h = <<encode_header(header) :: binary, 0x00, 0x06, "MQIsdp", 0x03>>
		flags = << 
			boolean_to_binary(user != "") :: bits, 
			boolean_to_binary(passwd != "") :: bits, 
			boolean_to_binary(con.will_retain) :: bits, 
 			qos_binary(con.will_qos) :: size(2), 
			boolean_to_binary(con.last_will) :: bits, 
			boolean_to_binary(con.clean_session) :: bits, 
			0 :: size(1)
			>> <> 
			keep_alive(keep_alive) # :: binary>>
		fields = [client_id ] ++
			if last_will do [con.will_topic, con.will_message] else [] end ++
			if (user != "") do [user] else [] end ++
			if (passwd != "") do [passwd] else [] end 
		# payload = [client_id, con.will_topic, con.will_message, user, passwd] |> Enum.map_join &utf8/1 
		payload = fields |> Enum.map_join &utf8/1 
		Enum.join([h, flags, payload])
	end
	def encode(any) do
		IO.inspect any	
	end
	


	@doc "Returns the one byte fixed header and the length encoding"
	def encode_header(:pub_rel, dup)do
		<<msg_type_to_binary(:pub_rel) :: size(4),
			boolean_to_binary(dup) :: bits, 
			qos_binary(:at_least_once) :: size(2), 
			boolean_to_binary(false) :: bits, 
			encode_length(2) :: binary>>
	end
	def encode_header(%Mqttex.Msg.FixedHeader{message_type: type, duplicate: dup, 
			retain: retain, qos: qos, length: length}) do
		<<msg_type_to_binary(type) :: size(4),
			boolean_to_binary(dup) :: bits, 
			qos_binary(qos) :: size(2), 
			boolean_to_binary(retain) :: bits, 
			encode_length(length) :: binary>>
	end

	def utf8(str), do: <<byte_size(str) :: big-size(16)>> <> str	

	def msg_id(id) when is_integer(id), do: <<id :: big-size(16)>>
	
	def keep_alive(:infinity), do: <<0 :: size(16)>>
	def keep_alive(n), do: <<n :: big-size(16)>>

	def encode_length(0), do: <<0x00>>
	def encode_length(l) when l <= 268_435_455, do: encode_length(l, <<>>)
	defp encode_length(0, acc), do: acc
	defp encode_length(l, acc) do
		digit = l &&& 0x7f # mod 128
		new_l = l >>> 7 # div 128
		if new_l > 0 do
			# add high bit since there is more to come
			encode_length(new_l, acc <> <<digit ||| 0x80>>)
		else 
			encode_length(new_l, acc <> <<digit>>)
		end
	end
	

	@doc "converts boolean to bits"
	def boolean_to_binary(true), do: <<1 :: size(1)>>
	def boolean_to_binary(false), do: <<0 :: size(1)>>

	@doc "converts atoms the binary qos"
	def qos_binary(:fire_and_forget), do: 0
	def qos_binary(:at_least_once),   do: 1
	def qos_binary(:exactly_once),    do: 2
	def qos_binary(:reserved),        do: 3

	@doc "Converts the atoms to binary message types"
	def msg_type_to_binary(:connect),     do: 1
	def msg_type_to_binary(:conn_ack),    do: 2
	def msg_type_to_binary(:publish),     do: 3
	def msg_type_to_binary(:pub_ack),     do: 4
	def msg_type_to_binary(:pub_rec),     do: 5
	def msg_type_to_binary(:pub_rel),     do: 6
	def msg_type_to_binary(:pub_comp),    do: 7
	def msg_type_to_binary(:subscribe),   do: 8
	def msg_type_to_binary(:sub_ack),     do: 9
	def msg_type_to_binary(:unsubscribe), do: 10
	def msg_type_to_binary(:unsub_ack),   do: 11
	def msg_type_to_binary(:ping_req),    do: 12
	def msg_type_to_binary(:ping_resp),   do: 13
	def msg_type_to_binary(:disconnect),  do: 14
	def msg_type_to_binary(:reserved),    do: 0

	def conn_ack_status(:ok),                            do: 0
	def conn_ack_status(:unaccaptable_protocol_version), do: 1
	def conn_ack_status(:identifier_rejected),           do: 2
	def conn_ack_status(:server_unavailable),            do: 3
	def conn_ack_status(:bad_user),                      do: 4
	def conn_ack_status(:not_authorized),                do: 5
	
end