defmodule Mqttex.OutboundQueue do
	@moduledoc """
	This implements the outbound queue, publishing messages towards a single destination. 
	It uses the QoS Protocols to factor out the correct behaviour for `at least once` or for 
	`at most once` guarantees.
	"""

	use Bitwise
	use GenServer.Behaviour
	@behaviour Mqttex.SenderBehaviour

	defrecord QueueState, counter: 0, session: :none, session_mod: :none, transfers: []

	#####################################################################################
	### API
	#####################################################################################
	@doc "Publishes a `message` with a `qos` for a `topic` via the `queue` process."
	def publish(queue, topic, message, qos) when 
		qos in [:fire_and_forget, :at_least_once, :at_most_once] do
		:gen_server.cast(queue, {:publish, topic, message, qos})
	end
	
	def start_link(session, session_mod) do
		:gen_server.start_link(__MODULE__, [session, session_mod], [])
	end
	
	@doc "Receives a message back from the destination of a protocol."
	def receive(queue, Mqttex.PubAckMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	def receive(queue, Mqttex.PubRecMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	def receive(queue, Mqttex.PubRelMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	def receive(queue, Mqttex.PubCompMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	def receive(queue, Mqttex.SubAckMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	def receive(queue, Mqttex.UnSubAckMsg[msg_id: msg_id] = msg) do
		:gen_server.cast(queue, {:receive, msg_id, msg})
	end
	

	#####################################################################################
	### QoS Behaviour Callbacks
	#####################################################################################
	@doc """
	Sends an outbound message as part of a QoS-Protocol. Is not a part of the general
	public API but only called from the an QoS-Protocol implementation.
	"""
	@spec send_msg(term, Mqttex.SenderBehaviour.message_type) :: integer
	def send_msg(queue, message) do
		:gen_server.call(queue, {:send, message})
	end

	@spec send_completed(term, Mqttex.PubCompMsg.t) :: :ok
	def send_completed(queue, message) do
		:gen_server.call(queue, {:send, message})
	end
	
	@doc """
	Sends a release message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	@spec send_release(term, Mqttex.PubRelMsg.t) :: integer
	def send_release(queue, message) do
		:gen_server.call(queue, {:send, message})
	end
	

	#####################################################################################
	### Gen Server Callbacks
	#####################################################################################
	def handle_cast({:publish, topic, message, qos}, QueueState[] = state) do
		msg = make_publish(topic, message, qos, state.counter)
		pid = start_protocol(msg, qos)
		new_state = new_protocol(pid, state, qos)
		pid <- :go
		{:noreply, new_state}
	end
	def handle_cast({recieve, msg_id, message}, QueueState[] = state) do
		case get_protocol(state, msg_id) do
			:none -> :ok # unknown process, we don't care
			pid   -> pid <- message # process found, send message
		end
		{:noreply, state}
	end
	
	def handle_call({:send, message}, from, 
			QueueState[session: session, session_mod: session_mod] = state) do
		session_mod.send_msg(session, message)
		{:reply, state.timeout, state}
	end
	def handle_call({:completed, msg_id}, from, QueueState[] = state) do
		new_state = delete_protocol(state, msg_id)
		{:reply, :ok, new_state}
	end
	
	

	def init([session, session_mod]) do
		{:ok, QueueState.new([session: session, session_mod: session_mod])}
	end
	

	#####################################################################################
	### internal functions
	#####################################################################################
	def make_publish(topic, message, qos, msg_id) do
		header = Mqttex.FixedHeader.new [qos: qos, message_type: :publish]
		Mqttex.PublishMsg.new [header: header, topic: topic, message: message, msg_id: msg_id]
	end
	
	@doc """
	Starts and initializes a qos protocol process and returns its PID. The sending process becomes active
	after receiving the `:go` message. 
	"""
	def start_protocol(Mqttex.PublishMsg[] = msg, :fire_and_forget) do
		spawn_link(Mqttex.Qos0Sender.start(msg, __MODULE__, self))
	end
	def start_protocol(Mqttex.PublishMsg[] = msg, :at_least_once) do
		spawn_link(Mqttex.Qos1Sender.start(msg, __MODULE__, self))
	end
	def start_protocol(Mqttex.PublishMsg[] = msg, :at_most_once) do
		spawn_link(Mqttex.Qos2Sender.start(msg, __MODULE__, self))
	end

	@doc "Adds a new message protocol process to the transfer dictionary"
	def new_protocol(pid, QueueState[] = state, :fire_and_forget) do
		# we do not store anything about fire_and_forget
		state
	end
	def new_protocol(pid, QueueState[counter: counter, transfers: transfers] = state, _qos) do
		# at_least_once and at_most_once have complex protocol: store the protocol process 
		# message counters are 16 bit numbers
		new_count = rem(counter + 1, 1 <<< 16)
		new_trans = Dict.put(transfers, counter, pid)
		state.update([counter: new_count, transfers: new_trans])
	end
	
	@doc """
	Retrieves the protocol process from the transfer dictionary. If no process is 
	associated with the `msg_id`, the function returns `:none`.
	"""
	def get_protocol(QueueState[] = state, msg_id) do
		Dict.get(state.transfers, msg_id, :none)
	end

	def delete_protocol(QueueState[transfers: transfers] = state, msg_id) do
		new_t = Dict.drop(transfers, msg_id)
		state[transfers: new_t]
	end

end
