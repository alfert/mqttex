defmodule MqttexTest do
	use ExUnit.Case

	test "a mqttx server is up and running" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest A"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		assert Mqttex.Server.stop(server) == :ok
	end

	test "start server and ping it" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest B"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		ping = Mqttex.PingReqMsg.new
		assert Mqttex.Server.ping(server, ping) == Mqttex.PingRespMsg[]

		assert Mqttex.Server.stop(server) == :ok
	end

	test "start server and reconnect" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest C"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.disconnect(server, dis) == :ok

		{ack, s} = Mqttex.Server.connect(connection, self)
		assert ack == Mqttex.ConnAckMsg.new
		assert s == server

		assert Mqttex.Server.stop(server) == :ok
	end

	test "disconnect server and ping" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest D"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.disconnect(server, dis) == :ok

		ping = Mqttex.PingReqMsg.new	
		assert catch_exit(Mqttex.Server.ping(server, ping)) == {:timeout,  
			{:gen_fsm, :sync_send_event, [server, :ping]}}


		assert Mqttex.Server.stop(server) == :ok
	end


end
