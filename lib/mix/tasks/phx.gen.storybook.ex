defmodule Mix.Tasks.Phx.Gen.Storybook do
  @shortdoc "Generates a Storybook to showcase your LiveComponents"
  @moduledoc """
  Generates a Storybook and provides setup instructions.

  ```bash
  $> mix phx.gen.storybook
  ```

  The generated files will contain:

    * the storybook backend in `lib/my_app_web/storybook.ex`
    * an index file in `storybook/_root.index.exs`
    * a welcome page in `storybook/welcome.story.exs`
    * an icon component in `storybook/components/icon.story.exs`
    * a custom js in `assets/js/storybook.js`
    * a custom css in `assets/css/storybook.css`

  The generator supports the `--no-tailwind` flag if you want to skip the TailwindCSS specific bit.
  """

  use Mix.Task

  @templates_folder "priv/templates/phx.gen.storybook"
  @switches [tailwind: :boolean]

  @doc false
  def run(argv) do
    opts = parse_opts(argv)

    if Mix.Project.umbrella?() do
      Mix.raise("""
      umbrella projects are not supported.
      mix phx.gen.storybook must be invoked from within your *_web application root directory")
      """)
    end

    Mix.shell().info("Starting storybook generation")

    web_module = web_module()
    web_module_name = Module.split(web_module) |> List.last()
    app_name = String.to_atom(Macro.underscore(web_module))
    app_folder = Path.join("lib", to_string(app_name))
    component_folder = "storybook/components"
    page_folder = "storybook"
    js_folder = "assets/js"
    css_folder = "assets/css"

    schema = %{
      app: app_name,
      sandbox_class: String.replace(to_string(app_name), "_", "-"),
      module: web_module
    }

    mapping = [
      {"storybook.ex.eex", Path.join(app_folder, "storybook.ex")},
      {"_root.index.exs", Path.join(page_folder, "_root.index.exs")},
      {"welcome.story.exs", Path.join(page_folder, "welcome.story.exs")},
      {"icon.story.exs", Path.join(component_folder, "icon.story.exs")},
      {"storybook.js", Path.join(js_folder, "storybook.js")}
    ]

    mapping =
      if opts[:tailwind] == false do
        mapping ++ [{"storybook.css.eex", Path.join(css_folder, "storybook.css")}]
      else
        mapping ++ [{"storybook.tailwind.css", Path.join(css_folder, "storybook.css")}]
      end

    for {source_file_path, target} <- mapping do
      templates_folder = Application.app_dir(:phx_live_storybook, @templates_folder)
      source = Path.join(templates_folder, source_file_path)

      source_content =
        case Path.extname(source) do
          ".eex" -> EEx.eval_file(source, schema: schema)
          _ -> File.read!(source)
        end

      Mix.Generator.create_file(target, source_content)
    end

    with true <- print_router_instructions(web_module_name, app_name, opts),
         true <- print_esbuild_instructions(web_module_name, app_name, opts),
         true <- print_tailwind_instructions(web_module_name, app_name, opts),
         true <- print_watchers_instructions(web_module_name, app_name, opts),
         true <- print_live_reload_instructions(web_module_name, app_name, opts),
         true <- print_formatter_instructions(web_module_name, app_name, opts) do
      Mix.shell().info("You are all set! 🚀")
      Mix.shell().info("You can run mix phx.server and visit http://localhost:4000/storybook")
    else
      _ -> Mix.shell().info("storybook setup aborted 🙁")
    end
  end

  defp web_module do
    base = Mix.Phoenix.base()

    cond do
      Mix.Phoenix.context_app() != Mix.Phoenix.otp_app() -> Module.concat([base])
      String.ends_with?(base, "Web") -> Module.concat([base])
      true -> Module.concat(["#{base}Web"])
    end
  end

  defp parse_opts(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} ->
        opts

      {_opts, [argv | _], _} ->
        Mix.raise("Invalid option: #{argv}")

      {_opts, _argv, [switch | _]} ->
        Mix.raise("Invalid option: " <> switch_to_string(switch))
    end
  end

  defp switch_to_string({name, nil}), do: name
  defp switch_to_string({name, val}), do: name <> "=" <> val

  defp print_router_instructions(web_module, _app_name, _opts) do
    print_instructions("""
      Add the following to your #{IO.ANSI.bright()}router.ex#{IO.ANSI.reset()}:

        use #{web_module}, :router
        import PhxLiveStorybook.Router

        scope "/" do
          storybook_assets()
        end

        scope "/", #{web_module} do
          pipe_through(:browser)
          live_storybook "/storybook", backend_module: #{web_module}.Storybook
        end
    """)
  end

  # prompt user to add ~r"storybook/.*(exs)$" in config/dev.exs live_reload patterns

  defp print_esbuild_instructions(_web_module, _app_name, _opts) do
    print_instructions("""
      Add #{IO.ANSI.bright()}js/storybook.js#{IO.ANSI.reset()} as a new entry point to your esbuild args in #{IO.ANSI.bright()}config/config.exs#{IO.ANSI.reset()}:

        config :esbuild,
        default: [
          args:
            ~w(js/app.js #{IO.ANSI.bright()}js/storybook.js#{IO.ANSI.reset()} --bundle --target=es2017 --outdir=../priv/static/assets ...),
          ...
        ]
    """)
  end

  defp print_tailwind_instructions(_web_module, _app_name, _opts = [tailwind: false]), do: true

  defp print_tailwind_instructions(_web_module, _app_name, _opts) do
    print_instructions("""
      Add a new Tailwind build profile for #{IO.ANSI.bright()}css/storybook.css#{IO.ANSI.reset()} in #{IO.ANSI.bright()}config/config.exs#{IO.ANSI.reset()}:

        config :tailwind,
          ...
          default: [
            ...
          ],
          #{IO.ANSI.bright()}storybook: [
            args: ~w(
              --config=tailwind.config.js
              --input=css/storybook.css
              --output=../priv/static/assets/storybook.css
            ),
            cd: Path.expand("../assets", __DIR__)
          ]#{IO.ANSI.reset()}
    """)
  end

  defp print_watchers_instructions(_web_module, _app_name, _opts = [tailwind: false]), do: true

  defp print_watchers_instructions(web_module, app_name, _opts) do
    print_instructions("""
      Add a new #{IO.ANSI.bright()}endpoint watcher#{IO.ANSI.reset()} for your new Tailwind build profile in #{IO.ANSI.bright()}config/dev.exs#{IO.ANSI.reset()}:

        config #{inspect(app_name)}, #{web_module}.Endpoint,
          ...
          watchers: [
            ...
            #{IO.ANSI.bright()}storybook_tailwind: {Tailwind, :install_and_run, [:storybook, ~w(--watch)]}#{IO.ANSI.reset()}
          ]
    """)
  end

  defp print_live_reload_instructions(web_module, app_name, _opts) do
    print_instructions("""
      Add a new #{IO.ANSI.bright()}live_reload pattern#{IO.ANSI.reset()} to your endpoint in #{IO.ANSI.bright()}config/dev.exs#{IO.ANSI.reset()}:

        config #{inspect(app_name)}, #{web_module}.Endpoint,
          live_reload: [
            patterns: [
              ...
              #{IO.ANSI.bright()}~r"storybook/.*(exs)$"#{IO.ANSI.reset()}
            ]
          ]
    """)
  end

  defp print_formatter_instructions(_web_module, _app_name, _opts) do
    print_instructions("""
      Add your storybook content to #{IO.ANSI.bright()}.formatter.exs#{IO.ANSI.reset()}

        [
          import_deps: [...],
          inputs: [
            ...
            #{IO.ANSI.bright()}"storybook/**/*.exs"#{IO.ANSI.reset()}
          ]
        ]
    """)
  end

  defp print_instructions(message) do
    Mix.shell().yes?(
      "#{IO.ANSI.green()}* manual setup instructions:#{IO.ANSI.reset()}\n#{message}\n\n#{IO.ANSI.bright()}[Y to continue]#{IO.ANSI.reset()}"
    )
  end
end
