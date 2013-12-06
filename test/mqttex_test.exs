defmodule MqttexTest do
	use ExUnit.Case

	test "the truth" do
		assert(true)
	end

	test "start server and ping it" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		ping = Mqttex.PingReqMsg.new
		assert Mqttex.Server.ping(server, ping) == Mqttex.PingRespMsg[]

		assert Mqttex.Server.stop(server) == :ok
	end

	test "start server and reconnect" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.connect(connection, self)
		assert(is_pid(server))

		dis = Mqttex.DisconnectMsg.new
		assert Mqttex.Server.disconnect(server, dis) == :ok

		{ack, s} = Mqttex.Server.connect(connection, self)
		assert ack == Mqttex.ConnAckMsg.new
		assert s == server

		assert Mqttex.Server.stop(server) == :ok
	end


end
