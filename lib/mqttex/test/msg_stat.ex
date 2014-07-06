defmodule Mqttex.Test.MsgStat do
	
	use GenServer
	@my_name __MODULE__

	require Lager

	defstruct messages: 0 :: pos_integer, 
		losses: 0 :: pos_integer

	def start_link() do
		:gen_server.start_link({:local, @my_name}, __MODULE__, [], [])
	end

	def stop() do
		:gen_server.cast(@my_name, :stop)
		Mqttex.Test.Tools.sleep(100)
	end
	
	
	def init([]) do
		Lager.info "Starting MsgStat server"
		{:ok, %Mqttex.Test.MsgStat{}}
	end
	
	def new_msg() do
		:gen_server.cast(@my_name, :new_msg)
	end

	def new_loss() do
		:gen_server.cast(@my_name, :new_loss)	
	end		

	def get_counts() do
		:gen_server.call(@my_name, :get_counts)
	end
	
	def clear() do
		:gen_server.call(@my_name, :clear)
	end
	
	def handle_call(:get_counts, _from, state = %Mqttex.Test.MsgStat{}) do
		{:reply, {state.messages, state.losses}, state}
	end
	def handle_call(:clear, _from, state = %Mqttex.Test.MsgStat{}) do
		{:reply, :ok, %{state | messages: 0, losses: 0}}
	end
	

	def handle_cast(:new_msg, state = %Mqttex.Test.MsgStat{}) do
		{:noreply, Map.update!(state, :messages, fn(count) -> count + 1 end) }
	end
	def handle_cast(:new_loss, state = %Mqttex.Test.MsgStat{}) do
		inc = fn(count) -> count + 1 end
		{:noreply, state |> Map.update!(:messages, inc) |> Map.update!(:losses, inc) }
	end
	def handle_cast(:stop, state) do
		{:stop, :normal, state}
	end	

	def terminate(reason, state) do
		Lager.info "Terminating MsgStag with reason #{inspect reason}"
		:ok
	end
	

end