defmodule Mqttex do
	use Application.Behaviour

  	# See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  	# for more information on OTP Applications
  	def start(_type, _args) do
  		Mqttex.Supervisor.start_link
  	end
  	def start() do
  		start(:none, :none)  		
  	end
  	

  	def start_client() do
  		IO.puts "Connecting client"
  		con = Mqttex.Client.Connection.new(server: {127, 0, 0, 1}, module: Mqttex.TCP)
  		{:ok, client} = Mqttex.Client.connect("any user", "passwd", self, con)
  		IO.puts("Wating for ConnAck")
  		receive do
  			con_ack -> 
  				IO.puts("Got ConnAck #{inspect con_ack}")
  			after 1_000 -> 
  				IO.puts("Still no ConnAck :-(")
  		end

  		IO.puts("Publishing <Hallo>")
  		Mqttex.Client.publish(client, "topic", "Hallo", :fire_and_forget)

  		IO.puts("I am not disconnected")
  		# Mqttex.Client.disconnect(client)
  		client
  	end
  	


  	@type qos_type :: :fire_and_forget | :at_least_once | :exactly_once
  	@type simple_message_type :: :conn_ack | :pub_ack | 
  						:pub_rec | :pub_comp | :unsub_ack | 
  						:ping_req | :ping_resp | :disconnect | 
						 :reserved
	@type message_type :: simple_message_type | :connect | :publish |
						:pub_rel |  :subscribe | :sub_ack | :unsubscribe  

	@type conn_ack_type :: :ok | :unaccaptable_protocol_version | 
						:identifier_rejected | :server_unavailable | :bad_user |
						:not_authorized 

	# The fixed header of a MQTT message
	defrecord FixedHeader, 
		message_type: :reserved,
		duplicate: false,
		qos: :fire_and_forget,
		retain: false,
		length: 0			

	# The connection information for new connections
	defrecord Connection, 
		client_id: "",
		user_name: "",
		password: "",
		keep_alive: :infinity, # or the keep-alive in milliseconds (=1000*mqtt-keep-alive)
		keep_alive_server: :infinity, # or 1.5 * keep-alive in milliseconds (=1500*mqtt-keep-alive)
		last_will: false,
		will_qos: :fire_and_forget,
		will_retain: false,
		will_topic: "",
		will_message: ""

	# The Connection message
	defrecord ConnectionMsg, header: FixedHeader.new, connection: Connection.new

	# The return code for a connection acknowledgement
	# defrecord ConnAckMsg, status: :ok

	# The publish message
	defrecord PublishMsg, header: FixedHeader.new, topic: "", msg_id: 0, message: ""



	# TODO:
	# Check, if it is a good idea to summarize several messages of the same kind
	# to one struct, e.g. all those with have only the msg_id as value (=> all kinds 
	# of ack-messages) or even only the status flag (ping, conn, disconn).
	# This approach will reduce the number of struct modules and in the best case also 
	# should reduce the number of lines / complexity in the functional modules.

	# The puback message
	# defmodule PubAckMsg do
	#	defstruct msg_id: 0 
	# end

	
	# The pubrec message
	defrecord PubRecMsg, msg_id: 0

	# The pubrel message
	defrecord PubRelMsg, header: FixedHeader.new, msg_id: 0

	# The pubcomp message
	defrecord PubCompMsg, msg_id: 0

	# The Subscribe message
	defrecord SubscribeMsg, header: FixedHeader.new, msg_id: 0, topics: [{"", :fire_and_forget}]

	# The Suback message
	defrecord SubAckMsg, msg_id: 0, granted_qos: []

	# The UnSubscribe message
	defrecord UnSubscribeMsg, header: FixedHeader.new, msg_id: 0, topics: []

	# The UnSubAck message
	#defrecord UnSubAckMsg, msg_id: 0

	# The ping request message (status is only a field to have field, has no semantics)
	defrecord PingReqMsg, status: :ok

	# The ping response message (status is only a field to have field, has no semantics)
	defrecord PingRespMsg, status: :ok

	# The disconnect message (status is only a field to have field, has no semantics)
	defrecord DisconnectMsg, status: :ok
end
