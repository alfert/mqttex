defmodule MqttexTest do
	use ExUnit.Case

	test "the truth" do
		assert(true)
	end

	test "start server and ping it" do
		connection = Mqttex.Connection.new [client_id: "MqttexTest"]
		{Mqttex.ConnAckMsg[], server} = Mqttex.Server.start_link(connection, self)
		assert(is_pid(server))

		ping = Mqttex.PingReqMsg.new
		Mqttex.PingRespMsg[] = Mqttex.Server.ping(server, ping)
	end
end
