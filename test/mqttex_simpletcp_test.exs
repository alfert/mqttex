defmodule MqttexSimpleTCPTest do
	use ExUnit.Case
	import Mqttex.Test.Tools
	require Lager

	# test "Environment is ok" do
	#     # env data for the application :mqttex is available
	#     assert {:ok, 1178} == :application.get_env(:mqttex, :port)

	#     # Obviously, we are not in the application :mqttex
	#     assert :undefined == :application.get_env(:port) 
	# end

	# test "Basic TCP connections work" do
	# 	server = Mqttex.TCP.start_server
	# 	assert is_pid(server)
	# 	serverRef = Process.monitor server

	# 	con = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
	# 	{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
	# 	assert is_pid(client)

	# 	# Waiting for ConnAck
	# 	# assert_receive(Mqttex.ConnAckMsg[status: :ok], 100, "Still no ConnAck :-(")
	# 	assert_receive(response, 1_000, "Still got no kind of ConnAck msg :-(")
	# 	assert %Mqttex.Msg.ConnAck{status: :ok} == response

	# 	# Publishing Hello
	# 	Mqttex.Client.publish(client, "topic", "Hello", :fire_and_forget)

	# 	# Disconnecting
	# 	Mqttex.Client.disconnect(client)

	# 	# Server shall go down
	# 	wait_for_shutdown(serverRef)
	# 	refute Process.alive? server

	# 	# Client shall be down
	# 	refute Process.alive? client
	# end

	# test "Basic TCP re-connections work" do
	# 	server = Mqttex.TCP.start_server
	# 	assert is_pid(server)
	# 	serverRef = Process.monitor server

	# 	conA = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
	# 	{:ok, clientA} = Mqttex.Client.connect("any user", "passwd", self, conA)
	# 	assert is_pid(clientA)
	# 	clientARef = Process.monitor clientA

	# 	# Waiting for ConnAck
	# 	assert_receive(%Mqttex.Msg.ConnAck{status: :ok}, 1_000, "Still no ConnAck :-(")

	# 	# Disconnecting
	# 	Mqttex.Client.disconnect(clientA)
	# 	wait_for_shutdown(clientARef)

	# 	# Client shall be down
	# 	refute Process.alive? clientA

	# 	conB = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
	# 	{:ok, clientB} = Mqttex.Client.connect("any user", "passwd", self, conB)
	# 	assert is_pid(clientB)
	# 	clientBRef = Process.monitor clientB

	# 	# Waiting for ConnAck
	# 	assert_receive(%Mqttex.Msg.ConnAck{status: :ok}, 1_000, "Still no ConnAck :-(")

	# 	# Publishing Hello
	# 	Mqttex.Client.publish(clientB, "topic", "Hello", :fire_and_forget)

	# 	# Disconnecting
	# 	Mqttex.Client.disconnect(clientB)
	# 	wait_for_shutdown(clientBRef)

	# 	# Server shall go down
	# 	wait_for_shutdown(serverRef)
	# 	refute Process.alive? server

	# 	# Client shall be down
	# 	refute Process.alive? clientB
	# end


	# test "Basic TCP connection, pings and disconnects work" do
	# 	server = Mqttex.TCP.start_server
	# 	assert is_pid(server)
	# 	serverRef = Process.monitor server

	# 	con = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
	# 	{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
	# 	assert is_pid(client)

	# 	# Waiting for ConnAck
	# 	assert_receive(%Mqttex.Msg.ConnAck{status: :ok}, 1_000, "Still no ConnAck :-(")

	# 	# Publishing Hello
	# 	Mqttex.Client.publish(client, "topic", "Hello", :fire_and_forget)

	# 	# Sleep sometime such that the ping mechanisms starts to work
	# 	sleep(2_000)

	# 	# Disconnecting
	# 	Mqttex.Client.disconnect(client)

	# 	# Server shall go down
	# 	assert :ok == wait_for_shutdown(serverRef)
	# 	refute Process.alive? server

	# 	# Client shall be down
	# 	refute Process.alive? client
	# end

	########################
	#### Define an end2end Test with 
	#### 2 clients, 1 server
	#### a publish and a subscribe
	#### to show that messages arrive at the subscriber
	########################
	
	test "TCP connection, subscribe and publishing works" do
		Lager.info("Subscribe test starts")
		server = Mqttex.TCP.start_server
		assert is_pid(server)
		serverRef = Process.monitor server

		tester = self()

		con = Mqttex.Client.new_connection({127, 0, 0, 1}, Mqttex.TCP)
		{:ok, sub} = Mqttex.Client.connect("client-sub", "any user", "passwd", 
			spawn_link(fn -> transmitter(:sub, tester) end), con)
		assert is_pid(sub)

		# Waiting for ConnAck
		assert_receive({:sub, %Mqttex.Msg.ConnAck{status: :ok}}, 2_000, "Still no ConnAck :-(")

		# Subscribe to topic `topic`
		:ok = Mqttex.Client.subscribe(sub, [{"topic", :fire_and_forget}])

		{:ok, pub} = Mqttex.Client.connect("client-pub", "any user", "passwd", 
			spawn_link(fn -> transmitter(:pub, tester) end), con)
		assert is_pid(pub)

		# Waiting for ConnAck
		assert_receive({:pub, %Mqttex.Msg.ConnAck{status: :ok}}, 1_000, "Still no ConnAck :-(")
			
		# Publishing Hello
		:ok = Mqttex.Client.publish(pub, "topic", "Hello", :fire_and_forget)

		# Waiting
		receive do
			message -> Lager.info "Got a message: #{inspect message} Is it a good one?"
			after 1_000 -> flunk "got nothing from publishing"
		end
		# Sleep sometime such that the ping mechanisms starts to work
		# sleep(2_000)

		# Disconnecting pub & sub
		Mqttex.Client.disconnect(pub)
		Mqttex.Client.disconnect(sub)

		# Server shall go down
		assert :ok == wait_for_shutdown(serverRef)
		refute Process.alive? server

		# Clients shall be down
		refute Process.alive? sub
		refute Process.alive? pub
	end

	# a process which sends all received messages to `target` but prefixed with `prefix`
	def transmitter(prefix, target) do
		receive do
			msg -> 
				Lager.info ("Transmitter #{inspect prefix} got message #{inspect msg} for target #{inspect target}")
				send(target, {prefix, msg})
				transmitter(prefix, target)
		end
	end
	

end
