defmodule EyeInTheSkyWebWeb.MobileLayoutTest do
  @moduledoc """
  Mobile layout regression tests.

  Validates structural invariants for the three primary mobile breakpoints:

    375×812  — iPhone SE / 13 mini
    390×844  — iPhone 14 Pro
    430×932  — iPhone 14 Pro Max

  Phoenix LiveViewTest renders full server HTML without a real browser, so these
  tests assert CSS class presence, ARIA attributes, and safe-area properties that
  drive correct rendering on the target viewports. Interaction tests (drawer
  open/close, backdrop dismiss) use LiveViewTest's event dispatching.

  All three breakpoints are narrower than the md breakpoint (768px), so
  md:hidden elements are present in the DOM and governs mobile-only UI.
  """

  use EyeInTheSkyWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Projects, Tasks}

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "mobile-test-#{uniq()}",
        path: "/tmp/mobile-test-#{uniq()}",
        slug: "mobile-test-#{uniq()}"
      })

    project
  end

  defp create_task(project, overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Mobile task #{uniq()}",
            state_id: 1,
            project_id: project.id,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  # ---------------------------------------------------------------------------
  # Mobile top header  (applies at 375, 390, 430 — all below md breakpoint)
  # ---------------------------------------------------------------------------

  describe "mobile top header" do
    test "renders hamburger, title, search and notification buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # md:hidden marks this header as mobile-only
      assert html =~ "md:hidden"
      assert html =~ ~s(aria-label="Open sidebar menu")
      assert html =~ "Eye in the Sky"
      assert html =~ ~s(aria-label="Open command palette")
      assert html =~ ~s(aria-label="Enable push notifications")
    end

    test "header height includes safe-area-inset-top for notched devices", %{conn: conn} do
      # Targets 390×844 (Dynamic Island) and 430×932 (Dynamic Island)
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "safe-area-inset-top"
    end

    test "header height is calc(3rem + env(safe-area-inset-top))", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "calc(3rem+env(safe-area-inset-top))"
    end

    test "push-setup button has phx-hook for JS interaction", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(phx-hook="PushSetup")
      assert html =~ ~s(data-push-state="disabled")
    end
  end

  # ---------------------------------------------------------------------------
  # Bottom navigation  (fixed 4-tab bar, md:hidden)
  # ---------------------------------------------------------------------------

  describe "bottom navigation" do
    test "bottom nav is present and fixed to the bottom edge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "fixed bottom-0 left-0 right-0"
      assert html =~ "md:hidden"
    end

    test "bottom nav has all four tabs: Sessions, Tasks, Notes, Project", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Sessions"
      assert html =~ "Tasks"
      assert html =~ "Notes"
      assert html =~ "Project"
    end

    test "bottom nav uses a 4-column grid layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "grid-cols-4"
    end

    test "bottom nav padding accounts for home indicator safe area", %{conn: conn} do
      # env(safe-area-inset-bottom) keeps content clear of iPhone home bar
      # Critical for 390×844 and 430×932 which have home indicators
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "safe-area-inset-bottom"
    end

    test "bottom nav has backdrop blur for legibility over scrolled content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "backdrop-blur"
    end

    test "Sessions tab is active when on the sessions route", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Active tab gets text-primary styling
      assert html =~ "text-primary"
    end

    test "bottom nav z-index is above main content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # z-40 keeps the nav above page content but below drawers (z-50)
      assert html =~ "z-40"
    end
  end

  # ---------------------------------------------------------------------------
  # Safe-area insets  (notch + home indicator compatibility)
  # ---------------------------------------------------------------------------

  describe "safe-area insets" do
    test "main content has bottom padding that clears bottom nav + home indicator", %{conn: conn} do
      # 4.25rem = bottom nav height; env(safe-area-inset-bottom) = home indicator
      # This prevents content from being obscured at 375×812, 390×844, 430×932
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "calc(4.25rem+env(safe-area-inset-bottom))"
    end

    test "main content bottom padding resets to 0 on md+ (md:pb-0)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "md:pb-0"
    end

    test "sidebar applies safe-inset-y class for notch-aware positioning", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "safe-inset-y"
    end

    test "task detail drawer has safe-inset-y for full-height slide-over panel", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "safe-inset-y"
    end

    test "app viewport uses --app-viewport-height CSS custom property", %{conn: conn} do
      # Avoids iOS Safari 100vh bug; JS sets --app-viewport-height to 100dvh
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "--app-viewport-height"
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar mobile overlay  (structure + server-side interactions)
  #
  # NOTE: open_mobile is triggered via a client-side JS.dispatch from the
  # hamburger button — untestable in LiveViewTest. We cover the initial state
  # and the toggle_collapsed event (which uses a real phx-click/phx-target).
  # ---------------------------------------------------------------------------

  describe "sidebar mobile overlay" do
    test "sidebar starts in closed state (-translate-x-full) on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "-translate-x-full"
      refute html =~ "bg-black/40"
    end

    test "sidebar width is 85vw capped at max-w-72 on mobile", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "w-[85vw] max-w-72"
    end

    test "sidebar is fixed on mobile, relative on md+", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # fixed for mobile overlay; reverts to relative column on desktop
      assert html =~ "fixed inset-y-0 left-0"
      assert html =~ "md:relative md:inset-auto"
    end

    test "sidebar has z-50 so it layers above bottom nav and content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "z-50"
    end

    test "toggle_collapsed event shrinks sidebar to icon-only width on desktop", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # The collapse button uses phx-click/phx-target on the component
      view
      |> element("[phx-click='toggle_collapsed'][phx-target]")
      |> render_click()

      # Collapsed class narrows sidebar to icon-only width (md:w-16)
      assert render(view) =~ "md:w-16"
    end

    test "toggle_collapsed twice returns sidebar to full width", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      btn = element(view, "[phx-click='toggle_collapsed'][phx-target]")
      render_click(btn)
      render_click(btn)

      # Back to expanded (md:w-60)
      assert render(view) =~ "md:w-60"
    end

    test "sidebar branding link navigates to root", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(href="/")
      assert html =~ "Eye in the Sky"
    end
  end

  # ---------------------------------------------------------------------------
  # Command palette  (modal positioning varies by breakpoint)
  # ---------------------------------------------------------------------------

  describe "command palette positioning" do
    test "slides up from bottom on mobile (modal-bottom), centered on sm+ (modal-middle)", %{
      conn: conn
    } do
      # 375×812 and 390×844 trigger modal-bottom
      # 640px+ (sm breakpoint) uses modal-middle
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "modal-bottom sm:modal-middle"
    end

    test "command palette input has descriptive placeholder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Search pages, projects, and commands..."
    end

    test "command palette results list has role=listbox for screen readers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(role="listbox")
      assert html =~ ~s(aria-label="Command palette results")
    end

    test "command palette has max height using dvh units", %{conn: conn} do
      # max-h-[55dvh] prevents palette from overflowing small screens
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "55dvh"
    end
  end

  # ---------------------------------------------------------------------------
  # Task detail drawer  (right-side slide-over, all breakpoints)
  # ---------------------------------------------------------------------------

  describe "task detail drawer" do
    test "drawer panel uses w-full max-w-lg for full-width layout on narrow screens", %{
      conn: conn
    } do
      # On 375-430px, max-w-lg (~512px) is irrelevant — w-full takes over
      project = create_project()
      task = create_task(project, %{title: "Drawer Width Test"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "w-full max-w-lg"
    end

    test "drawer has dimming backdrop covering the screen", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      html = render(view)
      assert html =~ "fixed inset-0"
      assert html =~ "bg-black/30"
    end

    test "backdrop event closes the drawer", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      # Backdrop (the dimming overlay) is present when drawer is open
      assert has_element?(view, ".fixed.inset-0.z-40")

      render_click(view, "toggle_task_detail_drawer", %{})

      # Backdrop gone once drawer is dismissed
      refute has_element?(view, ".fixed.inset-0.z-40")
    end

    test "drawer is fixed to the right edge and full-height", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "fixed inset-y-0 right-0"
    end

    test "drawer has z-50 so it floats above bottom nav (z-40)", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "z-50"
    end

    test "drawer content is scrollable (overflow-y-auto)", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "overflow-y-auto"
    end
  end

  # ---------------------------------------------------------------------------
  # Main content area  (scroll and overflow containment)
  # ---------------------------------------------------------------------------

  describe "main content layout" do
    test "main content area is scrollable", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(id="main-content")
      assert html =~ "overflow-auto"
    end

    test "min-w-0 on main content prevents flex blowout on narrow screens", %{conn: conn} do
      # Critical on 375px where flex children can exceed container width
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "flex flex-col min-w-0"
    end

    test "outer wrapper uses --app-viewport-height for full-screen layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "h-[var(--app-viewport-height)]"
    end
  end

  # ---------------------------------------------------------------------------
  # PWA and mobile meta tags  (critical for iOS Safari at all breakpoints)
  # ---------------------------------------------------------------------------

  describe "PWA and iOS meta tags" do
    test "viewport meta tag sets device-width and initial-scale=1", %{conn: conn} do
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ ~s(name="viewport")
      assert html =~ "width=device-width"
      assert html =~ "initial-scale=1"
    end

    test "apple-mobile-web-app-capable enables full-screen PWA mode on iOS", %{conn: conn} do
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ ~s(name="apple-mobile-web-app-capable")
      assert html =~ ~s(content="yes")
    end

    test "status bar style is black-translucent for edge-to-edge layout on iOS", %{conn: conn} do
      # Required for correct rendering at 390×844 and 430×932 (Dynamic Island devices)
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ "black-translucent"
    end

    test "theme-color meta tag is set for Chrome for Android tab color", %{conn: conn} do
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ ~s(name="theme-color")
    end

    test "web app manifest is linked for PWA installability", %{conn: conn} do
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ ~s(rel="manifest")
      assert html =~ "/manifest.json"
    end

    test "body uses 100dvh for correct full-screen height on mobile browsers", %{conn: conn} do
      html = html_response(get(conn, ~p"/"), 200)

      assert html =~ "100dvh"
    end
  end

  # ---------------------------------------------------------------------------
  # Accessibility  (skip link, ARIA)
  # ---------------------------------------------------------------------------

  describe "accessibility and skip navigation" do
    test "skip-to-content link is present for keyboard navigation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Skip to main content"
      assert html =~ ~s(href="#main-content")
    end

    test "skip link targets main-content id", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(id="main-content")
    end
  end
end
