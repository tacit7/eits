defmodule EyeInTheSkyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS
  use Gettext, backend: EyeInTheSkyWeb.Gettext

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook="FlashTimeout"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a custom square checkbox with optional indeterminate state.

  When `id` is provided, attaches the `IndeterminateCheckbox` hook to keep
  the native `.indeterminate` DOM property in sync with `data-indeterminate`.
  When `id` is nil, renders a plain checkbox without a hook.

  The `checkbox_area` attr adds `data-checkbox-area="true"` to the outer label —
  used by the `ShiftSelect` hook to detect checkbox clicks for range selection.
  """
  attr :id, :string, default: nil
  attr :checked, :boolean, required: true
  attr :indeterminate, :boolean, default: false
  attr :checkbox_area, :boolean, default: false
  attr :class, :string, default: ""
  attr :rest, :global

  def square_checkbox(assigns) do
    ~H"""
    <label
      data-checkbox-area={if @checkbox_area, do: "true", else: nil}
      class={"select-none flex items-center cursor-pointer " <> @class}
    >
      <%!-- With id: attach IndeterminateCheckbox hook to sync native .indeterminate property --%>
      <input
        :if={@id}
        id={@id}
        type="checkbox"
        class="sr-only"
        checked={@checked}
        data-indeterminate={to_string(@indeterminate)}
        phx-hook="IndeterminateCheckbox"
        {@rest}
      />
      <%!-- Without id: plain checkbox, no hook --%>
      <input
        :if={!@id}
        type="checkbox"
        class="sr-only"
        checked={@checked}
        data-indeterminate={to_string(@indeterminate)}
        {@rest}
      />
      <div class={[
        "shrink-0 size-4 flex items-center justify-center border rounded transition-colors duration-100",
        cond do
          @indeterminate -> "bg-primary/30 border-primary/60"
          @checked -> "bg-primary border-primary"
          true -> "bg-base-100 border-base-content/20 hover:border-primary/40"
        end
      ]}>
        <%= cond do %>
          <% @indeterminate -> %>
            <div class="w-2 h-0.5 bg-primary rounded-full"></div>
          <% @checked -> %>
            <.icon name="hero-check-mini" class="w-2.5 h-2.5 text-primary-content" />
          <% true -> %>
        <% end %>
      </div>
    </label>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a reusable empty state block for list and detail views.

  ## Examples

      <.empty_state
        id="agents-empty"
        icon="hero-users"
        title="No agents found"
        subtitle="Try adjusting your search filters"
      />
  """
  attr :id, :string, default: nil
  attr :icon, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :string, default: "py-12 text-center"
  attr :icon_class, :string, default: "mx-auto h-12 w-12 text-base-content/40"
  attr :title_class, :string, default: "mt-2 text-sm font-medium text-base-content"
  attr :subtitle_class, :string, default: "mt-1 text-sm text-base-content/60"

  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <.icon :if={@icon} name={@icon} class={@icon_class} />
      <h3 class={@title_class}>{@title}</h3>
      <p :if={@subtitle} class={@subtitle_class}>{@subtitle}</p>
      <div :if={@actions != []} class="mt-4 flex justify-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea text-base",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input text-base",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def custom_icon(%{name: "lucide-robot"} = assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
         fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M12 8V4H8"/>
      <rect width="16" height="12" x="4" y="8" rx="2"/>
      <path d="M2 14h2"/>
      <path d="M20 14h2"/>
      <path d="M15 13v2"/>
      <path d="M9 13v2"/>
    </svg>
    """
  end

  def custom_icon(%{name: "lucide-kanban"} = assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
         fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <rect width="18" height="18" x="3" y="3" rx="2"/>
      <path d="M8 7v7"/><path d="M12 7v4"/><path d="M16 7v9"/>
    </svg>
    """
  end

  attr :submit_text, :string, required: true
  attr :cancel_event, :any, default: nil
  attr :cancel_navigate, :string, default: nil
  attr :cancel_target, :any, default: nil
  attr :cancel_text, :string, default: "Cancel"
  attr :submit_disabled, :boolean, default: false
  attr :size, :string, default: nil
  attr :class, :string, default: nil

  def form_actions(assigns) do
    ~H"""
    <div class={["flex gap-2", @class]}>
      <button
        type="submit"
        class={["btn btn-primary flex-1", @size && "btn-#{@size}"]}
        disabled={@submit_disabled}
      >
        {@submit_text}
      </button>
      <%= if @cancel_navigate do %>
        <.link navigate={@cancel_navigate} class={["btn btn-ghost", @size && "btn-#{@size}"]}>
          {@cancel_text}
        </.link>
      <% else %>
        <button
          type="button"
          phx-click={@cancel_event}
          phx-target={@cancel_target}
          class={["btn btn-ghost", @size && "btn-#{@size}"]}
        >
          {@cancel_text}
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Icon action button with optional hover-reveal behavior.

  Used for delete, star, archive, and other icon-only actions
  that appear on hover in list/table rows.

  ## Examples

      <.icon_button icon="hero-trash-mini" on_click="delete" aria_label="Delete" color="error"
        values={%{"id" => @item.id}} />
      <.icon_button icon="hero-star-mini" on_click="star" aria_label="Star" show_on_hover={false} />
  """
  attr :icon, :string, required: true
  attr :on_click, :string, required: true
  attr :aria_label, :string, required: true
  attr :values, :map, default: %{}
  attr :color, :string, default: "primary"
  attr :show_on_hover, :boolean, default: true
  attr :class, :string, default: nil

  def icon_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_click}
      aria-label={@aria_label}
      class={[
        "flex-shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center rounded-md transition-all focus-visible:outline-none focus-visible:ring-2",
        @show_on_hover && "md:opacity-0 md:group-hover:opacity-100",
        color_classes(@color),
        @class
      ]}
      {phx_values(@values)}
    >
      <.icon name={@icon} class="size-3.5" />
    </button>
    """
  end

  defp color_classes("primary"),
    do: "text-base-content/40 hover:text-primary hover:bg-primary/10 focus-visible:ring-primary"

  defp color_classes("error"),
    do: "text-base-content/40 hover:text-error hover:bg-error/10 focus-visible:ring-error"

  defp color_classes("warning"),
    do: "text-base-content/40 hover:text-warning hover:bg-warning/10 focus-visible:ring-warning"

  defp color_classes("success"),
    do: "text-base-content/40 hover:text-success hover:bg-success/10 focus-visible:ring-success"

  defp color_classes(_),
    do: "text-base-content/40 hover:text-primary hover:bg-primary/10 focus-visible:ring-primary"

  defp phx_values(values) when map_size(values) == 0, do: []

  defp phx_values(values) do
    Enum.map(values, fn {k, v} -> {:"phx-value-#{k}", v} end)
  end

  @doc """
  Renders a form field container with a label above the inner input/select/textarea.

  ## Examples

      <.form_field label="Title">
        <input type="text" name="title" class="input input-bordered text-base" />
      </.form_field>

      <.form_field label="Budget" hint="Optional">
        <input type="number" name="budget" class="input input-bordered" />
      </.form_field>
  """
  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def form_field(assigns) do
    ~H"""
    <div class={["form-control", @class]}>
      <label class="label">
        <span class="label-text font-medium">{@label}</span>
        <span :if={@hint} class="label-text-alt">{@hint}</span>
      </label>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders the compact 11px uppercase label used in detail drawer field groups.

  ## Examples

      <.detail_label text="Status" />
  """
  attr :text, :string, required: true

  def detail_label(assigns) do
    ~H"""
    <label class="text-[11px] font-medium text-base-content/40 uppercase tracking-wider mb-1.5 block">
      {@text}
    </label>
    """
  end

  @doc """
  Renders a modal/drawer header with a title and close button.

  ## Examples

      <.modal_header title="New Task" toggle_event="toggle_new_task" />
      <.modal_header title="Edit" toggle_event="close" class="mb-5" />
  """
  attr :title, :string, required: true
  attr :toggle_event, :string, required: true
  attr :class, :string, default: nil
  attr :phx_target, :any, default: nil

  def modal_header(assigns) do
    ~H"""
    <div class={["flex items-center justify-between mb-6", @class]}>
      <h2 class="text-xl font-semibold">{@title}</h2>
      <button phx-click={@toggle_event} phx-target={@phx_target} class="btn btn-ghost btn-sm btn-circle">
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a search form with a magnifying glass icon on the left.

  Supports two sizes:
  - `"sm"` (default) — page-level search bars (`input-sm min-h-[44px]`)
  - `"xs"` — compact top-bar search bars (`input-xs h-7 text-[12px]`)

  ## Examples

      <.search_bar id="agent-search" placeholder="Search agents…" value={@query} />
      <.search_bar id="top-bar-search" size="xs" label="Search sessions" placeholder="Search…" value={@search_query || ""} class="flex-1 max-w-xs" />
  """
  attr :id, :string, required: true
  attr :size, :string, default: "sm"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: "Search…"
  attr :value, :string, default: ""
  attr :on_change, :string, default: "search"
  attr :on_submit, :string, default: nil
  attr :debounce, :string, default: "300"
  attr :autocomplete, :string, default: "off"
  attr :class, :string, default: ""

  def search_bar(assigns) do
    ~H"""
    <form
      id={@id}
      phx-change={@on_change}
      phx-submit={@on_submit}
      class={"relative flex items-center #{@class}"}
    >
      <label :if={@label} for={"#{@id}-input"} class="sr-only">{@label}</label>
      <.icon
        name="hero-magnifying-glass-mini"
        class={"absolute left-2.5 pointer-events-none " <>
          if(@size == "xs",
            do: "size-3.5 text-base-content/30",
            else: "size-4 text-base-content/40"
          )}
      />
      <input
        type="text"
        id={"#{@id}-input"}
        name="query"
        value={@value}
        placeholder={@placeholder}
        phx-debounce={@debounce}
        autocomplete={@autocomplete}
        class={"input w-full bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 " <>
          "focus:border-primary/30 focus:bg-base-100 transition-colors " <>
          if(@size == "xs",
            do: "input-xs pl-8 h-7 text-[12px]",
            else: "input-sm pl-9 min-h-[44px] text-base"
          )}
      />
    </form>
    """
  end

  @doc """
  Renders a loading spinner using the DaisyUI loading class.

  ## Examples

      <.spinner />
      <.spinner size="lg" class="text-primary" />
  """
  attr :size, :string, default: "sm"
  attr :class, :string, default: ""

  def spinner(assigns) do
    ~H"""
    <span class={"loading loading-spinner loading-#{@size} #{@class}"} aria-label="Loading" role="status" />
    """
  end

  @doc """
  Renders a single skeleton placeholder row for list loading states.

  ## Examples

      <.skeleton_row :for={_ <- 1..5} />
  """
  attr :class, :string, default: ""

  def skeleton_row(assigns) do
    ~H"""
    <div class={"flex items-center gap-3 px-3 py-2.5 #{@class}"}>
      <div class="skeleton size-4 rounded-full shrink-0" />
      <div class="flex flex-col gap-1.5 flex-1">
        <div class="skeleton h-3 w-2/3" />
        <div class="skeleton h-2.5 w-1/3" />
      </div>
    </div>
    """
  end

  @doc """
  Renders a small colored dot indicating a session or agent status.

  ## Examples

      <.status_dot status={:working} />
      <.status_dot status={:completed} size="md" />
  """
  attr :status, :atom, required: true
  attr :size, :string, default: "sm"
  attr :class, :string, default: ""

  def status_dot(assigns) do
    ~H"""
    <span class={"rounded-full #{status_dot_size(@size)} #{status_dot_color(@status)} shrink-0 #{@class}"} />
    """
  end

  @doc """
  Renders a DaisyUI badge with semantic status coloring and an optional dot.

  ## Examples

      <.status_badge status={:working} />
      <.status_badge status={:failed} show_dot={true} label="Error" />
  """
  attr :status, :atom, required: true
  attr :label, :string, default: nil
  attr :show_dot, :boolean, default: false
  attr :size, :string, default: "sm"
  attr :class, :string, default: ""

  def status_badge(assigns) do
    assigns =
      assign(assigns, :label_text,
        assigns[:label] || assigns.status |> Atom.to_string() |> String.replace("_", " ")
      )

    ~H"""
    <span class={"badge badge-#{@size} #{status_badge_color(@status)} #{@class}"}>
      <%= if @show_dot do %>
        <.status_dot status={@status} size="xs" />
      <% end %>
      {@label_text}
    </span>
    """
  end

  @doc """
  Renders a keyboard key using the DaisyUI kbd component.

  ## Examples

      <.kbd key="⌘" /><.kbd key="K" />
      <.kbd key="Esc" class="ml-1" />
  """
  attr :key, :string, required: true
  attr :class, :string, default: ""

  def kbd(assigns) do
    ~H"""
    <kbd class={"kbd kbd-xs #{@class}"}>{@key}</kbd>
    """
  end

  @doc """
  Renders a pill tab container. Each tab is declared with the `:item` slot.

  ## Examples

      <.tab_pills>
        <:item label="All" active={@tab == "all"} on_click="switch_tab" value="all" />
        <:item label="Running" active={@tab == "running"} on_click="switch_tab" value="running" />
      </.tab_pills>
  """
  attr :class, :string, default: ""

  slot :item, required: true do
    attr :label, :string, required: true
    attr :active, :boolean
    attr :on_click, :string
    attr :value, :string
  end

  def tab_pills(assigns) do
    ~H"""
    <div class={"flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5 #{@class}"}>
      <%= for item <- @item do %>
        <button
          type="button"
          phx-click={item[:on_click]}
          phx-value-tab={item[:value]}
          class={[
            "px-3 py-1 rounded-md text-sm font-medium transition-colors",
            if(item[:active],
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/60 hover:bg-base-200/60 hover:text-base-content"
            )
          ]}
        >
          {item[:label]}
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a responsive overlay drawer. On mobile it slides up from the bottom;
  on desktop it renders as a centered modal overlay.

  ## Examples

      <.side_drawer id="task-drawer" open={@drawer_open} on_close="close_drawer">
        <p>Drawer content here</p>
      </.side_drawer>
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :on_close, :string, default: "close_drawer"
  attr :aria_label, :string, default: "Dialog"
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def side_drawer(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <div
      :if={@open}
      phx-click={@on_close}
      class="fixed inset-0 bg-black/40 z-40 backdrop-blur-sm"
    />

    <%!-- Mobile: slide from bottom --%>
    <div
      id={"#{@id}-mobile"}
      role="dialog"
      aria-modal="true"
      aria-label={@aria_label}
      aria-hidden={to_string(!@open)}
      class={[
        "sm:hidden fixed inset-x-0 bottom-0 z-50 bg-base-100 rounded-t-2xl shadow-xl",
        "pb-[env(safe-area-inset-bottom)]",
        "transition-transform duration-200",
        if(@open, do: "translate-y-0", else: "translate-y-full")
      ]}
    >
      {render_slot(@inner_block)}
    </div>

    <%!-- Desktop: centered modal overlay --%>
    <div
      id={"#{@id}-desktop"}
      class={[
        "hidden sm:flex fixed inset-0 z-50 items-center justify-center",
        if(!@open, do: "pointer-events-none opacity-0", else: "opacity-100"),
        "transition-opacity duration-150"
      ]}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={@aria_label}
        aria-hidden={to_string(!@open)}
        class={"bg-base-100 rounded-xl shadow-2xl w-full max-w-lg mx-4 #{@class}"}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(EyeInTheSkyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EyeInTheSkyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # Badge components extracted to EyeInTheSkyWeb.TaskBadges
  defdelegate priority_badge(assigns), to: EyeInTheSkyWeb.TaskBadges
  defdelegate state_badge(assigns), to: EyeInTheSkyWeb.TaskBadges

  defp status_dot_size("xs"), do: "size-1.5"
  defp status_dot_size("sm"), do: "size-2"
  defp status_dot_size("md"), do: "size-2.5"
  defp status_dot_size(_), do: "size-2"

  defp status_dot_color(:working), do: "bg-success"
  defp status_dot_color(:running), do: "bg-success"
  defp status_dot_color(:idle), do: "bg-base-content/30"
  defp status_dot_color(:waiting), do: "bg-info"
  defp status_dot_color(:pending), do: "bg-info"
  defp status_dot_color(:completed), do: "bg-success"
  defp status_dot_color(:failed), do: "bg-error"
  defp status_dot_color(:stopped), do: "bg-base-content/20"
  defp status_dot_color(_), do: "bg-base-content/30"

  defp status_badge_color(:working), do: "badge-success"
  defp status_badge_color(:running), do: "badge-success"
  defp status_badge_color(:idle), do: "badge-ghost"
  defp status_badge_color(:waiting), do: "badge-info"
  defp status_badge_color(:pending), do: "badge-info"
  defp status_badge_color(:completed), do: "badge-success"
  defp status_badge_color(:failed), do: "badge-error"
  defp status_badge_color(:stopped), do: "badge-ghost"
  defp status_badge_color(_), do: "badge-ghost"

end
