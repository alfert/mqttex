defmodule Mqttex.Client do
	@moduledoc """
	The client interface to the MQTT Server. 
	"""

	use GenServer.Behaviour
	@my_name __MODULE__
	@default_timeout 500 # 100m milliseconds timeout 

	use Mqttex.SenderBehaviour
	use Mqttex.ReceiverBehaviour

	defrecord Connection, 
		server: "",
		protocol: :tcp,
		port: 1178, 
		module: nil		# a channel module

	defrecord ClientState, 
		client_proc: :none,
		out_fun: :none,
		timeout: @default_timeout, 
		subscriptions: [],
		senders: Mqttex.ProtocolManager.new(), 
		receivers: Mqttex.ProtocolManager.new()

	###############################################################################
	## API
	###############################################################################

	@doc """
	Connects to an MQTT Server and starts the client process.
	Returns a server id. 

	TODO: Will messages, clean connection? 
	"""
	@spec connect(binary, binary, pid, Connection.t | pid ) :: {:ok, term} | {:error, term} | :ignore
	def connect(username, password, callback_proc, network_channel) do
		connection = Mqttex.Connection.new([user_name: username, 
			password: password, client_id: "client #{inspect self}"])
		Mqttex.SupClient.start_client(connection, callback_proc, network_channel)
	end

	@doc """
	Disconnects from the MQTT Server
	"""
	def disconnect(server) do
		msg = Mqttex.DisconnectMsg.new
		:gen_server.cast(server, {:disconnect, msg})
	end
	
	@doc """
	Subscribes to the list of topics.
	"""
	def subscribe(server, topics) do
		
	end
	
	@doc """
	Unsubscribes to a list of topics.
	"""
	def unsubscribe(server, topics) do
		
	end


	@doc """
	Publishes a message with the given topic and qos.
	"""
	def publish(server, topic, message, qos) do
		header = Mqttex.FixedHeader.new([qos: qos])
		msg = Mqttex.PublishMsg.new([header: header, topic: topic, message: message])
		:gen_server.cast(server, {:publish, msg})
	end

	###############################################################################
	## Gen Server Callbacks
	###############################################################################
		
	@spec start_link(Mqttex.Connection.t, pid, pid | Connection.t) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def start_link(Mqttex.Connection[] = connection, client_proc \\ self(), network_channel) do
		:error_logger.info_msg "#{__MODULE__}.start_link for #{connection.client_id}"
		start_result = :gen_server.start_link({:global, "C" <> connection.client_id}, @my_name, 
									{connection, client_proc, network_channel},
									[timeout: connection.keep_alive_server])
		server = case start_result do
			{:ok, pid} -> pid
			{:error, {:already_started, pid}} -> pid
		end
		con_msg = Mqttex.ConnectionMsg.new([connection: connection])
		send_msg(server, con_msg)
		{:ok, server}
	end

	@spec init({Mqttex.Connection.t, pid, pid | Connection.t}) :: {:ok, ClientState.t}
	def init({connection, client_proc, network_channel}) when is_pid(network_channel) do
		out = fn (msg) -> send(network_channel, msg) end
		state = ClientState.new([client_proc: client_proc, out_fun: out])
		{:ok, state, state.timeout}
	end
	def init({connection, client_proc, Connection[module: mod] = network_channel}) do
		# TODO : make a TCP connection and store a sender function in out

		# use the module in network_channel as callback. Define a 
		# behaviour for the various client network options.

		channel = mod.start_channel(network_channel, self)
		out = fn(msg) -> send(channel, msg) end
		state = ClientState.new([client_proc: client_proc, out_fun: out])
		{:ok, state, state.timeout}		
	end
	

	def handle_call({:send, msg}, _from, ClientState[out_fun: out_fun] = state) do
		do_send_msg(msg, state)
		{:reply, state.timeout, state, state.timeout}
	end
	
	def handle_cast({:publish, msg}, ClientState[senders: senders] = state) do
		new_sender = Mqttex.ProtocolManager.sender(state.senders, msg, __MODULE__, self)
		{:noreply, state.update(senders: new_sender), state.timeout}
	end
	def handle_cast({:on, msg}, ClientState[client_proc: client] = state) do
		send(client, msg)
		{:noreply, state, state.timeout}
	end
	def handle_cast({:receive, Mqttex.PublishMsg[] = msg}, state) do 
		new_receiver = Mqttex.ProtocolManager.receiver(state.receivers, msg, __MODULE__, self)
		{:noreply, state.update(receivers: new_receiver), state.timeout}
	end
	def handle_cast({:receive, Mqttex.PubAckMsg[] = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, Mqttex.PubRecMsg[] = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, Mqttex.PubCompMsg[] = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, Mqttex.PubRelMsg[] = msg}, state), do: dispatch_receiver(msg, state)
	def handle_cast({:receive, Mqttex.PingRespMsg[] = msg}, state) do
		# nothing to do, timeout is set for starting next ping again
		{:noreply, state, state.timeout}
	end
	def handle_cast({:receive, Mqttex.ConnAckMsg[] = msg}, state) do
		:ok = on_message(self, msg)
		{:noreply, state, state.timeout}
	end
	def handle_cast({:drop_receiver, msg_id}, ClientState[receivers: receivers] = state) do
		new_receiver = Mqttex.ProtocolManager.delete(state.receivers, msg_id)
		{:noreply, state.update(receivers: new_receiver), state.timeout}
	end
	def handle_cast({:drop_sender, msg_id}, ClientState[senders: senders] = state) do
		new_sender = Mqttex.ProtocolManager.delete(state.senders, msg_id)
		{:noreply, state.update(sender: new_sender), state.timeout}
	end
	def handle_cast({:disconnect, msg}, ClientState[senders: senders] = state) do
		# send directly the message and quit the server
		do_send_msg(msg,state)
		{:stop, {:shutdown, :disconnect}, state}
	end
	
	defp dispatch_receiver(msg, ClientState[receivers: receivers] = state) do
		:ok = Mqttex.ProtocolManager.dispatch_receiver(receivers, msg)
		{:noreply, state, state.timeout}
	end
	defp dispatch_sender(msg, ClientState[senders: senders] = state) do
		:ok = Mqttex.ProtocolManager.dispatch_sender(senders, msg)
		{:noreply, state, state.timeout}
	end

	@doc "Initiate a Ping request, if there are no message transfers from/to the server"
	def handle_info(:timeout, ClientState[] = state) do
		# start a ping request
		ping = Mqttex.PingReqMsg.new
		do_send_msg(ping, state)		
		{:noreply, state, state.timeout}
	end
	def handle_info(msg, state) do
		:error_logger.error_msg("Client #{inspect self}: Unknown Message received: #{inspect msg}")
		:error_logger.error_msg("Client #{inspect self}: State #{inspect state}")
		{:noreply, state, state.timeout}
	end

	# Executes the send of a message as internal function
	defp do_send_msg(msg, ClientState[out_fun: out_fun] = state) do
		:error_logger.info_msg("Mqttex.Client.do_send: #{inspect msg}")
		out_fun.(msg)
	end

	def terminate(reason, state) do
		:error_logger.info_msg("Mqttex.Client.terminate with reason #{inspect reason} in #{inspect state}")
	end
	

	#############################################################################################
	#### API from the Channels
	#############################################################################################

	def receive(server, Mqttex.PublishMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PubAckMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PubRecMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PubRelMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PubCompMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.PingRespMsg[]= msg), do: do_receive(server, msg)
	def receive(server, Mqttex.ConnAckMsg[]= msg), do: do_receive(server, msg)
	
	defp do_receive(server, msg) do
		:gen_server.cast(server, {:receive, msg})
	end

	#############################################################################################
	#### Callbacks from QoS Behaviours
	#############################################################################################
	@doc """
	Sends a messages to the server side and returns the new timeout. Only called from a QoS protocol 
	process, not part of the general API.  
	"""
	def send_msg(server, msg) do
		:gen_server.call(server, {:send, msg})
	end
	@doc """
	Sends the received message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_received(server, msg) do
		:gen_server.call(server, {:send, msg})
	end
	@doc """
	Sends the release message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_release(server, msg) do
		:gen_server.call(server, {:send, msg})
	end
	@doc """
	Sends the complete message and returns the new timeout. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def send_complete(server, msg) do
		:gen_server.call(server, {:send, msg})
	end
	@doc """
	Finishes a sender protocol process. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def finish_sender(server, msg_id) do
		:gen_server.cast(server, {:drop_sender, msg_id})
	end
	@doc """
	Finishes a receiver protocol process. Only called from a QoS protocol process, 
	not part of the general API.
	"""
	def finish_receiver(server, msg_id) do
		:gen_server.cast(server, {:drop_receiver, msg_id})
	end
	
	@doc """
	Finally receives the regular message for delivery to a topic. Only called from a QoS 
	protocol process, not part of the general API.
	"""
	def on_message(server, msg) do
		:gen_server.cast(server, {:on, msg})		
	end

end
