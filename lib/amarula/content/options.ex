defmodule Amarula.Content.Options do
  @moduledoc """
  An incoming **interactive message that presents a set of choices** — a list
  menu, a buttons message, a template-button message, or a native-flow
  interactive message. These are what WhatsApp Business / call-center / automated
  flows send to ask "pick one of these". A normal linked-device client can't send
  them, but it receives them; the user's reply comes back as an
  `%Amarula.Content.Response{}`.

  The four proto shapes are unified into one:

    * `:kind`        — `:list | :buttons | :template | :interactive`.
    * `:title`       — header/title text, if any.
    * `:body`        — the main prompt text.
    * `:footer`      — footer text, if any.
    * `:button_text` — the label that opens the option list (list messages only).
    * `:options`     — the choices, each `%{id, text, description}` (`description`
      is `nil` for kinds that don't carry one). `id` is what your app keys the
      user's selection off; it matches the `id` of the later
      `%Amarula.Content.Response{}`.

  For anything beyond the choices (media headers, native-flow param JSON, …), read
  `msg.raw`.
  """

  @type kind :: :list | :buttons | :template | :interactive

  @type option :: %{
          id: String.t() | nil,
          text: String.t() | nil,
          description: String.t() | nil
        }

  @type t :: %__MODULE__{
          kind: kind(),
          title: String.t() | nil,
          body: String.t() | nil,
          footer: String.t() | nil,
          button_text: String.t() | nil,
          options: [option()]
        }

  @enforce_keys [:kind]
  defstruct [:kind, :title, :body, :footer, :button_text, options: []]

  @doc """
  Normalize one of the four interactive-presentation protos into a
  `%Amarula.Content.Options{}`. `kind` says which proto `m` is.
  """
  @spec from_proto(kind(), struct()) :: t()
  def from_proto(:list, %{} = m) do
    %__MODULE__{
      kind: :list,
      title: Map.get(m, :title),
      body: Map.get(m, :description),
      footer: Map.get(m, :footerText),
      button_text: Map.get(m, :buttonText),
      options: list_options(Map.get(m, :sections) || [])
    }
  end

  def from_proto(:buttons, %{} = m) do
    %__MODULE__{
      kind: :buttons,
      body: Map.get(m, :contentText),
      footer: Map.get(m, :footerText),
      options: Enum.map(Map.get(m, :buttons) || [], &button_option/1)
    }
  end

  def from_proto(:template, %{} = m) do
    # Received templates carry the hydrated form on either the standalone
    # `hydratedTemplate` field or the `format` oneof (as `{:hydratedFourRowTemplate,
    # tpl}` — oneof members live under the oneof name, not as plain fields).
    case Map.get(m, :hydratedTemplate) || hydrated_from_format(Map.get(m, :format)) do
      %{} = tpl ->
        %__MODULE__{
          kind: :template,
          title: title_text(Map.get(tpl, :title)),
          body: Map.get(tpl, :hydratedContentText),
          footer: Map.get(tpl, :hydratedFooterText),
          options: Enum.map(Map.get(tpl, :hydratedButtons) || [], &template_option/1)
        }

      _ ->
        %__MODULE__{kind: :template}
    end
  end

  def from_proto(:interactive, %{} = m) do
    %__MODULE__{
      kind: :interactive,
      title: text_field(Map.get(m, :header), :title),
      body: text_field(Map.get(m, :body), :text),
      footer: text_field(Map.get(m, :footer), :text),
      options: native_flow_options(m)
    }
  end

  # --- list: sections -> rows ---
  defp list_options(sections) do
    Enum.flat_map(sections, fn section ->
      Enum.map(Map.get(section, :rows) || [], fn row ->
        %{
          id: Map.get(row, :rowId),
          text: Map.get(row, :title),
          description: Map.get(row, :description)
        }
      end)
    end)
  end

  # --- buttons: buttonId + buttonText.displayText ---
  defp button_option(%{} = b) do
    %{
      id: Map.get(b, :buttonId),
      text: text_field(Map.get(b, :buttonText), :displayText),
      description: nil
    }
  end

  # The hydrated template when it rides in the `format` oneof rather than the
  # standalone `hydratedTemplate` field.
  defp hydrated_from_format({:hydratedFourRowTemplate, %{} = tpl}), do: tpl
  defp hydrated_from_format(_), do: nil

  # --- template: hydrated button is a `:hydratedButton` oneof (quick-reply/url/call) ---
  defp template_option(%{hydratedButton: {:quickReplyButton, %{} = qr}}),
    do: %{id: Map.get(qr, :id), text: Map.get(qr, :displayText), description: nil}

  defp template_option(%{hydratedButton: {:urlButton, %{} = url}}),
    do: %{id: Map.get(url, :url), text: Map.get(url, :displayText), description: nil}

  defp template_option(%{hydratedButton: {:callButton, %{} = call}}),
    do: %{id: Map.get(call, :phoneNumber), text: Map.get(call, :displayText), description: nil}

  defp template_option(_), do: %{id: nil, text: nil, description: nil}

  # --- interactive: native-flow buttons (name + params JSON on description). The
  # nativeFlowMessage rides in the `:interactiveMessage` oneof. ---
  defp native_flow_options(%{interactiveMessage: {:nativeFlowMessage, %{} = nf}}) do
    Enum.map(Map.get(nf, :buttons) || [], fn b ->
      %{id: nil, text: Map.get(b, :name), description: Map.get(b, :buttonParamsJson)}
    end)
  end

  defp native_flow_options(_), do: []

  # HydratedFourRowTemplate.title is a oneof; only the text case interests us.
  defp title_text({:hydratedTitleText, t}), do: t
  defp title_text(_), do: nil

  defp text_field(%{} = sub, key), do: Map.get(sub, key)
  defp text_field(_, _), do: nil
end
