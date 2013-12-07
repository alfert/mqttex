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

	defrecord ConnectionState, connection: :none, client_proc: :none, subscriptions: []

	#### API of the server
	@doc """
	Connects the client with the server process. If no server for the `client_id` exists, 
	then a new server is started and linked to the supervisor tree. If the server already 
	exists, we have a reconnection situation: if the server is in state `disconnected` 
	the reconnection can be executed. Otherwise an error occurs.
	"""
	@spec connect(Mqttex.Connection.t, pid) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def connect(Mqttex.Connection[] = connection, client_proc // self()) do
		case :global.whereis_name(connection.client_id) do
			:undefined -> start_link(connection, client_proc)
			pid -> reconnect(pid, connection, client_proc)
		end
	end

	# Reconnects an existing server with a new connection
	defp reconnect(server, connection, client_proc) do
		case :gen_fsm.sync_send_event(server, {:reconnect, connection, client_proc}) do
			{:ok, pid}       -> {Mqttex.ConnAckMsg.new([status: :ok]), pid}
			{:error, reason} -> Mqttex.ConnAckMsg.new [status: reason]
		end
	end
	
	@spec start_link(Mqttex.Connection.t, pid) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def start_link( Mqttex.Connection[] = connection, client_proc // self()) do
		case :gen_fsm.start_link({:global, connection.client_id}, @my_name, {connection, client_proc},
									[timeout: connection.keep_alive_server]) do
			{:ok, pid}       -> {Mqttex.ConnAckMsg.new([status: :ok]), pid}
			{:error, reason} -> Mqttex.ConnAckMsg.new [status: reason]
		end
	end

	@spec ping(pid, Mqttex.PingReqMsg.t) :: Mqttex.PingRespMsg
	def ping(server, Mqttex.PingReqMsg[] = _ping_req) do
		:pong =  :gen_fsm.sync_send_event(server, :ping)
		Mqttex.PingRespMsg.new
	end
	
	@spec disconnect(pid, Mqttex.DisconnectMsg.t) :: :ok
	def disconnect(server, _diconnect_msg) do
		:gen_fsm.send_event(server, :disconnect)
	end

	@doc "Internal function for stopping the server"
	@spec stop(pid) :: :ok
	def stop(server) do
		:gen_fsm.send_all_state_event(server, :stop)
	end
	

	#### Internal functions

	@doc "Initializes the FSM"
	def init({connection, client_proc}) do
		# TODO: check that the connection data is proper. Invalidity results in {:stop, error_code}, 
		# where error_code is of type conn_ack_type
		IO.puts "#{__MODULE__}.init"
		{:ok, :clean_session, 
			ConnectionState.new([connection: connection, client_proc: client_proc]), 
			connection.keep_alive_server }
	end

	@doc "Events in state `clean_session` with replies"
	def clean_session(:ping, _from, ConnectionState[]=state) do
		{:reply, :pong, :clean_session, state, state.connection.keep_alive_server}
	end

	@doc "Event in state `clean_session` without a reply"
	def clean_session(:timeout, ConnectionState[]=state) do
		# TODO: Publish Will Message if required
		# TODO: call unsubscribe all topics

		# no timeout here, we wait forever
		{:next_state, :clean_disconnect, state}
	end
	def clean_session(:disconnect, ConnectionState[]=state) do
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
		

	@doc "Checks the connection"
	@spec check_connection(Mqttex.Connection.t) :: Mqttex.conn_ack_type
	def check_connection(Mqttex.Connection[client_id: c_id]) 
		when length(c_id)> 26, do: :identifier_rejected
	def check_connection(Mqttex.Connection[] = _connection) do
		# TODO: check authentication
		:ok
	end
	


end
