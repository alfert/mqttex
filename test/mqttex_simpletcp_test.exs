defmodule MqttexSimpleTCPTest do
	use ExUnit.Case

	test "Basic TCP connections work" do
		server = Mqttex.TCP.start_server
		assert is_pid(server)
		ref = Process.monitor server

		con = Mqttex.Client.Connection.new(server: {127, 0, 0, 1}, module: Mqttex.TCP)
  		{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
  		assert is_pid(client)

  		# Waiting for ConnAck
  		assert_receive(Mqttex.ConnAckMsg[status: :ok], 100, "Still no ConnAck :-(")

  		# Publishing Hello
  		Mqttex.Client.publish(client, "topic", "Hello", :fire_and_forget)

  		# Disconnecting
  		Mqttex.Client.disconnect(client)

  		# Server shall go down
		wait_for_server_shutdown(ref)
		refute Process.alive? server

		# Client shall be down
		refute Process.alive? client
	end

	def wait_for_server_shutdown(ref) do
		receive do
			{:DOWN, ^ref, _type, _object, _info} ->
				:error_logger.info_msg "Got DOWN message"
			after 1_000 -> 				
				:error_logger.info_msg "Server does exit properly!"
		end		
	end
	

end
