defmodule Mqttex.Server do
	@moduledoc """
	The server implementation of MQTT. It works only Elixir Data Structures and with Erlang/Elixir 
	messages. All TPC/IP handling and en- and decoding of MQTT messages is done in a seperate 
	layer. 

	This approach eases implementation and testing. 
	"""

	use GenServer.Behaviour

	defrecord ConnectionState, connection: :none, client_proc: :none, state: :closed, subscriptions: []

	#### API of the server

	def init(connection, client_proc) do
		# TODO: check that the connection data is proper and check that no other process with this 
		# client id exists. 
		{:ok, ConnectionState.new [connection: connection, client_proc: client_proc, state: :open]}
	end
	
	@spec start_link(Mqttex.Connection.t, pid) -> Mqttex.ConnAckMsg.t
	def start_link(Mqttex.Connection= connection, client_proc // self()) do
		case :gen_server.start_link({:global, connection.client_id}, __MODULE__, [connection, client_proc], []) do
			{:ok, pid}       -> {:ok, pid}
			{:error, reason} -> {reason}
		end
	end



end
