defmodule Zdbeam.MixProject do
  use Mix.Project

  def project do
    [
      app: :zdbeam,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [
        zdbeam: [
          steps: [:assemble, &Burrito.wrap/1],
          burrito: [
            targets: [
              macos: [os: :darwin, cpu: :aarch64]
            ]
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Zdbeam.Application, []}
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      "build.prod": [
        &clean_burrito_cache/1,
        "release zdbeam --overwrite"
      ]
    ]
  end

  defp clean_burrito_cache(_) do
    binary_path = burrito_binary_path()

    with true <- File.exists?(binary_path) do
      Mix.shell().info("cleaning burrito cache...")
      uninstall_command(binary_path) |> System.shell()
    else
      _ -> Mix.shell().info("no existing binary to clean")
    end

    :ok
  end

  defp burrito_binary_path do
    binary_name = binary_name_for_os(:os.type())
    Path.expand("./burrito_out/#{binary_name}")
  end

  defp binary_name_for_os({:unix, :darwin}), do: "zdbeam_macos"
  defp binary_name_for_os({:unix, :linux}), do: "zdbeam_linux"
  defp binary_name_for_os({:win32, _}), do: "zdbeam_windows.exe"

  defp uninstall_command(binary_path) do
    case :os.type() do
      {:win32, _} -> "echo y | #{binary_path} maintenance uninstall 2>nul || echo."
      _ -> "echo 'y' | #{binary_path} maintenance uninstall 2>/dev/null || true"
    end
  end
end
