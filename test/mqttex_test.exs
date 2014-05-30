defmodule MqttexTest do
	use ExUnit.Case

	test "A mqttx server is up and running" do
		client_id = "MqttexTest A"
		conMsg = connect(client_id)
		{%Mqttex.Msg.ConnAck{}, server} = Mqttex.Server.connect(conMsg, self)
		assert(is_pid(server))
		ref = Process.monitor server

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "BA start server and ping it with messages" do
		client_id = "MqttexTest A"
		conMsg = connect(client_id)
		{%Mqttex.Msg.ConnAck{}, server} = Mqttex.Server.connect(conMsg, self)
		assert(is_pid(server))
		ref = Process.monitor server

		ping = Mqttex.Msg.ping_req()
		assert Mqttex.Server.receive(server, ping) == :ok

		assert_receive %Mqttex.Msg.Simple{msg_type: :ping_resp}

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	test "CA start server and reconnect with messages" do
		client_id = "MqttexTest A"
		conMsg = connect(client_id)
		{%Mqttex.Msg.ConnAck{}, server} = Mqttex.Server.connect(conMsg, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.Msg.disconnect()
		assert Mqttex.Server.receive(server, dis) == :ok

		{ack, s} = Mqttex.Server.connect(conMsg, self)
		assert ack == Mqttex.Msg.conn_ack
		assert s == server

		assert Mqttex.Server.stop(server) == :ok
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end


	test "DA disconnect server and ping with messages" do
		client_id = "MqttexTest A"
		conMsg = connect(client_id)
		{%Mqttex.Msg.ConnAck{}, server} = Mqttex.Server.connect(conMsg, self)
		assert(is_pid(server))
		ref = Process.monitor server

		dis = Mqttex.Msg.disconnect()
		assert Mqttex.Server.receive(server, dis) == :ok

		ping = Mqttex.Msg.ping_req()
		assert Mqttex.Server.receive(server, ping) == :ok

		assert Mqttex.Server.stop(server) == :ok
		
		wait_for_server_shutdown(ref)
		refute Process.alive? server
	end

	def connect(client_id) do
		Mqttex.Msg.connection(client_id, "", "", true)
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
