defmodule Animina.GenServers.ProfileViewCredits do
  use GenServer
  alias Phoenix.PubSub

  @moduledoc """
  This is the genserver that handles the credits added for the profile view
  """

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    PubSub.subscribe(Animina.PubSub, "credits")
    schedule_credits_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:credits_update, state) do
    schedule_credits_update()

    Enum.each(
      state,
      fn %{"points" => points, "user_id" => user_id} ->
        PubSub.broadcast(
          Animina.PubSub,
          "credits:" <> user_id,
          {:display_updated_credits, %{"points" => points, "user_id" => user_id}}
        )
      end
    )

    {:noreply, state}
  end

  def handle_info({:credit_updated, updated_credit}, state) do
    {:noreply, update_array(state, updated_credit)}
  end

  def handle_info({:display_updated_credits, _updated_credit}, state) do
    {:noreply, state}
  end

  defp schedule_credits_update do
    Process.send_after(self(), :credits_update, 2_000)
  end

  def update_array(state, map) do
    case Enum.find(state, fn x -> x["user_id"] == map["user_id"] end) do
      nil ->
        state ++ [map]

      _ ->
        Enum.drop_while(state, fn x -> x["user_id"] == map["user_id"] end)
        |> List.insert_at(0, map)
    end
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def get_updated_credits do
    GenServer.call(__MODULE__, :get)
  end
end
