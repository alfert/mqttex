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

	
	@spec start_link(Mqttex.Connection.t, pid) :: Mqttex.ConnAckMsg.t | {Mqttex.ConnAckMsg.t, pid}
	def start_link(Mqttex.Connection= connection, client_proc // self()) do
		case :gen_fsm.start_link({:global, connection.client_id}, @my_name, {connection, client_proc}) do
			{:ok, pid}       -> {Mqttex.ConnAckMsg.new[status: :ok], pid}
			{:error, reason} -> Mqttex.ConnAckMsg.new[status: reason]
		end
	end

	@spec ping(Mqttex.PingReqMsg.t) :: Mqttex.PingRespMsg
	def ping(_ping_req) do
		:pong =  :gen_fsm.sync_send_event(@my_name, :ping)
		Mqttex.PingRespMsg.new
	end
	
	@spec disconnect(Mqttex.DisconnectMsg.t) :: :none
	def disconnect(_diconnect_msg) do
		:gen_fsm.send_event(@my_name, :disconnect)
	end


	#### Internal functions

	@doc "Initializes the FSM"
	def init({connection, client_proc}) do
		# TODO: check that the connection data is proper. Invalidity results in {:stop, error_code}, 
		# where error_code is of type conn_ack_type
		{:ok, :clean_session, 
			ConnectionState.new([connection: connection, client_proc: client_proc]), 
			connection.keep_alive_server }
	end

	@doc "Events in state `clean_session` with replies"
	def clean_session(:ping, from, ConnectionState=state) do
		{:reply, :pong, :clean_session, state, state.connection.keep_alive_server}
	end

	@doc "Event in state `clean_session` without a reply"
	def clean_session(:timeout, ConnectionState=state) do
		# TODO: Publish Will Message if required
		# TODO: call unsubscribe all topics
		{:next_state, :clean_disconnect, state}
	end
	def clean_session(:disconnect, ConnectionState=state) do
		# TODO: call unsubscribe all topics
		{:next_state, :clean_disconnect, state}
	end
	


end
