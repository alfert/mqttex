defmodule Mqttex.ProtocolManager do
	@moduledoc """
	The `ProtocolManager` manages the QoS protocols. Its responsibilities are 

	* to start QoS protocols for sender or the receiver side
	* to store the running protocols in a map, associating the `msg_id` with protocol process
	* to delete the protocol process after the QoS protocol is finished

	The API of the `ProtocolManager` are `publish` and `receive` calls. 
	"""

	use Bitwise
	# use Dict.Behaviour

	defstruct counter: 0, transfers: HashDict.new()

	#################################################################################
	## Specific Functions
	#################################################################################

	@spec msg_id(ProtocolManager.t) :: integer
	@doc """
		Returns the current, fresh message_id. The Message ID is updated after
	each call to `put`.
	"""
	def msg_id(%Mqttex.ProtocolManager{counter: counter}) do
		counter
	end

	@doc """
	Sends the message. Starts a sender QoS-Protocol process if required and stores it in the
	transfers dictionary. The existing message id in the message is overriden by the 
	new calculated message id. 

	Any message that is not a `PublishMsg`, `SubscibeMsg` or `UnScubscribeMsg` is send
	as `:fire_and_forget`. It is not checked for correctness and allows to send e.g. 
	Ping-Messages via this approach. 
	"""
	def sender(state, msg, session_mod) do
		sender(state, msg, session_mod, self)
	end
	
	def sender(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Publish{} = msg, session_mod, session_pid) do
		msg_id = msg_id(state)
		new_msg = Mqttex.Msg.Publish.msg_id(msg, msg_id)
		header = msg.header
		do_send(state, new_msg, msg_id, header.qos, session_mod, session_pid)
	end
	def sender(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Subscribe{} = msg, session_mod, session_pid) do
		msg_id = msg_id(state)
		new_msg = Mqttex.Msg.Subscribe.msg_id(msg, msg_id)
		header = msg.header
		do_send(state, new_msg, msg_id, header.qos, session_mod, session_pid)
	end
	def sender(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Unsubscribe{} = msg, session_mod, session_pid) do
		msg_id = msg_id(state)
		new_msg = Mqttex.Msg.Unsubscribe.msg_id(msg, msg_id)
		header = msg.header
		
		do_send(state, new_msg, msg_id, header.qos, session_mod, session_pid)
	end
	def sender(%Mqttex.ProtocolManager{} = state, any_msg, session_mod, session_pid) do
		# This should hopefully only be a message, which does not require any 
		# other QoS or is even a inside-part of a protocol (e.g. Acks)
		do_send(state, any_msg, -1, :fire_and_forget, session_mod, session_pid)
	end


	@doc """
	Starts the real QoS-process
	"""
	def do_send(%Mqttex.ProtocolManager{} = state, msg, msg_id, qos, session_mod, session_pid) do				
		qos_pid = spawn_link(sender_protocol(qos), :start, [msg, session_mod, session_pid])
		new_state = case qos do
			:fire_and_forget -> state # we do not memorize fire-and-forget: just forget it
			_ -> put(state, msg_id, qos_pid)
		end
		send(qos_pid, :go)
		new_state
	end
	
	@doc """
	Receive a message. If it is a PublishMsg`, `SubscibeMsg` or `UnScubscribeMsg`, a QoS-Receiver
	protocol process is started. Otherwise we dispatch to the existing protocol.
	"""
	def receiver(state, msg, session_mod) do
		receiver(state, msg, session_mod, self)
	end
	def receiver(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Publish{msg_id: id} = msg, session_mod, session_pid) do
		header = msg.header
		do_receive(state, msg, id, header.qos, session_mod, session_pid)
	end
	def receiver(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Subscribe{msg_id: id} = msg, session_mod, session_pid) do
		header = msg.header
		do_receive(state, msg, id, header.qos, session_mod, session_pid)
	end
	def receiver(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Unsubscribe{msg_id: id} = msg, session_mod, session_pid) do
		header = msg.header
		do_receive(state, msg, id, header.qos, session_mod, session_pid)
	end
	def receiver(%Mqttex.ProtocolManager{} = state, any_msg, _session_mod, _session_pid) do
		:ok = dispatch_receiver(state, any_msg)
		state
	end
	
	def do_receive(state, msg, msg_id, qos, session_mod, session_pid) do
		qos_pid = spawn_link(receiver_protocol(qos), :start, [msg, session_mod, session_pid])
		new_state = put(state, msg_id, qos_pid) 
		new_state
	end



	@doc """
	Dispatches the message to the associated QoS-protocol. Dispatching depends on 
	the message id. Dispatching can only work for already active QoS protocols, 
	therefore for protocol initiating messages the function returns `:error`.

	Returns `:ok` if the OoS Protocol is found, otherwise `:error`.
	"""
	# def dispatch_sender(%Mqttex.ProtocolManager{} = state, Mqttex.PubAckMsg[msg_id: id] = msg),   do: dispatch(state, id, msg)
	# def dispatch_sender(%Mqttex.ProtocolManager{} = state, Mqttex.PubRecMsg[msg_id: id] = msg),   do: dispatch(state, id, msg)
	# def dispatch_sender(%Mqttex.ProtocolManager{} = state, Mqttex.PubCompMsg[msg_id: id] = msg),  do: dispatch(state, id, msg)
	# def dispatch_sender(%Mqttex.ProtocolManager{} = state, Mqttex.UnSubAckMsg[msg_id: id] = msg), do: dispatch(state, id, msg)
	def dispatch_sender(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Simple{msg_id: id} = msg), do: dispatch(state, id, msg)
	def dispatch_sender(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.SubAck{msg_id: id} = msg),   do: dispatch(state, id, msg)
	def dispatch_sender(%Mqttex.ProtocolManager{} = _state, _msg), do: :error

	# def dispatch_receiver(%Mqttex.ProtocolManager{} = state, Mqttex.PubCompMsg[msg_id: id] = msg),  do: dispatch(state, id, msg)
	def dispatch_receiver(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.Simple{msg_id: id} = msg), do: dispatch(state, id, msg)
	def dispatch_receiver(%Mqttex.ProtocolManager{} = state, %Mqttex.Msg.PubRel{msg_id: id} = msg),   do: dispatch(state, id, msg)
	def dispatch_receiver(%Mqttex.ProtocolManager{} = _state, _msg), do: :error

	@doc """
	Dispatches the message to its QoS-protocol. This function is not part of the 
	public API but is public available for testing purposes only.

	Returns `:ok` if the QoS Protocol is found, otherwise `:error`.
	"""
	def dispatch(%Mqttex.ProtocolManager{} = state, msg_id, msg) do
		case fetch(state, msg_id) do
			{:ok, pid} -> 
				send(pid, msg)
				:ok
			:error -> :error
		end
	end

	#################################################################################
	## API is based on Dict.Behaviour
	#################################################################################

	def new(), do: %Mqttex.ProtocolManager{} 
	
	@doc """
	Stores a new process at the given `msg_id` and calculates the next new `msg_id. 
	The new `msg_id` can be retrieved via the call to `msg_id`.

	According to MQTT the msg_id is a 16 bit value. The internal counter starts with
	`0`, counting up modulo 2^16.
	"""
	@spec put(ProtocolManager.t, integer, pid) :: ProtocolManager.t
	def put(%Mqttex.ProtocolManager{counter: counter, transfers: transfers} = state, msg_id, pid) do
		new_count = rem(counter + 1, 1 <<< 16)
		new_trans = Dict.put(transfers, msg_id, pid)
		%Mqttex.ProtocolManager{state | transfers: new_trans, counter: new_count}
	end
	
	@spec size(ProtocolManager.t) :: integer
	def size(%Mqttex.ProtocolManager{transfers: transfers}) do
		Dict.size(transfers)
	end
	
	@spec fetch(ProtocolManager.t, integer) :: pid
	def fetch(%Mqttex.ProtocolManager{transfers: transfers}, key) do
		Dict.fetch(transfers, key)
	end

	# unlike Dict.Behaviour 
	@spec update(ProtocolManager.t, integer, pid) :: ProtocolManager.t
	def update(%Mqttex.ProtocolManager{transfers: transfers} = state, key, initial) do
		new_trans = Dict.update(transfers, key, initial)
		%Mqttex.ProtocolManager{state | transfers: new_trans}
	end
	
	@spec delete(ProtocolManager.t, integer) :: ProtocolManager.t
	def delete(%Mqttex.ProtocolManager{transfers: transfers} = state, key) do
		new_trans = Dict.delete(transfers, key)
		%Mqttex.ProtocolManager{state | transfers: new_trans}
	end

	# only for Dict.Behaviour - not really needed
	@spec reduce(ProtocolManager.t, any, (any -> any)) :: any
	def reduce(%Mqttex.ProtocolManager{transfers: transfers}, acc, fun) do
		Enum.reduce(transfers, acc, fun)
	end
	

	#################################################################################
	## Internal Functions
	#################################################################################
	
	@doc """
	Returns the Module implementing the QoS sender protocol
	"""
	def sender_protocol(:fire_and_forget), do: Mqttex.QoS0Sender
	def sender_protocol(:at_least_once), do: Mqttex.QoS1Sender
	def sender_protocol(:exactly_once), do: Mqttex.QoS2Sender
	
	@doc """
	Returns the Module implementing the QoS receiver protocol
	"""
	def receiver_protocol(:fire_and_forget), do: Mqttex.QoS0Receiver
	def receiver_protocol(:at_least_once), do: Mqttex.QoS1Receiver
	def receiver_protocol(:exactly_once), do: Mqttex.QoS2Receiver


end

