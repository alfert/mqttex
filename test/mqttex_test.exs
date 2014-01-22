defmodule MqttexTest do
	use ExUnit.Case

	test "A mqttx server is up and running" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "B start server and ping it" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		ping = Mqttex.PingReqMsg.new
		assert Mqttex.Server.ping(server, ping) == Mqttex.PingRespMsg[]

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "BA start server and ping it with messages" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		ping = Mqttex.PingReqMsg.new
		assert Mqttex.Server.receive(server, ping) == :ok

		assert_receive Mqttex.PingRespMsg[]

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "C start server and reconnect" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.disconnect(server, dis) == :ok

		{ack, s} = Mqttex.Server.connect(connection, self)
		assert ack == Mqttex.ConnAckMsg.new
		assert s == server

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "CA start server and reconnect with messages" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.receive(server, dis) == :ok

		{ack, s} = Mqttex.Server.connect(connection, self)
		assert ack == Mqttex.ConnAckMsg.new
		assert s == server

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "D disconnect server and ping" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.disconnect(server, dis) == :ok

		ping = Mqttex.PingReqMsg.new	
		assert catch_exit(Mqttex.Server.ping(server, ping)) == {:timeout,  
			{:gen_fsm, :sync_send_event, [server, :ping]}}

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "DA disconnect server and ping with messages" do
		client_id = "MqttexTest A"
		connection = Mqttex.Connection.new [client_id: client_id]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.receive(server, dis) == :ok

		ping = Mqttex.PingReqMsg.new	
		assert Mqttex.Server.receive(server, ping) == :ok

		assert Mqttex.Server.stop(server) == :ok
		
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	def wait_for_server_shutdown(ref) do
		receive do
			{:DOWN, ^ref, type, object, info} ->
				:error_logger.info_msg "Got DOWN message"
			after 1_000 -> 				
				:error_logger.info_msg "Server does exit properly!"
		end		
	end
	

end
