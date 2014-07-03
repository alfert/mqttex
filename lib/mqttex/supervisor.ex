defmodule Mqttex.Supervisor do
    use Supervisor

    # name of the supervisor process
    @supervisor __MODULE__

    def start_link do
        :supervisor.start_link({:local, @supervisor}, __MODULE__, [])
    end

    def init([]) do
        children = [
            supervisor(Mqttex.SupClient, [],restart: :permanent),
            supervisor(Mqttex.SupServer, [],restart: :permanent),
            supervisor(Mqttex.SupTopic, [],restart: :permanent),
            worker(Mqttex.TopicManager, [], restart: :permanent)
        ]

        # See http://elixir-lang.org/docs/stable/Supervisor.Behaviour.html
        # for other strategies and supported options
        supervise(children, strategy: :one_for_one)
    end

  
end
