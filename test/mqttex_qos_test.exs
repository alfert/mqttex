defmodule MqttexQosTest do
	
	use ExUnit.Case

	test "Fire And Forget" do
		msg = makePublishMsg("x", "nix")
		senderQ = spawn(MqttextSimpleSenderAdapter, :start, [])
		qos = spawn(Mqttex.Qos0Sender, :start, [msg, MqttextSimpleSenderAdapter, self])
		IO.puts "#{__MODULE__}: process is #{inspect self}"
		qos <- :go
		receive do
			any -> assert ^any = :stop 
			after 1000 -> flunk
		end
	end

	test "At Least Once - one time" do

	end


	@doc "Generates lazily a sequence of Publish Msgs"
	def generatePublishMsgs(qos, countStart) do
		
	end
	
	def makePublishMsg(topic, content, qos // :fire_and_forget, id // 0 ) do
		header= Mqttex.FixedHeader.new([qos: qos, message_type: :publish])
		msg= Mqttex.PublishMsg.new([header: header, topic: topic, message: content, id: id ])
		msg
	end
	
end

defmodule MqttextSimpleSenderAdapter do
	
	use ExUnit.Case
	@behaviour Mqttex.SenderBehaviour

	def start() do
		
	end
	
	def send_msg(queue, msg) do
		IO.puts "#{__MODULE__}: send_msg mit msg = #{inspect msg}"
		IO.puts "#{__MODULE__}: process is #{inspect self}"
		# assert ^msg = Mqttex.PublishMsg.new
		queue <- :stop
	end
	
	def send_complete(queue, msg) do
		
	end
	
	def send_release(queue, msg) do
		
	end
	

end