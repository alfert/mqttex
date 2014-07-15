defmodule Mqttex.Client do
	@moduledoc """
	The client interface to the MQTT Server. 
	"""
	require Lager
	use GenServer
	@my_name __MODULE__
	@default_timeout 500 # 100m milliseconds timeout 

	use Mqttex.SenderBehaviour
	use Mqttex.ReceiverBehaviour

	defmodule Connection do
		defstruct server: "",
			protocol: :tcp,
			port: 1883, 
			module: nil		# a channel module
	end

	defstruct client_proc: :none,
		out_fun: :none,
		timeout: @default_timeout, 
		subscriptions: [],
		senders: %Mqttex.ProtocolManager{}, 
		receivers: %Mqttex.ProtocolManager{}

	###############################################################################
	## API
	###############################################################################

	@doc """
	Creates a new connection and uses the environment configuration. It is discouraged
	to instantiate the `Connection` directly
	"""
	@spec new_connection(binary, atom) :: Connection.t
	def new_connection(server, networkmodule) do
		{:ok, port } = :application.get_env(:mqttex, :port)
		new_connection(server, networkmodule, port)
	end
	@spec new_connection(binary, atom, number) :: Connection.t
	def new_connection(server, networkmodule, port) do
		%Mqttex.Client.Connection{server: server, port: port, module: networkmodule}
	end
	
	

	@doc """
	Connects to an MQTT Server and starts the client process.
	Returns a server id. 

	TODO: Will messages, clean connection? 
	"""
	@spec connect(binary, binary, pid, Connection.t | pid ) :: {:ok, term} | {:error, term} | :ignore
	def connect(client_id \\ "#{inspect self}", username, password, callback_proc, network_channel) do
		connection = Mqttex.Msg.connection(client_id, username, password, true)
		Mqttex.SupClient.start_client(connection, callback_proc, network_channel)
	end

	@doc """
	Disconnects from the MQTT Server
	"""
	def disconnect(server) do
		msg = Mqttex.Msg.disconnect()
		:gen_server.cast(server, {:disconnect, msg})
	end
	
	@doc """
	Subscribes to the list of topics.
	"""
	def subscribe(server, topics) do
		Lager.info ("Client #{inspect server}: Subscribing for topics #{inspect topics}")
		msg = Mqttex.Msg.subscribe(topics)
		:gen_server.cast(server, {:subscribe, msg})
	end
	
	@doc """
	Unsubscribes to a list of topics.
	"""
	def unsubscribe(server, topics) do
		:not_implemented_yet
	end


	@doc """
	Publishes a message with the given topic and qos.
	"""
	def publish(server, topic, message, qos) do
		msg = Mqttex.Msg.publish(topic, message, qos)
		:gen_server.cast(server, {:publish, msg})
	end

	###############################################################################
	## Gen Server Callbacks
	###############################################################################
		
	@spec start_link(Mqttex.Msg.Connection.t, pid, pid | Connection.t) :: {:ok, pid}
	def start_link(%Mqttex.Msg.Connection{} = connection, client_proc \\ self(), network_channel) do
		Lager.info "#{__MODULE__}.start_link for #{connection.client_id}"
		start_result = :gen_server.start_link({:global, "C" <> connection.client_id}, @my_name, 
									{connection, client_proc, network_channel},
									[timeout: connection.keep_alive])
		server = case start_result do
			{:ok, pid} -> pid
			{:error, {:already_started, pid}} -> pid
		end
		send_msg(server, connection)
		{:ok, server}
	end

	@spec init({Mqttex.Msg.Connection.t, pid, pid | Connection.t}) :: {:ok, ClientState.t}
	def init({connection, client_proc, network_channel}) when is_pid(network_channel) do
		out = fn (msg) -> send(network_channel, msg) end
		state = %Mqttex.Client{client_proc: client_proc, out_fun: out}
		{:ok, state, state.timeout}
	end
	def init({connection, client_proc, %Mqttex.Client.Connection{module: mod} = network_channel}) do
		# TODO : make a TCP connection and store a sender function in out

		# use the module in network_channel as callback. Define a 
		# behaviour for the various client network options.

		{channel, out} = mod.start_channel_with_outfun(network_channel, self)
		# out = fn(msg) -> send(channel, msg) end
		state = %Mqttex.Client{client_proc: client_proc, out_fun: out}
		{:ok, state, state.timeout}		
	end
	

	def handle_call({:send, msg}, _from, %Mqttex.Client{out_fun: out_fun} = state) do
		do_send_msg(msg, state)
		{:reply, state.timeout, state, state.timeout}
	end
	
	def handle_cast({:publish, msg}, %Mqttex.Client{senders: senders} = state) do
		new_sender = Mqttex.ProtocolManager.sender(state.senders, msg, __MODULE__, self)
		{:noreply, %Mqttex.Client{state | senders: new_sender}, state.timeout}
	end
	def handle_cast({:on, msg}, %Mqttex.Client{client_proc: client} = state) do
		send(client, msg)
		{:noreply, state, state.timeout}
	end
	def handle_cast({:subscribe, msg}, %Mqttex.Client{senders: senders} = state) do
		new_sender = Mqttex.ProtocolManager.sender(state.senders, msg, __MODULE__, self)
		Lager.info ("Client #{inspect state}: new_sender = #{inspect new_sender}")
		{:noreply, %Mqttex.Client{state | senders: new_sender}, state.timeout}
	end
	def handle_cast({:receive, %Mqttex.Msg.Publish{} = msg}, state) do 
		new_receiver = Mqttex.ProtocolManager.receiver(state.receivers, msg, __MODULE__, self)
		{:noreply, %Mqttex.Client{state | receivers: new_receiver}, state.timeout}
	end
	def handle_cast({:receive, %Mqttex.Msg.Simple{msg_type: :ping_resp} = msg}, state) do
		# nothing to do, timeout is set for starting next ping again
		{:noreply, state, state.timeout}
	end
	def handle_cast({:receive, %Mqttex.Msg.Simple{msg_type: :pub_ack} = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, %Mqttex.Msg.Simple{msg_type: :pub_rec} = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, %Mqttex.Msg.Simple{msg_type: :pub_comp} = msg}, state), do: dispatch_sender(msg, state)
	def handle_cast({:receive, %Mqttex.Msg.PubRel{}  = msg}, state), do: dispatch_receiver(msg, state)
	def handle_cast({:receive, msg = %Mqttex.Msg.SubAck{}}, state), do:  dispatch_sender(msg, state)
	def handle_cast({:receive, msg = %Mqttex.Msg.ConnAck{}}, state) do
		:ok = on_message(self, msg)
		{:noreply, state, state.timeout}
	end
	def handle_cast({:drop_receiver, msg_id}, %Mqttex.Client{receivers: receivers} = state) do
		new_receiver = Mqttex.ProtocolManager.delete(state.receivers, msg_id)
		{:noreply, %Mqttex.Client{state | receivers: new_receiver}, state.timeout}
	end
	def handle_cast({:drop_sender, msg_id}, %Mqttex.Client{senders: senders} = state) do
		new_senders = Mqttex.ProtocolManager.delete(state.senders, msg_id)
		{:noreply, %Mqttex.Client{state | senders: new_senders}, state.timeout}
	end
	def handle_cast({:disconnect, msg}, %Mqttex.Client{senders: senders} = state) do
		# send directly the message and quit the server
		do_send_msg(msg,state)
		{:stop, {:shutdown, :disconnect}, state}
	end
	
	defp dispatch_receiver(msg, %Mqttex.Client{receivers: receivers} = state) do
		:ok = Mqttex.ProtocolManager.dispatch_receiver(receivers, msg)
		{:noreply, state, state.timeout}
	end
	defp dispatch_sender(msg, %Mqttex.Client{senders: senders} = state) do
		r = case Mqttex.ProtocolManager.dispatch_sender(senders, msg) do
			:ok -> :ok
			:error -> 
				Lager.info("dispatch_sender failed with msg=#{inspect msg}")
				Lager.info("   state is #{inspect state}")
				# :error
				:ok
		end
		:ok = r
		{:noreply, state, state.timeout}
	end

	@doc "Initiate a Ping request, if there are no message transfers from/to the server"
	def handle_info(:timeout, %Mqttex.Client{} = state) do
		# start a ping request
		ping = Mqttex.Msg.ping_req
		do_send_msg(ping, state)		
		{:noreply, state, state.timeout}
	end
	def handle_info(msg, state) do
		Lager.error("Client #{inspect self}: Unknown Message received: #{inspect msg}")
		Lager.error("Client #{inspect self}: State #{inspect state}")
		{:noreply, state, state.timeout}
	end

	# Executes the send of a message as internal function
	defp do_send_msg(msg, %Mqttex.Client{out_fun: out_fun} = state) do
		Lager.info("Mqttex.Client.do_send: #{inspect msg}")
		out_fun.(msg)
	end

	def terminate(reason, state) do
		Lager.info("Mqttex.Client.terminate with reason #{inspect reason} in #{inspect state}")
	end
	

	#############################################################################################
	#### API from the Channels
	#############################################################################################

	def receive(server, %Mqttex.Msg.Publish{}= msg), do: do_receive(server, msg)
	def receive(server, %Mqttex.Msg.PubRel{}= msg), do: do_receive(server, msg)
	def receive(server, %Mqttex.Msg.Simple{}= msg), do: do_receive(server, msg)
	def receive(server, %Mqttex.Msg.SubAck{}= msg), do: do_receive(server, msg)
	def receive(server, %Mqttex.Msg.ConnAck{}= msg), do: do_receive(server, msg)
	
	defp do_receive(server, msg) do
		:gen_server.cast(server, {:receive, msg})
	end

	#############################################################################################
	#### Callbacks from QoS Behaviours.
	#### They have not specific functionality but delegate their messages to the `client`.
	#### They have all in common that they send the message via the client process to the 
	#### server nd return a new timeout.
	#############################################################################################
	def send_msg(server, msg),      do: do_send(server, msg)
	def send_received(server, msg), do: do_send(server, msg)
	def send_release(server, msg),  do: do_send(server, msg)
	def send_complete(server, msg), do: do_send(server, msg)
	defp do_send(server, msg) do
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
