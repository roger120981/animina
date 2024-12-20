defmodule AniminaWeb.StoryLive do
  alias Animina.ChatCompletion
  use AniminaWeb, :live_view

  alias Animina.Accounts.Photo
  alias Animina.Accounts.Points
  alias Animina.Accounts.User
  alias Animina.GenServers.ProfileViewCredits
  alias Animina.Narratives
  alias Animina.Narratives.Headline
  alias Animina.Narratives.Story
  alias Animina.PathHelper
  alias AshPhoenix.Form
  alias Phoenix.PubSub

  @impl true
  def mount(%{"id" => story_id}, %{"language" => language} = _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Animina.PubSub, "credits")
      PubSub.subscribe(Animina.PubSub, "messages")

      PubSub.subscribe(
        Animina.PubSub,
        "#{socket.assigns.current_user.id}"
      )
    end

    story = Story.by_id!(story_id)

    reasons = [
      with_locale(language, fn -> gettext("Fix spelling and grammar errors") end)
    ]

    socket =
      socket
      |> assign(language: language)
      |> assign(story: story)
      |> assign(active_tab: :home)
      |> assign(:photo, story.photo)
      |> assign(:story_position, nil)
      |> assign(:headline_position, nil)
      |> assign(:current_request, nil)
      |> assign(:errors, [])
      |> assign(:reasons, reasons)
      |> assign(:current_request, nil)
      |> assign(:content, story.content)
      |> assign(:headlines, get_user_headlines(socket))
      |> assign(:default_headline, nil)
      |> assign(:show_buttons, true)
      |> assign(:generating_story, false)
      |> assign(
        :message_when_generating_story,
        with_locale(language, fn ->
          gettext("Feeding our internal AI with this text. Please wait a second")
        end)
      )
      |> assign(:words, String.length(story.content))
      |> allow_upload(:photos, accept: ~w(.jpg .jpeg .png), max_entries: 1, id: "photo_file")

    {:ok, socket}
  end

  @impl true
  def mount(_params, %{"language" => language} = _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(Animina.PubSub, "credits")
      PubSub.subscribe(Animina.PubSub, "messages")

      PubSub.subscribe(
        Animina.PubSub,
        "#{socket.assigns.current_user.id}"
      )
    end

    reasons = [
      with_locale(language, fn -> gettext("Fix spelling and grammar errors") end)
    ]

    socket =
      socket
      |> assign(language: language)
      |> assign(active_tab: :home)
      |> assign(
        :photo,
        get_user_default_photo(socket)
      )
      |> assign(
        :story_position,
        get_user_story_position(socket)
      )
      |> assign(:reasons, reasons)
      |> assign(
        :headline_position,
        get_user_headline_position(socket)
      )
      |> assign(:errors, [])
      |> assign(:content, "")
      |> assign(:words, 0)
      |> assign(:current_request, nil)
      |> assign(:generating_story, false)
      |> assign(:show_buttons, true)
      |> assign(
        :message_when_generating_story,
        with_locale(language, fn ->
          gettext("Feeding our internal AI with this text. Please wait a second")
        end)
      )
      |> assign(:headlines, get_user_headlines(socket))
      |> assign(:default_headline, get_default_headline(socket))
      |> allow_upload(:photos, accept: ~w(.jpg .jpeg .png), max_entries: 1, id: "photo_file")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({:display_updated_credits, credits}, socket) do
    current_user_credit_points =
      ProfileViewCredits.get_updated_credit_for_current_user(socket.assigns.current_user, credits)
      |> Points.humanized_points()

    {:noreply,
     socket
     |> assign(current_user_credit_points: current_user_credit_points)}
  end

  @impl true
  def handle_info({:credit_updated, _updated_credit}, socket) do
    {:noreply, socket}
  end

  def handle_info({:user, current_user}, socket) do
    if current_user.state in user_states_to_be_auto_logged_out() do
      {:noreply,
       socket
       |> push_navigate(to: "/auth/user/sign-out?auto_log_out=#{current_user.state}")}
    else
      {:noreply, socket |> assign(:current_user, current_user)}
    end
  end

  def handle_info({:new_message, message}, socket) do
    unread_messages = socket.assigns.unread_messages ++ [message]

    {:noreply,
     socket
     |> assign(unread_messages: unread_messages)
     |> assign(number_of_unread_messages: Enum.count(unread_messages))}
  end

  @impl true
  def handle_info({request_pid, {:data, %{"done" => false, "response" => chunk}}}, socket) do
    updated_params =
      Map.update!(socket.assigns.form.params, "content", fn content ->
        content <> chunk
      end)

    socket =
      case socket.assigns.current_request do
        %{pid: ^request_pid} ->
          socket
          |> assign(:generating_story, false)
          |> assign(:words, String.length(updated_params["content"]))
          |> assign(:form, Form.validate(socket.assigns.form, updated_params))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({request_pid, {:data, %{"done" => true, "response" => _response}}}, socket) do
    socket =
      case socket.assigns.current_request do
        %{pid: ^request_pid} ->
          socket
          |> assign(:current_request, nil)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:render_generating_story, count}, socket) do
    if socket.assigns.generating_story do
      new_message =
        case count do
          1 -> "."
          2 -> "."
          3 -> "."
          _ -> "."
        end

      message_when_generating_story = socket.assigns.message_when_generating_story <> new_message

      Process.send_after(self(), {:render_generating_story, rem(count + 1, 4)}, 1000)

      if count == 1 do
        {:noreply,
         assign(
           socket,
           :message_when_generating_story,
           with_locale(socket.assigns.language, fn ->
             gettext("Feeding our internal AI with this text. Please wait a second ")
           end)
         )}
      else
        {:noreply, assign(socket, :message_when_generating_story, message_when_generating_story)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply,
     socket
     |> assign(:show_buttons, true)}
  end

  defp apply_action(socket, :edit, _params) do
    form =
      Form.for_update(socket.assigns.story, :update,
        domain: Narratives,
        as: "story",
        forms: [
          photo: [
            resource: Photo,
            create_action: :create
          ]
        ]
      )
      |> AshPhoenix.Form.add_form([:photo], validate?: false)
      |> to_form()

    socket
    |> assign(
      page_title: with_locale(socket.assigns.language, fn -> gettext("Edit your story") end)
    )
    |> assign(form_id: "edit-story-form")
    |> assign(title: with_locale(socket.assigns.language, fn -> gettext("Edit your story") end))
    |> assign(:image_required, false)
    |> assign(
      :either_content_or_photo_added,
      either_content_or_photo_added(socket.assigns.story.content, [], "")
    )
    |> assign(:cta, with_locale(socket.assigns.language, fn -> gettext("Save story") end))
    |> assign(
      info_text:
        with_locale(socket.assigns.language, fn ->
          gettext("Use stories to tell potential partners about yourself")
        end)
    )
    |> assign(form: form)
  end

  defp apply_action(socket, :about_me, _params) do
    form =
      Form.for_create(Story, :create,
        domain: Narratives,
        as: "story",
        forms: [
          photo: [
            resource: Photo,
            create_action: :create
          ]
        ]
      )
      |> AshPhoenix.Form.add_form([:photo], validate?: false)
      |> to_form()

    update_last_registration_page_visited(socket.assigns.current_user, "/my/about-me")

    if user_has_an_about_me_story?(socket.assigns.current_user) do
      about_me_story =
        get_stories_for_a_user(socket.assigns.current_user)
        |> Enum.find(fn story ->
          story.headline.subject == "About me"
        end)

      socket
      |> push_navigate(to: "/my/stories/#{about_me_story.id}/edit")
    else
      socket
      |> assign(
        page_title:
          with_locale(socket.assigns.language, fn -> gettext("Create your first story") end)
      )
      |> assign(form_id: "create-story-form")
      |> assign(
        title: with_locale(socket.assigns.language, fn -> gettext("Create your first story") end)
      )
      |> assign(
        :cta,
        with_locale(socket.assigns.language, fn -> gettext("Create about me story") end)
      )
      |> assign(:either_content_or_photo_added, either_content_or_photo_added("", [], :about_me))
      |> assign(:image_required, true)
      |> assign(
        info_text:
          with_locale(socket.assigns.language, fn ->
            gettext("Use stories to tell potential partners about yourself")
          end)
      )
      |> assign(form: form)
    end
  end

  defp apply_action(socket, _, _params) do
    form =
      Form.for_create(Story, :create,
        domain: Narratives,
        as: "story",
        forms: [
          photo: [
            resource: Photo,
            create_action: :create
          ]
        ]
      )
      |> AshPhoenix.Form.add_form([:photo], validate?: false)
      |> to_form()

    socket
    |> assign(
      page_title: with_locale(socket.assigns.language, fn -> gettext("Create a story") end)
    )
    |> assign(image_required: false)
    |> assign(form_id: "create-story-form")
    |> assign(
      title: with_locale(socket.assigns.language, fn -> gettext("Create your own story") end)
    )
    |> assign(:either_content_or_photo_added, either_content_or_photo_added("", [], ""))
    |> assign(:cta, with_locale(socket.assigns.language, fn -> gettext("Create new story") end))
    |> assign(
      info_text:
        with_locale(socket.assigns.language, fn ->
          gettext("Use stories to tell potential partners about yourself")
        end)
    )
    |> assign(form: form)
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:photos, ref)
     |> assign(
       :either_content_or_photo_added,
       either_content_or_photo_added(socket.assigns.content, [], "")
     )}
  end

  def handle_event("toggle_reason", %{"_target" => [reason]}, socket) do
    reasons = socket.assigns.reasons

    new_reasons = update_reasons(reasons, reason)

    new_reasons =
      if Enum.member?(reasons, reason) do
        new_reasons
      else
        reject_conflicting_reasons(new_reasons, reason)
      end

    {:noreply, assign(socket, :reasons, new_reasons)}
  end

  @impl true
  def handle_event("validate", %{"story" => story}, socket) do
    form = Form.validate(socket.assigns.form, story, errors: true)

    content =
      Map.get(story, "content")

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(
       :either_content_or_photo_added,
       either_content_or_photo_added(
         content,
         socket.assigns.uploads.photos.entries,
         socket.assigns.live_action
       )
     )
     |> assign(:words, String.length(content))
     |> assign(:content, content)}
  end

  @impl true
  def handle_event("submit", %{"story" => story}, socket) do
    form =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        filename = entry.uuid <> "." <> ext(entry)

        dest =
          PathHelper.uploads_path()
          |> Path.join(Path.basename(filename))

        File.cp!(path, dest)

        {:ok,
         %{
           "filename" => filename,
           "original_filename" => entry.client_name,
           "ext" => ext(entry),
           "mime" => entry.client_type,
           "size" => entry.client_size
         }}
      end)
      |> case do
        [] ->
          Form.remove_form(socket.assigns.form, [:photo])

        [%{} = file] ->
          photo = Map.get(story, "photo") |> Map.merge(file)
          story = Map.merge(story, %{"photo" => photo})

          delete_or_remove_photo_from_story(story, socket.assigns.photo)

          Form.validate(socket.assigns.form, story)
      end

    with [] <- Form.errors(form), {:ok, story} <- Form.submit(form) do
      if form.params["photo"] do
        Ash.Changeset.for_create(
          Photo,
          :create,
          Map.put(form.params["photo"], "story_id", story.id)
        )
        |> Ash.create()

        {:noreply,
         socket
         |> assign(:errors, [])
         |> assign(
           :form,
           nil
         )
         |> push_navigate(to: ~p"/#{socket.assigns.current_user.username}")}
      else
        {:noreply,
         socket
         |> assign(:errors, [])
         |> assign(
           :form,
           nil
         )
         |> push_navigate(to: ~p"/#{socket.assigns.current_user.username}")}
      end
    else
      {:error, form} ->
        {:noreply, socket |> assign(:form, form)}

      errors ->
        {:noreply, socket |> assign(:errors, errors)}
    end
  end

  def handle_event("delete_photo", _params, socket) do
    Photo.destroy(socket.assigns.photo)

    {:noreply,
     socket
     |> put_flash(
       :info,
       with_locale(socket.assigns.language, fn -> gettext("Photo removed successfully !") end)
     )
     |> push_navigate(to: ~p"/my/stories/#{socket.assigns.story.id}/edit")}
  end

  def handle_event("generate_story", _params, socket) do
    process_story(
      socket,
      socket.assigns.reasons,
      socket.assigns.live_action
    )
  end

  defp update_reasons(reasons, reason) do
    if Enum.member?(reasons, reason) do
      Enum.reject(reasons, fn r -> r == reason end)
    else
      [reason | reasons]
    end
  end

  defp reject_conflicting_reasons(updated_reasons, reason) do
    case reason do
      "Shorten Story" -> Enum.reject(updated_reasons, fn r -> r == "Lengthen Story" end)
      "Lengthen Story" -> Enum.reject(updated_reasons, fn r -> r == "Shorten Story" end)
      _ -> updated_reasons
    end
  end

  defp process_story(socket, reasons, :new) do
    Process.send_after(self(), {:render_generating_story, 1}, 1000)
    headline = Headline.by_id!(socket.assigns.form.params["headline_id"])

    previous_stories =
      get_stories_for_a_user(socket.assigns.current_user)
      |> Enum.map_join("\n\n", fn story ->
        "#{story.headline.subject}\n#{story.content}"
      end)

    socket =
      case ChatCompletion.request_stories(
             headline.subject,
             socket.assigns.form.params["content"],
             List.to_string(reasons),
             previous_stories
           ) do
        {:ok, task} ->
          updated_params =
            Map.update!(socket.assigns.form.params, "content", fn _content ->
              ""
            end)

          socket
          |> assign(:current_request, task)
          |> assign(:form, Form.validate(socket.assigns.form, updated_params))
          |> assign(:generating_story, true)
          |> assign(:show_buttons, false)

        {:error, _} ->
          socket
      end

    {:noreply, socket}
  end

  defp process_story(socket, reasons, :edit) do
    Process.send_after(self(), {:render_generating_story, 1}, 1000)

    previous_stories =
      get_stories_for_a_user(socket.assigns.current_user)
      |> Enum.map_join("\n\n", fn story ->
        "#{story.headline.subject}\n#{story.content}"
      end)

    socket =
      case ChatCompletion.request_stories(
             socket.assigns.story.headline.subject,
             socket.assigns.story.content,
             List.to_string(reasons),
             previous_stories
           ) do
        {:ok, task} ->
          new_story =
            if socket.assigns.story.photo == nil do
              %{
                "photo" => %{
                  "_form_type" => "create",
                  "_ignored" => "true",
                  "_persistent_id" => "0",
                  "user_id" => socket.assigns.story.user_id
                },
                "headline_id" => socket.assigns.story.headline_id,
                "content" => "",
                "position" => socket.assigns.story.position,
                "user_id" => socket.assigns.story.user_id,
                "headline" => socket.assigns.story.headline,
                "id" => socket.assigns.story.id
              }
            else
              %{
                "headline_id" => socket.assigns.story.headline_id,
                "content" => "",
                "position" => socket.assigns.story.position,
                "user_id" => socket.assigns.story.user_id,
                "headline" => socket.assigns.story.headline,
                "id" => socket.assigns.story.id
              }
            end

          form =
            Form.validate(
              socket.assigns.form,
              new_story,
              errors: true
            )

          socket
          |> assign(:current_request, task)
          |> assign(:form, form)
          |> assign(:generating_story, true)
          |> assign(:show_buttons, false)

        {:error, _} ->
          socket
      end

    {:noreply, socket}
  end

  defp update_last_registration_page_visited(user, page) do
    {:ok, _} =
      User.update_last_registration_page_visited(user, %{last_registration_page_visited: page})
  end

  defp user_has_an_about_me_story?(user) do
    case get_stories_for_a_user(user) do
      [] ->
        false

      stories ->
        Enum.any?(stories, fn story ->
          story.headline.subject == "About me"
        end)
    end
  end

  defp get_stories_for_a_user(user) do
    {:ok, stories} = Story.by_user_id(user.id)

    stories
  end

  defp get_user_default_photo(_socket) do
    nil
  end

  defp get_user_story_position(socket) do
    story_results =
      Story
      |> Ash.Query.for_read(:descending_by_user_id, %{user_id: socket.assigns.current_user.id})
      |> Ash.read!(page: [limit: 1, count: true])

    case Map.get(story_results, :results) do
      [story | _] -> story.position + 1
      _ -> Map.get(story_results, :count) + 1
    end
  end

  defp get_user_headline_position(socket) do
    headline_results =
      Story
      |> Ash.Query.for_read(:by_user_id, %{user_id: socket.assigns.current_user.id})
      |> Ash.read!(page: [limit: 1, count: true])

    Map.get(headline_results, :count) + 1
  end

  defp get_user_headlines(socket) do
    user_headlines =
      Story
      |> Ash.Query.for_read(:user_headlines, %{user_id: socket.assigns.current_user.id})
      |> Ash.read!()
      |> Enum.reduce(%{}, fn story, acc ->
        Map.put(acc, story.headline_id, "")
      end)

    Headline
    |> Ash.Query.for_read(:read)
    |> Ash.read!()
    |> Enum.map(fn headline ->
      [
        key: headline.subject,
        value: headline.id,
        disabled: Map.get(user_headlines, headline.id) != nil
      ]
    end)
  end

  defp user_states_to_be_auto_logged_out do
    [
      :under_investigation,
      :banned,
      :archived
    ]
  end

  defp get_default_headline(socket) when socket.assigns.live_action == :about_me do
    Narratives.Headline
    |> Ash.Query.for_read(:by_subject, %{subject: "About me"})
    |> Ash.read_one()
    |> case do
      {:ok, headline} -> headline.id
      _ -> nil
    end
  end

  defp get_default_headline(_socket) do
    nil
  end

  defp delete_or_remove_photo_from_story(story, photo) do
    if Map.has_key?(story, "id") do
      delete_or_remove_photo_from_story(story, photo, "delete_or_remove")
    end
  end

  defp delete_or_remove_photo_from_story(_story, photo, "delete_or_remove") do
    photo && Photo.destroy(photo)
  end

  defp either_content_or_photo_added(content, uploads, :about_me) do
    if content != "" && uploads != [] do
      true
    else
      false
    end
  end

  defp either_content_or_photo_added(content, uploads, _) do
    if content != "" || uploads != [] do
      true
    else
      false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-5 space-y-4">
      <h2 class="text-xl font-bold dark:text-white"><%= @title %></h2>

      <p class="dark:text-white"><%= @info_text %></p>

      <.form
        :let={f}
        id={@form_id}
        for={@form}
        class="space-y-6 group"
        phx-change="validate"
        phx-submit="submit"
      >
        <%= if @form.source.type == :create do %>
          <%= text_input(f, :position, type: :hidden, value: @story_position) %>
        <% end %>

        <%= if @form.source.type == :update do %>
          <%= text_input(f, :position, type: :hidden, value: f[:position].value) %>
          <%= text_input(f, :id, type: :hidden, value: f[:id].value) %>
        <% end %>

        <%= text_input(f, :user_id, type: :hidden, value: @current_user.id) %>

        <div>
          <label
            for="story_headline"
            class="block text-sm font-medium leading-6 text-gray-900 dark:text-white"
          >
            <%= with_locale(@language, fn -> %>
              <%= gettext("Headline") %>
            <% end) %>
          </label>

          <div :if={@default_headline == nil} phx-feedback-for={f[:headline_id].name} class="mt-2">
            <%= select(
              f,
              :headline_id,
              @headlines,
              class:
                "block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm  phx-no-feedback:ring-gray-300 phx-no-feedback:focus:ring-indigo-600 sm:leading-6 " <>
                  unless(get_field_errors(f[:headline_id], :headline_id) == [],
                    do: "ring-red-600 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  ) <>
                  if @generating_story do
                    " cursor-not-allowed disabled:pointer-events-none disabled:opacity-50"
                  else
                    ""
                  end,
              prompt: with_locale(@language, fn -> gettext("Select a headline") end),
              value: f[:headline_id].value,
              "phx-debounce": "200"
            ) %>

            <.error :for={msg <- get_field_errors(f[:headline_id], :headline_id)}>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Headline") <> " " <> msg %>
              <% end) %>
            </.error>
          </div>

          <div :if={@default_headline != nil} phx-feedback-for={f[:headline_id].name} class="mt-2">
            <%= select(
              f,
              :headline_id,
              [[key: gettext("About me"), value: @default_headline, selected: "selected"]],
              class:
                "block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm  phx-no-feedback:ring-gray-300 phx-no-feedback:focus:ring-indigo-600 sm:leading-6 " <>
                  unless(get_field_errors(f[:headline_id], :headline_id) == [],
                    do: "ring-red-600 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  ) <>
                  if @generating_story do
                    "cursor-not-allowed disabled:pointer-events-none disabled:opacity-50"
                  else
                    ""
                  end,
              prompt: with_locale(@language, fn -> gettext("Select a headline") end),
              value: @default_headline,
              "phx-debounce": "200"
            ) %>

            <.error :for={msg <- get_field_errors(f[:headline_id], :headline_id)}>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Headline") <> " " <> msg %>
              <% end) %>
            </.error>
          </div>
        </div>

        <div>
          <div class="flex justify-between">
            <label
              for="story_content"
              class="block text-sm font-medium leading-6 text-gray-900 dark:text-white"
            >
              <%= with_locale(@language, fn -> %>
                <%= gettext("Content") %>
              <% end) %>
            </label>

            <p class="text-sm text-gray-500 dark:text-white">
              <%= with_locale(@language, fn -> %>
                <%= gettext("Characters: ") %>
              <% end) %>
              <span class="font-semibold"><%= @words %> / 1024</span>
            </p>
          </div>
          <div :if={@generating_story == false} phx-feedback-for={f[:content].name} class="mt-2">
            <%= textarea(
              f,
              :content,
              class:
                "block w-full rounded-md border-0 py-1.5 text-gray-900 dark:bg-gray-700 dark:text-white shadow-sm ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm phx-no-feedback:ring-gray-300 phx-no-feedback:focus:ring-indigo-600 sm:leading-6 resize-none " <>
                  unless(get_field_errors(f[:content], :content) == [],
                    do: "ring-red-600 focus:ring-red-600",
                    else:
                      "ring-gray-300 focus:ring-indigo-600 #{if @words > 1024 do
                        "ring-red-600 focus:ring-red-600"
                      end}"
                  ),
              placeholder:
                with_locale(@language, fn ->
                  gettext(
                    "Use normal text or the Markdown format to write your story. You can use **bold**, *italic*, ~line-through~, [links](https://example.com) and more. Each story can be up to 1,024 characters long. Please do write multiple stories to tell potential partners more about yourself."
                  )
                end),
              value: f[:content].value,
              rows: 7,
              type: :text,
              "phx-debounce": "200",
              readonly: make_readonly(@words),
              maxlength: "1024"
            ) %>

            <.error :for={msg <- get_field_errors(f[:content], :content)}>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Content") <> " " <> msg %>
              <% end) %>
            </.error>
          </div>
          <div :if={@generating_story == true} phx-feedback-for={f[:content].name} class="mt-2">
            <%= textarea(
              f,
              :content,
              class:
                "block w-full rounded-md border-0 py-1.5 text-gray-900 dark:bg-gray-700 dark:text-white shadow-sm ring-1 ring-inset placeholder:text-gray-400 focus:ring-2 focus:ring-inset sm:text-sm  phx-no-feedback:ring-gray-300 phx-no-feedback:focus:ring-indigo-600 sm:leading-6 " <>
                  unless(get_field_errors(f[:content], :content) == [] || @words == 1024,
                    do: "ring-red-600 focus:ring-red-600",
                    else: "ring-gray-300 focus:ring-indigo-600"
                  ),
              placeholder:
                with_locale(@language, fn ->
                  gettext(
                    "Use normal text or the Markdown format to write your story. You can use **bold**, *italic*, ~line-through~, [links](https://example.com) and more. Each story can be up to 1,024 characters long. Please do write multiple stories to tell potential partners more about yourself."
                  )
                end),
              value: @message_when_generating_story,
              rows: 4,
              type: :text,
              readonly: true,
              "phx-debounce": "200",
              maxlength: "1024"
            ) %>

            <.error :for={msg <- get_field_errors(f[:content], :content)}>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Content") <> " " <> msg %>
              <% end) %>
            </.error>
          </div>

          <%= if @words > 50 do %>
            <div :if={@show_buttons == true} class="mt-4 flex flex-col md:flex-row  gap-3">
              <legend class="sr-only">
                <%= with_locale(@language, fn -> %>
                  <%= gettext("Optimize a Story") %>
                <% end) %>
              </legend>

              <div>
                <div class="space-y-5 grid grid-cols-1 md:grid-cols-5 items-center">
                  <div class="flex items-center space-x-4 flex-nowrap">
                    <div class="flex items-center">
                      <input
                        id="comments"
                        aria-describedby="comments-description"
                        name="Fix spelling and grammar errors."
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                        value="Fix spelling and grammar errors."
                        checked={Enum.member?(@reasons, gettext("Fix spelling and grammar errors."))}
                        phx-change="toggle_reason"
                      />
                      <label
                        for="comments"
                        class="ml-3 font-medium dark:text-[#fff] text-gray-900 whitespace-nowrap"
                      >
                        <%= with_locale(@language, fn -> %>
                          <%= gettext("Fix spelling and grammar errors") %>
                        <% end) %>
                      </label>
                    </div>
                    <div class="flex items-center">
                      <input
                        id="funnier"
                        aria-describedby="funnier-description"
                        name="Make Funnier"
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                        value="Make Funnier"
                        checked={Enum.member?(@reasons, gettext("Make Funnier"))}
                        phx-change="toggle_reason"
                      />
                      <label
                        for="funnier"
                        class="ml-3 font-medium dark:text-[#fff] text-gray-900 whitespace-nowrap"
                      >
                        <%= with_locale(@language, fn -> %>
                          <%= gettext("Make Funnier") %>
                        <% end) %>
                      </label>
                    </div>
                    <div class="flex items-center">
                      <input
                        id="exciting"
                        aria-describedby="exciting-description"
                        name="More Exciting"
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                        value="More Exciting"
                        checked={Enum.member?(@reasons, gettext("More Exciting"))}
                        phx-change="toggle_reason"
                      />
                      <label
                        for="exciting"
                        class="ml-3 font-medium dark:text-[#fff] text-gray-900 whitespace-nowrap"
                      >
                        <%= with_locale(@language, fn -> %>
                          <%= gettext("More Exciting") %>
                        <% end) %>
                      </label>
                    </div>
                    <div class="flex items-center">
                      <input
                        id="lengthen"
                        aria-describedby="lengthen-description"
                        name="Lengthen Story"
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                        value="Lengthen Story"
                        checked={Enum.member?(@reasons, gettext("Lengthen Story"))}
                        phx-change="toggle_reason"
                      />
                      <label
                        for="lengthen"
                        class="ml-3 font-medium dark:text-[#fff] text-gray-900 whitespace-nowrap"
                      >
                        <%= with_locale(@language, fn -> %>
                          <%= gettext("Lengthen Story") %>
                        <% end) %>
                      </label>
                    </div>
                    <div class="flex items-center">
                      <input
                        id="shorten"
                        aria-describedby="shorten-description"
                        name="Shorten Story"
                        type="checkbox"
                        class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                        value="Shorten Story"
                        checked={Enum.member?(@reasons, gettext("Shorten Story"))}
                        phx-change="toggle_reason"
                      />
                      <label
                        for="shorten"
                        class="ml-3 font-medium dark:text-[#fff] text-gray-900 whitespace-nowrap"
                      >
                        <%= with_locale(@language, fn -> %>
                          <%= gettext("Shorten Story") %>
                        <% end) %>
                      </label>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <button
              :if={length(@reasons) > 0 && @show_buttons == true && f[:headline_id].value != nil}
              type="button"
              phx-click="generate_story"
              class="flex mt-5 justify-center rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-semibold leading-6 text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              <%= with_locale(@language, fn -> %>
                <%= gettext("Generate story") %>
              <% end) %>
            </button>
          <% end %>
        </div>

        <div :if={@photo != nil} class="w-full space-y-2">
          <p class="block text-sm font-medium leading-6 text-gray-900 dark:text-white">
            <%= with_locale(@language, fn -> %>
              <%= gettext("Photo") %>
            <% end) %>
          </p>
          <div class="md:w-[300px] w-[100%] relative">
            <div
              class="absolute z-50 top-4 right-2 h-[40px] cursor-pointer text-white w-[40px] bg-red-500 p-2 rounded-md "
              phx-click="delete_photo"
              data-confirm={
                if @story.headline && @story.headline.subject == "About me" do
                  with_locale(@language, fn ->
                    gettext(
                      "Are you sure you want to delete your about me photo ? This will hibernate your account until you upload another photo"
                    )
                  end)
                else
                  with_locale(@language, fn ->
                    gettext("Are you sure you want to delete this photo ?")
                  end)
                end
              }
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true"
              >
                <path
                  fill-rule="evenodd"
                  d="M8.75 1A2.75 2.75 0 006 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 10.23 1.482l.149-.022.841 10.518A2.75 2.75 0 007.596 19h4.807a2.75 2.75 0 002.742-2.53l.841-10.52.149.023a.75.75 0 00.23-1.482A41.03 41.03 0 0014 4.193V3.75A2.75 2.75 0 0011.25 1h-2.5zM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4zM8.58 7.72a.75.75 0 00-1.5.06l.3 7.5a.75.75 0 101.5-.06l-.3-7.5zm4.34.06a.75.75 0 10-1.5-.06l-.3 7.5a.75.75 0 101.5.06l.3-7.5z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <img
              class="object-cover md:h-200  drop-shadow border md:w-[300px] w-[100%] rounded-lg"
              src={Photo.get_optimized_photo_to_use(@photo, :normal)}
            />
          </div>
        </div>

        <.inputs_for :let={photo_form} field={@form[:photo]}>
          <p class="block text-sm font-medium leading-6 text-gray-900 dark:text-white">
            <%= if @form_id == "edit-story-form" do %>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Update Photo") %>
              <% end) %>
            <% else %>
              <%= with_locale(@language, fn -> %>
                <%= gettext("Photo") %>
              <% end) %>
            <% end %>
            <span :if={@image_required} class="text-red-600">* required</span>
          </p>

          <.live_file_input
            type="file"
            accept="image/*"
            upload={@uploads.photos}
            class="hidden"
            required={@image_required}
          />

          <%= text_input(photo_form, :user_id, type: :hidden, value: @current_user.id) %>

          <div :if={Enum.count(@uploads.photos.entries) == 0}>
            <%= text_input(photo_form, :_ignored, type: :hidden, value: "true") %>
          </div>

          <div
            :if={Enum.count(@uploads.photos.entries) == 0}
            id={"photo-#{@uploads.photos.ref}"}
            phx-click={JS.dispatch("click", to: "##{@uploads.photos.ref}", bubbles: false)}
            phx-drop-target={@uploads.photos.ref}
            for={@uploads.photos.ref}
            data-upload-target="photos"
            data-input={@uploads.photos.ref}
            class="flex flex-col items-center w-full px-6 py-8 mx-auto text-center border-2 border-gray-300 border-dashed rounded-md cursor-pointer bg-gray-50 dark:bg-gray-700"
          >
            <.icon name="hero-cloud-arrow-up" class="w-8 h-8 mb-4 text-gray-500 dark:text-gray-400" />

            <p class="text-sm dark:text-white">
              <%= with_locale(@language, fn -> %>
                <%= gettext("Upload or drag & drop your photo file JPG, JPEG, PNG") %>
              <% end) %>
            </p>
          </div>

          <%= for entry <- @uploads.photos.entries do %>
            <%= text_input(f, :filename, type: :hidden, value: entry.uuid <> "." <> ext(entry)) %>
            <%= text_input(f, :original_filename, type: :hidden, value: entry.client_name) %>
            <%= text_input(f, :ext, type: :hidden, value: ext(entry)) %>
            <%= text_input(f, :mime, type: :hidden, value: entry.client_type) %>
            <%= text_input(f, :size, type: :hidden, value: entry.client_size) %>

            <div class="flex space-x-8">
              <.live_img_preview class="inline-block object-cover w-32 h-32 rounded-md" entry={entry} />

              <div class="flex flex-col justify-center flex-1 dark:text-white">
                <p><%= entry.client_name %></p>
                <p class="text-sm text-gray-600 dark:text-white">
                  <%= Size.humanize!(entry.client_size, output: :string) %>
                </p>

                <div class="mt-4">
                  <button
                    type="button"
                    class="flex w-24 justify-center rounded-md border border-red-600 bg-red-100 px-3 py-1.5 text-sm font-semibold shadow-none leading-6 text-red-600 hover:bg-red-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    aria-label="cancel"
                  >
                    <%= with_locale(@language, fn -> %>
                      <%= gettext("Cancel") %>
                    <% end) %>
                  </button>
                </div>
              </div>
            </div>

            <div
              :if={Enum.count(upload_errors(@uploads.photos, entry))}
              class="mb-4 danger"
              role="alert"
            >
              <ul class="error-messages">
                <%= for err <- upload_errors(@uploads.photos, entry) do %>
                  <li>
                    <p><%= error_to_string(err, @language) %></p>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </.inputs_for>

        <div>
          <%= submit(@cta,
            phx_disable_with: gettext("Saving..."),
            class:
              "flex w-full justify-center rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-semibold leading-6 text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 " <>
                if(@form.source.source.valid? == false || @either_content_or_photo_added == false,
                  do: "opacity-40 cursor-not-allowed hover:bg-blue-500 active:bg-blue-500",
                  else: ""
                ),
            disabled:
              if @form.source.source.valid? == false || @either_content_or_photo_added == false ||
                   @generating_story == true do
                true
              else
                false
              end
          ) %>
        </div>
      </.form>
    </div>
    """
  end

  defp get_field_errors(field, _name) do
    Enum.map(field.errors, &translate_error(&1))
  end

  defp error_to_string(:too_large, language),
    do: with_locale(language, fn -> gettext("Too large") end)

  defp error_to_string(:not_accepted, language),
    do: with_locale(language, fn -> gettext("You have selected an unacceptable file type") end)

  defp error_to_string(:too_many_files, language),
    do: with_locale(language, fn -> gettext("You have selected too many files") end)

  defp error_to_string(_, language),
    do:
      with_locale(language, fn ->
        gettext("Something went wrong uploading your photo. Try again")
      end)

  defp ext(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    ext
  end

  def make_readonly(words) do
    if words > 1024 do
      true
    else
      false
    end
  end
end
