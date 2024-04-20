defmodule Animina.Accounts.Message do
  @moduledoc """
  This is the Message module which we use to manage messages between users.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: Ash.Policy.Authorizer

  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      constraints max_length: 1_024
      allow_nil? false
    end

    attribute :read_at, :utc_datetime_usec do
      allow_nil? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sender, Animina.Accounts.User do
      api Animina.Accounts
      attribute_writable? true
      allow_nil? false
    end

    belongs_to :receiver, Animina.Accounts.User do
      api Animina.Accounts
      attribute_writable? true
      allow_nil? false
    end
  end

  actions do
    defaults [:create, :read]
  end

  code_interface do
    define_for Animina.Accounts
    define :read
    define :create
    define :by_sender_and_receiver_id, get_by: [:sender_id, :receiver_id], action: :read
  end

  policies do
    policy action_type(:create) do
      authorize_if Animina.Checks.CreateMessageCheck
    end
  end

  postgres do
    table "messages"
    repo Animina.Repo

    references do
      reference :sender, on_delete: :delete
      reference :receiver, on_delete: :delete
    end
  end
end
