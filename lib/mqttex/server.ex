defmodule Mqttex.Server do
	@moduledoc """
	The server implementation of MQTT. It works only Elixir Data Structures and with Erlang/Elixir 
	messages. All TPC/IP handling and en- and decoding of MQTT messages is done in a seperate 
	layer. 

	All API functions take an Elixir representation of a MQTT message and return the corresponding
	answer, if it exists.

	This approach eases implementation and testing. 
	"""

	use GenFSM.Behaviour
	@my_name __MODULE__
	@default_timeout 500 # 100m milliseconds timeout 

	use Mqttex.SenderBehaviour
	use Mqttex.ReceiverBehaviour

	defrecord ConnectionState, connection: :none, 
		client_proc: :none,
		timeout: @default_timeout, 
		subscriptions: [],
		senders: Mqttex.ProtocolManager.new(), 
		receivers: Mqttex.ProtocolManager.new()

	#### API of the server
	@doc """
	Connects the client with the server process. If no server for the `client_id` exists, 
	then a new server is started and linked to the supervisor tree. If the server already 
	exists, we have a reconnection situation: if the server is in state `disconnected` 
	the reconnection can be executed. Otherwise an error occurs.
	"""
	@spec connect(Mqttex.ConnectionMsg.t, pid) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def connect(Mqttex.ConnectionMsg[connection: connection] = con, client_proc \\ self()) do
		value = case Mqttex.SupServer.start_server(connection, client_proc) do
			{:error, {:already_started, pid}} -> reconnect(pid, connection, client_proc) 
			any -> any
		end
		case value do 
			{:ok, pid}       -> {Mqttex.ConnAckMsg.new([status: :ok]), pid}
			{:error, reason} -> Mqttex.ConnAckMsg.new [status: reason]
		end
	end

	@doc """
	Is called to receive an outbound message, i.e. the message must be a valid
	MQTT message. The functions sends the message asynchronously to the 
	session and returns immediatly.
	"""
	def receive(server, Mqttex.PublishMsg[] = msg), do: do_receive(server, msg)
	def receive(server, Mqttex.SubscribeMsg[] = msg), do: do_receive(server, msg)
	def receive(server, Mqttex.UnSubscribeMsg[] = msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PingReqMsg[] = msg), do: do_receive(server, msg)
	def receive(server, Mqttex.DisconnectMsg[] = msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PubRelMsg[] = msg), do: do_receive(server, msg)
	
	# internal function sending the message to the server
	defp do_receive(server, msg) do
		:gen_fsm.send_event(server, {:receive, msg})
	end

	@doc "Internal function for stopping the server"
	@spec stop(pid) :: :ok
	def stop(server) do
		:gen_fsm.send_all_state_event(server, :stop)
	end

	@doc """
	Publishes a message to be send to the client. This is called 
	from the `Topic`. 
	"""	
	def publish(server, topic, body, qos) do
		header = Mqttex.FixedHeader.new([qos: qos])
		msg = Mqttex.PublishMsg.new([header: header, topic: topic, message: body])
		:gen_fsm.send_event(server, {:publish, msg})
	end

	#############################################################################################
	#### Callbacks from QoS Behaviours
	#############################################################################################
	@doc """
	Sends a messages to the client side and returns the new timeout. Only called from a QoS protocol 
	process, not part of the general API.  
	"""
	def send_msg(server, msg) do
		:gen_fsm.sync_send_event(server, {:send, msg})
	end
	@doc """
	Sends the received message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_received(server, msg) do
		:gen_fsm.sync_send_event(server, {:send, msg})
	end
	@doc """
	Sends the release message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_release(server, msg) do
		:gen_fsm.sync_send_event(server, {:send, msg})
	end
	@doc """
	Sends the complete message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_complete(server, msg) do
		:gen_fsm.sync_send_event(server, {:send, msg})
	end
	@doc """
	Finishes a sender protocol process. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def finish_sender(server, msg_id) do
		:gen_fsm.send_event(server, {:drop_sender, msg_id})
	end
	@doc """
	Finishes a receiver protocol process. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def finish_receiver(server, msg_id) do
		:gen_fsm.send_event(server, {:drop_receiver, msg_id})
	end
	
	@doc """
	Finally receives the regular message for delivery to a topic. Only called from a QoS 
	protocol process, not part of the general API.
	"""
	def on_message(server, msg) do
		:gen_fsm.send_event(server, {:on, msg})		
	end


	#############################################################################################
	#### Internal functions
	#############################################################################################

	@spec start_link(Mqttex.Connection.t, pid) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def start_link( Mqttex.Connection[] = connection, client_proc \\ self()) do
		:error_logger.info_msg "#{__MODULE__}.start_link for `#{connection.client_id}'"
		:gen_fsm.start_link({:global, "S" <> connection.client_id}, @my_name, {connection, client_proc},
									[timeout: connection.keep_alive_server])
	end

	@doc "Initializes the FSM"
	def init({connection, client_proc}) do
		# TODO: check that the connection data is proper. Invalidity results in {:stop, error_code}, 
		# where error_code is of type conn_ack_type
		:error_logger.info_msg "#{__MODULE__}.init in #{inspect self} for client_proc #{inspect client_proc}"
		queue = nil # Mqttex.OutboundQueue.start_link(self, __MODULE__)
		{:ok, :clean_session, 
			ConnectionState.new([connection: connection, client_proc: client_proc, 
				out_queue: queue]), 
			connection.keep_alive_server }
	end

	# Reconnects an existing server with a new connection
	defp reconnect(server, connection, client_proc) do
		:gen_fsm.sync_send_event(server, {:reconnect, connection, client_proc})
	end
	
	

	#############################################################################################
	#### Event/State Handling
	#############################################################################################

	@doc "Events in state `clean_session` with replies"
	def clean_session({:send, msg}, _from, ConnectionState[client_proc: client, connection: con] = state) do
		# Send the message directly to the client and calculate the new timeout
		timeout = calc_timeout(msg, state)
		send(client, msg)
		new_state = state.update(timeout: timeout)
		{:reply, timeout, :clean_session, new_state, con.keep_alive_server}
	end
	def clean_session(:ping, _from, ConnectionState[connection: con]=state) do
		{:reply, :pong, :clean_session, state, con.keep_alive_server}
	end
	

	########################################################################################
	### All messages coming from the outside as MQTT-Messages ({:receive, msg})
	########################################################################################

	@doc "Event in state `clean_session` without a reply"
	def clean_session({:receive, Mqttex.PublishMsg[] = msg}, ConnectionState[connection: con] = state) do
		# initiate a new protocol for receiving a published message
		# sending to the TopicManager is the task of the on_message callback!!!
		new_rec = Mqttex.ProtocolManager.receiver(state.receivers, msg, __MODULE__, self)
		{:next_state, :clean_session, state.update(receivers: new_rec), state.connection.keep_alive_server}
	end
	def clean_session({:receive, Mqttex.PubRelMsg = msg}, ConnectionState[receivers: receivers] = state) do
		# delegate to the receivers
		Mqttex.ProtocolManager.dispatch_receiver(receivers, msg)
		{:next_state, :clean_session, state, state.connection.keep_alive_server}
	end
	def clean_session({:receive, Mqttex.PingReqMsg[] = _msg}, ConnectionState[client_proc: client, connection: con]=state) do
		send(client, Mqttex.PingRespMsg.new)
		{:next_state, :clean_session, state, con.keep_alive_server}
	end
	def clean_session({:receive, Mqttex.SubscribeMsg[] = topics}, ConnectionState[]=state) do
		# subscribe to topics at the subscription server
		#   -> the server adds all existing topics 
		# send the status of freshly subscribed topics back to the client
		
		# TODO: return the new_state
		new_state = state
		{:next_state, :clean_session, new_state, new_state.connection.keep_alive_server}
	end
	def clean_session({:receive, Mqttex.UnSubscribeMsg[] = topics}, ConnectionState[]=state) do
		# unsubscribe to topics at the subscription server
		#   -> the server drops all existing topics 
		
		# TODO: return the new_state
		new_state = state
		{:next_state, :clean_session, new_state, new_state.connection.keep_alive_server}
	end
	def clean_session({:receive, Mqttex.DisconnectMsg[] = _msg}, ConnectionState[]=state) do
		# TODO: call unsubscribe all topics
		:error_logger.info_msg("Got Disconnect, going to disconnected mode")
		# no timeout here, we wait forever
		{:next_state, :clean_disconnect, state}
	end
	########################################################################################
	### All messages coming from the inside and the protocol handling
	########################################################################################
	# a lot missing here
	def clean_session({:publish, Mqttex.PublishMsg[] = msg}, ConnectionState[] = state) do
		# publish the message towards the client
		# sending is delegated to the QoS protocol 
		new_sender = Mqttex.ProtocolManager.sender(state.senders, msg, __MODULE__, self)
		new_state = state.update(senders: new_sender)
		{:next_state, :clean_session, new_state, state.connection.keep_alive_server}
	end
	def clean_session({:on, msg}, ConnectionState[] = state) do
		# TODO: Send the message to the Topic Master
		IO.puts "Yeah: Got this message #{inspect msg}"
		{:next_state, :clean_session, state, state.connection.keep_alive_server}
	end
	def clean_session({:drop_receiver, msg_id}, ConnectionState[receivers: receivers] = state) do
		new_receiver = Mqttex.ProtocolManager.delete(state.receivers, msg_id)
		{:next_state, :clean_session, state.update(receivers: new_receiver), 
				state.connection.keep_alive_server}
	end
	def clean_session({:drop_sender, msg_id}, ConnectionState[senders: senders] = state) do
		new_sender = Mqttex.ProtocolManager.delete(state.senders, msg_id)
		{:next_state, :clean_session, state.update(senders: new_sender), 
				state.connection.keep_alive_server}
	end
	
	########################################################################################
	### Finally: timeout - the client does not respond fast enough
	########################################################################################
	def clean_session(:timeout, ConnectionState[]=state) do
		# TODO: Publish Will Message if required
		# TODO: call unsubscribe all topics

		# no timeout here, we wait forever
		{:next_state, :clean_disconnect, state}
	end
	
	
	@doc "Reconnection with reply"
	def clean_disconnect({:reconnect, connection, client_proc}, _from, ConnectionState[]=state) do
		{reply, s, new_state_data} = case check_connection(connection) do
			:ok -> {{:ok, self}, :clean_session, 
				state.update [connection: connection, client_proc: client_proc]}
			error -> {{:error, error}, :clean_disconnect, state}
		end
		{:reply, reply, s, new_state_data, new_state_data.connection.keep_alive_server}
	end
	def clean_disconnect(any_msg, _from, ConnectionState[]=state) do
		:error_logger.error_msg("Disconnected Server #{state.connection.client_id} got message #{inspect any_msg}")
		{:next_state, :clean_disconnect, state}
	end

	@doc "Received messages in the disconnected state are simply ignored"
	def clean_disconnect(any_msg, ConnectionState[]=state) do
		:error_logger.error_msg("Disconnected Server #{state.connection.client_id} got message #{inspect any_msg}")
		{:next_state, :clean_disconnect, state}
	end
	

	@doc """
	The stop event is only allowed if we have no subscriptions: there is no relevant
	state data in the server available. The only bad thing that can happen is another 
	non-connecting message from the client, for which no server exists any longer. However,
	since the client-socket-process is linked to the server, the terminating server should
	send the socket process an `EXIT` message resuling in an shutdown of the socket as well.
	"""
	def handle_event(:stop, _state, ConnectionState[subscriptions: []] = state_data) do
		{:stop, :normal, state_data}
	end
	def handle_event(:stop, state, ConnectionState[] = state_data) do
		{:next_state, state, state_data}
	end

	@doc "Terminaction call back"
	def terminate(reason, state, ConnectionState[connection: con] = state_data) do
		:error_logger.info_msg "Shutting down for reason #{inspect reason} " <> 
			"in state #{inspect state} for connection #{inspect con.client_id}"
	end		

	########################################################################################
	### Helper functions
	########################################################################################

	@doc "Checks the connection"
	@spec check_connection(Mqttex.Connection.t) :: Mqttex.conn_ack_type
	def check_connection(Mqttex.Connection[client_id: c_id]) 
		when length(c_id)> 26, do: :identifier_rejected
	def check_connection(Mqttex.Connection[] = _connection) do
		# TODO: check authentication
		:ok
	end
	
	@doc """
	Calculates the new timeout depending on the last retries (in the future). 
	The default implementation is to return a constant value.
	"""
	def calc_timeout(msg, ConnectionState[timeout: timeout] = _state) do
		timeout
	end
	


end
