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
		def duplicate(%Unsubscribe{header: h} = m, dup \\ true) do
			new_h = %FixedHeader{h | duplicate: dup}
			%Unsubscribe{m | header: new_h}
		end

		@doc "Sets the message id"
		def msg_id(%Unsubscribe{} = m, id \\ 0) do
			%Unsubscribe{m | msg_id: id}
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
	
	defmodule SubAck do
		defstruct msg_id: 0 :: pos_integer, 
			granted_qos: [] :: [pos_integer],
			header: %FixedHeader{} :: FixedHeader.t

		@doc "Sets the message id"
		def msg_id(%SubAck{} = m, id \\ 0) do
			%SubAck{m | msg_id: id}
		end
	
	end

	@doc "Creates a new sub_ack message. The message id is not set per default"
	@spec sub_ack([Mqttex.qos_type], pos_integer) :: SubAck.t
	def sub_ack(granted_qos, msg_id \\ 0) do
		length = 2 + # 16 bit message id
			length(granted_qos) # number of bytes per qos
		h = fixed_header(:sub_ack, false, :fire_and_forget, false, length)
		%SubAck{msg_id: msg_id, granted_qos: granted_qos, header: h }
	end
	
	defmodule Subscribe do
		defstruct msg_id: 0 :: pos_integer,
			header: %FixedHeader{} :: FixedHeader.t,
			topics: [{"", :fire_and_forget}] :: [{binary, Mqttex.qos_type}]

		@doc "Sets the message id"
		def msg_id(%Subscribe{} = m, id \\ 0) do
			%Subscribe{m | msg_id: id}
		end
	
		@doc "Sets the duplicate flag to `dup` in the message"
		def duplicate(%Subscribe{header: h} = m, dup \\ true) do
			new_h = %FixedHeader{h | duplicate: dup}
			%Subscribe{m | header: new_h}
		end

	end

	def subscribe(topics, msg_id \\ 0) do
		length = 2 + # 16 bit message id
			topics |> Enum.map(fn(t,q) -> size(t) + 3 # + 16 bit length + 1 byte qos
				end) |> Enum.sum
		h = fixed_header(:subscribe, false, :at_least_once, false, length)
		%Subscribe{msg_id: msg_id, topics: topics, header: h}
	end


	defmodule Connection do

		defstruct client_id: "" :: binary,
			user_name: "" :: binary,
			password: "" :: binary,
			keep_alive: :infinity, # or the keep-alive in milliseconds (=1000*mqtt-keep-alive)
			# keep_alive_server: :infinity, # or 1.5 * keep-alive in milliseconds (=1500*mqtt-keep-alive)
			last_will: false :: boolean,
			will_qos: :fire_and_forget :: Mqttex.qos_type,
			will_retain: false :: boolean,
			will_topic: "" :: binary,
			will_message: "" :: binary, 
			clean_session: true :: boolean,
			header: %FixedHeader{} :: FixedHeader.t
			
	end	

	@doc """
	Creates a new connect message.
	"""
	def connection(client_id, user_name, password, clean_session, keep_alive \\ :infinity, # keep_alive_server \\ :infinity, 
			last_will \\ false, will_qos \\ :fire_and_forget, will_retain \\ false, will_topic \\ "", will_message \\ "") do
		length = 12 +  # variable header size 
			size(client_id) + 2 + 
			size(will_topic) + 2 +
			size(will_message) + 2 +
			size(user_name) + 2 +
			size(password) + 2
		h = fixed_header(:subscribe, false, :fire_and_forget, false, length)
		%Connection{client_id: client_id, user_name: user_name, password: password, 
			keep_alive: keep_alive, last_will: last_will, will_qos: will_qos, 
			will_retain: will_retain, will_topic: will_topic, 
			will_message: will_message, clean_session: clean_session, header: h }
	end
	

end
