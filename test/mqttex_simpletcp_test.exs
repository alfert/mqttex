defmodule MqttexSimpleTCPTest do
	use ExUnit.Case
	import Mqttex.Test.Tools

  test "Environment is ok" do
    # env data for the application :mqttex is available
    assert {:ok, 1178} == :application.get_env(:mqttex, :port)

    # Obviously, we are not in the application :mqttex
    assert :undefined == :application.get_env(:port)
    
  end

	test "Basic TCP connections work" do
		server = Mqttex.TCP.start_server
		assert is_pid(server)
		serverRef = Process.monitor server

		con = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
		{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
		assert is_pid(client)

		# Waiting for ConnAck
		# assert_receive(Mqttex.ConnAckMsg[status: :ok], 100, "Still no ConnAck :-(")
		assert_receive(response, 1_000, "Still got no kind of ConnAck msg :-(")
		assert Mqttex.ConnAckMsg[status: :ok] == response

		# Publishing Hello
		Mqttex.Client.publish(client, "topic", "Hello", :fire_and_forget)

		# Disconnecting
		Mqttex.Client.disconnect(client)

		# Server shall go down
		wait_for_shutdown(serverRef)
		refute Process.alive? server

		# Client shall be down
		refute Process.alive? client
	end

	test "Basic TCP re-connections work" do
		server = Mqttex.TCP.start_server
		assert is_pid(server)
		serverRef = Process.monitor server

		conA = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
		{:ok, clientA} = Mqttex.Client.connect("any user", "passwd", self, conA)
		assert is_pid(clientA)
		clientARef = Process.monitor clientA

		# Waiting for ConnAck
		assert_receive(Mqttex.ConnAckMsg[status: :ok], 1_000, "Still no ConnAck :-(")

		# Disconnecting
		Mqttex.Client.disconnect(clientA)
		wait_for_shutdown(clientARef)

		# Client shall be down
		refute Process.alive? clientA

		conB = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
		{:ok, clientB} = Mqttex.Client.connect("any user", "passwd", self, conB)
		assert is_pid(clientB)
		clientBRef = Process.monitor clientB

		# Waiting for ConnAck
		assert_receive(Mqttex.ConnAckMsg[status: :ok], 1_000, "Still no ConnAck :-(")

		# Publishing Hello
		Mqttex.Client.publish(clientB, "topic", "Hello", :fire_and_forget)

		# Disconnecting
		Mqttex.Client.disconnect(clientB)
		wait_for_shutdown(clientBRef)

		# Server shall go down
		wait_for_shutdown(serverRef)
		refute Process.alive? server

		# Client shall be down
		refute Process.alive? clientB
	end


	test "Basic TCP connection, pings and disconnects work" do
		server = Mqttex.TCP.start_server
		assert is_pid(server)
		serverRef = Process.monitor server

		con = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
		{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
		assert is_pid(client)

		# Waiting for ConnAck
		assert_receive(Mqttex.ConnAckMsg[status: :ok], 1_000, "Still no ConnAck :-(")

		# Publishing Hello
		Mqttex.Client.publish(client, "topic", "Hello", :fire_and_forget)

		# Sleep sometime such that the ping mechanisms starts to work
		sleep(2_000)

		# Disconnecting
		Mqttex.Client.disconnect(client)

		# Server shall go down
		assert :ok == wait_for_shutdown(serverRef)
		refute Process.alive? server

		# Client shall be down
		refute Process.alive? client
	end

end
