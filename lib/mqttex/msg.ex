defmodule Mqttex.Msg do
	defmodule Simple do
		@moduledoc """
		Defines all simple messages as structs. They contain at most a message id.
		"""
		defstruct msg_type: :reserved :: Mqttex.simple_message_type, 
			msg_id: 0 :: integer
	end
	
	@doc "Creates a new simple message of type `pub_ack`"
	def pub_ack(msg_id) when is_integer(msg_id), do: %Simple{msg_type: :pub_ack, msg_id: msg_id}

	@doc "Creates a new simple message of type `pub_rec`"
	def pub_rec(msg_id) when is_integer(msg_id), do: %Simple{msg_type: :pub_rec, msg_id: msg_id}

	@doc "Creates a new simple message of type `pub_rel`"
	def pub_rel(msg_id) when is_integer(msg_id), do: %Simple{msg_type: :pub_rel, msg_id: msg_id}

	@doc "Creates a new simple message of type `pub_comp`"
	def pub_comp(msg_id) when is_integer(msg_id), do: %Simple{msg_type: :pub_comp, msg_id: msg_id}

	@doc "Creates a new simple message of type `ping_req`"
	def ping_req(), do: %Simple{msg_type: :ping_req}

	@doc "Creates a new simple message of type `ping_resp`"
	def ping_resp(), do: %Simple{msg_type: :ping_resp}

	@doc "Creates a new simple message of type `disconnect`"
	def disconnect(), do: %Simple{msg_type: :disconnect}

	@doc "Creates a new simple message of type `unsub_ack`"
	def unsub_ack(msg_id) when is_integer(msg_id), do: %Simple{msg_type: :unsub_ack, msg_id: msg_id}

	defmodule ConnAck do
		@moduledoc """
		Define the `conn ack` message
		"""
		defstruct status: :ok :: Mqttex.conn_ack_type
	end

	@doc "Creates a new message of type `conn_ack`"
	def conn_ack(status \\ :ok), do: %ConnAck{status: status}
	
	defmodule FixedHeader do
		@moduledoc """
		Defines the fixed header of a MQTT message.
		"""
		defstruct message_type: :reserved :: Mqttex.message_type,
			duplicate: false :: boolean,
			qos: :fire_and_forget :: Mqttex.qos_type,
			retain: false :: boolean,
			length: 0 :: pos_integer
	end

	def fixed_header(msg_type \\ :reserved, dup \\ false, qos \\ :fire_and_forget, 
			retain \\ false, length \\ 0) when 
		is_atom(msg_type) and is_boolean(dup) and is_atom(qos) and
		is_boolean(retain) and is_integer(length) and length >= 0
		do
		%FixedHeader{message_type: msg_type, duplicate: dup, 
			qos: qos, retain: retain, length: length}
	end
	
	defmodule Publish do
		@moduledoc """
		Defines the publish message.
		"""

		defstruct topic: "" :: binary,
			msg_id: 0 :: pos_integer,
			message: "" :: binary,
			header: %FixedHeader{} :: Mqttex.Msg.FixedHeader 

		@doc "Sets the duplicate flag to `dup` in the message"
		def duplicate(%Publish{header: h} = m, dup \\ true) do
			new_h = %FixedHeader{h | duplicate: dup}
			%Publish{m | header: new_h}
		end

		@doc "Sets the message id"
		def msg_id(%Publish{} = m, id \\ 0) do
			%Publish{m | msg_id: id}
		end
		
		@doc "Set the retain flag to `retain` in the message"
		def retain(%Publish{header: h} = m, retain \\ true) do
			new_h = %FixedHeader{h | retain: retain}
			%Publish{m | header: new_h}
		end
		
	end
	
	##############
	## define publish function and replace Record
	## does the function compute/correct the fixed header (i.e. length attribute) 
	##    Makes sense, or?
	##############

	@doc "Creates a new publish message. The message id is not set per default."
	def publish(topic, message, qos, msg_id \\ 0) do
		length = size(message) + 
		         size(topic) + 2 + # with 16 bit size of topic
		         2 # 16 bit message id
		h = fixed_header(:publish, false, qos, false, length)
		%Publish{topic: topic, message: message, msg_id: msg_id, header: h}
	end


	defmodule Unsubscribe do
		defstruct topics: [] :: [binary],
			msg_id: 0 :: pos_integer,
			header: %FixedHeader{} :: Mqttex.Msg.FixedHeader 

		@doc "Sets the duplicate flag to `dup` in the message"
		def duplicate(%Publish{header: h} = m, dup \\ true) do
			new_h = %FixedHeader{h | duplicate: dup}
			%Publish{m | header: new_h}
		end

		@doc "Sets the message id"
		def msg_id(%Publish{} = m, id \\ 0) do
			%Publish{m | msg_id: id}
		end
		
	end
	
	@doc "Creates a new unsubscribe message. The message id is not set per default"
	@spec unsubscribe([binary], pos_integer) :: Unsubscribe.t
	def unsubscribe(topics, msg_id \\ 0) do
		length = 2 + #  16 bit message id
			(topics |> Enum.map(fn(t) -> size(t) + 2 end) |> Enum.sum)
		h = fixed_header(:unsubscribe, false, :at_least_once, false, length)
		%Unsubscribe{topics: topics, msg_id: msg_id, header: h}
	end
	

end
