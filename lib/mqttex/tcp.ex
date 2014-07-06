defmodule Mqttex.TCP do
	require Lager


	@moduledoc """
	This module provides network connectivity with Erlang's standard TCP libraries (i.e. `gen_tcp`).
	"""


	@doc """
	Starts a server socket at port `port` and connect it with the MQTT `server`. 
	Uses the default port from the application environment (usually port 1883)
	"""
	def start_server() do
		{:ok, port} = :application.get_env(:mqttex, :port)
		start_server(port)
	end
	
	def start_server(port) do
		{:ok, listen} = :gen_tcp.listen(port, [:binary, {:packet, 4},
											 {:reuseaddr, true},	
											 {:active, true}])
		Lager.info("Mqttex.Server at port #{port} is listening")
		spawn(fn() -> spawn_acceptor(listen) end)
	end

	defp spawn_acceptor(listen) do
		Lager.info("#{inspect self}: starting spawn_acceptor(#{inspect listen}")
		case :gen_tcp.accept(listen) do
			{:ok, socket} -> 
				Lager.info("Mqttex.Server has accepted and spawns new acceptor")
				spawn(fn() -> spawn_acceptor(listen) end)
				loop(socket, :nil, Mqttex.Server)				
			any -> Lager.info("accecpt returned #{inspect any} - finishing now")
		end
	end
	
	@doc """
	Starts a client socket connecting to `server` at `port`. The client process
	is `client`.
	"""
	def start_client(server, port, client) do
		{:ok, socket} = :gen_tcp.connect(server, port, [:binary, {:packet, 4}])
		loop(socket, client, Mqttex.Client)
	end
	

	@doc """
	Starts a new channel and returns its process id.
	"""
	def start_channel(%Mqttex.Client.Connection{server: server, port: port} = _con, client) do
		looper = fn() -> 
				{:ok, socket} = :gen_tcp.connect(server, port, [:binary, {:packet, 4}])
				loop(socket, client, Mqttex.Client)
			end
		spawn_link(looper)
	end
	

	@doc """
	Socket loop
	"""
	def loop(socket, server, mod) do
		Lager.debug("loop #{inspect self} for #{inspect socket} and process #{inspect server} with module #{mod}")
		receive do
			{:tcp, ^socket, bin} ->
				Lager.debug("loop #{inspect self}: Socket received binary = #{inspect bin}")
				str = :erlang.binary_to_term(bin)
				Lager.debug("loop #{inspect self}: Socket (unpacked) #{inspect str}")
				# call the server
				case str do
					%Mqttex.Msg.Connection{} = con -> 
						do_connect(socket, con, mod)
					_ ->
						mod.receive(server, str)
						loop(socket, server, mod)
				end
			{:tcp_closed, ^socket} ->
				Lager.info("loop #{inspect self}: Socket #{inspect socket} closed")
			msg ->
				Lager.info("loop #{inspect self}: Socket #{inspect socket} sends message #{inspect msg}")
				:gen_tcp.send(socket, :erlang.term_to_binary(msg))
				loop(socket, server, mod)
		end
	end


	@doc """
	Start the server and sends the acknowledgement to the socket 
	(either with an error, closing the socket, or with the `:ok`) 
	"""
	def do_connect(socket, %Mqttex.Msg.Connection{} = con, mod) do
		Lager.info("TCP.do_connect self=#{inspect self} and con = #{inspect con}")
		case Mqttex.Server.connect(con, self) do
			{msg, server_pid} -> 
				send(self, msg)	
				loop(socket, server_pid, mod)
			error -> :gen_tcp.send(socket, :erlang.term_to_binary(error))
		end
	end

end