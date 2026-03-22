defmodule EyeInTheSkyWeb.Components.DatePickerModal do
  @moduledoc """
  Trello-style calendar date picker modal for setting task due dates.
  """

  use EyeInTheSkyWeb, :html

  @day_names ~w(Sun Mon Tue Wed Thu Fri Sat)

  attr :show, :boolean, required: true
  attr :task, :map, default: nil
  attr :year, :integer, default: nil
  attr :month, :integer, default: nil
  attr :selected_date, :string, default: nil

  def date_picker_modal(assigns) do
    today = Date.utc_today()
    year = assigns.year || today.year
    month = assigns.month || today.month
    month_name = month_name(month)
    weeks = calendar_weeks(year, month)

    assigns =
      assigns
      |> assign(:today, today)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:month_name, month_name)
      |> assign(:weeks, weeks)
      |> assign(:day_names, @day_names)

    ~H"""
    <%= if @show && @task do %>
      <%!-- Backdrop --%>
      <div
        class="fixed inset-0 z-50 bg-black/40"
        phx-click="close_date_picker"
      />
      <%!-- Modal panel --%>
      <div class="fixed inset-0 z-50 flex items-center justify-center p-4 pointer-events-none">
        <div class="pointer-events-auto w-72 rounded-2xl bg-base-200 dark:bg-[hsl(225,10%,22%)] shadow-2xl flex flex-col overflow-hidden">
          <%!-- Month navigation --%>
          <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/10">
            <button
              type="button"
              phx-click="date_picker_prev_month"
              class="w-7 h-7 flex items-center justify-center rounded-lg text-base-content/50 hover:text-base-content hover:bg-base-content/8 transition-colors"
            >
              <.icon name="hero-chevron-left-mini" class="w-4 h-4" />
            </button>
            <span class="text-sm font-semibold text-base-content">
              {@month_name} {@year}
            </span>
            <button
              type="button"
              phx-click="date_picker_next_month"
              class="w-7 h-7 flex items-center justify-center rounded-lg text-base-content/50 hover:text-base-content hover:bg-base-content/8 transition-colors"
            >
              <.icon name="hero-chevron-right-mini" class="w-4 h-4" />
            </button>
          </div>

          <%!-- Calendar grid --%>
          <div class="px-3 pt-3 pb-1">
            <%!-- Day headers --%>
            <div class="grid grid-cols-7 mb-1">
              <%= for day <- @day_names do %>
                <div class="text-center text-[10px] font-medium text-base-content/40 py-1">
                  {day}
                </div>
              <% end %>
            </div>
            <%!-- Weeks --%>
            <div class="grid grid-cols-7 gap-y-0.5">
              <%= for week <- @weeks do %>
                <%= for date <- week do %>
                  <%= if date do %>
                    <% date_str = Date.to_iso8601(date) %>
                    <% is_today = date == @today %>
                    <% is_selected = @selected_date == date_str %>
                    <button
                      type="button"
                      phx-click="select_due_date"
                      phx-value-date={date_str}
                      class={[
                        "w-full aspect-square rounded-lg text-xs flex items-center justify-center transition-colors",
                        is_selected && "bg-base-content text-base-100 font-semibold",
                        is_today && !is_selected && "bg-primary text-primary-content font-semibold",
                        !is_today && !is_selected && "text-base-content hover:bg-base-content/10"
                      ]}
                    >
                      {date.day}
                    </button>
                  <% else %>
                    <div />
                  <% end %>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Due date form --%>
          <form phx-submit="save_due_date" class="px-4 pb-4 pt-3 border-t border-base-content/10 mt-2">
            <input type="hidden" name="task_id" value={@task.uuid || to_string(@task.id)} />
            <div class="mb-3">
              <label class="text-[11px] font-medium text-base-content/50 uppercase tracking-wider mb-1.5 block">
                Due date
              </label>
              <input
                type="date"
                name="due_at"
                value={@selected_date || ""}
                class="input input-sm w-full bg-base-300 dark:bg-base-100/10 border-base-content/15 text-sm focus:border-primary/50"
              />
            </div>
            <div class="flex gap-2">
              <button
                type="submit"
                class="flex-1 btn btn-sm btn-primary"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="remove_due_date"
                phx-value-task_id={@task.uuid || to_string(@task.id)}
                class="flex-1 btn btn-sm btn-ghost text-base-content/60"
              >
                Remove
              </button>
            </div>
          </form>
        </div>
      </div>
    <% end %>
    """
  end

  # Build calendar grid (nils for padding cells), weeks start Sunday
  defp calendar_weeks(year, month) do
    first = Date.new!(year, month, 1)
    # :sunday mode: 1=Sun, 2=Mon, ..., 7=Sat
    offset = Date.day_of_week(first, :sunday) - 1
    days_in_month = Date.days_in_month(first)

    dates =
      List.duplicate(nil, offset) ++
        Enum.map(1..days_in_month, &Date.new!(year, month, &1))

    remainder = rem(length(dates), 7)
    padded = if remainder == 0, do: dates, else: dates ++ List.duplicate(nil, 7 - remainder)

    Enum.chunk_every(padded, 7)
  end

  defp month_name(1), do: "January"
  defp month_name(2), do: "February"
  defp month_name(3), do: "March"
  defp month_name(4), do: "April"
  defp month_name(5), do: "May"
  defp month_name(6), do: "June"
  defp month_name(7), do: "July"
  defp month_name(8), do: "August"
  defp month_name(9), do: "September"
  defp month_name(10), do: "October"
  defp month_name(11), do: "November"
  defp month_name(12), do: "December"
end
