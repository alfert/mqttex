defmodule Mqttex.SupClient do
    use Supervisor

    # name of the supervisor process
    @supervisor __MODULE__

    def start_link do
        :supervisor.start_link({:local, @supervisor}, __MODULE__, [])
    end

    def init([]) do
        children = [
            # a simple one for one supervisor has a basic child definition
            # with default arguments for all children, to which the 
            # current arguments are add while calling :supervisor.start_child
            worker(Mqttex.Client, [], restart: :transient)
        ]

        # See http://elixir-lang.org/docs/stable/Supervisor.Behaviour.html
        # for other strategies and supported options
        supervise(children, strategy: :simple_one_for_one)
    end

    @doc """
    Creates a child specification for dynamically attaching a MQTTEX server to 
    the supervisor hierarchy
    """
    def start_client(%Mqttex.Msg.Connection{} = connection, client_proc, network_channel) do
        # IO.puts "start server for #{connection.client_id}"
        :supervisor.start_child @supervisor, [connection, client_proc, network_channel]
    end
  
end
