defmodule Mqttex.Msg do
	defmodule Simple do
		@moduledoc """
		Defines all simple messages as structs. They contain at most a message id.
		"""
		defstruct msg_type: :reserved :: Mqttex.simple_message_type, 
			msg_id: 0 :: integer
	end
	
	@doc """
	Creates a new simple message of type `pub_ack`
	"""
	def pub_ack(msg_id) do
		%Simple{msg_type: :pub_ack, msg_id: msg_id}
	end


end
